const std = @import("std");

pub const Network = struct {
    Name: []const u8,
    Id: []const u8,
    Created: ?[]const u8 = null,
    Scope: []const u8,
    Driver: []const u8,
    EnableIPv4: ?bool = null,
    EnableIPv6: bool = false,
    Internal: bool = false,
    Attachable: bool = false,
    Ingress: bool = false,
    Options: ?std.json.ArrayHashMap([]const u8) = null,
    Labels: ?std.json.ArrayHashMap([]const u8) = null,
};

pub const Create = struct {
    Id: []const u8,
    Warning: []const u8,
};

pub const Prune = struct {
    NetworksDeleted: ?[]const []const u8 = null,
};
