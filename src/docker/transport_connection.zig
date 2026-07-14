const builtin = @import("builtin");
const std = @import("std");

const Transport = @import("transport.zig").Transport;

const buffer_size = 8192;

pub fn connect(allocator: std.mem.Allocator, transport: Transport) !Transport.Connection {
    try transport.validate();
    return switch (transport) {
        .named_pipe => |config| connectNamedPipe(allocator, config),
        .ssh => |config| connectSsh(allocator, config),
        .custom => |config| config.connect(allocator),
        else => error.TransportDoesNotUseRawConnection,
    };
}

const FileConnection = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    read_buffer: [buffer_size]u8 = undefined,
    write_buffer: [buffer_size]u8 = undefined,
    reader: std.fs.File.Reader = undefined,
    writer: std.fs.File.Writer = undefined,

    fn init(allocator: std.mem.Allocator, file: std.fs.File) !Transport.Connection {
        const state = try allocator.create(FileConnection);
        state.* = .{ .allocator = allocator, .file = file };
        state.reader = file.readerStreaming(&state.read_buffer);
        state.writer = file.writerStreaming(&state.write_buffer);
        return .{
            .context = state,
            .reader = &state.reader.interface,
            .writer = &state.writer.interface,
            .vtable = &.{ .close = close, .close_write = closeWrite },
        };
    }

    fn close(context: *anyopaque) void {
        const state: *FileConnection = @ptrCast(@alignCast(context));
        state.file.close();
        state.allocator.destroy(state);
    }

    fn closeWrite(context: *anyopaque) !void {
        const state: *FileConnection = @ptrCast(@alignCast(context));
        try state.writer.interface.flush();
        return error.HalfCloseUnsupported;
    }
};

fn connectNamedPipe(
    allocator: std.mem.Allocator,
    config: Transport.NamedPipe,
) !Transport.Connection {
    if (builtin.os.tag != .windows) return error.NamedPipeUnsupported;
    const file = try std.fs.openFileAbsolute(config.path, .{ .mode = .read_write });
    errdefer file.close();
    return FileConnection.init(allocator, file);
}

const SshConnection = struct {
    allocator: std.mem.Allocator,
    child: std.process.Child,
    read_buffer: [buffer_size]u8 = undefined,
    write_buffer: [buffer_size]u8 = undefined,
    reader: std.fs.File.Reader = undefined,
    writer: std.fs.File.Writer = undefined,

    fn init(allocator: std.mem.Allocator, child: std.process.Child) !Transport.Connection {
        const state = try allocator.create(SshConnection);
        state.* = .{ .allocator = allocator, .child = child };
        state.reader = state.child.stdout.?.readerStreaming(&state.read_buffer);
        state.writer = state.child.stdin.?.writerStreaming(&state.write_buffer);
        return .{
            .context = state,
            .reader = &state.reader.interface,
            .writer = &state.writer.interface,
            .vtable = &.{ .close = close, .close_write = closeWrite },
        };
    }

    fn close(context: *anyopaque) void {
        const state: *SshConnection = @ptrCast(@alignCast(context));
        _ = state.child.kill() catch |err| {
            std.debug.panic("failed to stop ssh process: {s}", .{@errorName(err)});
        };
        state.allocator.destroy(state);
    }

    fn closeWrite(context: *anyopaque) !void {
        const state: *SshConnection = @ptrCast(@alignCast(context));
        const stdin = state.child.stdin orelse return;
        try state.writer.interface.flush();
        stdin.close();
        state.child.stdin = null;
    }
};

fn connectSsh(allocator: std.mem.Allocator, config: Transport.Ssh) !Transport.Connection {
    const destination = if (config.user) |user|
        try std.fmt.allocPrint(allocator, "{s}@{s}", .{ user, config.host })
    else
        try allocator.dupe(u8, config.host);
    defer allocator.free(destination);

    const port = if (config.port) |value| try std.fmt.allocPrint(allocator, "{d}", .{value}) else null;
    defer if (port) |value| allocator.free(value);

    var arguments: std.ArrayList([]const u8) = .empty;
    defer arguments.deinit(allocator);
    try arguments.append(allocator, config.binary);
    try arguments.appendSlice(allocator, config.extra_arguments);
    if (port) |value| try arguments.appendSlice(allocator, &.{ "-p", value });
    if (config.identity_file) |path| try arguments.appendSlice(allocator, &.{ "-i", path });
    try arguments.appendSlice(allocator, &.{ destination, "docker", "system", "dial-stdio" });

    var child = std.process.Child.init(arguments.items, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    errdefer _ = child.kill() catch unreachable;
    return SshConnection.init(allocator, child);
}

test "SSH adapter builds without invoking a shell" {
    const config = Transport.Ssh{
        .host = "docker.example.com",
        .user = "builder",
        .port = 2222,
        .identity_file = "/tmp/key",
    };
    try (Transport{ .ssh = config }).validate();
}
