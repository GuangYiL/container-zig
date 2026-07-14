const std = @import("std");

const json = @import("../json.zig");

const model = @import("model.zig");

const RawSwarm = struct {
    ID: []const u8,
    Version: ?RawVersion = null,
    CreatedAt: ?[]const u8 = null,
    UpdatedAt: ?[]const u8 = null,
    Spec: ?RawSpec = null,
    TLSInfo: ?RawTlsInfo = null,
    RootRotationInProgress: ?bool = null,
    DataPathPort: ?u32 = null,
    DefaultAddrPool: ?[]const []const u8 = null,
    SubnetSize: ?u32 = null,
    JoinTokens: ?RawJoinTokens = null,
};

const RawVersion = struct { Index: ?u64 = null };

const RawSpec = struct {
    Name: ?[]const u8 = null,
    Labels: ?std.json.ArrayHashMap([]const u8) = null,
    Orchestration: ?RawOrchestration = null,
    Raft: ?RawRaft = null,
    Dispatcher: ?RawDispatcher = null,
    CAConfig: ?RawCaConfig = null,
    EncryptionConfig: ?RawEncryptionConfig = null,
    TaskDefaults: ?RawTaskDefaults = null,
};

const RawOrchestration = struct { TaskHistoryRetentionLimit: ?i64 = null };
const RawDispatcher = struct { HeartbeatPeriod: ?i64 = null };
const RawEncryptionConfig = struct { AutoLockManagers: ?bool = null };
const RawVersionedString = struct { UnlockKey: []const u8 };

const RawRaft = struct {
    SnapshotInterval: ?u64 = null,
    KeepOldSnapshots: ?u64 = null,
    LogEntriesForSlowFollowers: ?u64 = null,
    ElectionTick: ?i64 = null,
    HeartbeatTick: ?i64 = null,
};

const RawCaConfig = struct {
    NodeCertExpiry: ?i64 = null,
    ExternalCAs: ?[]RawExternalCa = null,
    SigningCACert: ?[]const u8 = null,
    SigningCAKey: ?[]const u8 = null,
    ForceRotate: ?u64 = null,
};

const RawExternalCa = struct {
    Protocol: ?[]const u8 = null,
    URL: ?[]const u8 = null,
    Options: ?std.json.ArrayHashMap([]const u8) = null,
    CACert: ?[]const u8 = null,
};

const RawTaskDefaults = struct {
    LogDriver: ?RawLogDriver = null,
};

const RawLogDriver = struct {
    Name: ?[]const u8 = null,
    Options: ?std.json.ArrayHashMap([]const u8) = null,
};

const RawTlsInfo = struct {
    TrustRoot: ?[]const u8 = null,
    CertIssuerSubject: ?[]const u8 = null,
    CertIssuerPublicKey: ?[]const u8 = null,
};

const RawJoinTokens = struct {
    Worker: ?[]const u8 = null,
    Manager: ?[]const u8 = null,
};

