const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const create_config = @import("create_config.zig");

pub const CreateOptions = struct {
    name: ?[]const u8 = null,
    platform: ?[]const u8 = null,
};

pub const Create = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    warnings: []const []const u8,

    pub const Body = create_config.Body;
    pub const HostConfig = create_config.HostConfig;
    pub const NetworkingConfig = create_config.NetworkingConfig;
    pub const StringMap = create_config.StringMap;
    pub const StringPair = create_config.StringPair;
    pub const ObjectSet = create_config.ObjectSet;

    pub fn deinit(self: *Create) void {
        self.allocator.free(self.id);
        for (self.warnings) |warning| self.allocator.free(warning);
        self.allocator.free(self.warnings);
        self.* = undefined;
    }
};

pub fn create(allocator: std.mem.Allocator, client: *Client, options: CreateOptions, body: anytype) !Create {
    requireObjectBody(@TypeOf(body));

    const path = try createPath(allocator, options);
    defer allocator.free(path);

    const request_body = try createRequestBody(allocator, body);
    defer allocator.free(request_body);

    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = request_body },
    });
    defer response.deinit();

    switch (response.status()) {
        .created => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ImageNotFound,
        .conflict => return error.ContainerConflict,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const response_body = try response.body() orelse return error.EmptyResponse;
    return parseCreate(allocator, response_body);
}

const RawCreate = struct {
    Id: []const u8,
    Warnings: ?[]const []const u8 = null,
};

fn createPath(allocator: std.mem.Allocator, options: CreateOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/containers/create");
    defer builder.deinit();

    if (options.name) |name| try builder.add("name", name);
    if (options.platform) |platform| try builder.add("platform", platform);

    return builder.finish();
}

fn createRequestBody(allocator: std.mem.Allocator, body: anytype) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, body, .{
        .emit_null_optional_fields = false,
    });
}

fn jsonHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

fn parseCreate(allocator: std.mem.Allocator, body: []const u8) !Create {
    const parsed = try std.json.parseFromSlice(RawCreate, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, parsed.value.Id),
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

fn requireObjectBody(comptime Body: type) void {
    switch (@typeInfo(Body)) {
        .@"struct" => {},
        else => @compileError("Docker container create body must be a struct JSON object"),
    }
}

test "createPath encodes name and platform" {
    const path = try createPath(std.testing.allocator, .{
        .name = "web name",
        .platform = "linux/arm64/v8",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/create?name=web%20name&platform=linux%2Farm64%2Fv8",
        path,
    );
}

test "createRequestBody maps public config to Docker JSON" {
    const body = try createRequestBody(std.testing.allocator, Create.Body{
        .image = "ubuntu",
        .cmd = &.{ "date", "-u" },
        .env = &.{"FOO=bar"},
        .labels = .{ .entries = &.{
            .{ .name = "com.example.vendor", .value = "Acme" },
        } },
        .exposed_ports = .{ .names = &.{"80/tcp"} },
        .host_config = .{
            .resources = .{ .memory = 314572800 },
            .restart_policy = .{
                .name = .on_failure,
                .maximum_retry_count = 4,
            },
            .auto_remove = true,
        },
    });
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Image\":\"ubuntu\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Cmd\":[\"date\",\"-u\"]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Env\":[\"FOO=bar\"]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"ExposedPorts\":{\"80/tcp\":{}}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Memory\":314572800"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Name\":\"on-failure\""));
    try std.testing.expect(std.mem.indexOf(u8, body, "hostname") == null);
}

test "parseCreate owns id and warnings" {
    var result = try parseCreate(std.testing.allocator,
        \\{
        \\  "Id": "abc123",
        \\  "Warnings": ["platform mismatch"]
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("abc123", result.id);
    try std.testing.expectEqualStrings("platform mismatch", result.warnings[0]);
}
