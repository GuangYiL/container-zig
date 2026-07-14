const std = @import("std");

const json = @import("../json.zig");

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const CreateOptions = struct {
    name: ?[]const u8 = null,
    driver: ?[]const u8 = null,
    driver_options: ?StringMap = null,
    labels: ?StringMap = null,
    cluster_volume_spec: ?ClusterVolumeSpec = null,

    pub fn jsonStringify(self: CreateOptions, writer: anytype) !void {
        try writer.write(RawCreateConfig{
            .Name = self.name,
            .Driver = self.driver,
            .DriverOpts = self.driver_options,
            .Labels = self.labels,
            .ClusterVolumeSpec = self.cluster_volume_spec,
        });
    }
};

pub const UpdateOptions = struct {
    version: i64,
    spec: ClusterVolumeSpec,
};

pub const RemoveOptions = struct {
    force: ?bool = null,
};

pub const PruneOptions = struct {
    filters: ?[]const u8 = null,
};

pub const VolumeList = struct {
    allocator: std.mem.Allocator,
    volumes: []Volume,
    warnings: []const []const u8,

    pub fn deinit(self: *VolumeList) void {
        for (self.volumes) |*volume| volume.deinit(self.allocator);
        self.allocator.free(self.volumes);
        freeStringList(self.allocator, self.warnings);
        self.allocator.free(self.warnings);
        self.* = undefined;
    }
};

pub const Volume = struct {
    name: []const u8,
    driver: []const u8,
    mountpoint: []const u8,
    created_at: ?[]const u8,
    labels: []const Pair,
    scope: []const u8,
    options: []const Pair,
    usage_data: ?UsageData,

    pub const UsageData = struct {
        size: i64,
        ref_count: i64,
    };

    pub fn deinit(self: *Volume, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.driver);
        allocator.free(self.mountpoint);
        if (self.created_at) |created_at| allocator.free(created_at);
        freePairs(allocator, self.labels);
        allocator.free(self.labels);
        allocator.free(self.scope);
        freePairs(allocator, self.options);
        allocator.free(self.options);
        self.* = undefined;
    }
};

