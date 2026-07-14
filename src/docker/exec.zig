const std = @import("std");
const http = @import("http.zig");
const Client = @import("client.zig").Client;
const query = @import("query.zig");
const Session = @import("stream/session.zig").Session;
const url = @import("url.zig");
const wire = @import("exec/wire.zig");

pub const CreateOptions = struct {
    attach_stdin: ?bool = null,
    attach_stdout: ?bool = null,
    attach_stderr: ?bool = null,
    console_size: ?[2]u32 = null,
    detach_keys: ?[]const u8 = null,
    tty: ?bool = null,
    env: ?[]const []const u8 = null,
    cmd: ?[]const []const u8 = null,
    privileged: ?bool = null,
    user: ?[]const u8 = null,
    working_dir: ?[]const u8 = null,

    pub fn jsonStringify(self: CreateOptions, writer: anytype) !void {
        try writer.write(wire.CreateConfig{
            .AttachStdin = self.attach_stdin,
            .AttachStdout = self.attach_stdout,
            .AttachStderr = self.attach_stderr,
            .ConsoleSize = self.console_size,
            .DetachKeys = self.detach_keys,
            .Tty = self.tty,
            .Env = self.env,
            .Cmd = self.cmd,
            .Privileged = self.privileged,
            .User = self.user,
            .WorkingDir = self.working_dir,
        });
    }
};

pub const StartOptions = struct {
    tty: bool = false,
    console_size: ?[2]u32 = null,
    max_frame_bytes: usize = 16 * 1024 * 1024,

    pub fn jsonStringify(self: StartOptions, writer: anytype) !void {
        try writer.write(wire.StartConfig{
            .Detach = false,
            .Tty = self.tty,
            .ConsoleSize = self.console_size,
        });
    }
};

pub const ResizeOptions = struct {
    height: u32,
    width: u32,
};

pub const Create = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    pub fn deinit(self: *Create) void {
        self.allocator.free(self.id);
        self.* = undefined;
    }
};
pub const Inspect = struct {
    allocator: std.mem.Allocator,
    can_remove: ?bool,
    detach_keys: ?[]const u8,
    id: []const u8,
    running: bool,
    exit_code: ?i64,
    process_config: ?ProcessConfig,
    open_stdin: bool,
    open_stderr: bool,
    open_stdout: bool,
    container_id: []const u8,
    pid: i64,
    pub const ProcessConfig = struct {
        arguments: []const []const u8,
        entrypoint: ?[]const u8,
        privileged: ?bool,
        tty: ?bool,
        user: ?[]const u8,
        fn deinit(self: *ProcessConfig, allocator: std.mem.Allocator) void {
            for (self.arguments) |argument| allocator.free(argument);
            allocator.free(self.arguments);
            if (self.entrypoint) |entrypoint| allocator.free(entrypoint);
            if (self.user) |user| allocator.free(user);
            self.* = undefined;
        }
    };
    pub fn deinit(self: *Inspect) void {
        if (self.detach_keys) |detach_keys| self.allocator.free(detach_keys);
        self.allocator.free(self.id);
        if (self.process_config) |*process_config| process_config.deinit(self.allocator);
        self.allocator.free(self.container_id);
        self.* = undefined;
    }
};
pub fn create(allocator: std.mem.Allocator, client: *Client, container_id: []const u8, options: CreateOptions) !Create {
    const path = try url.pathWithSegment(allocator, "/containers/", container_id, "/exec");
    defer allocator.free(path);
    const body = try requestBody(allocator, options);
    defer allocator.free(body);
    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    switch (response.status()) {
        .created => {},
        .not_found => return error.ContainerNotFound,
        .conflict => return error.ContainerPaused,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
    const response_body = try response.body() orelse return error.EmptyResponse;
    return parseCreate(allocator, response_body);
}
pub fn start(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: StartOptions) !Session {
    const path = try url.pathWithSegment(allocator, "/exec/", id, "/start");
    defer allocator.free(path);
    const body = try requestBody(allocator, options);
    defer allocator.free(body);
    var headers = try startHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    errdefer response.deinit();
    switch (response.status()) {
        .ok, .switching_protocols => {},
        .not_found => return error.ExecNotFound,
        .conflict => return error.ContainerNotRunning,
        else => return error.UnexpectedStatus,
    }
    const duplex = if (response.status() == .switching_protocols)
        response.takeRawDuplex()
    else
        response.takeBodyDuplex();
    return Session.init(duplex, options.tty, options.max_frame_bytes);
}

pub fn resize(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: ResizeOptions) !void {
    const path = try resizePath(allocator, id, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .post,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ExecNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, id: []const u8) !Inspect {
    const path = try url.pathWithSegment(allocator, "/exec/", id, "/json");
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ExecNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseInspect(allocator, body);
}

fn resizePath(allocator: std.mem.Allocator, id: []const u8, options: ResizeOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/exec/", id, "/resize");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    try builder.addInt("h", options.height);
    try builder.addInt("w", options.width);

    return builder.finish();
}

fn requestBody(allocator: std.mem.Allocator, options: anytype) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, options, .{
        .emit_null_optional_fields = false,
    });
}

