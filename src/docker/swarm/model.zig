const std = @import("std");

pub const Swarm = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    version_index: ?u64,
    created_at: ?[]const u8,
    updated_at: ?[]const u8,
    spec: ?Spec,
    tls_info: ?TlsInfo,
    root_rotation_in_progress: ?bool,
    data_path_port: ?u32,
    default_addr_pool: []const []const u8,
    subnet_size: ?u32,
    join_tokens: ?JoinTokens,

    pub fn deinit(self: *Swarm) void {
        self.allocator.free(self.id);
        freeOptional(self.allocator, self.created_at);
        freeOptional(self.allocator, self.updated_at);
        if (self.spec) |*spec| spec.deinit(self.allocator);
        if (self.tls_info) |*tls_info| tls_info.deinit(self.allocator);
        freeStringList(self.allocator, self.default_addr_pool);
        self.allocator.free(self.default_addr_pool);
        if (self.join_tokens) |*join_tokens| join_tokens.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const Spec = struct {
    name: ?[]const u8 = null,
    labels: ?StringMap = null,
    orchestration: ?Orchestration = null,
    raft: ?Raft = null,
    dispatcher: ?Dispatcher = null,
    ca_config: ?CaConfig = null,
    encryption_config: ?EncryptionConfig = null,
    task_defaults: ?TaskDefaults = null,

    pub fn jsonStringify(self: Spec, writer: anytype) !void {
        try writer.write(RawSpec{
            .Name = self.name,
            .Labels = self.labels,
            .Orchestration = self.orchestration,
            .Raft = self.raft,
            .Dispatcher = self.dispatcher,
            .CAConfig = self.ca_config,
            .EncryptionConfig = self.encryption_config,
            .TaskDefaults = self.task_defaults,
        });
    }

    pub fn deinit(self: *Spec, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.name);
        if (self.labels) |labels| freeMap(allocator, labels);
        if (self.ca_config) |*ca_config| ca_config.deinit(allocator);
        if (self.task_defaults) |*task_defaults| task_defaults.deinit(allocator);
        self.* = undefined;
    }
};

pub const Orchestration = struct {
    task_history_retention_limit: ?i64 = null,

    pub fn jsonStringify(self: Orchestration, writer: anytype) !void {
        try writer.write(RawOrchestration{ .TaskHistoryRetentionLimit = self.task_history_retention_limit });
    }
};

pub const Raft = struct {
    snapshot_interval: ?u64 = null,
    keep_old_snapshots: ?u64 = null,
    log_entries_for_slow_followers: ?u64 = null,
    election_tick: ?i64 = null,
    heartbeat_tick: ?i64 = null,

    pub fn jsonStringify(self: Raft, writer: anytype) !void {
        try writer.write(RawRaft{
            .SnapshotInterval = self.snapshot_interval,
            .KeepOldSnapshots = self.keep_old_snapshots,
            .LogEntriesForSlowFollowers = self.log_entries_for_slow_followers,
            .ElectionTick = self.election_tick,
            .HeartbeatTick = self.heartbeat_tick,
        });
    }
};

pub const Dispatcher = struct {
    heartbeat_period: ?i64 = null,

    pub fn jsonStringify(self: Dispatcher, writer: anytype) !void {
        try writer.write(RawDispatcher{ .HeartbeatPeriod = self.heartbeat_period });
    }
};

pub const CaConfig = struct {
    node_cert_expiry: ?i64 = null,
    external_cas: ?[]const ExternalCa = null,
    signing_ca_cert: ?[]const u8 = null,
    signing_ca_key: ?[]const u8 = null,
    force_rotate: ?u64 = null,

    pub fn jsonStringify(self: CaConfig, writer: anytype) !void {
        try writer.write(RawCaConfig{
            .NodeCertExpiry = self.node_cert_expiry,
            .ExternalCAs = self.external_cas,
            .SigningCACert = self.signing_ca_cert,
            .SigningCAKey = self.signing_ca_key,
            .ForceRotate = self.force_rotate,
        });
    }

    pub fn deinit(self: *CaConfig, allocator: std.mem.Allocator) void {
        if (self.external_cas) |external_cas| {
            for (external_cas) |external_ca| freeExternalCa(allocator, external_ca);
            allocator.free(external_cas);
        }
        freeOptional(allocator, self.signing_ca_cert);
        freeOptional(allocator, self.signing_ca_key);
        self.* = undefined;
    }
};

