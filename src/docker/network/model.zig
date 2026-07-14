const std = @import("std");

const json = @import("../json.zig");
const wire = @import("wire.zig");

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const InspectOptions = struct {
    verbose: ?bool = null,
    scope: ?[]const u8 = null,
};

pub const CreateOptions = struct {
    name: []const u8,
    driver: ?[]const u8 = null,
    scope: ?[]const u8 = null,
    internal: ?bool = null,
    attachable: ?bool = null,
    ingress: ?bool = null,
    config_only: ?bool = null,
    config_from: ?ConfigReference = null,
    enable_ipv4: ?bool = null,
    enable_ipv6: ?bool = null,
    options: ?StringMap = null,
    labels: ?StringMap = null,

    pub fn jsonStringify(self: CreateOptions, writer: anytype) !void {
        try writer.write(RawCreateConfig{
            .Name = self.name,
            .Driver = self.driver,
            .Scope = self.scope,
            .Internal = self.internal,
            .Attachable = self.attachable,
            .Ingress = self.ingress,
            .ConfigOnly = self.config_only,
            .ConfigFrom = self.config_from,
            .EnableIPv4 = self.enable_ipv4,
            .EnableIPv6 = self.enable_ipv6,
            .Options = self.options,
            .Labels = self.labels,
        });
    }
};

pub const ConnectOptions = struct {
    container: []const u8,
    endpoint: ?EndpointConfig = null,

    pub fn jsonStringify(self: ConnectOptions, writer: anytype) !void {
        try writer.write(RawConnect{ .Container = self.container, .EndpointConfig = self.endpoint });
    }
};

pub const DisconnectOptions = struct {
    container: []const u8,
    force: ?bool = null,

    pub fn jsonStringify(self: DisconnectOptions, writer: anytype) !void {
        try writer.write(RawDisconnect{ .Container = self.container, .Force = self.force });
    }
};

pub const PruneOptions = struct {
    filters: ?[]const u8 = null,
};

pub const NetworkList = struct {
    allocator: std.mem.Allocator,
    items: []Network,

    pub fn deinit(self: *NetworkList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Network = struct {
    name: []const u8,
    id: []const u8,
    created: ?[]const u8,
    scope: []const u8,
    driver: []const u8,
    enable_ipv4: ?bool,
    enable_ipv6: bool,
    internal: bool,
    attachable: bool,
    ingress: bool,
    options: []const Pair,
    labels: []const Pair,

    pub fn deinit(self: *Network, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.id);
        if (self.created) |created| allocator.free(created);
        allocator.free(self.scope);
        allocator.free(self.driver);
        freePairs(allocator, self.options);
        allocator.free(self.options);
        freePairs(allocator, self.labels);
        allocator.free(self.labels);
        self.* = undefined;
    }
};

pub const Create = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    warning: []const u8,

    pub fn deinit(self: *Create) void {
        self.allocator.free(self.id);
        self.allocator.free(self.warning);
        self.* = undefined;
    }
};

pub const ConfigReference = struct {
    network: ?[]const u8 = null,

    pub fn jsonStringify(self: ConfigReference, writer: anytype) !void {
        try writer.write(RawConfigReference{ .Network = self.network });
    }
};

pub const EndpointConfig = struct {
    aliases: ?[]const []const u8 = null,
    links: ?[]const []const u8 = null,
    driver_options: ?StringMap = null,
    ipv4_address: ?[]const u8 = null,
    ipv6_address: ?[]const u8 = null,

    pub fn jsonStringify(self: EndpointConfig, writer: anytype) !void {
        try writer.write(RawEndpoint{
            .Aliases = self.aliases,
            .Links = self.links,
            .DriverOpts = self.driver_options,
            .IPAMConfig = endpointIpam(self),
        });
    }
};

