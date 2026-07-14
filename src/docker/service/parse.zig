const std = @import("std");

const json = @import("../json.zig");

const model = @import("model.zig");

const RawService = struct {
    ID: []const u8,
    Version: ?RawVersion = null,
    CreatedAt: ?[]const u8 = null,
    UpdatedAt: ?[]const u8 = null,
    Spec: ?RawSpec = null,
    Endpoint: ?RawEndpoint = null,
    UpdateStatus: ?RawUpdateStatus = null,
    ServiceStatus: ?RawServiceStatus = null,
};

const RawVersion = struct { Index: ?u64 = null };
const RawSpec = struct { Name: ?[]const u8 = null };

const RawEndpoint = struct {
    Ports: ?[]RawPort = null,
    VirtualIPs: ?[]RawVirtualIp = null,
};

const RawPort = struct {
    Name: ?[]const u8 = null,
    Protocol: ?[]const u8 = null,
    TargetPort: ?u16 = null,
    PublishedPort: ?u16 = null,
    PublishMode: ?[]const u8 = null,
};

const RawVirtualIp = struct {
    NetworkID: ?[]const u8 = null,
    Addr: ?[]const u8 = null,
};

const RawUpdateStatus = struct {
    State: ?[]const u8 = null,
    StartedAt: ?[]const u8 = null,
    CompletedAt: ?[]const u8 = null,
    Message: ?[]const u8 = null,
};

const RawServiceStatus = struct {
    RunningTasks: ?u64 = null,
    DesiredTasks: ?u64 = null,
    CompletedTasks: ?u64 = null,
};

const RawCreate = struct {
    ID: []const u8,
    Warnings: ?[]const []const u8 = null,
};

const RawUpdate = struct {
    Warnings: ?[]const []const u8 = null,
};

