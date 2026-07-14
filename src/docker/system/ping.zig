const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;

pub const Ping = struct {
    allocator: std.mem.Allocator,
    api_version: []const u8,
    builder_version: ?[]const u8,
    experimental: bool,
    swarm: ?[]const u8,
    cache_control: ?[]const u8,
    pragma: ?[]const u8,
    os_type: ?[]const u8,
    body: ?[]const u8,

    const Fields = struct {
        api_version: []const u8,
        builder_version: ?[]const u8 = null,
        experimental: bool,
        swarm: ?[]const u8 = null,
        cache_control: ?[]const u8 = null,
        pragma: ?[]const u8 = null,
        os_type: ?[]const u8 = null,
        body: ?[]const u8 = null,
    };

    fn init(allocator: std.mem.Allocator, fields: Fields) !Ping {
        const api_version = try allocator.dupe(u8, fields.api_version);
        errdefer allocator.free(api_version);

        const builder_version = try dupeOptionalString(allocator, fields.builder_version);
        errdefer freeOptionalString(allocator, builder_version);

        const swarm = try dupeOptionalString(allocator, fields.swarm);
        errdefer freeOptionalString(allocator, swarm);

        const cache_control = try dupeOptionalString(allocator, fields.cache_control);
        errdefer freeOptionalString(allocator, cache_control);

        const pragma = try dupeOptionalString(allocator, fields.pragma);
        errdefer freeOptionalString(allocator, pragma);

        const os_type = try dupeOptionalString(allocator, fields.os_type);
        errdefer freeOptionalString(allocator, os_type);

        const body = try dupeOptionalString(allocator, fields.body);
        errdefer freeOptionalString(allocator, body);

        return .{
            .allocator = allocator,
            .api_version = api_version,
            .builder_version = builder_version,
            .experimental = fields.experimental,
            .swarm = swarm,
            .cache_control = cache_control,
            .pragma = pragma,
            .os_type = os_type,
            .body = body,
        };
    }

    pub fn deinit(self: *Ping) void {
        self.allocator.free(self.api_version);
        freeOptionalString(self.allocator, self.builder_version);
        freeOptionalString(self.allocator, self.swarm);
        freeOptionalString(self.allocator, self.cache_control);
        freeOptionalString(self.allocator, self.pragma);
        freeOptionalString(self.allocator, self.os_type);
        freeOptionalString(self.allocator, self.body);
        self.* = undefined;
    }
};

pub fn ping(allocator: std.mem.Allocator, client: *Client) !Ping {
    return requestPing(allocator, client, .head, false);
}

pub fn pingText(allocator: std.mem.Allocator, client: *Client) !Ping {
    return requestPing(allocator, client, .get, true);
}

fn requestPing(allocator: std.mem.Allocator, client: *Client, method: http.Method, include_body: bool) !Ping {
    var response = try client.request(.{
        .method = method,
        .path = "/_ping",
        .versioned = false,
    });
    defer response.deinit();

    if (response.status() != .ok) {
        return error.UnexpectedStatus;
    }

    const api_version = response.header("Api-Version") orelse return error.MissingApiVersion;
    const body = if (include_body) try response.body() else null;
    return Ping.init(allocator, .{
        .api_version = api_version,
        .builder_version = response.header("Builder-Version"),
        .experimental = parseExperimental(response.header("Docker-Experimental")),
        .swarm = response.header("Swarm"),
        .cache_control = response.header("Cache-Control"),
        .pragma = response.header("Pragma"),
        .os_type = response.header("OSType") orelse response.header("OS-Type"),
        .body = body,
    });
}

fn parseExperimental(header_value: ?[]const u8) bool {
    const header = header_value orelse return false;
    return std.ascii.eqlIgnoreCase(header, "true");
}

fn dupeOptionalString(allocator: std.mem.Allocator, bytes: ?[]const u8) !?[]const u8 {
    if (bytes) |string| {
        return try allocator.dupe(u8, string);
    }
    return null;
}

fn freeOptionalString(allocator: std.mem.Allocator, string: ?[]const u8) void {
    if (string) |owned| allocator.free(owned);
}

test "Ping owns duplicated headers and body" {
    var ping_result = try Ping.init(std.testing.allocator, .{
        .api_version = "1.55",
        .builder_version = "2",
        .experimental = true,
        .swarm = "inactive",
        .cache_control = "no-cache, no-store, must-revalidate",
        .pragma = "no-cache",
        .os_type = "linux",
        .body = "OK",
    });
    defer ping_result.deinit();

    try std.testing.expectEqualStrings("1.55", ping_result.api_version);
    try std.testing.expectEqualStrings("2", ping_result.builder_version.?);
    try std.testing.expect(ping_result.experimental);
    try std.testing.expectEqualStrings("inactive", ping_result.swarm.?);
    try std.testing.expectEqualStrings("no-cache, no-store, must-revalidate", ping_result.cache_control.?);
    try std.testing.expectEqualStrings("no-cache", ping_result.pragma.?);
    try std.testing.expectEqualStrings("linux", ping_result.os_type.?);
    try std.testing.expectEqualStrings("OK", ping_result.body.?);
}