fn jsonHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

fn startHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 3);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    try headers.put("Connection", "Upgrade");
    try headers.put("Upgrade", "tcp");
    return headers;
}

fn parseCreate(allocator: std.mem.Allocator, body: []const u8) !Create {
    const parsed = try std.json.parseFromSlice(wire.Id, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, parsed.value.Id),
    };
}

fn parseInspect(allocator: std.mem.Allocator, body: []const u8) !Inspect {
    const parsed = try std.json.parseFromSlice(wire.Inspect, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var result = Inspect{
        .allocator = allocator,
        .can_remove = parsed.value.CanRemove,
        .detach_keys = try dupeOptional(allocator, parsed.value.DetachKeys),
        .id = try allocator.dupe(u8, parsed.value.ID),
        .running = parsed.value.Running,
        .exit_code = parsed.value.ExitCode,
        .process_config = null,
        .open_stdin = parsed.value.OpenStdin,
        .open_stderr = parsed.value.OpenStderr,
        .open_stdout = parsed.value.OpenStdout,
        .container_id = try allocator.dupe(u8, parsed.value.ContainerID),
        .pid = parsed.value.Pid,
    };
    errdefer result.deinit();

    if (parsed.value.ProcessConfig) |process_config| {
        result.process_config = try dupeProcessConfig(allocator, process_config);
    }

    return result;
}

fn dupeProcessConfig(allocator: std.mem.Allocator, raw: wire.ProcessConfig) !Inspect.ProcessConfig {
    return .{
        .arguments = try dupeList(allocator, raw.arguments),
        .entrypoint = try dupeOptional(allocator, raw.entrypoint),
        .privileged = raw.privileged,
        .tty = raw.tty,
        .user = try dupeOptional(allocator, raw.user),
    };
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn dupeList(allocator: std.mem.Allocator, values: ?[]const []const u8) ![]const []const u8 {
    const source = values orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, source.len);
    var filled: usize = 0;
    errdefer {
        for (owned[0..filled]) |value| allocator.free(value);
        allocator.free(owned);
    }

    for (source) |value| {
        owned[filled] = try allocator.dupe(u8, value);
        filled += 1;
    }

    return owned;
}

test "exec request bodies use Docker field names" {
    const create_body = try requestBody(std.testing.allocator, CreateOptions{
        .attach_stdout = true,
        .attach_stderr = true,
        .detach_keys = "ctrl-p,ctrl-q",
        .tty = false,
        .cmd = &.{"date"},
        .env = &.{"FOO=bar"},
    });
    defer std.testing.allocator.free(create_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, create_body, 1, "\"AttachStdout\":true"));
    try std.testing.expect(std.mem.containsAtLeast(u8, create_body, 1, "\"Cmd\":[\"date\"]"));
    try std.testing.expect(std.mem.indexOf(u8, create_body, "attach_stdout") == null);

    const start_body = try requestBody(std.testing.allocator, StartOptions{
        .tty = true,
        .console_size = .{ 80, 64 },
    });
    defer std.testing.allocator.free(start_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, start_body, 1, "\"ConsoleSize\":[80,64]"));
}

test "resizePath encodes dimensions" {
    const path = try resizePath(std.testing.allocator, "exec id", .{
        .height = 80,
        .width = 120,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/exec/exec%20id/resize?h=80&w=120", path);
}

test "parseCreate owns exec id" {
    var result = try parseCreate(std.testing.allocator, "{\"Id\":\"exec123\"}");
    defer result.deinit();

    try std.testing.expectEqualStrings("exec123", result.id);
}

test "parseInspect owns process config" {
    const body =
        \\{
        \\  "CanRemove": false,
        \\  "DetachKeys": "",
        \\  "ID": "exec123",
        \\  "Running": false,
        \\  "ExitCode": 2,
        \\  "ProcessConfig": {
        \\    "arguments": ["-c", "exit 2"],
        \\    "entrypoint": "sh",
        \\    "privileged": false,
        \\    "tty": true,
        \\    "user": "1000"
        \\  },
        \\  "OpenStdin": true,
        \\  "OpenStderr": true,
        \\  "OpenStdout": true,
        \\  "ContainerID": "container123",
        \\  "Pid": 42000
        \\}
    ;
    var result = try parseInspect(std.testing.allocator, body);
    defer result.deinit();

    try std.testing.expectEqualStrings("exec123", result.id);
    try std.testing.expectEqualStrings("-c", result.process_config.?.arguments[0]);
    try std.testing.expectEqualStrings("sh", result.process_config.?.entrypoint.?);
    try std.testing.expectEqual(@as(i64, 2), result.exit_code.?);
}
