const std = @import("std");

const api_version = @import("api_version.zig");
const http = @import("http.zig");

pub const ApiFailure = struct {
    allocator: std.mem.Allocator,
    method: http.Method,
    endpoint: []const u8,
    status: http.Status,
    daemon_message: ?[]const u8,
    api_version: ?api_version.Version,
    resource_id: ?[]const u8,

    pub fn read(
        allocator: std.mem.Allocator,
        response: anytype,
        method: http.Method,
        endpoint: []const u8,
        version: ?api_version.Version,
        resource_id: ?[]const u8,
    ) !ApiFailure {
        var result = ApiFailure{
            .allocator = allocator,
            .method = method,
            .endpoint = try allocator.dupe(u8, endpoint),
            .status = response.status(),
            .daemon_message = null,
            .api_version = version,
            .resource_id = null,
        };
        errdefer result.deinit();
        if (resource_id) |id| result.resource_id = try allocator.dupe(u8, id);
        if (try response.body()) |body| result.daemon_message = try parseMessage(allocator, body);
        return result;
    }

    pub fn deinit(self: *ApiFailure) void {
        self.allocator.free(self.endpoint);
        if (self.daemon_message) |message| self.allocator.free(message);
        if (self.resource_id) |resource_id| self.allocator.free(resource_id);
        self.* = undefined;
    }
};

pub const Handler = struct {
    context: *anyopaque,
    handle_fn: *const fn (*anyopaque, *const ApiFailure) void,

    pub fn handle(self: Handler, failure: *const ApiFailure) void {
        self.handle_fn(self.context, failure);
    }
};

fn parseMessage(allocator: std.mem.Allocator, body: []const u8) !?[]const u8 {
    const parsed = std.json.parseFromSlice(struct { message: ?[]const u8 = null }, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch return try allocator.dupe(u8, body);
    defer parsed.deinit();
    return if (parsed.value.message) |message| try allocator.dupe(u8, message) else null;
}

test "ApiFailure parses Docker daemon messages" {
    const MockResponse = struct {
        fn status(_: *@This()) http.Status {
            return .conflict;
        }
        fn body(_: *@This()) !?[]const u8 {
            return "{\"message\":\"name is already in use\"}";
        }
    };
    var response = MockResponse{};
    var failure = try ApiFailure.read(
        std.testing.allocator,
        &response,
        .post,
        "/v1.55/containers/create",
        .{ .major = 1, .minor = 55 },
        null,
    );
    defer failure.deinit();
    try std.testing.expectEqual(http.Status.conflict, failure.status);
    try std.testing.expectEqualStrings("name is already in use", failure.daemon_message.?);
}
