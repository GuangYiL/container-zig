const std = @import("std");

pub const Resources = struct {
    cpu_shares: ?i64 = null,
    memory: ?i64 = null,
    cgroup_parent: ?[]const u8 = null,
    blkio_weight: ?u16 = null,
    blkio_weight_devices: ?[]const WeightDevice = null,
    blkio_device_read_bps: ?[]const ThrottleDevice = null,
    blkio_device_write_bps: ?[]const ThrottleDevice = null,
    blkio_device_read_iops: ?[]const ThrottleDevice = null,
    blkio_device_write_iops: ?[]const ThrottleDevice = null,
    cpu_period: ?i64 = null,
    cpu_quota: ?i64 = null,
    cpu_realtime_period: ?i64 = null,
    cpu_realtime_runtime: ?i64 = null,
    cpuset_cpus: ?[]const u8 = null,
    cpuset_mems: ?[]const u8 = null,
    devices: ?[]const DeviceMapping = null,
    device_cgroup_rules: ?[]const []const u8 = null,
    device_requests: ?[]const DeviceRequest = null,
    memory_reservation: ?i64 = null,
    memory_swap: ?i64 = null,
    memory_swappiness: ?i64 = null,
    nano_cpus: ?i64 = null,
    oom_kill_disable: ?bool = null,
    init: ?bool = null,
    pids_limit: ?i64 = null,
    ulimits: ?[]const Ulimit = null,
    cpu_count: ?i64 = null,
    cpu_percent: ?i64 = null,
    io_maximum_iops: ?i64 = null,
    io_maximum_bandwidth: ?i64 = null,

    pub fn jsonStringify(self: Resources, writer: anytype) !void {
        try writer.beginObject();
        try writeFields(writer, self);
        try writer.endObject();
    }
};

pub const WeightDevice = struct {
    path: ?[]const u8 = null,
    weight: ?i64 = null,

    pub fn jsonStringify(self: WeightDevice, writer: anytype) !void {
        try writer.beginObject();
        try writeOptionalField(writer, "Path", self.path);
        try writeOptionalField(writer, "Weight", self.weight);
        try writer.endObject();
    }
};

pub const ThrottleDevice = struct {
    path: ?[]const u8 = null,
    rate: ?i64 = null,

    pub fn jsonStringify(self: ThrottleDevice, writer: anytype) !void {
        try writer.beginObject();
        try writeOptionalField(writer, "Path", self.path);
        try writeOptionalField(writer, "Rate", self.rate);
        try writer.endObject();
    }
};

pub const DeviceMapping = struct {
    path_on_host: ?[]const u8 = null,
    path_in_container: ?[]const u8 = null,
    cgroup_permissions: ?[]const u8 = null,

    pub fn jsonStringify(self: DeviceMapping, writer: anytype) !void {
        try writer.beginObject();
        try writeOptionalField(writer, "PathOnHost", self.path_on_host);
        try writeOptionalField(writer, "PathInContainer", self.path_in_container);
        try writeOptionalField(writer, "CgroupPermissions", self.cgroup_permissions);
        try writer.endObject();
    }
};

pub const DeviceRequest = struct {
    driver: ?[]const u8 = null,
    count: ?i64 = null,
    device_ids: ?[]const []const u8 = null,
    capabilities: ?[]const []const []const u8 = null,
    options: ?[]const Option = null,

    pub fn jsonStringify(self: DeviceRequest, writer: anytype) !void {
        try writer.beginObject();
        try writeOptionalField(writer, "Driver", self.driver);
        try writeOptionalField(writer, "Count", self.count);
        try writeOptionalField(writer, "DeviceIDs", self.device_ids);
        try writeOptionalField(writer, "Capabilities", self.capabilities);
        if (self.options) |options| {
            try writer.objectField("Options");
            try writer.beginObject();
            for (options) |option| {
                try writer.objectField(option.name);
                try writer.write(option.value);
            }
            try writer.endObject();
        }
        try writer.endObject();
    }
};