pub const Prune = struct {
    allocator: std.mem.Allocator,
    networks_deleted: []const []const u8,

    pub fn deinit(self: *Prune) void {
        freeStringList(self.allocator, self.networks_deleted);
        self.allocator.free(self.networks_deleted);
        self.* = undefined;
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

pub const Pair = struct {
    name: []const u8,
    value: []const u8,
};

const RawCreateConfig = struct {
    Name: []const u8,
    Driver: ?[]const u8 = null,
    Scope: ?[]const u8 = null,
    Internal: ?bool = null,
    Attachable: ?bool = null,
    Ingress: ?bool = null,
    ConfigOnly: ?bool = null,
    ConfigFrom: ?ConfigReference = null,
    EnableIPv4: ?bool = null,
    EnableIPv6: ?bool = null,
    Options: ?StringMap = null,
    Labels: ?StringMap = null,
};

const RawConfigReference = struct {
    Network: ?[]const u8 = null,
};

const RawConnect = struct {
    Container: []const u8,
    EndpointConfig: ?EndpointConfig = null,
};

const RawDisconnect = struct {
    Container: []const u8,
    Force: ?bool = null,
};

const RawEndpoint = struct {
    Aliases: ?[]const []const u8 = null,
    Links: ?[]const []const u8 = null,
    DriverOpts: ?StringMap = null,
    IPAMConfig: ?RawEndpointIpam = null,
};

const RawEndpointIpam = struct {
    IPv4Address: ?[]const u8 = null,
    IPv6Address: ?[]const u8 = null,
};

pub fn parseList(allocator: std.mem.Allocator, body: []const u8) !NetworkList {
    const parsed = try std.json.parseFromSlice([]wire.Network, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    const items = try allocator.alloc(Network, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    for (parsed.value) |raw| {
        items[filled] = try networkFromRaw(allocator, raw);
        filled += 1;
    }
    return .{ .allocator = allocator, .items = items };
}

pub fn parseNetwork(allocator: std.mem.Allocator, body: []const u8) !Network {
    const parsed = try std.json.parseFromSlice(wire.Network, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return networkFromRaw(allocator, parsed.value);
}

pub fn parseCreate(allocator: std.mem.Allocator, body: []const u8) !Create {
    const parsed = try std.json.parseFromSlice(wire.Create, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, parsed.value.Id),
        .warning = try allocator.dupe(u8, parsed.value.Warning),
    };
}

pub fn parsePrune(allocator: std.mem.Allocator, body: []const u8) !Prune {
    const parsed = try std.json.parseFromSlice(wire.Prune, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return .{
        .allocator = allocator,
        .networks_deleted = try dupeStringList(allocator, parsed.value.NetworksDeleted),
    };
}

fn endpointIpam(endpoint: EndpointConfig) ?RawEndpointIpam {
    if (endpoint.ipv4_address == null and endpoint.ipv6_address == null) return null;
    return .{ .IPv4Address = endpoint.ipv4_address, .IPv6Address = endpoint.ipv6_address };
}

fn networkFromRaw(allocator: std.mem.Allocator, raw: wire.Network) !Network {
    return .{
        .name = try allocator.dupe(u8, raw.Name),
        .id = try allocator.dupe(u8, raw.Id),
        .created = try dupeOptional(allocator, raw.Created),
        .scope = try allocator.dupe(u8, raw.Scope),
        .driver = try allocator.dupe(u8, raw.Driver),
        .enable_ipv4 = raw.EnableIPv4,
        .enable_ipv6 = raw.EnableIPv6,
        .internal = raw.Internal,
        .attachable = raw.Attachable,
        .ingress = raw.Ingress,
        .options = try dupePairs(allocator, raw.Options),
        .labels = try dupePairs(allocator, raw.Labels),
    };
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn dupeStringList(allocator: std.mem.Allocator, values: ?[]const []const u8) ![]const []const u8 {
    const source = values orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, source.len);
    var filled: usize = 0;
    errdefer {
        freeStringList(allocator, owned[0..filled]);
        allocator.free(owned);
    }
    for (source) |value| {
        owned[filled] = try allocator.dupe(u8, value);
        filled += 1;
    }
    return owned;
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}

fn dupePairs(allocator: std.mem.Allocator, raw_pairs: ?std.json.ArrayHashMap([]const u8)) ![]Pair {
    const pairs = raw_pairs orelse return try allocator.alloc(Pair, 0);
    const owned = try allocator.alloc(Pair, pairs.map.count());
    var filled: usize = 0;
    errdefer {
        freePairs(allocator, owned[0..filled]);
        allocator.free(owned);
    }
    var iterator = pairs.map.iterator();
    while (iterator.next()) |entry| {
        const name = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(name);
        const value = try allocator.dupe(u8, entry.value_ptr.*);
        owned[filled] = .{ .name = name, .value = value };
        filled += 1;
    }
    return owned;
}

fn freePairs(allocator: std.mem.Allocator, pairs: []const Pair) void {
    for (pairs) |pair| {
        allocator.free(pair.name);
        allocator.free(pair.value);
    }
}

test "network request bodies use Docker field names" {
    const create_body = try json.stringifyAlloc(std.testing.allocator, CreateOptions{
        .name = "app",
        .driver = "bridge",
        .enable_ipv4 = true,
        .labels = .{ .entries = &.{.{ .name = "project", .value = "sdk" }} },
    });
    defer std.testing.allocator.free(create_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, create_body, 1, "\"EnableIPv4\":true"));

    const connect_body = try json.stringifyAlloc(std.testing.allocator, ConnectOptions{
        .container = "web",
        .endpoint = .{ .aliases = &.{"server"}, .ipv4_address = "172.20.0.10" },
    });
    defer std.testing.allocator.free(connect_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, connect_body, 1, "\"IPv4Address\":\"172.20.0.10\""));
}

test "parse network list create and prune responses" {
    var list_result = try parseList(std.testing.allocator,
        \\[{
        \\  "Name": "bridge",
        \\  "Id": "net123",
        \\  "Created": "2026-07-02T17:12:47Z",
        \\  "Scope": "local",
        \\  "Driver": "bridge",
        \\  "EnableIPv4": true,
        \\  "EnableIPv6": false,
        \\  "Internal": false,
        \\  "Attachable": false,
        \\  "Ingress": false,
        \\  "Options": {"mtu": "1500"},
        \\  "Labels": {"project": "sdk"}
        \\}]
    );
    defer list_result.deinit();
    try std.testing.expectEqualStrings("bridge", list_result.items[0].name);
    try std.testing.expectEqualStrings("mtu", list_result.items[0].options[0].name);

    var create_result = try parseCreate(std.testing.allocator, "{\"Id\":\"net123\",\"Warning\":\"\"}");
    defer create_result.deinit();
    try std.testing.expectEqualStrings("net123", create_result.id);

    var prune_result = try parsePrune(std.testing.allocator, "{\"NetworksDeleted\":[\"net123\"]}");
    defer prune_result.deinit();
    try std.testing.expectEqualStrings("net123", prune_result.networks_deleted[0]);
}
