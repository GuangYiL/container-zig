const std = @import("std");

const Client = @import("../client.zig").Client;
const http_status = @import("../status.zig");
const query = @import("../query.zig");
const strings = @import("strings.zig");

pub const SummaryList = struct {
    allocator: std.mem.Allocator,
    items: []Summary,

    pub fn deinit(self: *SummaryList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Summary = struct {
    id: []const u8,
    parent_id: []const u8,
    repo_tags: []const []const u8,
    repo_digests: []const []const u8,
    labels: []const strings.Pair,
    created: i64,
    size: i64,
    shared_size: i64,
    containers: i64,

    fn deinit(self: *Summary, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.parent_id);
        strings.freeList(allocator, self.repo_tags);
        allocator.free(self.repo_tags);
        strings.freeList(allocator, self.repo_digests);
        allocator.free(self.repo_digests);
        strings.freePairs(allocator, self.labels);
        allocator.free(self.labels);
        self.* = undefined;
    }
};

pub const ListOptions = struct {
    all: ?bool = null,
    filters: ?[]const u8 = null,
    shared_size: ?bool = null,
    digests: ?bool = null,
    manifests: ?bool = null,
    identity: ?bool = null,
};

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !SummaryList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return parseList(allocator, body);
}

const RawSummary = struct {
    Id: []const u8,
    ParentId: []const u8,
    RepoTags: ?[]const []const u8 = null,
    RepoDigests: ?[]const []const u8 = null,
    Created: i64,
    Size: i64,
    SharedSize: i64,
    Labels: ?std.json.ArrayHashMap([]const u8) = null,
    Containers: i64,
};

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/images/json");
    defer builder.deinit();

    if (options.all) |value| try builder.addBool("all", value);
    if (options.filters) |filters| try builder.add("filters", filters);
    if (options.shared_size) |value| try builder.addBool("shared-size", value);
    if (options.digests) |value| try builder.addBool("digests", value);
    if (options.manifests) |value| try builder.addBool("manifests", value);
    if (options.identity) |value| try builder.addBool("identity", value);

    return builder.finish();
}

fn parseList(allocator: std.mem.Allocator, body: []const u8) !SummaryList {
    const parsed = try std.json.parseFromSlice([]RawSummary, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const items = try allocator.alloc(Summary, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        items[filled] = .{
            .id = try allocator.dupe(u8, raw.Id),
            .parent_id = try allocator.dupe(u8, raw.ParentId),
            .repo_tags = try strings.dupeList(allocator, raw.RepoTags),
            .repo_digests = try strings.dupeList(allocator, raw.RepoDigests),
            .labels = try strings.dupePairs(allocator, raw.Labels),
            .created = raw.Created,
            .size = raw.Size,
            .shared_size = raw.SharedSize,
            .containers = raw.Containers,
        };
        filled += 1;
    }

    return .{ .allocator = allocator, .items = items };
}

test "listPath encodes image list filters" {
    const path = try listPath(std.testing.allocator, .{
        .all = true,
        .filters = "{\"dangling\":[\"false\"]}",
        .shared_size = true,
        .digests = true,
        .manifests = false,
        .identity = true,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/images/json?all=true&filters=%7B%22dangling%22%3A%5B%22false%22%5D%7D" ++
            "&shared-size=true&digests=true&manifests=false&identity=true",
        path,
    );
}

test "parseList owns image summaries" {
    var result = try parseList(std.testing.allocator,
        \\[
        \\  {
        \\    "Id": "sha256:abc",
        \\    "ParentId": "",
        \\    "RepoTags": ["ubuntu:latest"],
        \\    "RepoDigests": ["ubuntu@sha256:def"],
        \\    "Created": 1644009612,
        \\    "Size": 172064416,
        \\    "SharedSize": -1,
        \\    "Labels": {"org.opencontainers.image.title": "ubuntu"},
        \\    "Containers": 2
        \\  }
        \\]
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("sha256:abc", result.items[0].id);
    try std.testing.expectEqualStrings("ubuntu:latest", result.items[0].repo_tags[0]);
    try std.testing.expectEqualStrings("org.opencontainers.image.title", result.items[0].labels[0].name);
    try std.testing.expectEqual(@as(i64, 2), result.items[0].containers);
}
