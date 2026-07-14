const http = @import("http.zig");

const Client = @import("client.zig").Client;

const std = @import("std");

pub fn start(allocator: std.mem.Allocator, client: *Client) !Client.Duplex {
    var headers = try upgradeHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = "/session",
        .headers = &headers,
    });
    errdefer response.deinit();

    try expectStartStatus(response.status());
    return response.takeRawDuplex();
}

fn upgradeHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 2);
    errdefer headers.deinit(allocator);

    try headers.put("Connection", "Upgrade");
    try headers.put("Upgrade", "h2c");
    return headers;
}

fn expectStartStatus(status: http.Status) !void {
    switch (status) {
        .switching_protocols => {},
        .bad_request => return error.BadParameter,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

test "session upgrade headers request h2c" {
    var headers = try upgradeHeaders(std.testing.allocator);
    defer headers.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("Upgrade", headers.get("Connection").?);
    try std.testing.expectEqualStrings("h2c", headers.get("Upgrade").?);
}

test "session start status handling is explicit" {
    try expectStartStatus(.switching_protocols);
    try std.testing.expectError(error.BadParameter, expectStartStatus(.bad_request));
    try std.testing.expectError(error.ServerError, expectStartStatus(.internal_server_error));
    try std.testing.expectError(error.UnexpectedStatus, expectStartStatus(.ok));
}
