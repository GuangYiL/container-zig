const std = @import("std");

const Client = @import("../client.zig").Client;
const model = @import("info_model.zig");
const http_status = @import("../status.zig");

pub const Info = model.Info;

pub fn info(allocator: std.mem.Allocator, client: *Client) !Info {
    var response = try client.request(.{
        .method = .get,
        .path = "/info",
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return model.parseInfo(allocator, body);
}
