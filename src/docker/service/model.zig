const std = @import("std");
const RegistryAuth = @import("../registry_auth.zig").RegistryAuth;

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
    status: ?bool = null,
};

pub const InspectOptions = struct {
    insert_defaults: ?bool = null,
};

pub const CreateOptions = struct {
    spec: Spec,
    registry_auth: ?RegistryAuth = null,
};

pub const UpdateOptions = struct {
    version: i64,
    spec: Spec,
    registry_auth_from: ?RegistryAuthFrom = null,
    rollback: ?Rollback = null,
    registry_auth: ?RegistryAuth = null,
};

pub const LogsOptions = struct {
    details: ?bool = null,
    follow: ?bool = null,
    stdout: ?bool = null,
    stderr: ?bool = null,
    since: ?i64 = null,
    timestamps: ?bool = null,
    tail: ?[]const u8 = null,
    max_frame_bytes: usize = 16 * 1024 * 1024,
};

pub const ServiceList = struct {
    allocator: std.mem.Allocator,
    items: []Service,

    pub fn deinit(self: *ServiceList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Service = struct {
    id: []const u8,
    version_index: ?u64,
    created_at: ?[]const u8,
    updated_at: ?[]const u8,
    spec_name: ?[]const u8,
    service_status: ?ServiceStatus,
    update_status: ?UpdateStatus,
    endpoint_ports: []Port,
    virtual_ips: []VirtualIp,

    pub fn deinit(self: *Service, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        freeOptional(allocator, self.created_at);
        freeOptional(allocator, self.updated_at);
        freeOptional(allocator, self.spec_name);
        if (self.update_status) |*status| status.deinit(allocator);
        for (self.endpoint_ports) |*port| port.deinit(allocator);
        allocator.free(self.endpoint_ports);
        for (self.virtual_ips) |*virtual_ip| virtual_ip.deinit(allocator);
        allocator.free(self.virtual_ips);
        self.* = undefined;
    }
};

pub const Create = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    warnings: []const []const u8,

    pub fn deinit(self: *Create) void {
        self.allocator.free(self.id);
        freeStringList(self.allocator, self.warnings);
        self.allocator.free(self.warnings);
        self.* = undefined;
    }
};

pub const Update = struct {
    allocator: std.mem.Allocator,
    warnings: []const []const u8,

    pub fn deinit(self: *Update) void {
        freeStringList(self.allocator, self.warnings);
        self.allocator.free(self.warnings);
        self.* = undefined;
    }
};

pub const Spec = struct {
    name: ?[]const u8 = null,
    labels: ?StringMap = null,
    task_template: ?TaskSpec = null,
    mode: ?Mode = null,
    update_config: ?UpdatePolicy = null,
    rollback_config: ?UpdatePolicy = null,
    endpoint_spec: ?EndpointSpec = null,

    pub fn jsonStringify(self: Spec, writer: anytype) !void {
        try writer.write(RawSpec{
            .Name = self.name,
            .Labels = self.labels,
            .TaskTemplate = self.task_template,
            .Mode = self.mode,
            .UpdateConfig = self.update_config,
            .RollbackConfig = self.rollback_config,
            .EndpointSpec = self.endpoint_spec,
        });
    }
};

pub const TaskSpec = struct {
    container: ?ContainerSpec = null,
    log_driver: ?LogDriver = null,
    force_update: ?u64 = null,
    runtime: ?[]const u8 = null,

    pub fn jsonStringify(self: TaskSpec, writer: anytype) !void {
        try writer.write(RawTaskSpec{
            .ContainerSpec = self.container,
            .LogDriver = self.log_driver,
            .ForceUpdate = self.force_update,
            .Runtime = self.runtime,
        });
    }
};

pub const ContainerSpec = struct {
    image: ?[]const u8 = null,
    labels: ?StringMap = null,
    command: ?[]const []const u8 = null,
    args: ?[]const []const u8 = null,
    hostname: ?[]const u8 = null,
    env: ?[]const []const u8 = null,
    dir: ?[]const u8 = null,
    user: ?[]const u8 = null,
    groups: ?[]const []const u8 = null,
    tty: ?bool = null,
    open_stdin: ?bool = null,
    read_only: ?bool = null,
    stop_signal: ?[]const u8 = null,
    stop_grace_period: ?i64 = null,
    hosts: ?[]const []const u8 = null,
    init: ?bool = null,

    pub fn jsonStringify(self: ContainerSpec, writer: anytype) !void {
        try writer.write(RawContainerSpec{
            .Image = self.image,
            .Labels = self.labels,
            .Command = self.command,
            .Args = self.args,
            .Hostname = self.hostname,
            .Env = self.env,
            .Dir = self.dir,
            .User = self.user,
            .Groups = self.groups,
            .TTY = self.tty,
            .OpenStdin = self.open_stdin,
            .ReadOnly = self.read_only,
            .StopSignal = self.stop_signal,
            .StopGracePeriod = self.stop_grace_period,
            .Hosts = self.hosts,
            .Init = self.init,
        });
    }
};

pub const Mode = struct {
    replicated: ?Replicated = null,
    global: ?EmptyObject = null,
    replicated_job: ?ReplicatedJob = null,
    global_job: ?EmptyObject = null,

    pub fn jsonStringify(self: Mode, writer: anytype) !void {
        try writer.write(RawMode{
            .Replicated = self.replicated,
            .Global = self.global,
            .ReplicatedJob = self.replicated_job,
            .GlobalJob = self.global_job,
        });
    }
};

pub const EmptyObject = struct {
    pub fn jsonStringify(_: EmptyObject, writer: anytype) !void {
        try writer.beginObject();
        try writer.endObject();
    }
};

pub const Replicated = struct { replicas: ?i64 = null };
pub const ReplicatedJob = struct { max_concurrent: ?i64 = null, total_completions: ?i64 = null };

pub const UpdatePolicy = struct {
    parallelism: ?i64 = null,
    delay: ?i64 = null,
    failure_action: ?[]const u8 = null,
    monitor: ?i64 = null,
    max_failure_ratio: ?f64 = null,
    order: ?[]const u8 = null,

    pub fn jsonStringify(self: UpdatePolicy, writer: anytype) !void {
        try writer.write(RawUpdatePolicy{
            .Parallelism = self.parallelism,
            .Delay = self.delay,
            .FailureAction = self.failure_action,
            .Monitor = self.monitor,
            .MaxFailureRatio = self.max_failure_ratio,
            .Order = self.order,
        });
    }
};

pub const EndpointSpec = struct {
    mode: ?[]const u8 = null,
    ports: ?[]const Port = null,

    pub fn jsonStringify(self: EndpointSpec, writer: anytype) !void {
        try writer.write(RawEndpointSpec{ .Mode = self.mode, .Ports = self.ports });
    }
};

pub const Port = struct {
    name: ?[]const u8 = null,
    protocol: ?[]const u8 = null,
    target_port: ?u16 = null,
    published_port: ?u16 = null,
    publish_mode: ?[]const u8 = null,

    pub fn jsonStringify(self: Port, writer: anytype) !void {
        try writer.write(RawPort{
            .Name = self.name,
            .Protocol = self.protocol,
            .TargetPort = self.target_port,
            .PublishedPort = self.published_port,
            .PublishMode = self.publish_mode,
        });
    }

    pub fn deinit(self: *Port, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.name);
        freeOptional(allocator, self.protocol);
        freeOptional(allocator, self.publish_mode);
        self.* = undefined;
    }
};

