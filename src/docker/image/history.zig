const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");
const strings = @import("strings.zig");

pub const HistoryOptions = struct {
    platform: ?[]const u8 = null,
};

pub const HistoryList = struct {
    allocator: std.mem.Allocator,
    items: []History,

    pub fn deinit(self: *HistoryList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const History = struct {
    id: []const u8,
    created: i64,
    created_by: []const u8,
    tags: []const []const u8,
    size: i64,
    comment: []const u8,

    fn deinit(self: *History, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.created_by);
        strings.freeList(allocator, self.tags);
        allocator.free(self.tags);
        allocator.free(self.comment);
        self.* = undefined;
    }
};

pub fn history(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: HistoryOptions) !HistoryList {
    const path = try historyPath(allocator, name, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ImageNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseHistory(allocator, body);
}

const RawHistory = struct {
    Id: []const u8,
    Created: i64,
    CreatedBy: []const u8,
    Tags: ?[]const []const u8 = null,
    Size: i64,
    Comment: []const u8,
};

fn historyPath(allocator: std.mem.Allocator, name: []const u8, options: HistoryOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/images/", name, "/history");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.platform) |platform| try builder.add("platform", platform);

    return builder.finish();
}

fn parseHistory(allocator: std.mem.Allocator, body: []const u8) !HistoryList {
    const parsed = try std.json.parseFromSlice([]RawHistory, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const items = try allocator.alloc(History, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        items[filled] = .{
            .id = try allocator.dupe(u8, raw.Id),
            .created = raw.Created,
            .created_by = try allocator.dupe(u8, raw.CreatedBy),
            .tags = try strings.dupeList(allocator, raw.Tags),
            .size = raw.Size,
            .comment = try allocator.dupe(u8, raw.Comment),
        };
        filled += 1;
    }

    return .{ .allocator = allocator, .items = items };
}

test "historyPath encodes platform" {
    const path = try historyPath(std.testing.allocator, "repo/image:tag", .{
        .platform = "linux/arm64",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/images/repo%2Fimage%3Atag/history?platform=linux%2Farm64",
        path,
    );
}

test "parseHistory owns history items" {
    var result = try parseHistory(std.testing.allocator,
        \\[
        \\  {
        \\    "Id": "sha256:layer",
        \\    "Created": 1644009612,
        \\    "CreatedBy": "/bin/sh -c echo ok",
        \\    "Tags": ["ubuntu:latest"],
        \\    "Size": 42,
        \\    "Comment": "created"
        \\  }
        \\]
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("sha256:layer", result.items[0].id);
    try std.testing.expectEqualStrings("ubuntu:latest", result.items[0].tags[0]);
    try std.testing.expectEqual(@as(i64, 42), result.items[0].size);
}
