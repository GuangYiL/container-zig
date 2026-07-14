const std = @import("std");

const model = @import("summary.zig");

const SummaryModel = model.Summary;

pub const Summary = struct {
    Id: ?[]const u8 = null,
    Names: ?[]const []const u8 = null,
    Image: ?[]const u8 = null,
    ImageID: ?[]const u8 = null,
    Command: ?[]const u8 = null,
    Created: ?i64 = null,
    Ports: ?[]const Port = null,
    SizeRw: ?i64 = null,
    SizeRootFs: ?i64 = null,
    Labels: ?std.json.ArrayHashMap([]const u8) = null,
    State: ?SummaryModel.State = null,
    Status: ?[]const u8 = null,
    HostConfig: ?HostConfig = null,
    NetworkSettings: ?NetworkSettings = null,
    Mounts: ?[]const Mount = null,
    Health: ?Health = null,
};

pub const Port = struct {
    IP: ?[]const u8 = null,
    PrivatePort: u16,
    PublicPort: ?u16 = null,
    Type: SummaryModel.Port.Protocol,
};

pub const HostConfig = struct {
    NetworkMode: ?[]const u8 = null,
    Annotations: ?std.json.ArrayHashMap([]const u8) = null,
};

pub const NetworkSettings = struct {
    Networks: ?std.json.ArrayHashMap(Endpoint) = null,
};

pub const Endpoint = struct {
    NetworkID: ?[]const u8 = null,
    EndpointID: ?[]const u8 = null,
    Gateway: ?[]const u8 = null,
    IPAddress: ?[]const u8 = null,
    IPPrefixLen: ?i64 = null,
    IPv6Gateway: ?[]const u8 = null,
    GlobalIPv6Address: ?[]const u8 = null,
    GlobalIPv6PrefixLen: ?i64 = null,
    MacAddress: ?[]const u8 = null,
    DNSNames: ?[]const []const u8 = null,
};

pub const Mount = struct {
    Type: ?SummaryModel.Mount.MountType = null,
    Name: ?[]const u8 = null,
    Source: ?[]const u8 = null,
    Destination: ?[]const u8 = null,
    Driver: ?[]const u8 = null,
    Mode: ?[]const u8 = null,
    RW: ?bool = null,
    Propagation: ?[]const u8 = null,
};

pub const Health = struct {
    Status: ?SummaryModel.Health.Status = null,
    FailingStreak: ?i64 = null,
};
