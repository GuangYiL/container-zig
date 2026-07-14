const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;

pub const AuthOptions = struct {
    username: []const u8,
    password: []const u8,
    server_address: []const u8,
};

pub const Auth = union(enum) {
    authenticated: void,
    identity_token: OwnedString,
    auth_failed: OwnedString,
    server_error: OwnedString,

    pub const OwnedString = struct {
        allocator: std.mem.Allocator,
        value: []const u8,

        fn init(allocator: std.mem.Allocator, value: []const u8) !OwnedString {
            return .{
                .allocator = allocator,
                .value = try allocator.dupe(u8, value),
            };
        }

        pub fn deinit(self: *OwnedString) void {
            self.allocator.free(self.value);
            self.* = undefined;
        }
    };

    pub fn deinit(self: *Auth) void {
        switch (self.*) {
            .identity_token, .auth_failed, .server_error => |*owned| owned.deinit(),
            .authenticated => {},
        }
        self.* = undefined;
    }
};

pub fn auth(allocator: std.mem.Allocator, client: *Client, options: AuthOptions) !Auth {
    const body = try authRequestBody(allocator, options);
    defer allocator.free(body);

    var headers = try authHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = "/auth",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();

    const status = response.status();
    const body_or_null = switch (status) {
        .ok, .unauthorized, .internal_server_error => try response.body(),
        .no_content => null,
        else => return error.UnexpectedStatus,
    };

    return parseAuthResponse(allocator, status, body_or_null);
}

const RawAuthConfig = struct {
    username: []const u8,
    password: []const u8,
    serveraddress: []const u8,
};

const RawAuthResponse = struct {
    Status: []const u8,
    IdentityToken: ?[]const u8 = null,
};

const RawErrorResponse = struct {
    message: []const u8,
};

fn authRequestBody(allocator: std.mem.Allocator, options: AuthOptions) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, RawAuthConfig{
        .username = options.username,
        .password = options.password,
        .serveraddress = options.server_address,
    }, .{});
}

fn authHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

fn parseAuthResponse(allocator: std.mem.Allocator, status: http.Status, body: ?[]const u8) !Auth {
    return switch (status) {
        .ok => parseAuthOk(allocator, body orelse return error.EmptyResponse),
        .no_content => .{ .authenticated = {} },
        .unauthorized => .{ .auth_failed = try parseAuthError(allocator, body) },
        .internal_server_error => .{ .server_error = try parseAuthError(allocator, body) },
        else => error.UnexpectedStatus,
    };
}

fn parseAuthOk(allocator: std.mem.Allocator, body: []const u8) !Auth {
    const parsed = try std.json.parseFromSlice(RawAuthResponse, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    if (parsed.value.IdentityToken) |token| {
        if (token.len > 0) {
            return .{ .identity_token = try Auth.OwnedString.init(allocator, token) };
        }
    }

    return .{ .authenticated = {} };
}

fn parseAuthError(allocator: std.mem.Allocator, body: ?[]const u8) !Auth.OwnedString {
    const error_body = body orelse return error.EmptyResponse;
    const parsed = try std.json.parseFromSlice(RawErrorResponse, allocator, error_body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return Auth.OwnedString.init(allocator, parsed.value.message);
}

test "Auth deinit releases owned strings" {
    {
        var result = Auth{
            .identity_token = try Auth.OwnedString.init(std.testing.allocator, "token"),
        };
        defer result.deinit();
        try std.testing.expectEqualStrings("token", result.identity_token.value);
    }

    {
        var result = Auth{
            .auth_failed = try Auth.OwnedString.init(std.testing.allocator, "bad credentials"),
        };
        defer result.deinit();
        try std.testing.expectEqualStrings("bad credentials", result.auth_failed.value);
    }

    {
        var result = Auth{
            .server_error = try Auth.OwnedString.init(std.testing.allocator, "registry unavailable"),
        };
        defer result.deinit();
        try std.testing.expectEqualStrings("registry unavailable", result.server_error.value);
    }

    {
        var result = Auth{ .authenticated = {} };
        result.deinit();
    }
}

test "authRequestBody uses Docker serveraddress field" {
    const body = try authRequestBody(std.testing.allocator, .{
        .username = "user",
        .password = "pass",
        .server_address = "https://index.docker.io/v1/",
    });
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"username\":\"user\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"password\":\"pass\""));
    try std.testing.expect(std.mem.containsAtLeast(
        u8,
        body,
        1,
        "\"serveraddress\":\"https://index.docker.io/v1/\"",
    ));
}

test "authHeaders sets JSON content type" {
    var headers = try authHeaders(std.testing.allocator);
    defer headers.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

test "parseAuthResponse handles identity token" {
    var result = try parseAuthResponse(
        std.testing.allocator,
        .ok,
        "{\"Status\":\"Login Succeeded\",\"IdentityToken\":\"opaque-token\"}",
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("opaque-token", result.identity_token.value);
}

test "parseAuthResponse handles authenticated without token" {
    var result = try parseAuthResponse(
        std.testing.allocator,
        .ok,
        "{\"Status\":\"Login Succeeded\"}",
    );
    defer result.deinit();

    try expectAuthTag(result, .authenticated);
}

test "parseAuthResponse handles authenticated with empty token" {
    var result = try parseAuthResponse(
        std.testing.allocator,
        .ok,
        "{\"Status\":\"Login Succeeded\",\"IdentityToken\":\"\"}",
    );
    defer result.deinit();

    try expectAuthTag(result, .authenticated);
}

test "parseAuthResponse handles no content" {
    var result = try parseAuthResponse(std.testing.allocator, .no_content, null);
    defer result.deinit();

    try expectAuthTag(result, .authenticated);
}

test "parseAuthResponse handles unauthorized message" {
    var result = try parseAuthResponse(
        std.testing.allocator,
        .unauthorized,
        "{\"message\":\"invalid credentials\"}",
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("invalid credentials", result.auth_failed.value);
}

test "parseAuthResponse handles server error message" {
    var result = try parseAuthResponse(
        std.testing.allocator,
        .internal_server_error,
        "{\"message\":\"registry unavailable\"}",
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("registry unavailable", result.server_error.value);
}

test "parseAuthResponse rejects unexpected status without body" {
    try std.testing.expectError(
        error.UnexpectedStatus,
        parseAuthResponse(std.testing.allocator, .bad_request, null),
    );
}

test "parseAuthResponse requires body for ok and error responses" {
    try std.testing.expectError(
        error.EmptyResponse,
        parseAuthResponse(std.testing.allocator, .ok, null),
    );
    try std.testing.expectError(
        error.EmptyResponse,
        parseAuthResponse(std.testing.allocator, .unauthorized, null),
    );
    try std.testing.expectError(
        error.EmptyResponse,
        parseAuthResponse(std.testing.allocator, .internal_server_error, null),
    );
}

fn expectAuthTag(result: Auth, expected: std.meta.Tag(Auth)) !void {
    try std.testing.expectEqual(expected, std.meta.activeTag(result));
}