pub const ExternalCa = struct {
    protocol: ?[]const u8 = null,
    url: ?[]const u8 = null,
    options: ?StringMap = null,
    ca_cert: ?[]const u8 = null,

    pub fn jsonStringify(self: ExternalCa, writer: anytype) !void {
        try writer.write(RawExternalCa{
            .Protocol = self.protocol,
            .URL = self.url,
            .Options = self.options,
            .CACert = self.ca_cert,
        });
    }

    pub fn deinit(self: *ExternalCa, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.protocol);
        freeOptional(allocator, self.url);
        if (self.options) |options| freeMap(allocator, options);
        freeOptional(allocator, self.ca_cert);
        self.* = undefined;
    }
};

pub const EncryptionConfig = struct {
    auto_lock_managers: ?bool = null,

    pub fn jsonStringify(self: EncryptionConfig, writer: anytype) !void {
        try writer.write(RawEncryptionConfig{ .AutoLockManagers = self.auto_lock_managers });
    }
};

pub const TaskDefaults = struct {
    log_driver: ?LogDriver = null,

    pub fn jsonStringify(self: TaskDefaults, writer: anytype) !void {
        try writer.write(RawTaskDefaults{ .LogDriver = self.log_driver });
    }

    pub fn deinit(self: *TaskDefaults, allocator: std.mem.Allocator) void {
        if (self.log_driver) |*log_driver| log_driver.deinit(allocator);
        self.* = undefined;
    }
};

pub const LogDriver = struct {
    name: ?[]const u8 = null,
    options: ?StringMap = null,

    pub fn jsonStringify(self: LogDriver, writer: anytype) !void {
        try writer.write(RawLogDriver{ .Name = self.name, .Options = self.options });
    }

    pub fn deinit(self: *LogDriver, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.name);
        if (self.options) |options| freeMap(allocator, options);
        self.* = undefined;
    }
};

pub const TlsInfo = struct {
    trust_root: ?[]const u8,
    cert_issuer_subject: ?[]const u8,
    cert_issuer_public_key: ?[]const u8,

    pub fn deinit(self: *TlsInfo, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.trust_root);
        freeOptional(allocator, self.cert_issuer_subject);
        freeOptional(allocator, self.cert_issuer_public_key);
        self.* = undefined;
    }
};

pub const JoinTokens = struct {
    worker: ?[]const u8,
    manager: ?[]const u8,

    pub fn deinit(self: *JoinTokens, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.worker);
        freeOptional(allocator, self.manager);
        self.* = undefined;
    }
};

pub const InitOptions = struct {
    listen_addr: ?[]const u8 = null,
    advertise_addr: ?[]const u8 = null,
    data_path_addr: ?[]const u8 = null,
    data_path_port: ?u32 = null,
    default_addr_pool: ?[]const []const u8 = null,
    force_new_cluster: ?bool = null,
    subnet_size: ?u32 = null,
    spec: ?Spec = null,

    pub fn jsonStringify(self: InitOptions, writer: anytype) !void {
        try writer.write(RawInit{
            .ListenAddr = self.listen_addr,
            .AdvertiseAddr = self.advertise_addr,
            .DataPathAddr = self.data_path_addr,
            .DataPathPort = self.data_path_port,
            .DefaultAddrPool = self.default_addr_pool,
            .ForceNewCluster = self.force_new_cluster,
            .SubnetSize = self.subnet_size,
            .Spec = self.spec,
        });
    }
};

pub const JoinOptions = struct {
    listen_addr: []const u8,
    advertise_addr: ?[]const u8 = null,
    data_path_addr: ?[]const u8 = null,
    remote_addrs: []const []const u8,
    join_token: []const u8,

    pub fn jsonStringify(self: JoinOptions, writer: anytype) !void {
        try writer.write(RawJoin{
            .ListenAddr = self.listen_addr,
            .AdvertiseAddr = self.advertise_addr,
            .DataPathAddr = self.data_path_addr,
            .RemoteAddrs = self.remote_addrs,
            .JoinToken = self.join_token,
        });
    }
};