pub fn parseSwarm(allocator: std.mem.Allocator, body: []const u8) !model.Swarm {
    const parsed = try std.json.parseFromSlice(RawSwarm, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return swarmFromRaw(allocator, parsed.value);
}

pub fn parseInit(allocator: std.mem.Allocator, body: []const u8) !model.Init {
    const parsed = try std.json.parseFromSlice([]const u8, allocator, body, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    return .{ .allocator = allocator, .node_id = try allocator.dupe(u8, parsed.value) };
}

pub fn parseUnlockKey(allocator: std.mem.Allocator, body: []const u8) !model.UnlockKey {
    const parsed = try std.json.parseFromSlice(RawVersionedString, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return .{ .allocator = allocator, .value = try allocator.dupe(u8, parsed.value.UnlockKey) };
}

fn swarmFromRaw(allocator: std.mem.Allocator, raw: RawSwarm) !model.Swarm {
    const id = try allocator.dupe(u8, raw.ID);
    errdefer allocator.free(id);
    const created_at = try dupeOptional(allocator, raw.CreatedAt);
    errdefer model.freeOptional(allocator, created_at);
    const updated_at = try dupeOptional(allocator, raw.UpdatedAt);
    errdefer model.freeOptional(allocator, updated_at);
    var spec = try specFromRaw(allocator, raw.Spec);
    errdefer if (spec) |*value| value.deinit(allocator);
    var tls_info = try tlsInfoFromRaw(allocator, raw.TLSInfo);
    errdefer if (tls_info) |*value| value.deinit(allocator);
    const default_addr_pool = try dupeOptionalStrings(allocator, raw.DefaultAddrPool);
    errdefer freeStrings(allocator, default_addr_pool);
    var join_tokens = try joinTokensFromRaw(allocator, raw.JoinTokens);
    errdefer if (join_tokens) |*value| value.deinit(allocator);
    return .{
        .allocator = allocator,
        .id = id,
        .version_index = if (raw.Version) |version| version.Index else null,
        .created_at = created_at,
        .updated_at = updated_at,
        .spec = spec,
        .tls_info = tls_info,
        .root_rotation_in_progress = raw.RootRotationInProgress,
        .data_path_port = raw.DataPathPort,
        .default_addr_pool = default_addr_pool,
        .subnet_size = raw.SubnetSize,
        .join_tokens = join_tokens,
    };
}

fn specFromRaw(allocator: std.mem.Allocator, raw: ?RawSpec) !?model.Spec {
    const value = raw orelse return null;
    const name = try dupeOptional(allocator, value.Name);
    errdefer model.freeOptional(allocator, name);
    const labels = try mapFromRaw(allocator, value.Labels);
    errdefer if (labels) |label_map| model.freeMap(allocator, label_map);
    var ca_config = try caConfigFromRaw(allocator, value.CAConfig);
    errdefer if (ca_config) |*item| item.deinit(allocator);
    var task_defaults = try taskDefaultsFromRaw(allocator, value.TaskDefaults);
    errdefer if (task_defaults) |*item| item.deinit(allocator);
    return .{
        .name = name,
        .labels = labels,
        .orchestration = if (value.Orchestration) |item| .{
            .task_history_retention_limit = item.TaskHistoryRetentionLimit,
        } else null,
        .raft = if (value.Raft) |item| .{
            .snapshot_interval = item.SnapshotInterval,
            .keep_old_snapshots = item.KeepOldSnapshots,
            .log_entries_for_slow_followers = item.LogEntriesForSlowFollowers,
            .election_tick = item.ElectionTick,
            .heartbeat_tick = item.HeartbeatTick,
        } else null,
        .dispatcher = if (value.Dispatcher) |item| .{ .heartbeat_period = item.HeartbeatPeriod } else null,
        .ca_config = ca_config,
        .encryption_config = if (value.EncryptionConfig) |item| .{
            .auto_lock_managers = item.AutoLockManagers,
        } else null,
        .task_defaults = task_defaults,
    };
}

fn caConfigFromRaw(allocator: std.mem.Allocator, raw: ?RawCaConfig) !?model.CaConfig {
    const value = raw orelse return null;
    const external_cas = try externalCasFromRaw(allocator, value.ExternalCAs);
    errdefer if (external_cas) |items| {
        for (items) |item| {
            model.freeOptional(allocator, item.protocol);
            model.freeOptional(allocator, item.url);
            if (item.options) |options| model.freeMap(allocator, options);
            model.freeOptional(allocator, item.ca_cert);
        }
        allocator.free(items);
    };
    const signing_ca_cert = try dupeOptional(allocator, value.SigningCACert);
    errdefer model.freeOptional(allocator, signing_ca_cert);
    const signing_ca_key = try dupeOptional(allocator, value.SigningCAKey);
    errdefer model.freeOptional(allocator, signing_ca_key);
    return .{
        .node_cert_expiry = value.NodeCertExpiry,
        .external_cas = external_cas,
        .signing_ca_cert = signing_ca_cert,
        .signing_ca_key = signing_ca_key,
        .force_rotate = value.ForceRotate,
    };
}

fn externalCasFromRaw(allocator: std.mem.Allocator, raw_values: ?[]RawExternalCa) !?[]model.ExternalCa {
    const source = raw_values orelse return null;
    const values = try allocator.alloc(model.ExternalCa, source.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |value| {
            model.freeOptional(allocator, value.protocol);
            model.freeOptional(allocator, value.url);
            if (value.options) |options| model.freeMap(allocator, options);
            model.freeOptional(allocator, value.ca_cert);
        }
        allocator.free(values);
    }
    for (source) |raw| {
        values[filled] = try externalCaFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn externalCaFromRaw(allocator: std.mem.Allocator, raw: RawExternalCa) !model.ExternalCa {
    const protocol = try dupeOptional(allocator, raw.Protocol);
    errdefer model.freeOptional(allocator, protocol);
    const ca_url = try dupeOptional(allocator, raw.URL);
    errdefer model.freeOptional(allocator, ca_url);
    const options = try mapFromRaw(allocator, raw.Options);
    errdefer if (options) |option_map| model.freeMap(allocator, option_map);
    const ca_cert = try dupeOptional(allocator, raw.CACert);
    errdefer model.freeOptional(allocator, ca_cert);
    return .{ .protocol = protocol, .url = ca_url, .options = options, .ca_cert = ca_cert };
}

fn taskDefaultsFromRaw(allocator: std.mem.Allocator, raw: ?RawTaskDefaults) !?model.TaskDefaults {
    const value = raw orelse return null;
    var log_driver = try logDriverFromRaw(allocator, value.LogDriver);
    errdefer if (log_driver) |*item| item.deinit(allocator);
    return .{ .log_driver = log_driver };
}

fn logDriverFromRaw(allocator: std.mem.Allocator, raw: ?RawLogDriver) !?model.LogDriver {
    const value = raw orelse return null;
    const name = try dupeOptional(allocator, value.Name);
    errdefer model.freeOptional(allocator, name);
    const options = try mapFromRaw(allocator, value.Options);
    errdefer if (options) |option_map| model.freeMap(allocator, option_map);
    return .{ .name = name, .options = options };
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

fn joinTokensFromRaw(allocator: std.mem.Allocator, raw: ?RawJoinTokens) !?model.JoinTokens {
    const value = raw orelse return null;
    const worker = try dupeOptional(allocator, value.Worker);
    errdefer model.freeOptional(allocator, worker);
    const manager = try dupeOptional(allocator, value.Manager);
    errdefer model.freeOptional(allocator, manager);
    return .{ .worker = worker, .manager = manager };
}

fn mapFromRaw(allocator: std.mem.Allocator, raw: ?std.json.ArrayHashMap([]const u8)) !?model.StringMap {
    const map = raw orelse return null;
    const entries = try allocator.alloc(model.Pair, map.map.count());
    var filled: usize = 0;
    errdefer {
        for (entries[0..filled]) |entry| {
            allocator.free(entry.name);
            allocator.free(entry.value);
        }
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

fn freeStrings(allocator: std.mem.Allocator, values: []const []const u8) void {
    model.freeStringList(allocator, values);
    allocator.free(values);
}
