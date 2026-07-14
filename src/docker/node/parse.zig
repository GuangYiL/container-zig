const std = @import("std");

const json = @import("../json.zig");

const model = @import("model.zig");

const RawNode = struct {
    ID: []const u8,
    Version: ?RawVersion = null,
    CreatedAt: ?[]const u8 = null,
    UpdatedAt: ?[]const u8 = null,
    Spec: ?RawNodeSpec = null,
    Description: ?RawDescription = null,
    Status: ?RawStatus = null,
    ManagerStatus: ?RawManagerStatus = null,
};

const RawVersion = struct { Index: ?u64 = null };

const RawNodeSpec = struct {
    Name: ?[]const u8 = null,
    Labels: ?std.json.ArrayHashMap([]const u8) = null,
    Role: ?[]const u8 = null,
    Availability: ?[]const u8 = null,
};

const RawDescription = struct {
    Hostname: ?[]const u8 = null,
    Platform: ?RawPlatform = null,
    Resources: ?RawResources = null,
    Engine: ?RawEngine = null,
    TLSInfo: ?RawTlsInfo = null,
};

const RawPlatform = struct {
    Architecture: ?[]const u8 = null,
    OS: ?[]const u8 = null,
};

const RawResources = struct {
    NanoCPUs: ?i64 = null,
    MemoryBytes: ?i64 = null,
    GenericResources: ?[]RawGenericResource = null,
};

const RawGenericResource = struct {
    NamedResourceSpec: ?RawNamedResource = null,
    DiscreteResourceSpec: ?RawDiscreteResource = null,
};

const RawNamedResource = struct {
    Kind: []const u8,
    Value: []const u8,
};

const RawDiscreteResource = struct {
    Kind: []const u8,
    Value: i64,
};

const RawEngine = struct {
    EngineVersion: ?[]const u8 = null,
    Labels: ?std.json.ArrayHashMap([]const u8) = null,
    Plugins: ?[]RawEnginePlugin = null,
};

const RawEnginePlugin = struct {
    Type: ?[]const u8 = null,
    Name: ?[]const u8 = null,
};

const RawTlsInfo = struct {
    TrustRoot: ?[]const u8 = null,
    CertIssuerSubject: ?[]const u8 = null,
    CertIssuerPublicKey: ?[]const u8 = null,
};

const RawStatus = struct {
    State: ?[]const u8 = null,
    Message: ?[]const u8 = null,
    Addr: ?[]const u8 = null,
};

const RawManagerStatus = struct {
    Leader: ?bool = null,
    Reachability: ?[]const u8 = null,
    Addr: ?[]const u8 = null,
};

