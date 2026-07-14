const std = @import("std");

const wire = @import("info_wire.zig");

pub const Info = struct {
    arena: std.heap.ArenaAllocator,
    id: ?[]const u8,
    containers: ?u64,
    containers_running: ?u64,
    containers_paused: ?u64,
    containers_stopped: ?u64,
    images: ?u64,
    driver: ?[]const u8,
    driver_status: ?[]const DriverStatus,
    docker_root_dir: ?[]const u8,
    memory_limit_supported: ?bool,
    swap_limit_supported: ?bool,
    cpu_cfs_period_supported: ?bool,
    cpu_cfs_quota_supported: ?bool,
    cpu_shares_supported: ?bool,
    cpu_set_supported: ?bool,
    pids_limit_supported: ?bool,
    oom_kill_disable_supported: ?bool,
    ipv4_forwarding_enabled: ?bool,
    debug_enabled: ?bool,
    file_descriptor_count: ?u64,
    goroutine_count: ?u64,
    system_time: ?[]const u8,
    logging_driver: ?[]const u8,
    cgroup_driver: ?[]const u8,
    cgroup_version: ?[]const u8,
    event_listener_count: ?u64,
    kernel_version: ?[]const u8,
    operating_system: ?[]const u8,
    os_version: ?[]const u8,
    os_type: ?[]const u8,
    architecture: ?[]const u8,
    cpu_count: ?u64,
    memory_total: ?i64,
    index_server_address: ?[]const u8,
    http_proxy: ?[]const u8,
    https_proxy: ?[]const u8,
    no_proxy: ?[]const u8,
    name: ?[]const u8,
    labels: ?[]const []const u8,
    experimental_build: ?bool,
    server_version: ?[]const u8,
    default_runtime: ?[]const u8,
    live_restore_enabled: ?bool,
    isolation: ?[]const u8,
    init_binary: ?[]const u8,
    security_options: ?[]const []const u8,
    product_license: ?[]const u8,
    warnings: ?[]const []const u8,
    cdi_spec_dirs: ?[]const []const u8,

    pub const DriverStatus = struct {
        label: []const u8,
        value: []const u8,
    };

    fn init(allocator: std.mem.Allocator, raw: wire.Info) !Info {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const owned = arena.allocator();

        const id = try dupeOptionalString(owned, raw.ID);
        const driver = try dupeOptionalString(owned, raw.Driver);
        const driver_status = try dupeDriverStatus(owned, raw.DriverStatus);
        const docker_root_dir = try dupeOptionalString(owned, raw.DockerRootDir);
        const system_time = try dupeOptionalString(owned, raw.SystemTime);
        const logging_driver = try dupeOptionalString(owned, raw.LoggingDriver);
        const cgroup_driver = try dupeOptionalString(owned, raw.CgroupDriver);
        const cgroup_version = try dupeOptionalString(owned, raw.CgroupVersion);
        const kernel_version = try dupeOptionalString(owned, raw.KernelVersion);
        const operating_system = try dupeOptionalString(owned, raw.OperatingSystem);
        const os_version = try dupeOptionalString(owned, raw.OSVersion);
        const os_type = try dupeOptionalString(owned, raw.OSType);
        const architecture = try dupeOptionalString(owned, raw.Architecture);
        const index_server_address = try dupeOptionalString(owned, raw.IndexServerAddress);
        const http_proxy = try dupeOptionalString(owned, raw.HttpProxy);
        const https_proxy = try dupeOptionalString(owned, raw.HttpsProxy);
        const no_proxy = try dupeOptionalString(owned, raw.NoProxy);
        const name = try dupeOptionalString(owned, raw.Name);
        const labels = try dupeStringList(owned, raw.Labels);
        const server_version = try dupeOptionalString(owned, raw.ServerVersion);
        const default_runtime = try dupeOptionalString(owned, raw.DefaultRuntime);
        const isolation = try dupeOptionalString(owned, raw.Isolation);
        const init_binary = try dupeOptionalString(owned, raw.InitBinary);
        const security_options = try dupeStringList(owned, raw.SecurityOptions);
        const product_license = try dupeOptionalString(owned, raw.ProductLicense);
        const warnings = try dupeStringList(owned, raw.Warnings);
        const cdi_spec_dirs = try dupeStringList(owned, raw.CDISpecDirs);

        return .{
            .arena = arena,
            .id = id,
            .containers = raw.Containers,
            .containers_running = raw.ContainersRunning,
            .containers_paused = raw.ContainersPaused,
            .containers_stopped = raw.ContainersStopped,
            .images = raw.Images,
            .driver = driver,
            .driver_status = driver_status,
            .docker_root_dir = docker_root_dir,
            .memory_limit_supported = raw.MemoryLimit,
            .swap_limit_supported = raw.SwapLimit,
            .cpu_cfs_period_supported = raw.CpuCfsPeriod,
            .cpu_cfs_quota_supported = raw.CpuCfsQuota,
            .cpu_shares_supported = raw.CPUShares,
            .cpu_set_supported = raw.CPUSet,
            .pids_limit_supported = raw.PidsLimit,
            .oom_kill_disable_supported = raw.OomKillDisable,
            .ipv4_forwarding_enabled = raw.IPv4Forwarding,
            .debug_enabled = raw.Debug,
            .file_descriptor_count = raw.NFd,
            .goroutine_count = raw.NGoroutines,
            .system_time = system_time,
            .logging_driver = logging_driver,
            .cgroup_driver = cgroup_driver,
            .cgroup_version = cgroup_version,
            .event_listener_count = raw.NEventsListener,
            .kernel_version = kernel_version,
            .operating_system = operating_system,
            .os_version = os_version,
            .os_type = os_type,
            .architecture = architecture,
            .cpu_count = raw.NCPU,
            .memory_total = raw.MemTotal,
            .index_server_address = index_server_address,
            .http_proxy = http_proxy,
            .https_proxy = https_proxy,
            .no_proxy = no_proxy,
            .name = name,
            .labels = labels,
            .experimental_build = raw.ExperimentalBuild,
            .server_version = server_version,
            .default_runtime = default_runtime,
            .live_restore_enabled = raw.LiveRestoreEnabled,
            .isolation = isolation,
            .init_binary = init_binary,
            .security_options = security_options,
            .product_license = product_license,
            .warnings = warnings,
            .cdi_spec_dirs = cdi_spec_dirs,
        };
    }

    pub fn deinit(self: *Info) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn parseInfo(allocator: std.mem.Allocator, body: []const u8) !Info {
    const parsed = try std.json.parseFromSlice(wire.Info, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return Info.init(allocator, parsed.value);
}

fn dupeOptionalString(allocator: std.mem.Allocator, bytes: ?[]const u8) !?[]const u8 {
    if (bytes) |string| {
        return try allocator.dupe(u8, string);
    }
    return null;
}

fn dupeStringList(allocator: std.mem.Allocator, values: ?[][]const u8) !?[]const []const u8 {
    const source = values orelse return null;
    const owned = try allocator.alloc([]const u8, source.len);

    for (source, owned) |value, *target| {
        target.* = try allocator.dupe(u8, value);
    }

    return owned;
}

fn dupeDriverStatus(
    allocator: std.mem.Allocator,
    rows: ?[][]const []const u8,
) !?[]const Info.DriverStatus {
    const source = rows orelse return null;
    const owned = try allocator.alloc(Info.DriverStatus, source.len);

    for (source, owned) |row, *target| {
        if (row.len != 2) {
            return error.InvalidDriverStatus;
        }

        target.* = .{
            .label = try allocator.dupe(u8, row[0]),
            .value = try allocator.dupe(u8, row[1]),
        };
    }

    return owned;
}

test "parseInfo owns Docker info fields" {
    var result = try parseInfo(std.testing.allocator,
        \\{
        \\  "ID": "daemon-id",
        \\  "Containers": 6,
        \\  "ContainersRunning": 2,
        \\  "ContainersPaused": 1,
        \\  "ContainersStopped": 3,
        \\  "Images": 8,
        \\  "Driver": "overlay2",
        \\  "DriverStatus": [["Backing Filesystem", "extfs"], ["Supports d_type", "true"]],
        \\  "DockerRootDir": "/var/lib/docker",
        \\  "Plugins": {"Volume": ["local"]},
        \\  "MemoryLimit": true,
        \\  "SwapLimit": true,
        \\  "CpuCfsPeriod": true,
        \\  "CpuCfsQuota": true,
        \\  "CPUShares": true,
        \\  "CPUSet": true,
        \\  "PidsLimit": true,
        \\  "OomKillDisable": false,
        \\  "IPv4Forwarding": true,
        \\  "Debug": true,
        \\  "NFd": 42,
        \\  "NGoroutines": 33,
        \\  "SystemTime": "2026-07-02T10:11:12.123456789+08:00",
        \\  "LoggingDriver": "json-file",
        \\  "CgroupDriver": "systemd",
        \\  "CgroupVersion": "2",
        \\  "NEventsListener": 4,
        \\  "KernelVersion": "6.10.0",
        \\  "OperatingSystem": "Ubuntu 24.04 LTS",
        \\  "OSVersion": "24.04",
        \\  "OSType": "linux",
        \\  "Architecture": "x86_64",
        \\  "NCPU": 12,
        \\  "MemTotal": 8589934592,
        \\  "IndexServerAddress": "https://index.docker.io/v1/",
        \\  "RegistryConfig": null,
        \\  "GenericResources": [],
        \\  "HttpProxy": "http://proxy.example",
        \\  "HttpsProxy": "https://proxy.example",
        \\  "NoProxy": "localhost,127.0.0.1",
        \\  "Name": "docker-host",
        \\  "Labels": ["env=dev", "team=sdk"],
        \\  "ExperimentalBuild": false,
        \\  "ServerVersion": "28.3.0",
        \\  "Runtimes": {"runc": {"path": "runc"}},
        \\  "DefaultRuntime": "runc",
        \\  "Swarm": {"LocalNodeState": "inactive"},
        \\  "LiveRestoreEnabled": true,
        \\  "Isolation": "default",
        \\  "InitBinary": "docker-init",
        \\  "SecurityOptions": ["name=seccomp,profile=builtin"],
        \\  "ProductLicense": "Community Engine",
        \\  "Warnings": ["bridge-nf-call-iptables is disabled"],
        \\  "CDISpecDirs": ["/etc/cdi"]
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("daemon-id", result.id.?);
    try std.testing.expectEqual(@as(u64, 6), result.containers.?);
    try std.testing.expectEqual(@as(u64, 2), result.containers_running.?);
    try std.testing.expectEqual(@as(u64, 1), result.containers_paused.?);
    try std.testing.expectEqual(@as(u64, 3), result.containers_stopped.?);
    try std.testing.expectEqual(@as(u64, 8), result.images.?);
    try std.testing.expectEqualStrings("overlay2", result.driver.?);
    try std.testing.expectEqual(@as(usize, 2), result.driver_status.?.len);
    try std.testing.expectEqualStrings("Backing Filesystem", result.driver_status.?[0].label);
    try std.testing.expectEqualStrings("extfs", result.driver_status.?[0].value);
    try std.testing.expectEqualStrings("/var/lib/docker", result.docker_root_dir.?);
    try std.testing.expectEqual(true, result.memory_limit_supported.?);
    try std.testing.expectEqual(true, result.swap_limit_supported.?);
    try std.testing.expectEqual(true, result.cpu_cfs_period_supported.?);
    try std.testing.expectEqual(true, result.cpu_cfs_quota_supported.?);
    try std.testing.expectEqual(true, result.cpu_shares_supported.?);
    try std.testing.expectEqual(true, result.cpu_set_supported.?);
    try std.testing.expectEqual(true, result.pids_limit_supported.?);
    try std.testing.expectEqual(false, result.oom_kill_disable_supported.?);
    try std.testing.expectEqual(true, result.ipv4_forwarding_enabled.?);
    try std.testing.expectEqual(true, result.debug_enabled.?);
    try std.testing.expectEqual(@as(u64, 42), result.file_descriptor_count.?);
    try std.testing.expectEqual(@as(u64, 33), result.goroutine_count.?);
    try std.testing.expectEqualStrings("2026-07-02T10:11:12.123456789+08:00", result.system_time.?);
    try std.testing.expectEqualStrings("json-file", result.logging_driver.?);
    try std.testing.expectEqualStrings("systemd", result.cgroup_driver.?);
    try std.testing.expectEqualStrings("2", result.cgroup_version.?);
    try std.testing.expectEqual(@as(u64, 4), result.event_listener_count.?);
    try std.testing.expectEqualStrings("6.10.0", result.kernel_version.?);
    try std.testing.expectEqualStrings("Ubuntu 24.04 LTS", result.operating_system.?);
    try std.testing.expectEqualStrings("24.04", result.os_version.?);
    try std.testing.expectEqualStrings("linux", result.os_type.?);
    try std.testing.expectEqualStrings("x86_64", result.architecture.?);
    try std.testing.expectEqual(@as(u64, 12), result.cpu_count.?);
    try std.testing.expectEqual(@as(i64, 8589934592), result.memory_total.?);
    try std.testing.expectEqualStrings("https://index.docker.io/v1/", result.index_server_address.?);
    try std.testing.expectEqualStrings("http://proxy.example", result.http_proxy.?);
    try std.testing.expectEqualStrings("https://proxy.example", result.https_proxy.?);
    try std.testing.expectEqualStrings("localhost,127.0.0.1", result.no_proxy.?);
    try std.testing.expectEqualStrings("docker-host", result.name.?);
    try std.testing.expectEqual(@as(usize, 2), result.labels.?.len);
    try std.testing.expectEqualStrings("env=dev", result.labels.?[0]);
    try std.testing.expectEqual(false, result.experimental_build.?);
    try std.testing.expectEqualStrings("28.3.0", result.server_version.?);
    try std.testing.expectEqualStrings("runc", result.default_runtime.?);
    try std.testing.expectEqual(true, result.live_restore_enabled.?);
    try std.testing.expectEqualStrings("default", result.isolation.?);
    try std.testing.expectEqualStrings("docker-init", result.init_binary.?);
    try std.testing.expectEqualStrings("name=seccomp,profile=builtin", result.security_options.?[0]);
    try std.testing.expectEqualStrings("Community Engine", result.product_license.?);
    try std.testing.expectEqualStrings("bridge-nf-call-iptables is disabled", result.warnings.?[0]);
    try std.testing.expectEqualStrings("/etc/cdi", result.cdi_spec_dirs.?[0]);
}

test "parseInfo keeps absent fields as null" {
    var result = try parseInfo(std.testing.allocator,
        \\{
        \\  "ID": "daemon-id",
        \\  "Name": "docker-host",
        \\  "ServerVersion": "28.3.0"
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("daemon-id", result.id.?);
    try std.testing.expectEqualStrings("docker-host", result.name.?);
    try std.testing.expectEqualStrings("28.3.0", result.server_version.?);
    try std.testing.expectEqual(@as(?u64, null), result.containers);
    try std.testing.expectEqual(@as(?bool, null), result.memory_limit_supported);
    try std.testing.expectEqual(@as(?[]const Info.DriverStatus, null), result.driver_status);
    try std.testing.expectEqual(@as(?[]const []const u8, null), result.labels);
}

test "parseInfo rejects malformed driver status rows" {
    try std.testing.expectError(error.InvalidDriverStatus, parseInfo(std.testing.allocator,
        \\{
        \\  "DriverStatus": [["missing value"]]
        \\}
    ));
}

test "parseInfo cleans up allocation failures" {
    const body =
        \\{
        \\  "ID": "daemon-id",
        \\  "Driver": "overlay2",
        \\  "DriverStatus": [["Backing Filesystem", "extfs"], ["Supports d_type", "true"]],
        \\  "Labels": ["env=dev", "team=sdk"],
        \\  "SecurityOptions": ["name=seccomp,profile=builtin"],
        \\  "Warnings": ["bridge-nf-call-iptables is disabled"],
        \\  "CDISpecDirs": ["/etc/cdi"]
        \\}
    ;

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseInfoForAllocationFailure,
        .{body},
    );
}

fn parseInfoForAllocationFailure(allocator: std.mem.Allocator, body: []const u8) !void {
    var result = try parseInfo(allocator, body);
    result.deinit();
}