pub const Option = struct {
    name: []const u8,
    value: []const u8,
};

pub const Ulimit = struct {
    name: ?[]const u8 = null,
    soft: ?i64 = null,
    hard: ?i64 = null,

    pub fn jsonStringify(self: Ulimit, writer: anytype) !void {
        try writer.beginObject();
        try writeOptionalField(writer, "Name", self.name);
        try writeOptionalField(writer, "Soft", self.soft);
        try writeOptionalField(writer, "Hard", self.hard);
        try writer.endObject();
    }
};

pub const RestartPolicy = struct {
    name: ?Name = null,
    maximum_retry_count: ?i64 = null,

    pub const Name = enum {
        disabled,
        no,
        always,
        unless_stopped,
        on_failure,

        pub fn jsonStringify(self: Name, writer: anytype) !void {
            try writer.write(switch (self) {
                .disabled => "",
                .no => "no",
                .always => "always",
                .unless_stopped => "unless-stopped",
                .on_failure => "on-failure",
            });
        }
    };

    pub fn jsonStringify(self: RestartPolicy, writer: anytype) !void {
        try writer.beginObject();
        try writeOptionalField(writer, "Name", self.name);
        try writeOptionalField(writer, "MaximumRetryCount", self.maximum_retry_count);
        try writer.endObject();
    }
};

pub fn writeFields(writer: anytype, resources: Resources) !void {
    try writeOptionalField(writer, "CpuShares", resources.cpu_shares);
    try writeOptionalField(writer, "Memory", resources.memory);
    try writeOptionalField(writer, "CgroupParent", resources.cgroup_parent);
    try writeOptionalField(writer, "BlkioWeight", resources.blkio_weight);
    try writeOptionalField(writer, "BlkioWeightDevice", resources.blkio_weight_devices);
    try writeOptionalField(writer, "BlkioDeviceReadBps", resources.blkio_device_read_bps);
    try writeOptionalField(writer, "BlkioDeviceWriteBps", resources.blkio_device_write_bps);
    try writeOptionalField(writer, "BlkioDeviceReadIOps", resources.blkio_device_read_iops);
    try writeOptionalField(writer, "BlkioDeviceWriteIOps", resources.blkio_device_write_iops);
    try writeOptionalField(writer, "CpuPeriod", resources.cpu_period);
    try writeOptionalField(writer, "CpuQuota", resources.cpu_quota);
    try writeOptionalField(writer, "CpuRealtimePeriod", resources.cpu_realtime_period);
    try writeOptionalField(writer, "CpuRealtimeRuntime", resources.cpu_realtime_runtime);
    try writeOptionalField(writer, "CpusetCpus", resources.cpuset_cpus);
    try writeOptionalField(writer, "CpusetMems", resources.cpuset_mems);
    try writeOptionalField(writer, "Devices", resources.devices);
    try writeOptionalField(writer, "DeviceCgroupRules", resources.device_cgroup_rules);
    try writeOptionalField(writer, "DeviceRequests", resources.device_requests);
    try writeOptionalField(writer, "MemoryReservation", resources.memory_reservation);
    try writeOptionalField(writer, "MemorySwap", resources.memory_swap);
    try writeOptionalField(writer, "MemorySwappiness", resources.memory_swappiness);
    try writeOptionalField(writer, "NanoCpus", resources.nano_cpus);
    try writeOptionalField(writer, "OomKillDisable", resources.oom_kill_disable);
    try writeOptionalField(writer, "Init", resources.init);
    try writeOptionalField(writer, "PidsLimit", resources.pids_limit);
    try writeOptionalField(writer, "Ulimits", resources.ulimits);
    try writeOptionalField(writer, "CpuCount", resources.cpu_count);
    try writeOptionalField(writer, "CpuPercent", resources.cpu_percent);
    try writeOptionalField(writer, "IOMaximumIOps", resources.io_maximum_iops);
    try writeOptionalField(writer, "IOMaximumBandwidth", resources.io_maximum_bandwidth);
}