pub fn parseList(allocator: std.mem.Allocator, body: []const u8) !model.ServiceList {
    const parsed = try std.json.parseFromSlice([]RawService, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    const items = try allocator.alloc(model.Service, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    for (parsed.value) |raw| {
        items[filled] = try serviceFromRaw(allocator, raw);
        filled += 1;
    }
    return .{ .allocator = allocator, .items = items };
}

pub fn parseService(allocator: std.mem.Allocator, body: []const u8) !model.Service {
    const parsed = try std.json.parseFromSlice(RawService, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return serviceFromRaw(allocator, parsed.value);
}

pub fn parseCreate(allocator: std.mem.Allocator, body: []const u8) !model.Create {
    const parsed = try std.json.parseFromSlice(RawCreate, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    const id = try allocator.dupe(u8, parsed.value.ID);
    errdefer allocator.free(id);
    const warnings = try dupeOptionalStrings(allocator, parsed.value.Warnings);
    errdefer {
        model.freeStringList(allocator, warnings);
        allocator.free(warnings);
    }
    return .{
        .allocator = allocator,
        .id = id,
        .warnings = warnings,
    };
}

pub fn parseUpdate(allocator: std.mem.Allocator, body: []const u8) !model.Update {
    const parsed = try std.json.parseFromSlice(RawUpdate, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return .{ .allocator = allocator, .warnings = try dupeOptionalStrings(allocator, parsed.value.Warnings) };
}

fn serviceFromRaw(allocator: std.mem.Allocator, raw: RawService) !model.Service {
    const id = try allocator.dupe(u8, raw.ID);
    errdefer allocator.free(id);
    const created_at = try dupeOptional(allocator, raw.CreatedAt);
    errdefer model.freeOptional(allocator, created_at);
    const updated_at = try dupeOptional(allocator, raw.UpdatedAt);
    errdefer model.freeOptional(allocator, updated_at);
    const spec_name = try dupeOptional(allocator, if (raw.Spec) |spec| spec.Name else null);
    errdefer model.freeOptional(allocator, spec_name);
    var update_status = try updateStatusFromRaw(allocator, raw.UpdateStatus);
    errdefer if (update_status) |*status| status.deinit(allocator);
    const endpoint_ports = try portsFromRaw(allocator, if (raw.Endpoint) |endpoint| endpoint.Ports else null);
    errdefer freePorts(allocator, endpoint_ports);
    const virtual_ips = try virtualIpsFromRaw(allocator, if (raw.Endpoint) |endpoint| endpoint.VirtualIPs else null);
    errdefer freeVirtualIps(allocator, virtual_ips);

    return .{
        .id = id,
        .version_index = if (raw.Version) |version| version.Index else null,
        .created_at = created_at,
        .updated_at = updated_at,
        .spec_name = spec_name,
        .service_status = if (raw.ServiceStatus) |status| .{
            .running_tasks = status.RunningTasks,
            .desired_tasks = status.DesiredTasks,
            .completed_tasks = status.CompletedTasks,
        } else null,
        .update_status = update_status,
        .endpoint_ports = endpoint_ports,
        .virtual_ips = virtual_ips,
    };
}

fn updateStatusFromRaw(allocator: std.mem.Allocator, raw: ?RawUpdateStatus) !?model.UpdateStatus {
    const value = raw orelse return null;
    const state = try dupeOptional(allocator, value.State);
    errdefer model.freeOptional(allocator, state);
    const started_at = try dupeOptional(allocator, value.StartedAt);
    errdefer model.freeOptional(allocator, started_at);
    const completed_at = try dupeOptional(allocator, value.CompletedAt);
    errdefer model.freeOptional(allocator, completed_at);
    const message = try dupeOptional(allocator, value.Message);
    errdefer model.freeOptional(allocator, message);
    return .{ .state = state, .started_at = started_at, .completed_at = completed_at, .message = message };
}

fn portsFromRaw(allocator: std.mem.Allocator, raw_values: ?[]RawPort) ![]model.Port {
    const source = raw_values orelse return try allocator.alloc(model.Port, 0);
    const values = try allocator.alloc(model.Port, source.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (source) |raw| {
        values[filled] = try portFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn portFromRaw(allocator: std.mem.Allocator, raw: RawPort) !model.Port {
    const name = try dupeOptional(allocator, raw.Name);
    errdefer model.freeOptional(allocator, name);
    const protocol = try dupeOptional(allocator, raw.Protocol);
    errdefer model.freeOptional(allocator, protocol);
    const publish_mode = try dupeOptional(allocator, raw.PublishMode);
    errdefer model.freeOptional(allocator, publish_mode);
    return .{
        .name = name,
        .protocol = protocol,
        .target_port = raw.TargetPort,
        .published_port = raw.PublishedPort,
        .publish_mode = publish_mode,
    };
}

fn virtualIpsFromRaw(allocator: std.mem.Allocator, raw_values: ?[]RawVirtualIp) ![]model.VirtualIp {
    const source = raw_values orelse return try allocator.alloc(model.VirtualIp, 0);
    const values = try allocator.alloc(model.VirtualIp, source.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (source) |raw| {
        values[filled] = try virtualIpFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn virtualIpFromRaw(allocator: std.mem.Allocator, raw: RawVirtualIp) !model.VirtualIp {
    const network_id = try dupeOptional(allocator, raw.NetworkID);
    errdefer model.freeOptional(allocator, network_id);
    const addr = try dupeOptional(allocator, raw.Addr);
    errdefer model.freeOptional(allocator, addr);
    return .{ .network_id = network_id, .addr = addr };
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn dupeOptionalStrings(allocator: std.mem.Allocator, values: ?[]const []const u8) ![]const []const u8 {
    const source = values orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, source.len);
    var filled: usize = 0;
    errdefer {
        model.freeStringList(allocator, owned[0..filled]);
        allocator.free(owned);
    }
    for (source) |value| {
        owned[filled] = try allocator.dupe(u8, value);
        filled += 1;
    }
    return owned;
}

fn freePorts(allocator: std.mem.Allocator, values: []model.Port) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

fn freeVirtualIps(allocator: std.mem.Allocator, values: []model.VirtualIp) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}
