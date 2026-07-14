const std = @import("std");
const RegistryAuth = @import("../registry_auth.zig").RegistryAuth;
const Upload = @import("../http_request.zig").Upload;

const json = @import("../json.zig");

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const RemoveOptions = struct {
    force: ?bool = null,
};

pub const PullOptions = struct {
    remote: []const u8,
    name: ?[]const u8 = null,
    registry_auth: ?RegistryAuth = null,
    privileges: []const Privilege,
};

pub const UpgradeOptions = struct {
    remote: []const u8,
    registry_auth: ?RegistryAuth = null,
    privileges: []const Privilege,
};

pub const CreateOptions = struct {
    name: []const u8,
    context: Upload,
};

pub const EnableOptions = struct {
    timeout: ?i64 = null,
};

pub const DisableOptions = struct {
    force: ?bool = null,
};

pub const SetOptions = struct {
    values: []const []const u8,
};

pub const PluginList = struct {
    allocator: std.mem.Allocator,
    items: []Plugin,

    pub fn deinit(self: *PluginList) void {
        for (self.items) |*item| item.deinit();
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Plugin = struct {
    allocator: std.mem.Allocator,
    id: ?[]const u8,
    name: []const u8,
    enabled: bool,
    settings: Settings,
    plugin_reference: ?[]const u8,
    config: PluginConfig,

    pub fn deinit(self: *Plugin) void {
        freeOptional(self.allocator, self.id);
        self.allocator.free(self.name);
        self.settings.deinit(self.allocator);
        freeOptional(self.allocator, self.plugin_reference);
        self.config.deinit(self.allocator);
        self.* = undefined;
    }
};

pub const Settings = struct {
    mounts: []Mount,
    env: []const []const u8,
    args: []const []const u8,
    devices: []Device,

    pub fn deinit(self: *Settings, allocator: std.mem.Allocator) void {
        freeMounts(allocator, self.mounts);
        allocator.free(self.mounts);
        freeStringList(allocator, self.env);
        allocator.free(self.env);
        freeStringList(allocator, self.args);
        allocator.free(self.args);
        freeDevices(allocator, self.devices);
        allocator.free(self.devices);
        self.* = undefined;
    }
};

pub const PluginConfig = struct {
    description: []const u8,
    documentation: []const u8,
    interface: Interface,
    entrypoint: []const []const u8,
    work_dir: []const u8,
    user: ?User,
    network: NetworkConfig,
    linux: LinuxConfig,
    propagated_mount: []const u8,
    ipc_host: bool,
    pid_host: bool,
    mounts: []Mount,
    env: []Env,
    args: Args,
    rootfs: ?Rootfs,

    pub fn deinit(self: *PluginConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.description);
        allocator.free(self.documentation);
        self.interface.deinit(allocator);
        freeStringList(allocator, self.entrypoint);
        allocator.free(self.entrypoint);
        allocator.free(self.work_dir);
        self.network.deinit(allocator);
        self.linux.deinit(allocator);
        allocator.free(self.propagated_mount);
        freeMounts(allocator, self.mounts);
        allocator.free(self.mounts);
        freeEnvs(allocator, self.env);
        allocator.free(self.env);
        self.args.deinit(allocator);
        if (self.rootfs) |*rootfs| rootfs.deinit(allocator);
        self.* = undefined;
    }
};

pub const Interface = struct {
    types: []const []const u8,
    socket: []const u8,
    protocol_scheme: ?[]const u8,

    pub fn deinit(self: *Interface, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.types);
        allocator.free(self.types);
        allocator.free(self.socket);
        freeOptional(allocator, self.protocol_scheme);
        self.* = undefined;
    }
};

pub const User = struct {
    uid: ?u32,
    gid: ?u32,
};

pub const NetworkConfig = struct {
    type: []const u8,

    pub fn deinit(self: *NetworkConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        self.* = undefined;
    }
};

