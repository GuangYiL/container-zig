const summary = @import("summary.zig");

pub const Inspect = struct {
    Id: ?[]const u8 = null,
    Created: ?[]const u8 = null,
    Path: ?[]const u8 = null,
    Args: ?[]const []const u8 = null,
    State: ?StateValue = null,
    Image: ?[]const u8 = null,
    ResolvConfPath: ?[]const u8 = null,
    HostnamePath: ?[]const u8 = null,
    HostsPath: ?[]const u8 = null,
    LogPath: ?[]const u8 = null,
    Name: ?[]const u8 = null,
    RestartCount: ?i64 = null,
    Driver: ?[]const u8 = null,
    Platform: ?[]const u8 = null,
    MountLabel: ?[]const u8 = null,
    ProcessLabel: ?[]const u8 = null,
    AppArmorProfile: ?[]const u8 = null,
    ExecIDs: ?[]const []const u8 = null,
    SizeRw: ?i64 = null,
    SizeRootFs: ?i64 = null,
    Mounts: ?[]const Mount = null,
};

pub const StateValue = struct {
    Status: ?summary.Summary.State = null,
    Running: ?bool = null,
    Paused: ?bool = null,
    Restarting: ?bool = null,
    OOMKilled: ?bool = null,
    Dead: ?bool = null,
    Pid: ?i64 = null,
    ExitCode: ?i64 = null,
    Error: ?[]const u8 = null,
    StartedAt: ?[]const u8 = null,
    FinishedAt: ?[]const u8 = null,
    Health: ?Health = null,
};

pub const Health = struct {
    Status: ?summary.Summary.Health.Status = null,
    FailingStreak: ?i64 = null,
};

pub const Mount = struct {
    Type: ?summary.Summary.Mount.MountType = null,
    Name: ?[]const u8 = null,
    Source: ?[]const u8 = null,
    Destination: ?[]const u8 = null,
    Driver: ?[]const u8 = null,
    Mode: ?[]const u8 = null,
    RW: ?bool = null,
    Propagation: ?[]const u8 = null,
};