pub fn parseList(allocator: std.mem.Allocator, body: []const u8) !model.NodeList {
    const parsed = try std.json.parseFromSlice([]RawNode, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    const items = try allocator.alloc(model.Node, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit();
        allocator.free(items);
    }
    for (parsed.value) |raw| {
        items[filled] = try nodeFromRaw(allocator, raw);
        filled += 1;
    }
    return .{ .allocator = allocator, .items = items };
}

pub fn parseNode(allocator: std.mem.Allocator, body: []const u8) !model.Node {
    const parsed = try std.json.parseFromSlice(RawNode, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return nodeFromRaw(allocator, parsed.value);
}

fn nodeFromRaw(allocator: std.mem.Allocator, raw: RawNode) !model.Node {
    const id = try allocator.dupe(u8, raw.ID);
    errdefer allocator.free(id);
    const created_at = try dupeOptional(allocator, raw.CreatedAt);
    errdefer model.freeOptional(allocator, created_at);
    const updated_at = try dupeOptional(allocator, raw.UpdatedAt);
    errdefer model.freeOptional(allocator, updated_at);
    var spec = try specFromRaw(allocator, raw.Spec);
    errdefer if (spec) |*value| value.deinit(allocator);
    var description = try descriptionFromRaw(allocator, raw.Description);
    errdefer if (description) |*value| value.deinit(allocator);
    var status = try statusFromRaw(allocator, raw.Status);
    errdefer if (status) |*value| value.deinit(allocator);
    var manager_status = try managerStatusFromRaw(allocator, raw.ManagerStatus);
    errdefer if (manager_status) |*value| value.deinit(allocator);

    return .{
        .allocator = allocator,
        .id = id,
        .version_index = if (raw.Version) |version| version.Index else null,
        .created_at = created_at,
        .updated_at = updated_at,
        .spec = spec,
        .description = description,
        .status = status,
        .manager_status = manager_status,
    };
}

fn specFromRaw(allocator: std.mem.Allocator, raw: ?RawNodeSpec) !?model.NodeSpec {
    const value = raw orelse return null;
    const name = try dupeOptional(allocator, value.Name);
    errdefer model.freeOptional(allocator, name);
    const labels = try mapFromRaw(allocator, value.Labels);
    errdefer if (labels) |label_map| freeMap(allocator, label_map);
    return .{
        .name = name,
        .labels = labels,
        .role = try roleFromRaw(value.Role),
        .availability = try availabilityFromRaw(value.Availability),
    };
}

fn descriptionFromRaw(allocator: std.mem.Allocator, raw: ?RawDescription) !?model.Description {
    const value = raw orelse return null;
    const hostname = try dupeOptional(allocator, value.Hostname);
    errdefer model.freeOptional(allocator, hostname);
    var platform = try platformFromRaw(allocator, value.Platform);
    errdefer if (platform) |*item| item.deinit(allocator);
    var resources = try resourcesFromRaw(allocator, value.Resources);
    errdefer if (resources) |*item| item.deinit(allocator);
    var engine = try engineFromRaw(allocator, value.Engine);
    errdefer if (engine) |*item| item.deinit(allocator);
    var tls_info = try tlsInfoFromRaw(allocator, value.TLSInfo);
    errdefer if (tls_info) |*item| item.deinit(allocator);
    return .{
        .hostname = hostname,
        .platform = platform,
        .resources = resources,
        .engine = engine,
        .tls_info = tls_info,
    };
}

fn platformFromRaw(allocator: std.mem.Allocator, raw: ?RawPlatform) !?model.Platform {
    const value = raw orelse return null;
    const architecture = try dupeOptional(allocator, value.Architecture);
    errdefer model.freeOptional(allocator, architecture);
    const os = try dupeOptional(allocator, value.OS);
    errdefer model.freeOptional(allocator, os);
    return .{ .architecture = architecture, .os = os };
}

fn resourcesFromRaw(allocator: std.mem.Allocator, raw: ?RawResources) !?model.Resources {
    const value = raw orelse return null;
    const generic_resources = try genericResourcesFromRaw(allocator, value.GenericResources);
    errdefer freeGenericResources(allocator, generic_resources);
    return .{ .nano_cpus = value.NanoCPUs, .memory_bytes = value.MemoryBytes, .generic_resources = generic_resources };
}

fn genericResourcesFromRaw(allocator: std.mem.Allocator, raw_values: ?[]RawGenericResource) ![]model.GenericResource {
    const source = raw_values orelse return try allocator.alloc(model.GenericResource, 0);
    const values = try allocator.alloc(model.GenericResource, source.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (source) |raw| {
        values[filled] = try genericResourceFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn genericResourceFromRaw(allocator: std.mem.Allocator, raw: RawGenericResource) !model.GenericResource {
    if (raw.NamedResourceSpec) |named| {
        const kind = try allocator.dupe(u8, named.Kind);
        errdefer allocator.free(kind);
        const value = try allocator.dupe(u8, named.Value);
        errdefer allocator.free(value);
        return .{ .named = .{ .kind = kind, .value = value } };
    }
    if (raw.DiscreteResourceSpec) |discrete| {
        const kind = try allocator.dupe(u8, discrete.Kind);
        errdefer allocator.free(kind);
        return .{ .discrete = .{ .kind = kind, .value = discrete.Value } };
    }
    return error.InvalidGenericResource;
}

fn engineFromRaw(allocator: std.mem.Allocator, raw: ?RawEngine) !?model.Engine {
    const value = raw orelse return null;
    const version = try dupeOptional(allocator, value.EngineVersion);
    errdefer model.freeOptional(allocator, version);
    const labels = try mapFromRaw(allocator, value.Labels);
    errdefer if (labels) |label_map| freeMap(allocator, label_map);
    const plugins = try enginePluginsFromRaw(allocator, value.Plugins);
    errdefer freeEnginePlugins(allocator, plugins);
    return .{ .version = version, .labels = labels, .plugins = plugins };
}

fn enginePluginsFromRaw(allocator: std.mem.Allocator, raw_values: ?[]RawEnginePlugin) ![]model.EnginePlugin {
    const source = raw_values orelse return try allocator.alloc(model.EnginePlugin, 0);
    const values = try allocator.alloc(model.EnginePlugin, source.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (source) |raw| {
        values[filled] = try enginePluginFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn enginePluginFromRaw(allocator: std.mem.Allocator, raw: RawEnginePlugin) !model.EnginePlugin {
    const plugin_type = try dupeOptional(allocator, raw.Type);
    errdefer model.freeOptional(allocator, plugin_type);
    const name = try dupeOptional(allocator, raw.Name);
    errdefer model.freeOptional(allocator, name);
    return .{ .type = plugin_type, .name = name };
}

fn tlsInfoFromRaw(allocator: std.mem.Allocator, raw: ?RawTlsInfo) !?model.TlsInfo {
    const value = raw orelse return null;
    const trust_root = try dupeOptional(allocator, value.TrustRoot);
    errdefer model.freeOptional(allocator, trust_root);
    const cert_issuer_subject = try dupeOptional(allocator, value.CertIssuerSubject);
    errdefer model.freeOptional(allocator, cert_issuer_subject);
    const cert_issuer_public_key = try dupeOptional(allocator, value.CertIssuerPublicKey);
    errdefer model.freeOptional(allocator, cert_issuer_public_key);
    return .{
        .trust_root = trust_root,
        .cert_issuer_subject = cert_issuer_subject,
        .cert_issuer_public_key = cert_issuer_public_key,
    };
}

fn statusFromRaw(allocator: std.mem.Allocator, raw: ?RawStatus) !?model.Status {
    const value = raw orelse return null;
    const message = try dupeOptional(allocator, value.Message);
    errdefer model.freeOptional(allocator, message);
    const addr = try dupeOptional(allocator, value.Addr);
    errdefer model.freeOptional(allocator, addr);
    return .{ .state = try nodeStateFromRaw(value.State), .message = message, .addr = addr };
}

fn managerStatusFromRaw(allocator: std.mem.Allocator, raw: ?RawManagerStatus) !?model.ManagerStatus {
    const value = raw orelse return null;
    const addr = try dupeOptional(allocator, value.Addr);
    errdefer model.freeOptional(allocator, addr);
    return .{ .leader = value.Leader, .reachability = try reachabilityFromRaw(value.Reachability), .addr = addr };
}

fn mapFromRaw(allocator: std.mem.Allocator, raw: ?std.json.ArrayHashMap([]const u8)) !?model.StringMap {
    const map = raw orelse return null;
    const entries = try allocator.alloc(model.Pair, map.map.count());
    var filled: usize = 0;
    errdefer {
        model.freePairs(allocator, entries[0..filled]);
        allocator.free(entries);
    }
    var iterator = map.map.iterator();
    while (iterator.next()) |entry| {
        const name = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(name);
        const value = try allocator.dupe(u8, entry.value_ptr.*);
        entries[filled] = .{ .name = name, .value = value };
        filled += 1;
    }
    return .{ .entries = entries };
}

fn roleFromRaw(value: ?[]const u8) !?model.Role {
    const text = value orelse return null;
    if (std.mem.eql(u8, text, "worker")) return .worker;
    if (std.mem.eql(u8, text, "manager")) return .manager;
    return error.UnknownNodeRole;
}

fn availabilityFromRaw(value: ?[]const u8) !?model.Availability {
    const text = value orelse return null;
    if (std.mem.eql(u8, text, "active")) return .active;
    if (std.mem.eql(u8, text, "pause")) return .pause;
    if (std.mem.eql(u8, text, "drain")) return .drain;
    return error.UnknownNodeAvailability;
}

fn nodeStateFromRaw(value: ?[]const u8) !?model.NodeState {
    const text = value orelse return null;
    if (std.mem.eql(u8, text, "unknown")) return .unknown;
    if (std.mem.eql(u8, text, "down")) return .down;
    if (std.mem.eql(u8, text, "ready")) return .ready;
    if (std.mem.eql(u8, text, "disconnected")) return .disconnected;
    return error.UnknownNodeState;
}

fn reachabilityFromRaw(value: ?[]const u8) !?model.Reachability {
    const text = value orelse return null;
    if (std.mem.eql(u8, text, "unknown")) return .unknown;
    if (std.mem.eql(u8, text, "unreachable")) return .@"unreachable";
    if (std.mem.eql(u8, text, "reachable")) return .reachable;
    return error.UnknownNodeReachability;
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn freeMap(allocator: std.mem.Allocator, map: model.StringMap) void {
    model.freePairs(allocator, map.entries);
    allocator.free(map.entries);
}

fn freeGenericResources(allocator: std.mem.Allocator, values: []model.GenericResource) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

fn freeEnginePlugins(allocator: std.mem.Allocator, values: []model.EnginePlugin) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}
