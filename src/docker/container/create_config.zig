const std = @import("std");

const resources = @import("resources.zig");

pub const Body = struct {
    image: []const u8,
    hostname: ?[]const u8 = null,
    domain_name: ?[]const u8 = null,
    user: ?[]const u8 = null,
    attach_stdin: ?bool = null,
    attach_stdout: ?bool = null,
    attach_stderr: ?bool = null,
    exposed_ports: ?ObjectSet = null,
    tty: ?bool = null,
    open_stdin: ?bool = null,
    stdin_once: ?bool = null,
    env: ?[]const []const u8 = null,
    cmd: ?[]const []const u8 = null,
    entrypoint: ?[]const []const u8 = null,
    labels: ?StringMap = null,
    volumes: ?ObjectSet = null,
    working_dir: ?[]const u8 = null,
    network_disabled: ?bool = null,
    stop_signal: ?[]const u8 = null,
    stop_timeout: ?i64 = null,
    shell: ?[]const []const u8 = null,
    host_config: ?HostConfig = null,
    networking_config: ?NetworkingConfig = null,

    pub fn jsonStringify(self: Body, writer: anytype) !void {
        try writer.write(RawBody{
            .Hostname = self.hostname,
            .Domainname = self.domain_name,
            .User = self.user,
            .AttachStdin = self.attach_stdin,
            .AttachStdout = self.attach_stdout,
            .AttachStderr = self.attach_stderr,
            .ExposedPorts = self.exposed_ports,
            .Tty = self.tty,
            .OpenStdin = self.open_stdin,
            .StdinOnce = self.stdin_once,
            .Env = self.env,
            .Cmd = self.cmd,
            .Image = self.image,
            .Volumes = self.volumes,
            .WorkingDir = self.working_dir,
            .Entrypoint = self.entrypoint,
            .NetworkDisabled = self.network_disabled,
            .Labels = self.labels,
            .StopSignal = self.stop_signal,
            .StopTimeout = self.stop_timeout,
            .Shell = self.shell,
            .HostConfig = self.host_config,
            .NetworkingConfig = self.networking_config,
        });
    }
};

pub const HostConfig = struct {
    resources: resources.Resources = .{},
    binds: ?[]const []const u8 = null,
    container_id_file: ?[]const u8 = null,
    network_mode: ?[]const u8 = null,
    restart_policy: ?resources.RestartPolicy = null,
    auto_remove: ?bool = null,
    volume_driver: ?[]const u8 = null,
    volumes_from: ?[]const []const u8 = null,
    cap_add: ?[]const []const u8 = null,
    cap_drop: ?[]const []const u8 = null,
    dns: ?[]const []const u8 = null,
    dns_options: ?[]const []const u8 = null,
    dns_search: ?[]const []const u8 = null,
    extra_hosts: ?[]const []const u8 = null,
    group_add: ?[]const []const u8 = null,
    links: ?[]const []const u8 = null,
    pid_mode: ?[]const u8 = null,
    privileged: ?bool = null,
    publish_all_ports: ?bool = null,
    readonly_rootfs: ?bool = null,
    security_opt: ?[]const []const u8 = null,
    storage_opt: ?StringMap = null,
    tmpfs: ?StringMap = null,
    uts_mode: ?[]const u8 = null,
    userns_mode: ?[]const u8 = null,
    shm_size: ?i64 = null,
    sysctls: ?StringMap = null,
    runtime: ?[]const u8 = null,
    isolation: ?[]const u8 = null,

    pub fn jsonStringify(self: HostConfig, writer: anytype) !void {
        try writer.beginObject();
        try resources.writeFields(writer, self.resources);
        try resources.writeOptionalField(writer, "Binds", self.binds);
        try resources.writeOptionalField(writer, "ContainerIDFile", self.container_id_file);
        try resources.writeOptionalField(writer, "NetworkMode", self.network_mode);
        try resources.writeOptionalField(writer, "RestartPolicy", self.restart_policy);
        try resources.writeOptionalField(writer, "AutoRemove", self.auto_remove);
        try resources.writeOptionalField(writer, "VolumeDriver", self.volume_driver);
        try resources.writeOptionalField(writer, "VolumesFrom", self.volumes_from);
        try resources.writeOptionalField(writer, "CapAdd", self.cap_add);
        try resources.writeOptionalField(writer, "CapDrop", self.cap_drop);
        try resources.writeOptionalField(writer, "Dns", self.dns);
        try resources.writeOptionalField(writer, "DnsOptions", self.dns_options);
        try resources.writeOptionalField(writer, "DnsSearch", self.dns_search);
        try resources.writeOptionalField(writer, "ExtraHosts", self.extra_hosts);
        try resources.writeOptionalField(writer, "GroupAdd", self.group_add);
        try resources.writeOptionalField(writer, "Links", self.links);
        try resources.writeOptionalField(writer, "PidMode", self.pid_mode);
        try resources.writeOptionalField(writer, "Privileged", self.privileged);
        try resources.writeOptionalField(writer, "PublishAllPorts", self.publish_all_ports);
        try resources.writeOptionalField(writer, "ReadonlyRootfs", self.readonly_rootfs);
        try resources.writeOptionalField(writer, "SecurityOpt", self.security_opt);
        try resources.writeOptionalField(writer, "StorageOpt", self.storage_opt);
        try resources.writeOptionalField(writer, "Tmpfs", self.tmpfs);
        try resources.writeOptionalField(writer, "UTSMode", self.uts_mode);
        try resources.writeOptionalField(writer, "UsernsMode", self.userns_mode);
        try resources.writeOptionalField(writer, "ShmSize", self.shm_size);
        try resources.writeOptionalField(writer, "Sysctls", self.sysctls);
        try resources.writeOptionalField(writer, "Runtime", self.runtime);
        try resources.writeOptionalField(writer, "Isolation", self.isolation);
        try writer.endObject();
    }
};

