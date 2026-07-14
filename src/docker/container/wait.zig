const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");

pub const Wait = struct {
    allocator: std.mem.Allocator,
    status_code: i64,
    error_message: ?[]const u8,

    pub const Condition = enum {
        not_running,
        next_exit,
        removed,

        fn queryValue(self: Condition) []const u8 {
            return switch (self) {
                .not_running => "not-running",
                .next_exit => "next-exit",
                .removed => "removed",
            };
        }
    };

    pub fn deinit(self: *Wait) void {
        if (self.error_message) |message| self.allocator.free(message);
        self.* = undefined;
    }
};

pub const WaitOptions = struct {
    condition: ?Wait.Condition = null,
};

pub fn wait(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: WaitOptions) !Wait {
    const path = try waitPath(allocator, id, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .post,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseWait(allocator, body);
}

const RawWait = struct {
    StatusCode: i64,
    Error: ?RawError = null,
};

const RawError = struct {
    Message: ?[]const u8 = null,
};

fn waitPath(allocator: std.mem.Allocator, id: []const u8, options: WaitOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/wait");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.condition) |condition| try builder.add("condition", condition.queryValue());

    return builder.finish();
}

fn parseWait(allocator: std.mem.Allocator, body: []const u8) !Wait {
    const parsed = try std.json.parseFromSlice(RawWait, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .status_code = parsed.value.StatusCode,
        .error_message = try dupeOptionalString(
            allocator,
            if (parsed.value.Error) |container_error| container_error.Message else null,
        ),
    };
}

fn dupeOptionalString(allocator: std.mem.Allocator, bytes: ?[]const u8) !?[]const u8 {
    if (bytes) |string| return try allocator.dupe(u8, string);
    return null;
}

test "waitPath encodes condition" {
    const path = try waitPath(std.testing.allocator, "web name", .{
        .condition = .next_exit,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/web%20name/wait?condition=next-exit", path);
}

test "parseWait owns status and error message" {
    var result = try parseWait(std.testing.allocator,
        \\{
        \\  "StatusCode": 137,
        \\  "Error": {"Message": "killed"}
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(i64, 137), result.status_code);
    try std.testing.expectEqualStrings("killed", result.error_message.?);
}
