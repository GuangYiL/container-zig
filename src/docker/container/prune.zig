const std = @import("std");

const Client = @import("../client.zig").Client;
const http_status = @import("../status.zig");
const query = @import("../query.zig");

pub const PruneOptions = struct {
    filters: ?[]const u8 = null,
};

pub const Prune = struct {
    allocator: std.mem.Allocator,
    containers_deleted: []const []const u8,
    space_reclaimed: ?i64,

    pub fn deinit(self: *Prune) void {
        for (self.containers_deleted) |container_id| self.allocator.free(container_id);
        self.allocator.free(self.containers_deleted);
        self.* = undefined;
    }
};

pub fn prune(allocator: std.mem.Allocator, client: *Client, options: PruneOptions) !Prune {
    const path = try prunePath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .post,
        .path = path,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return parsePrune(allocator, body);
}

const RawPrune = struct {
    ContainersDeleted: ?[]const []const u8 = null,
    SpaceReclaimed: ?i64 = null,
};

fn prunePath(allocator: std.mem.Allocator, options: PruneOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/containers/prune");
    defer builder.deinit();

    if (options.filters) |filters| try builder.add("filters", filters);

    return builder.finish();
}

fn parsePrune(allocator: std.mem.Allocator, body: []const u8) !Prune {
    const parsed = try std.json.parseFromSlice(RawPrune, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .containers_deleted = try dupeStringList(allocator, parsed.value.ContainersDeleted),
        .space_reclaimed = parsed.value.SpaceReclaimed,
    };
}

fn dupeStringList(allocator: std.mem.Allocator, raw_strings: ?[]const []const u8) ![]const []const u8 {
    const strings = raw_strings orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, strings.len);
    var filled: usize = 0;
    errdefer {
        for (owned[0..filled]) |string| allocator.free(string);
        allocator.free(owned);
    }

    for (strings) |string| {
        owned[filled] = try allocator.dupe(u8, string);
        filled += 1;
    }

    return owned;
}

test "prunePath encodes filters" {
    const path = try prunePath(std.testing.allocator, .{
        .filters = "{\"label\":[\"keep=false\"]}",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/prune?filters=%7B%22label%22%3A%5B%22keep%3Dfalse%22%5D%7D",
        path,
    );
}

test "parsePrune owns deleted container IDs" {
    var result = try parsePrune(std.testing.allocator,
        \\{
        \\  "ContainersDeleted": ["a", "b"],
        \\  "SpaceReclaimed": 4096
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("a", result.containers_deleted[0]);
    try std.testing.expectEqualStrings("b", result.containers_deleted[1]);
    try std.testing.expectEqual(@as(i64, 4096), result.space_reclaimed.?);
}