pub const NetworkingConfig = struct {
    endpoints: ?[]const Endpoint = null,

    pub const Endpoint = struct {
        name: []const u8,
        settings: EndpointSettings = .{},
    };

    pub const EndpointSettings = struct {
        aliases: ?[]const []const u8 = null,
        links: ?[]const []const u8 = null,
        driver_opts: ?StringMap = null,
        ipv4_address: ?[]const u8 = null,
        ipv6_address: ?[]const u8 = null,

        pub fn jsonStringify(self: EndpointSettings, writer: anytype) !void {
            try writer.write(RawEndpointSettings{
                .Aliases = self.aliases,
                .Links = self.links,
                .DriverOpts = self.driver_opts,
                .IPAMConfig = endpointIpam(self),
            });
        }
    };

    pub fn jsonStringify(self: NetworkingConfig, writer: anytype) !void {
        try writer.beginObject();
        if (self.endpoints) |endpoints| {
            try writer.objectField("EndpointsConfig");
            try writer.beginObject();
            for (endpoints) |endpoint| {
                try writer.objectField(endpoint.name);
                try endpoint.settings.jsonStringify(writer);
            }
            try writer.endObject();
        }
        try writer.endObject();
    }
};

pub const StringPair = struct {
    name: []const u8,
    value: []const u8,
};

pub const StringMap = struct {
    entries: []const StringPair,

    pub fn jsonStringify(self: StringMap, writer: anytype) !void {
        try writer.beginObject();
        for (self.entries) |entry| {
            try writer.objectField(entry.name);
            try writer.write(entry.value);
        }
        try writer.endObject();
    }
};

pub const ObjectSet = struct {
    names: []const []const u8,

    pub fn jsonStringify(self: ObjectSet, writer: anytype) !void {
        try writer.beginObject();
        for (self.names) |name| {
            try writer.objectField(name);
            try writer.beginObject();
            try writer.endObject();
        }
        try writer.endObject();
    }
};

const RawBody = struct {
    Hostname: ?[]const u8 = null,
    Domainname: ?[]const u8 = null,
    User: ?[]const u8 = null,
    AttachStdin: ?bool = null,
    AttachStdout: ?bool = null,
    AttachStderr: ?bool = null,
    ExposedPorts: ?ObjectSet = null,
    Tty: ?bool = null,
    OpenStdin: ?bool = null,
    StdinOnce: ?bool = null,
    Env: ?[]const []const u8 = null,
    Cmd: ?[]const []const u8 = null,
    Image: []const u8,
    Volumes: ?ObjectSet = null,
    WorkingDir: ?[]const u8 = null,
    Entrypoint: ?[]const []const u8 = null,
    NetworkDisabled: ?bool = null,
    Labels: ?StringMap = null,
    StopSignal: ?[]const u8 = null,
    StopTimeout: ?i64 = null,
    Shell: ?[]const []const u8 = null,
    HostConfig: ?HostConfig = null,
    NetworkingConfig: ?NetworkingConfig = null,
};

const RawEndpointSettings = struct {
    Aliases: ?[]const []const u8 = null,
    Links: ?[]const []const u8 = null,
    DriverOpts: ?StringMap = null,
    IPAMConfig: ?RawEndpointIpam = null,
};

const RawEndpointIpam = struct {
    IPv4Address: ?[]const u8 = null,
    IPv6Address: ?[]const u8 = null,
};

fn endpointIpam(settings: NetworkingConfig.EndpointSettings) ?RawEndpointIpam {
    if (settings.ipv4_address == null and settings.ipv6_address == null) return null;
    return .{
        .IPv4Address = settings.ipv4_address,
        .IPv6Address = settings.ipv6_address,
    };
}

fn stringify(allocator: std.mem.Allocator, body: anytype) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, body, .{
        .emit_null_optional_fields = false,
    });
}

test "Body stringify maps public names to Docker fields" {
    const body = try stringify(std.testing.allocator, Body{
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

test "NetworkingConfig stringify maps endpoint settings" {
    const body = try stringify(std.testing.allocator, Body{
        .image = "ubuntu",
        .networking_config = .{
            .endpoints = &.{
                .{
                    .name = "isolated_nw",
                    .settings = .{
                        .aliases = &.{"server_x"},
                        .ipv4_address = "172.20.30.33",
                    },
                },
            },
        },
    });
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"EndpointsConfig\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"isolated_nw\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"IPv4Address\":\"172.20.30.33\""));
}
