const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;
const url = @import("../url.zig");
const resources = @import("resources.zig");

pub const UpdateOptions = struct {
    resources: resources.Resources = .{},
    restart_policy: ?resources.RestartPolicy = null,

    pub fn jsonStringify(self: UpdateOptions, writer: anytype) !void {
        try writer.beginObject();
        try resources.writeFields(writer, self.resources);
        try resources.writeOptionalField(writer, "RestartPolicy", self.restart_policy);
        try writer.endObject();
    }
};

pub const Update = struct {
    allocator: std.mem.Allocator,
    warnings: []const []const u8,

    pub fn deinit(self: *Update) void {
        for (self.warnings) |warning| self.allocator.free(warning);
        self.allocator.free(self.warnings);
        self.* = undefined;
    }
};

pub fn update(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: UpdateOptions) !Update {
    const path = try url.pathWithSegment(allocator, "/containers/", id, "/update");
    defer allocator.free(path);

    const body = try updateRequestBody(allocator, options);
    defer allocator.free(body);

    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const response_body = try response.body() orelse return error.EmptyResponse;
    return parseUpdate(allocator, response_body);
}

const RawUpdate = struct {
    Warnings: ?[]const []const u8 = null,
};

fn updateRequestBody(allocator: std.mem.Allocator, options: UpdateOptions) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, options, .{
        .emit_null_optional_fields = false,
    });
}

fn jsonHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

fn parseUpdate(allocator: std.mem.Allocator, body: []const u8) !Update {
    const parsed = try std.json.parseFromSlice(RawUpdate, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .warnings = try dupeStringList(allocator, parsed.value.Warnings),
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

test "update path encodes container id" {
    const path = try url.pathWithSegment(std.testing.allocator, "/containers/", "web name", "/update");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/web%20name/update", path);
}

test "updateRequestBody maps public options to Docker JSON" {
    const body = try updateRequestBody(std.testing.allocator, .{
        .resources = .{
            .cpu_shares = 512,
            .memory = 314572800,
            .memory_swap = 514288000,
        },
        .restart_policy = .{
            .name = .on_failure,
            .maximum_retry_count = 4,
        },
    });
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"CpuShares\":512"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Memory\":314572800"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"MemorySwap\":514288000"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Name\":\"on-failure\""));
    try std.testing.expect(std.mem.indexOf(u8, body, "cpu_shares") == null);
}

test "parseUpdate owns warnings" {
    var result = try parseUpdate(std.testing.allocator,
        \\{
        \\  "Warnings": ["Published ports are discarded"]
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("Published ports are discarded", result.warnings[0]);
}