pub const LinuxConfig = struct {
    capabilities: []const []const u8,
    allow_all_devices: bool,
    devices: []Device,

    pub fn deinit(self: *LinuxConfig, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.capabilities);
        allocator.free(self.capabilities);
        freeDevices(allocator, self.devices);
        allocator.free(self.devices);
        self.* = undefined;
    }
};

pub const Mount = struct {
    name: []const u8,
    description: []const u8,
    settable: []const []const u8,
    source: []const u8,
    destination: []const u8,
    type: []const u8,
    options: []const []const u8,

    pub fn deinit(self: *Mount, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        freeStringList(allocator, self.settable);
        allocator.free(self.settable);
        allocator.free(self.source);
        allocator.free(self.destination);
        allocator.free(self.type);
        freeStringList(allocator, self.options);
        allocator.free(self.options);
        self.* = undefined;
    }
};

pub const Device = struct {
    name: []const u8,
    description: []const u8,
    settable: []const []const u8,
    path: []const u8,

    pub fn deinit(self: *Device, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        freeStringList(allocator, self.settable);
        allocator.free(self.settable);
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const Env = struct {
    name: []const u8,
    description: []const u8,
    settable: []const []const u8,
    value: []const u8,

    pub fn deinit(self: *Env, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        freeStringList(allocator, self.settable);
        allocator.free(self.settable);
        allocator.free(self.value);
        self.* = undefined;
    }
};

pub const Args = struct {
    name: []const u8,
    description: []const u8,
    settable: []const []const u8,
    value: []const []const u8,

    pub fn deinit(self: *Args, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        freeStringList(allocator, self.settable);
        allocator.free(self.settable);
        freeStringList(allocator, self.value);
        allocator.free(self.value);
        self.* = undefined;
    }
};

pub const Rootfs = struct {
    type: ?[]const u8,
    diff_ids: []const []const u8,

    pub fn deinit(self: *Rootfs, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.type);
        freeStringList(allocator, self.diff_ids);
        allocator.free(self.diff_ids);
        self.* = undefined;
    }
};

pub const PrivilegeList = struct {
    allocator: std.mem.Allocator,
    items: []Privilege,

    pub fn deinit(self: *PrivilegeList) void {
        freePrivileges(self.allocator, self.items);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Privilege = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    value: []const []const u8 = &.{},

    pub fn jsonStringify(self: Privilege, writer: anytype) !void {
        try writer.write(RawPrivilege{
            .Name = self.name,
            .Description = self.description,
            .Value = self.value,
        });
    }

    pub fn deinit(self: *Privilege, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        freeOptional(allocator, self.description);
        freeStringList(allocator, self.value);
        allocator.free(self.value);
        self.* = undefined;
    }
};

const RawPrivilege = struct {
    Name: []const u8,
    Description: ?[]const u8 = null,
    Value: []const []const u8 = &.{},
};

fn freeMounts(allocator: std.mem.Allocator, values: []Mount) void {
    for (values) |*value| value.deinit(allocator);
}

fn freeDevices(allocator: std.mem.Allocator, values: []Device) void {
    for (values) |*value| value.deinit(allocator);
}

fn freeEnvs(allocator: std.mem.Allocator, values: []Env) void {
    for (values) |*value| value.deinit(allocator);
}

fn freePrivileges(allocator: std.mem.Allocator, values: []Privilege) void {
    for (values) |*value| value.deinit(allocator);
}

pub fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}

pub fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |string| allocator.free(string);
}

test "plugin privilege body uses Docker field names" {
    const body = try json.stringifyAlloc(std.testing.allocator, [_]Privilege{
        .{ .name = "network", .description = "", .value = &.{"host"} },
    });
    defer std.testing.allocator.free(body);

    try std.testing.expectEqualStrings(
        "[{\"Name\":\"network\",\"Description\":\"\",\"Value\":[\"host\"]}]",
        body,
    );
}