pub const LogDriver = struct {
    name: ?[]const u8 = null,
    options: ?StringMap = null,

    pub fn jsonStringify(self: LogDriver, writer: anytype) !void {
        try writer.write(RawLogDriver{ .Name = self.name, .Options = self.options });
    }
};

pub const ServiceStatus = struct { running_tasks: ?u64, desired_tasks: ?u64, completed_tasks: ?u64 };

pub const UpdateStatus = struct {
    state: ?[]const u8,
    started_at: ?[]const u8,
    completed_at: ?[]const u8,
    message: ?[]const u8,

    pub fn deinit(self: *UpdateStatus, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.state);
        freeOptional(allocator, self.started_at);
        freeOptional(allocator, self.completed_at);
        freeOptional(allocator, self.message);
        self.* = undefined;
    }
};

pub const VirtualIp = struct {
    network_id: ?[]const u8,
    addr: ?[]const u8,

    pub fn deinit(self: *VirtualIp, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.network_id);
        freeOptional(allocator, self.addr);
        self.* = undefined;
    }
};

pub const RegistryAuthFrom = enum {
    spec,
    previous_spec,

    pub fn text(self: RegistryAuthFrom) []const u8 {
        return switch (self) {
            .spec => "spec",
            .previous_spec => "previous-spec",
        };
    }
};

pub const Rollback = enum { previous };

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
    TaskTemplate: ?TaskSpec = null,
    Mode: ?Mode = null,
    UpdateConfig: ?UpdatePolicy = null,
    RollbackConfig: ?UpdatePolicy = null,
    EndpointSpec: ?EndpointSpec = null,
};

const RawTaskSpec = struct {
    ContainerSpec: ?ContainerSpec = null,
    LogDriver: ?LogDriver = null,
    ForceUpdate: ?u64 = null,
    Runtime: ?[]const u8 = null,
};

const RawContainerSpec = struct {
    Image: ?[]const u8 = null,
    Labels: ?StringMap = null,
    Command: ?[]const []const u8 = null,
    Args: ?[]const []const u8 = null,
    Hostname: ?[]const u8 = null,
    Env: ?[]const []const u8 = null,
    Dir: ?[]const u8 = null,
    User: ?[]const u8 = null,
    Groups: ?[]const []const u8 = null,
    TTY: ?bool = null,
    OpenStdin: ?bool = null,
    ReadOnly: ?bool = null,
    StopSignal: ?[]const u8 = null,
    StopGracePeriod: ?i64 = null,
    Hosts: ?[]const []const u8 = null,
    Init: ?bool = null,
};

const RawMode = struct {
    Replicated: ?Replicated = null,
    Global: ?EmptyObject = null,
    ReplicatedJob: ?ReplicatedJob = null,
    GlobalJob: ?EmptyObject = null,
};

const RawUpdatePolicy = struct {
    Parallelism: ?i64 = null,
    Delay: ?i64 = null,
    FailureAction: ?[]const u8 = null,
    Monitor: ?i64 = null,
    MaxFailureRatio: ?f64 = null,
    Order: ?[]const u8 = null,
};

const RawEndpointSpec = struct { Mode: ?[]const u8 = null, Ports: ?[]const Port = null };
const RawLogDriver = struct { Name: ?[]const u8 = null, Options: ?StringMap = null };

const RawPort = struct {
    Name: ?[]const u8 = null,
    Protocol: ?[]const u8 = null,
    TargetPort: ?u16 = null,
    PublishedPort: ?u16 = null,
    PublishMode: ?[]const u8 = null,
};

pub fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |string| allocator.free(string);
}

pub fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}
