const builtin = @import("builtin");
const std = @import("std");

const Transport = @import("transport.zig").Transport;

const buffer_size = 8192;

pub fn connect(allocator: std.mem.Allocator, io: std.Io, transport: Transport) !Transport.Connection {
    try transport.validate();
    return switch (transport) {
        .named_pipe => |config| connectNamedPipe(allocator, io, config),
        .ssh => |config| connectSsh(allocator, io, config),
        .custom => |config| config.connect(allocator, io),
        else => error.TransportDoesNotUseRawConnection,
    };
}

const FileConnection = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    read_buffer: [buffer_size]u8 = undefined,
    write_buffer: [buffer_size]u8 = undefined,
    reader: std.Io.File.Reader = undefined,
    writer: std.Io.File.Writer = undefined,

    fn init(allocator: std.mem.Allocator, io: std.Io, file: std.Io.File) !Transport.Connection {
        const state = try allocator.create(FileConnection);
        state.* = .{ .allocator = allocator, .io = io, .file = file };
        state.reader = file.readerStreaming(io, &state.read_buffer);
        state.writer = file.writerStreaming(io, &state.write_buffer);
        return .{
            .context = state,
            .reader = &state.reader.interface,
            .writer = &state.writer.interface,
            .vtable = &.{ .close = close, .close_write = closeWrite },
        };
    }

    fn close(context: *anyopaque) void {
        const state: *FileConnection = @ptrCast(@alignCast(context));
        state.file.close(state.io);
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
    io: std.Io,
    config: Transport.NamedPipe,
) !Transport.Connection {
    if (builtin.os.tag != .windows) return error.NamedPipeUnsupported;
    const file = try std.Io.Dir.openFileAbsolute(io, config.path, .{ .mode = .read_write });
    errdefer file.close(io);
    return FileConnection.init(allocator, io, file);
}

const SshConnection = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    child: std.process.Child,
    read_buffer: [buffer_size]u8 = undefined,
    write_buffer: [buffer_size]u8 = undefined,
    reader: std.Io.File.Reader = undefined,
    writer: std.Io.File.Writer = undefined,

    fn init(allocator: std.mem.Allocator, io: std.Io, child: std.process.Child) !Transport.Connection {
        const state = try allocator.create(SshConnection);
        state.* = .{ .allocator = allocator, .io = io, .child = child };
        state.reader = state.child.stdout.?.readerStreaming(io, &state.read_buffer);
        state.writer = state.child.stdin.?.writerStreaming(io, &state.write_buffer);
        return .{
            .context = state,
            .reader = &state.reader.interface,
            .writer = &state.writer.interface,
            .vtable = &.{ .close = close, .close_write = closeWrite },
        };
    }

    fn close(context: *anyopaque) void {
        const state: *SshConnection = @ptrCast(@alignCast(context));
        state.child.kill(state.io);
        state.allocator.destroy(state);
    }

    fn closeWrite(context: *anyopaque) !void {
        const state: *SshConnection = @ptrCast(@alignCast(context));
        const stdin = state.child.stdin orelse return;
        try state.writer.interface.flush();
        stdin.close(state.io);
        state.child.stdin = null;
    }
};

fn connectSsh(allocator: std.mem.Allocator, io: std.Io, config: Transport.Ssh) !Transport.Connection {
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

    var child = try std.process.spawn(io, .{
        .argv = arguments.items,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .inherit,
    });
    errdefer child.kill(io);
    return SshConnection.init(allocator, io, child);
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
