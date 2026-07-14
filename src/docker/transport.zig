const std = @import("std");

pub const Transport = union(enum) {
    unix_socket: UnixSocket,
    tcp: Tcp,
    tls: Tls,
    named_pipe: NamedPipe,
    ssh: Ssh,
    custom: Custom,

    pub const default_unix_socket_path = "/var/run/docker.sock";
    pub const default_named_pipe_path = "\\\\.\\pipe\\docker_engine";

    pub const UnixSocket = struct {
        path: []const u8,
    };

    pub const Tcp = struct {
        host: []const u8,
        port: u16 = 2375,
        allow_insecure_remote: bool = false,
    };

    pub const Tls = struct {
        host: []const u8,
        port: u16 = 2376,
    };

    pub const NamedPipe = struct {
        path: []const u8 = default_named_pipe_path,
    };

    pub const Ssh = struct {
        host: []const u8,
        user: ?[]const u8 = null,
        port: ?u16 = null,
        identity_file: ?[]const u8 = null,
        binary: []const u8 = "ssh",
        extra_arguments: []const []const u8 = &.{},
    };

    pub const Custom = struct {
        context: *anyopaque,
        connect_fn: *const fn (*anyopaque, std.mem.Allocator) anyerror!Connection,

        pub fn connect(self: Custom, allocator: std.mem.Allocator) !Connection {
            return self.connect_fn(self.context, allocator);
        }
    };

    pub const Connection = struct {
        context: *anyopaque,
        reader: *std.Io.Reader,
        writer: *std.Io.Writer,
        vtable: *const VTable,

        pub const VTable = struct {
            close: *const fn (*anyopaque) void,
            close_write: *const fn (*anyopaque) anyerror!void,
        };

        pub fn close(self: *Connection) void {
            self.vtable.close(self.context);
            self.* = undefined;
        }

        pub fn closeWrite(self: *Connection) !void {
            return self.vtable.close_write(self.context);
        }
    };

    pub fn validate(self: Transport) !void {
        switch (self) {
            .unix_socket => |config| try validateText(config.path),
            .tcp => |config| {
                try validateHost(config.host);
                if (!config.allow_insecure_remote and !isLoopback(config.host)) {
                    return error.InsecureRemoteTcpDisabled;
                }
            },
            .tls => |config| try validateHost(config.host),
            .named_pipe => |config| try validateText(config.path),
            .ssh => |config| {
                try validateHost(config.host);
                if (config.user) |user| try validateSshArgument(user);
                try validateSshArgument(config.binary);
                if (config.identity_file) |path| try validateSshArgument(path);
                for (config.extra_arguments) |argument| try validateText(argument);
            },
            .custom => {},
        }
    }
};

fn validateHost(host: []const u8) !void {
    try validateText(host);
    if (host[0] == '-') return error.InvalidTransportAddress;
}

fn validateSshArgument(argument: []const u8) !void {
    try validateText(argument);
    if (argument[0] == '-') return error.InvalidSshArgument;
}

fn validateText(text: []const u8) !void {
    if (text.len == 0 or std.mem.indexOfAny(u8, text, "\r\n\x00") != null) {
        return error.InvalidTransportAddress;
    }
}

fn isLoopback(host: []const u8) bool {
    return std.ascii.eqlIgnoreCase(host, "localhost") or
        std.mem.eql(u8, host, "127.0.0.1") or
        std.mem.eql(u8, host, "::1") or
        std.mem.eql(u8, host, "[::1]");
}

test "Transport validates every built-in transport" {
    try (Transport{ .unix_socket = .{ .path = Transport.default_unix_socket_path } }).validate();
    try (Transport{ .tcp = .{ .host = "127.0.0.1" } }).validate();
    try (Transport{ .tls = .{ .host = "docker.example.com" } }).validate();
    try (Transport{ .named_pipe = .{} }).validate();
    try (Transport{ .ssh = .{ .host = "docker.example.com", .user = "builder" } }).validate();
}

test "Transport rejects insecure remote TCP by default" {
    try std.testing.expectError(
        error.InsecureRemoteTcpDisabled,
        (Transport{ .tcp = .{ .host = "docker.example.com" } }).validate(),
    );
    try (Transport{ .tcp = .{
        .host = "docker.example.com",
        .allow_insecure_remote = true,
    } }).validate();
}

test "Transport rejects SSH option injection" {
    try std.testing.expectError(
        error.InvalidTransportAddress,
        (Transport{ .ssh = .{ .host = "-oProxyCommand=bad" } }).validate(),
    );
    try std.testing.expectError(
        error.InvalidSshArgument,
        (Transport{ .ssh = .{ .host = "host", .user = "-root" } }).validate(),
    );
}
