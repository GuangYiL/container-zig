const std = @import("std");

const http = @import("http.zig");

pub const Error = error{
    BadParameter,
    Unauthorized,
    Forbidden,
    NotFound,
    Conflict,
    NotModified,
    ServerError,
    NotImplemented,
    ServiceUnavailable,
    UnexpectedStatus,
};

pub fn expect(status: http.Status, comptime expected: anytype) Error!void {
    inline for (expected) |value| {
        if (status == value) return;
    }
    return mapError(status);
}

pub fn mapError(status: http.Status) Error {
    return switch (status) {
        .bad_request => error.BadParameter,
        .unauthorized => error.Unauthorized,
        .forbidden => error.Forbidden,
        .not_found => error.NotFound,
        .not_modified => error.NotModified,
        .conflict => error.Conflict,
        .internal_server_error => error.ServerError,
        .not_implemented => error.NotImplemented,
        .service_unavailable => error.ServiceUnavailable,
        else => error.UnexpectedStatus,
    };
}

test "expect accepts allowed statuses" {
    try expect(.ok, .{ .ok, .created });
    try expect(.created, .{ .ok, .created });
}

test "expect maps common Docker errors" {
    try std.testing.expectError(error.BadParameter, expect(.bad_request, .{.ok}));
    try std.testing.expectError(error.Unauthorized, expect(.unauthorized, .{.ok}));
    try std.testing.expectError(error.Forbidden, expect(.forbidden, .{.ok}));
    try std.testing.expectError(error.NotFound, expect(.not_found, .{.ok}));
    try std.testing.expectError(error.Conflict, expect(.conflict, .{.ok}));
    try std.testing.expectError(error.ServerError, expect(.internal_server_error, .{.ok}));
    try std.testing.expectError(error.NotImplemented, expect(.not_implemented, .{.ok}));
    try std.testing.expectError(error.ServiceUnavailable, expect(.service_unavailable, .{.ok}));
    try std.testing.expectError(error.UnexpectedStatus, expect(.accepted, .{.ok}));
}
