pub const CreateConfig = struct {
    AttachStdin: ?bool = null,
    AttachStdout: ?bool = null,
    AttachStderr: ?bool = null,
    ConsoleSize: ?[2]u32 = null,
    DetachKeys: ?[]const u8 = null,
    Tty: ?bool = null,
    Env: ?[]const []const u8 = null,
    Cmd: ?[]const []const u8 = null,
    Privileged: ?bool = null,
    User: ?[]const u8 = null,
    WorkingDir: ?[]const u8 = null,
};

pub const StartConfig = struct {
    Detach: ?bool = null,
    Tty: ?bool = null,
    ConsoleSize: ?[2]u32 = null,
};

pub const Id = struct {
    Id: []const u8,
};

pub const Inspect = struct {
    CanRemove: ?bool = null,
    DetachKeys: ?[]const u8 = null,
    ID: []const u8,
    Running: bool,
    ExitCode: ?i64 = null,
    ProcessConfig: ?ProcessConfig = null,
    OpenStdin: bool,
    OpenStderr: bool,
    OpenStdout: bool,
    ContainerID: []const u8,
    Pid: i64,
};

pub const ProcessConfig = struct {
    arguments: ?[]const []const u8 = null,
    entrypoint: ?[]const u8 = null,
    privileged: ?bool = null,
    tty: ?bool = null,
    user: ?[]const u8 = null,
};
