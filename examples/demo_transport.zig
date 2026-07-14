const builtin = @import("builtin");
const std = @import("std");

const docker = @import("container_zig");

const user_socket_suffixes = [_][]const u8{
    ".orbstack/run/docker.sock",
    ".docker/run/docker.sock",
};

pub const Resolved = struct {
    arena: std.heap.ArenaAllocator,
    transport: docker.Transport,
    display_name: []const u8,

    pub fn deinit(self: *Resolved) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn resolve(
    allocator: std.mem.Allocator,
    environment: *const std.process.EnvMap,
    explicit_host: ?[]const u8,
) anyerror!Resolved {
    var result = Resolved{
        .arena = .init(allocator),
        .transport = undefined,
        .display_name = undefined,
    };
    errdefer result.arena.deinit();
    const arena = result.arena.allocator();

    if (explicit_host orelse environment.get("DOCKER_HOST")) |host| {
        result.transport = try parseHost(arena, host);
        result.display_name = try arena.dupe(u8, host);
        return result;
    }

    if (builtin.os.tag == .windows) {
        result.transport = .{ .named_pipe = .{} };
        result.display_name = docker.Transport.default_named_pipe_path;
        return result;
    }

    const path = try discoverUnixSocket(arena, environment);
    result.transport = .{ .unix_socket = .{ .path = path } };
    result.display_name = path;
    return result;
}

fn parseHost(allocator: std.mem.Allocator, value: []const u8) !docker.Transport {
    if (std.fs.path.isAbsolute(value)) {
        if (builtin.os.tag == .windows) {
            if (!std.mem.startsWith(u8, value, "\\\\.\\pipe\\")) return error.InvalidDockerHost;
            return .{ .named_pipe = .{ .path = try allocator.dupe(u8, value) } };
        }
        return .{ .unix_socket = .{ .path = try allocator.dupe(u8, value) } };
    }

    const uri = std.Uri.parse(value) catch return error.InvalidDockerHost;
    if (std.mem.eql(u8, uri.scheme, "unix")) {
        const path = try uri.path.toRawMaybeAlloc(allocator);
        if (!std.fs.path.isAbsolute(path)) return error.InvalidDockerHost;
        return .{ .unix_socket = .{ .path = try allocator.dupe(u8, path) } };
    }
    if (std.mem.eql(u8, uri.scheme, "npipe")) {
        if (builtin.os.tag != .windows) return error.NamedPipeUnsupported;
        return .{ .named_pipe = .{ .path = docker.Transport.default_named_pipe_path } };
    }

    const host = try uri.getHostAlloc(allocator);
    if (std.mem.eql(u8, uri.scheme, "tcp") or std.mem.eql(u8, uri.scheme, "http")) {
        return .{ .tcp = .{ .host = host, .port = uri.port orelse 2375 } };
    }
    if (std.mem.eql(u8, uri.scheme, "https")) {
        return .{ .tls = .{ .host = host, .port = uri.port orelse 2376 } };
    }
    if (std.mem.eql(u8, uri.scheme, "ssh")) {
        const user = if (uri.user) |component| try component.toRawMaybeAlloc(allocator) else null;
        return .{ .ssh = .{ .host = host, .user = user, .port = uri.port } };
    }
    return error.UnsupportedDockerHost;
}

fn discoverUnixSocket(
    allocator: std.mem.Allocator,
    environment: *const std.process.EnvMap,
) ![]const u8 {
    if (try isUnixSocket(docker.Transport.default_unix_socket_path)) {
        return try allocator.dupe(u8, docker.Transport.default_unix_socket_path);
    }
    const home = environment.get("HOME") orelse return error.DockerSocketNotFound;
    for (user_socket_suffixes) |suffix| {
        const candidate = try std.fs.path.join(allocator, &.{ home, suffix });
        if (try isUnixSocket(candidate)) return candidate;
    }
    return error.DockerSocketNotFound;
}

fn isUnixSocket(path: []const u8) !bool {
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => |unexpected| return unexpected,
    };
    return stat.kind == .unix_domain_socket;
}

test "Docker host parses Unix TCP TLS and SSH transports" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const unix = try parseHost(allocator, "unix:///tmp/docker.sock");
    try std.testing.expectEqualStrings("/tmp/docker.sock", unix.unix_socket.path);
    const tcp = try parseHost(allocator, "tcp://127.0.0.1:1234");
    try std.testing.expectEqual(@as(u16, 1234), tcp.tcp.port);
    const tls = try parseHost(allocator, "https://docker.example.com:2376");
    try std.testing.expectEqualStrings("docker.example.com", tls.tls.host);
    const ssh = try parseHost(allocator, "ssh://builder@docker.example.com:2222");
    try std.testing.expectEqualStrings("builder", ssh.ssh.user.?);
    try std.testing.expectEqual(@as(?u16, 2222), ssh.ssh.port);
}

test "unsupported Docker host fails explicitly" {
    try std.testing.expectError(
        error.UnsupportedDockerHost,
        parseHost(std.testing.allocator, "ftp://docker.example.com"),
    );
}
