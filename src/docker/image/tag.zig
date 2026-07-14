const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");

pub const TagOptions = struct {
    repo: ?[]const u8 = null,
    tag: ?[]const u8 = null,
};

pub fn tag(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: TagOptions) !void {
    const path = try tagPath(allocator, name, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .post,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .created => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ImageNotFound,
        .conflict => return error.ImageConflict,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

fn tagPath(allocator: std.mem.Allocator, name: []const u8, options: TagOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/images/", name, "/tag");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.repo) |repo| try builder.add("repo", repo);
    if (options.tag) |tag_name| try builder.add("tag", tag_name);

    return builder.finish();
}

test "tagPath encodes repo and tag" {
    const path = try tagPath(std.testing.allocator, "sha256:abc", .{
        .repo = "example/app",
        .tag = "v1",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/images/sha256%3Aabc/tag?repo=example%2Fapp&tag=v1",
        path,
    );
}
