const std = @import("std");

const json = @import("../json.zig");

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const RemoveOptions = struct {
    force: ?bool = null,
};

pub const UpdateOptions = struct {
    version: i64,
    spec: NodeSpec,
};

pub const NodeList = struct {
    allocator: std.mem.Allocator,
    items: []Node,

    pub fn deinit(self: *NodeList) void {
        for (self.items) |*item| item.deinit();
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Node = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    version_index: ?u64,
    created_at: ?[]const u8,
    updated_at: ?[]const u8,
    spec: ?NodeSpec,
    description: ?Description,
    status: ?Status,
    manager_status: ?ManagerStatus,

    pub fn deinit(self: *Node) void {
        self.allocator.free(self.id);
        freeOptional(self.allocator, self.created_at);
        freeOptional(self.allocator, self.updated_at);
        if (self.spec) |*spec| spec.deinit(self.allocator);
        if (self.description) |*description| description.deinit(self.allocator);
        if (self.status) |*status| status.deinit(self.allocator);
        if (self.manager_status) |*manager_status| manager_status.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const NodeSpec = struct {
    name: ?[]const u8 = null,
    labels: ?StringMap = null,
    role: ?Role = null,
    availability: ?Availability = null,

    pub fn jsonStringify(self: NodeSpec, writer: anytype) !void {
        try writer.write(RawNodeSpec{
            .Name = self.name,
            .Labels = self.labels,
            .Role = self.role,
            .Availability = self.availability,
        });
    }

    pub fn deinit(self: *NodeSpec, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.name);
        if (self.labels) |labels| {
            freePairs(allocator, labels.entries);
            allocator.free(labels.entries);
        }
        self.* = undefined;
    }
};

pub const Description = struct {
    hostname: ?[]const u8,
    platform: ?Platform,
    resources: ?Resources,
    engine: ?Engine,
    tls_info: ?TlsInfo,

    pub fn deinit(self: *Description, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.hostname);
        if (self.platform) |*platform| platform.deinit(allocator);
        if (self.resources) |*resources| resources.deinit(allocator);
        if (self.engine) |*engine| engine.deinit(allocator);
        if (self.tls_info) |*tls_info| tls_info.deinit(allocator);
        self.* = undefined;
    }
};

pub const Platform = struct {
    architecture: ?[]const u8,
    os: ?[]const u8,

    pub fn deinit(self: *Platform, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.architecture);
        freeOptional(allocator, self.os);
        self.* = undefined;
    }
};

pub const Resources = struct {
    nano_cpus: ?i64,
    memory_bytes: ?i64,
    generic_resources: []GenericResource,

    pub fn deinit(self: *Resources, allocator: std.mem.Allocator) void {
        for (self.generic_resources) |*resource| resource.deinit(allocator);
        allocator.free(self.generic_resources);
        self.* = undefined;
    }
};

pub const GenericResource = union(enum) {
    named: NamedResource,
    discrete: DiscreteResource,

    pub fn deinit(self: *GenericResource, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .named => |*named| named.deinit(allocator),
            .discrete => |*discrete| discrete.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const NamedResource = struct {
    kind: []const u8,
    value: []const u8,

    pub fn deinit(self: *NamedResource, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.value);
        self.* = undefined;
    }
};

pub const DiscreteResource = struct {
    kind: []const u8,
    value: i64,

    pub fn deinit(self: *DiscreteResource, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        self.* = undefined;
    }
};

pub const Engine = struct {
    version: ?[]const u8,
    labels: ?StringMap,
    plugins: []EnginePlugin,

    pub fn deinit(self: *Engine, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.version);
        if (self.labels) |labels| {
            freePairs(allocator, labels.entries);
            allocator.free(labels.entries);
        }
        for (self.plugins) |*plugin| plugin.deinit(allocator);
        allocator.free(self.plugins);
        self.* = undefined;
    }
};

pub const EnginePlugin = struct {
    type: ?[]const u8,
    name: ?[]const u8,

    pub fn deinit(self: *EnginePlugin, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.type);
        freeOptional(allocator, self.name);
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

pub const Status = struct {
    state: ?NodeState,
    message: ?[]const u8,
    addr: ?[]const u8,

    pub fn deinit(self: *Status, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.message);
        freeOptional(allocator, self.addr);
        self.* = undefined;
    }
};

pub const ManagerStatus = struct {
    leader: ?bool,
    reachability: ?Reachability,
    addr: ?[]const u8,

    pub fn deinit(self: *ManagerStatus, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.addr);
        self.* = undefined;
    }
};

pub const Role = enum {
    worker,
    manager,

    pub fn jsonStringify(self: Role, writer: anytype) !void {
        try writer.write(switch (self) {
            .worker => "worker",
            .manager => "manager",
        });
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

pub const NodeState = enum { unknown, down, ready, disconnected };

pub const Reachability = enum { unknown, @"unreachable", reachable };

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

const RawNodeSpec = struct {
    Name: ?[]const u8 = null,
    Labels: ?StringMap = null,
    Role: ?Role = null,
    Availability: ?Availability = null,
};

pub fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |string| allocator.free(string);
}

pub fn freePairs(allocator: std.mem.Allocator, values: []const Pair) void {
    for (values) |value| {
        allocator.free(value.name);
        allocator.free(value.value);
    }
}

test "node spec body uses Docker field names" {
    const body = try json.stringifyAlloc(std.testing.allocator, NodeSpec{
        .name = "worker-1",
        .role = .manager,
        .availability = .drain,
        .labels = .{ .entries = &.{.{ .name = "zone", .value = "east" }} },
    });
    defer std.testing.allocator.free(body);

    try std.testing.expectEqualStrings(
        "{\"Name\":\"worker-1\",\"Labels\":{\"zone\":\"east\"},\"Role\":\"manager\",\"Availability\":\"drain\"}",
        body,
    );
}
