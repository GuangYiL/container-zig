pub const Plugin = struct {
    Id: ?[]const u8 = null,
    Name: []const u8,
    Enabled: bool,
    Settings: Settings,
    PluginReference: ?[]const u8 = null,
    Config: PluginConfig,
};

pub const Settings = struct {
    Mounts: []Mount,
    Env: []const []const u8,
    Args: []const []const u8,
    Devices: []Device,
};

pub const PluginConfig = struct {
    Description: []const u8,
    Documentation: []const u8,
    Interface: Interface,
    Entrypoint: []const []const u8,
    WorkDir: []const u8,
    User: ?User = null,
    Network: NetworkConfig,
    Linux: LinuxConfig,
    PropagatedMount: []const u8,
    IpcHost: bool,
    PidHost: bool,
    Mounts: []Mount,
    Env: []Env,
    Args: Args,
    rootfs: ?Rootfs = null,
};

pub const Interface = struct {
    Types: []const []const u8,
    Socket: []const u8,
    ProtocolScheme: ?[]const u8 = null,
};

pub const User = struct {
    UID: ?u32 = null,
    GID: ?u32 = null,
};

pub const NetworkConfig = struct {
    Type: []const u8,
};

pub const LinuxConfig = struct {
    Capabilities: []const []const u8,
    AllowAllDevices: bool,
    Devices: []Device,
};

pub const Mount = struct {
    Name: []const u8,
    Description: []const u8,
    Settable: ?[]const []const u8 = null,
    Source: []const u8,
    Destination: []const u8,
    Type: []const u8,
    Options: ?[]const []const u8 = null,
};

pub const Device = struct {
    Name: []const u8,
    Description: []const u8,
    Settable: ?[]const []const u8 = null,
    Path: []const u8,
};

pub const Env = struct {
    Name: []const u8,
    Description: []const u8,
    Settable: ?[]const []const u8 = null,
    Value: []const u8,
};

pub const Args = struct {
    Name: []const u8,
    Description: []const u8,
    Settable: ?[]const []const u8 = null,
    Value: ?[]const []const u8 = null,
};

pub const Rootfs = struct {
    type: ?[]const u8 = null,
    diff_ids: ?[]const []const u8 = null,
};

pub const Privilege = struct {
    Name: []const u8,
    Description: ?[]const u8 = null,
    Value: ?[]const []const u8 = null,
};
