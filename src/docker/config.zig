const std = @import("std");

const json = @import("json.zig");

const http = @import("http.zig");

const Client = @import("client.zig").Client;
const query = @import("query.zig");
const url = @import("url.zig");

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const CreateOptions = struct {
    spec: Spec,
};

pub const UpdateOptions = struct {
    version: i64,
    spec: Spec,
};

pub const ConfigList = struct {
    allocator: std.mem.Allocator,
    items: []Config,

    pub fn deinit(self: *ConfigList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Config = struct {
    id: []const u8,
    version_index: ?u64,
    created_at: ?[]const u8,
    updated_at: ?[]const u8,
    spec_name: ?[]const u8,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        freeOptional(allocator, self.created_at);
        freeOptional(allocator, self.updated_at);
        freeOptional(allocator, self.spec_name);
        self.* = undefined;
    }
};

pub const Spec = struct {
    name: ?[]const u8 = null,
    labels: ?StringMap = null,
    data: ?[]const u8 = null,
    templating: ?Driver = null,

    pub fn jsonStringify(self: Spec, writer: anytype) !void {
        try writer.write(RawSpec{
            .Name = self.name,
            .Labels = self.labels,
            .Data = self.data,
            .Templating = self.templating,
        });
    }
};

pub const Create = struct {
    allocator: std.mem.Allocator,
    id: []const u8,

    pub fn deinit(self: *Create) void {
        self.allocator.free(self.id);
        self.* = undefined;
    }
};

pub const Driver = struct {
    name: []const u8,
    options: ?StringMap = null,

    pub fn jsonStringify(self: Driver, writer: anytype) !void {
        try writer.write(RawDriver{ .Name = self.name, .Options = self.options });
    }
};

pub const StringMap = struct {
    entries: []const Pair,

    pub fn jsonStringify(self: StringMap, writer: anytype) !void {
        try writer.beginObject();
        for (self.entries) |entry| {
            try writer.objectField(entry.name);
            try writer.write(entry.value);
        }
        try writer.endObject();
    }
};

pub const Pair = struct { name: []const u8, value: []const u8 };

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !ConfigList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parseList(allocator, body);
}

pub fn create(allocator: std.mem.Allocator, client: *Client, options: CreateOptions) !Create {
    const body = try json.stringifyAlloc(allocator, options.spec);
    defer allocator.free(body);
    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = "/configs/create",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    switch (response.status()) {
        .created => {},
        .conflict => return error.ConfigNameConflict,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
    const response_body = try response.body() orelse return error.EmptyResponse;
    return parseCreate(allocator, response_body);
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, id: []const u8) !Config {
    const path = try url.pathWithSegment(allocator, "/configs/", id, "");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectConfig(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parseConfig(allocator, body);
}

pub fn remove(allocator: std.mem.Allocator, client: *Client, id: []const u8) !void {
    const path = try url.pathWithSegment(allocator, "/configs/", id, "");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .delete, .path = path });
    defer response.deinit();
    try expectNoContentConfig(response.status());
}

pub fn update(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: UpdateOptions) !void {
    const path = try updatePath(allocator, id, options.version);
    defer allocator.free(path);
    const body = try json.stringifyAlloc(allocator, options.spec);
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
        .bad_request => return error.BadParameter,
        .not_found => return error.ConfigNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

const RawSpec = struct {
    Name: ?[]const u8 = null,
    Labels: ?StringMap = null,
    Data: ?[]const u8 = null,
    Templating: ?Driver = null,
};

const RawDriver = struct {
    Name: []const u8,
    Options: ?StringMap = null,
};

const RawConfig = struct {
    ID: []const u8,
    Version: ?RawVersion = null,
    CreatedAt: ?[]const u8 = null,
    UpdatedAt: ?[]const u8 = null,
    Spec: ?RawConfigSpec = null,
};

const RawConfigSpec = struct { Name: ?[]const u8 = null };
const RawVersion = struct { Index: ?u64 = null };
const RawId = struct { ID: []const u8 };

fn parseList(allocator: std.mem.Allocator, body: []const u8) !ConfigList {
    const parsed = try std.json.parseFromSlice([]RawConfig, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    const items = try allocator.alloc(Config, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    for (parsed.value) |raw| {
        items[filled] = try configFromRaw(allocator, raw);
        filled += 1;
    }
    return .{ .allocator = allocator, .items = items };
}

fn parseConfig(allocator: std.mem.Allocator, body: []const u8) !Config {
    const parsed = try std.json.parseFromSlice(RawConfig, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return configFromRaw(allocator, parsed.value);
}

fn parseCreate(allocator: std.mem.Allocator, body: []const u8) !Create {
    const parsed = try std.json.parseFromSlice(RawId, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return .{ .allocator = allocator, .id = try allocator.dupe(u8, parsed.value.ID) };
}

fn configFromRaw(allocator: std.mem.Allocator, raw: RawConfig) !Config {
    const id = try allocator.dupe(u8, raw.ID);
    errdefer allocator.free(id);
    const created_at = try dupeOptional(allocator, raw.CreatedAt);
    errdefer freeOptional(allocator, created_at);
    const updated_at = try dupeOptional(allocator, raw.UpdatedAt);
    errdefer freeOptional(allocator, updated_at);
    const spec_name = try dupeOptional(allocator, if (raw.Spec) |spec| spec.Name else null);
    errdefer freeOptional(allocator, spec_name);
    return .{
        .id = id,
        .version_index = if (raw.Version) |version| version.Index else null,
        .created_at = created_at,
        .updated_at = updated_at,
        .spec_name = spec_name,
    };
}

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/configs");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    return builder.finish();
}

fn updatePath(allocator: std.mem.Allocator, id: []const u8, version: i64) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/configs/", id, "/update");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    try builder.addInt("version", version);
    return builder.finish();
}

fn jsonHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

fn expectOk(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn expectConfig(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .not_found => return error.ConfigNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn expectNoContentConfig(status: http.Status) !void {
    switch (status) {
        .no_content => {},
        .not_found => return error.ConfigNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |string| allocator.free(string);
}

test "config paths body and parsing" {
    const list_path = try listPath(std.testing.allocator, .{ .filters = "{\"name\":[\"app\"]}" });
    defer std.testing.allocator.free(list_path);
    try std.testing.expectEqualStrings("/configs?filters=%7B%22name%22%3A%5B%22app%22%5D%7D", list_path);

    const update_path_result = try updatePath(std.testing.allocator, "config/id", 4);
    defer std.testing.allocator.free(update_path_result);
    try std.testing.expectEqualStrings("/configs/config%2Fid/update?version=4", update_path_result);

    const body = try json.stringifyAlloc(std.testing.allocator, Spec{
        .name = "app",
        .data = "YXBw",
        .labels = .{ .entries = &.{.{ .name = "tier", .value = "config" }} },
    });
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Data\":\"YXBw\""));

    var config = try parseConfig(
        std.testing.allocator,
        "{\"ID\":\"config-id\",\"Version\":{\"Index\":2},\"Spec\":{\"Name\":\"app\"}}",
    );
    defer config.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("app", config.spec_name.?);
}