pub fn writeOptionalField(writer: anytype, key: []const u8, value: anytype) !void {
    if (value) |payload| {
        try writer.objectField(key);
        try writer.write(payload);
    }
}

fn stringify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{
        .emit_null_optional_fields = false,
    });
}

fn expectContains(body: []const u8, expected: []const u8) !void {
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, expected));
}

test "Resources stringify uses Docker field names" {
    const body = try stringify(std.testing.allocator, Resources{
        .cpu_shares = 512,
        .memory = 314572800,
        .cpuset_cpus = "0,1",
        .oom_kill_disable = false,
        .blkio_weight_devices = &.{.{ .path = "/dev/sda", .weight = 500 }},
        .blkio_device_read_bps = &.{.{ .path = "/dev/sda", .rate = 1_048_576 }},
        .blkio_device_write_bps = &.{.{ .path = "/dev/sda", .rate = 2_097_152 }},
        .blkio_device_read_iops = &.{.{ .path = "/dev/sda", .rate = 1000 }},
        .blkio_device_write_iops = &.{.{ .path = "/dev/sda", .rate = 2000 }},
    });
    defer std.testing.allocator.free(body);

    try expectContains(body, "\"CpuShares\":512");
    try expectContains(body, "\"Memory\":314572800");
    try expectContains(body, "\"CpusetCpus\":\"0,1\"");
    try expectContains(body, "\"OomKillDisable\":false");
    try expectContains(body, "\"BlkioWeightDevice\":[{\"Path\":\"/dev/sda\",\"Weight\":500}]");
    try expectContains(body, "\"BlkioDeviceReadBps\":[{\"Path\":\"/dev/sda\",\"Rate\":1048576}]");
    try expectContains(body, "\"BlkioDeviceWriteBps\":[{\"Path\":\"/dev/sda\",\"Rate\":2097152}]");
    try expectContains(body, "\"BlkioDeviceReadIOps\":[{\"Path\":\"/dev/sda\",\"Rate\":1000}]");
    try expectContains(body, "\"BlkioDeviceWriteIOps\":[{\"Path\":\"/dev/sda\",\"Rate\":2000}]");
}

test "RestartPolicy stringify maps enum values" {
    const body = try stringify(std.testing.allocator, RestartPolicy{
        .name = .on_failure,
        .maximum_retry_count = 4,
    });
    defer std.testing.allocator.free(body);

    try expectContains(body, "\"Name\":\"on-failure\"");
    try expectContains(body, "\"MaximumRetryCount\":4");
}

test "Resources stringify maps device requests and ulimits" {
    const body = try stringify(std.testing.allocator, Resources{
        .devices = &.{.{
            .path_on_host = "/dev/fuse",
            .path_in_container = "/dev/fuse",
            .cgroup_permissions = "rwm",
        }},
        .device_cgroup_rules = &.{"c 13:* rwm"},
        .device_requests = &.{.{
            .driver = "nvidia",
            .count = -1,
            .device_ids = &.{ "0", "1" },
            .capabilities = &.{&.{ "gpu", "compute" }},
            .options = &.{.{ .name = "mig", .value = "true" }},
        }},
        .ulimits = &.{.{ .name = "nofile", .soft = 1024, .hard = 2048 }},
    });
    defer std.testing.allocator.free(body);

    try expectContains(
        body,
        "\"Devices\":[{\"PathOnHost\":\"/dev/fuse\",\"PathInContainer\":\"/dev/fuse\"," ++
            "\"CgroupPermissions\":\"rwm\"}]",
    );
    try expectContains(body, "\"DeviceCgroupRules\":[\"c 13:* rwm\"]");
    try expectContains(body, "\"Driver\":\"nvidia\"");
    try expectContains(body, "\"Capabilities\":[[\"gpu\",\"compute\"]]");
    try expectContains(body, "\"Options\":{\"mig\":\"true\"}");
    try expectContains(body, "\"Ulimits\":[{\"Name\":\"nofile\",\"Soft\":1024,\"Hard\":2048}]");
}
