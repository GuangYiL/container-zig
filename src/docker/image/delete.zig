const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");
const strings = @import("strings.zig");

pub const RemoveOptions = struct {
    force: ?bool = null,
    no_prune: ?bool = null,
    platforms: ?[]const []const u8 = null,
};

pub const DeleteList = struct {
    allocator: std.mem.Allocator,
    items: []Delete,

    pub fn deinit(self: *DeleteList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Delete = struct {
    untagged: ?[]const u8,
    deleted: ?[]const u8,

    fn deinit(self: *Delete, allocator: std.mem.Allocator) void {
        strings.freeOptional(allocator, self.untagged);
        strings.freeOptional(allocator, self.deleted);
        self.* = undefined;
    }
};

pub fn remove(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: RemoveOptions) !DeleteList {
    const path = try deletePath(allocator, name, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .delete,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ImageNotFound,
        .conflict => return error.ImageConflict,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseDelete(allocator, body);
}

const RawDelete = struct {
    Untagged: ?[]const u8 = null,
    Deleted: ?[]const u8 = null,
};

fn deletePath(allocator: std.mem.Allocator, name: []const u8, options: RemoveOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/images/", name, "");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.force) |force| try builder.addBool("force", force);
    if (options.no_prune) |no_prune| try builder.addBool("noprune", no_prune);
    if (options.platforms) |platforms| {
        for (platforms) |platform| try builder.add("platforms", platform);
    }

    return builder.finish();
}

fn parseDelete(allocator: std.mem.Allocator, body: []const u8) !DeleteList {
    const parsed = try std.json.parseFromSlice([]RawDelete, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const items = try allocator.alloc(Delete, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        items[filled] = .{
            .untagged = try strings.dupeOptional(allocator, raw.Untagged),
            .deleted = try strings.dupeOptional(allocator, raw.Deleted),
        };
        filled += 1;
    }

    return .{ .allocator = allocator, .items = items };
}

test "deletePath encodes image delete options" {
    const path = try deletePath(std.testing.allocator, "repo/image:tag", .{
        .force = true,
        .no_prune = false,
        .platforms = &.{ "linux/amd64", "linux/arm64" },
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/images/repo%2Fimage%3Atag?force=true&noprune=false&platforms=linux%2Famd64&platforms=linux%2Farm64",
        path,
    );
}

test "parseDelete owns delete items" {
    var result = try parseDelete(std.testing.allocator,
        \\[
        \\  {"Untagged": "ubuntu:latest"},
        \\  {"Deleted": "sha256:abc"}
        \\]
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("ubuntu:latest", result.items[0].untagged.?);
    try std.testing.expectEqualStrings("sha256:abc", result.items[1].deleted.?);
}