pub const LeaveOptions = struct {
    force: ?bool = null,
};

pub const UpdateOptions = struct {
    version: i64,
    spec: Spec,
    rotate_worker_token: ?bool = null,
    rotate_manager_token: ?bool = null,
    rotate_manager_unlock_key: ?bool = null,
};

pub const UnlockOptions = struct {
    unlock_key: []const u8,

    pub fn jsonStringify(self: UnlockOptions, writer: anytype) !void {
        try writer.write(RawUnlock{ .UnlockKey = self.unlock_key });
    }
};

pub const Init = struct {
    allocator: std.mem.Allocator,
    node_id: []const u8,

    pub fn deinit(self: *Init) void {
        self.allocator.free(self.node_id);
        self.* = undefined;
    }
};

pub const UnlockKey = struct {
    allocator: std.mem.Allocator,
    value: []const u8,

    pub fn deinit(self: *UnlockKey) void {
        self.allocator.free(self.value);
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

pub const Pair = struct { name: []const u8, value: []const u8 };

const RawSpec = struct {
    Name: ?[]const u8 = null,
    Labels: ?StringMap = null,
    Orchestration: ?Orchestration = null,
    Raft: ?Raft = null,
    Dispatcher: ?Dispatcher = null,
    CAConfig: ?CaConfig = null,
    EncryptionConfig: ?EncryptionConfig = null,
    TaskDefaults: ?TaskDefaults = null,
};

const RawOrchestration = struct { TaskHistoryRetentionLimit: ?i64 = null };
const RawDispatcher = struct { HeartbeatPeriod: ?i64 = null };
const RawEncryptionConfig = struct { AutoLockManagers: ?bool = null };
const RawTaskDefaults = struct { LogDriver: ?LogDriver = null };
const RawLogDriver = struct { Name: ?[]const u8 = null, Options: ?StringMap = null };
const RawUnlock = struct { UnlockKey: []const u8 };

const RawRaft = struct {
    SnapshotInterval: ?u64 = null,
    KeepOldSnapshots: ?u64 = null,
    LogEntriesForSlowFollowers: ?u64 = null,
    ElectionTick: ?i64 = null,
    HeartbeatTick: ?i64 = null,
};

const RawCaConfig = struct {
    NodeCertExpiry: ?i64 = null,
    ExternalCAs: ?[]const ExternalCa = null,
    SigningCACert: ?[]const u8 = null,
    SigningCAKey: ?[]const u8 = null,
    ForceRotate: ?u64 = null,
};

const RawExternalCa = struct {
    Protocol: ?[]const u8 = null,
    URL: ?[]const u8 = null,
    Options: ?StringMap = null,
    CACert: ?[]const u8 = null,
};

const RawInit = struct {
    ListenAddr: ?[]const u8 = null,
    AdvertiseAddr: ?[]const u8 = null,
    DataPathAddr: ?[]const u8 = null,
    DataPathPort: ?u32 = null,
    DefaultAddrPool: ?[]const []const u8 = null,
    ForceNewCluster: ?bool = null,
    SubnetSize: ?u32 = null,
    Spec: ?Spec = null,
};

const RawJoin = struct {
    ListenAddr: []const u8,
    AdvertiseAddr: ?[]const u8 = null,
    DataPathAddr: ?[]const u8 = null,
    RemoteAddrs: []const []const u8,
    JoinToken: []const u8,
};

pub fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}

pub fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |string| allocator.free(string);
}

pub fn freeMap(allocator: std.mem.Allocator, map: StringMap) void {
    for (map.entries) |entry| {
        allocator.free(entry.name);
        allocator.free(entry.value);
    }
    allocator.free(map.entries);
}

fn freeExternalCa(allocator: std.mem.Allocator, external_ca: ExternalCa) void {
    freeOptional(allocator, external_ca.protocol);
    freeOptional(allocator, external_ca.url);
    if (external_ca.options) |options| freeMap(allocator, options);
    freeOptional(allocator, external_ca.ca_cert);
}