pub const ClusterVolumeSpec = struct {
    group: ?[]const u8 = null,
    access_mode: ?AccessMode = null,

    pub const AccessMode = struct {
        availability: ?Availability = null,

        pub fn jsonStringify(self: AccessMode, writer: anytype) !void {
            try writer.write(RawAccessMode{ .Availability = self.availability });
        }
    };

    pub const Availability = enum {
        active,
        pause,
        drain,

        pub fn jsonStringify(self: Availability, writer: anytype) !void {
            try writer.write(switch (self) {
                .active => "active",
                .pause => "pause",
                .drain => "drain",
            });
        }
    };

    pub fn jsonStringify(self: ClusterVolumeSpec, writer: anytype) !void {
        try writer.write(RawClusterVolumeSpec{
            .Group = self.group,
            .AccessMode = self.access_mode,
        });
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

pub const Prune = struct {
    allocator: std.mem.Allocator,
    volumes_deleted: []const []const u8,
    space_reclaimed: ?i64,

    pub fn deinit(self: *Prune) void {
        freeStringList(self.allocator, self.volumes_deleted);
        self.allocator.free(self.volumes_deleted);
        self.* = undefined;
    }
};

const RawCreateConfig = struct {
    Name: ?[]const u8 = null,
    Driver: ?[]const u8 = null,
    DriverOpts: ?StringMap = null,
    Labels: ?StringMap = null,
    ClusterVolumeSpec: ?ClusterVolumeSpec = null,
};

const RawClusterVolumeSpec = struct {
    Group: ?[]const u8 = null,
    AccessMode: ?ClusterVolumeSpec.AccessMode = null,
};

const RawAccessMode = struct {
    Availability: ?ClusterVolumeSpec.Availability = null,
};

const RawUpdate = struct {
    Spec: ClusterVolumeSpec,
};

const RawVolume = struct {
    Name: []const u8,
    Driver: []const u8,
    Mountpoint: []const u8,
    CreatedAt: ?[]const u8 = null,
    Labels: ?std.json.ArrayHashMap([]const u8) = null,
    Scope: []const u8,
    Options: ?std.json.ArrayHashMap([]const u8) = null,
    UsageData: ?RawUsageData = null,
};

const RawUsageData = struct {
    Size: i64,
    RefCount: i64,
};

const RawList = struct {
    Volumes: ?[]RawVolume = null,
    Warnings: ?[]const []const u8 = null,
};

const RawPrune = struct {
    VolumesDeleted: ?[]const []const u8 = null,
    SpaceReclaimed: ?i64 = null,
};

pub fn updateBody(allocator: std.mem.Allocator, spec: ClusterVolumeSpec) ![]const u8 {
    return json.stringifyAlloc(allocator, RawUpdate{ .Spec = spec });
}

pub fn parseList(allocator: std.mem.Allocator, body: []const u8) !VolumeList {
    const parsed = try std.json.parseFromSlice(RawList, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    const raw_volumes = parsed.value.Volumes orelse &.{};
    const volumes = try allocator.alloc(Volume, raw_volumes.len);
    var filled: usize = 0;
    errdefer {
        for (volumes[0..filled]) |*volume| volume.deinit(allocator);
        allocator.free(volumes);
    }
    for (raw_volumes) |raw_volume| {
        volumes[filled] = try volumeFromRaw(allocator, raw_volume);
        filled += 1;
    }
    return .{
        .allocator = allocator,
        .volumes = volumes,
        .warnings = try dupeStringList(allocator, parsed.value.Warnings),
    };
}

pub fn parseVolume(allocator: std.mem.Allocator, body: []const u8) !Volume {
    const parsed = try std.json.parseFromSlice(RawVolume, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return volumeFromRaw(allocator, parsed.value);
}

pub fn parsePrune(allocator: std.mem.Allocator, body: []const u8) !Prune {
    const parsed = try std.json.parseFromSlice(RawPrune, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return .{
        .allocator = allocator,
        .volumes_deleted = try dupeStringList(allocator, parsed.value.VolumesDeleted),
        .space_reclaimed = parsed.value.SpaceReclaimed,
    };
}

fn volumeFromRaw(allocator: std.mem.Allocator, raw: RawVolume) !Volume {
    return .{
        .name = try allocator.dupe(u8, raw.Name),
        .driver = try allocator.dupe(u8, raw.Driver),
        .mountpoint = try allocator.dupe(u8, raw.Mountpoint),
        .created_at = try dupeOptional(allocator, raw.CreatedAt),
        .labels = try dupePairs(allocator, raw.Labels),
        .scope = try allocator.dupe(u8, raw.Scope),
        .options = try dupePairs(allocator, raw.Options),
        .usage_data = if (raw.UsageData) |usage| .{ .size = usage.Size, .ref_count = usage.RefCount } else null,
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

test "volume request bodies use Docker field names" {
    const create_body = try json.stringifyAlloc(std.testing.allocator, CreateOptions{
        .name = "data",
        .driver = "local",
        .driver_options = .{ .entries = &.{.{ .name = "type", .value = "tmpfs" }} },
        .labels = .{ .entries = &.{.{ .name = "project", .value = "sdk" }} },
    });
    defer std.testing.allocator.free(create_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, create_body, 1, "\"DriverOpts\":{\"type\":\"tmpfs\"}"));

    const update_body = try updateBody(std.testing.allocator, .{ .access_mode = .{ .availability = .drain } });
    defer std.testing.allocator.free(update_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, update_body, 1, "\"Availability\":\"drain\""));
}

test "parseList and parsePrune own volume results" {
    var list_result = try parseList(std.testing.allocator,
        \\{
        \\  "Volumes": [{
        \\    "Name": "data",
        \\    "Driver": "local",
        \\    "Mountpoint": "/var/lib/docker/volumes/data",
        \\    "CreatedAt": "2026-07-02T17:05:41Z",
        \\    "Labels": {"project": "sdk"},
        \\    "Scope": "local",
        \\    "Options": {"type": "tmpfs"},
        \\    "UsageData": {"Size": 42, "RefCount": 1}
        \\  }],
        \\  "Warnings": ["warn"]
        \\}
    );
    defer list_result.deinit();
    try std.testing.expectEqualStrings("data", list_result.volumes[0].name);
    try std.testing.expectEqualStrings("project", list_result.volumes[0].labels[0].name);
    try std.testing.expectEqual(@as(i64, 42), list_result.volumes[0].usage_data.?.size);
    try std.testing.expectEqualStrings("warn", list_result.warnings[0]);

    var prune_result = try parsePrune(std.testing.allocator, "{\"VolumesDeleted\":[\"data\"],\"SpaceReclaimed\":4096}");
    defer prune_result.deinit();
    try std.testing.expectEqualStrings("data", prune_result.volumes_deleted[0]);
    try std.testing.expectEqual(@as(i64, 4096), prune_result.space_reclaimed.?);
}
