const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const create_config = @import("../container/create_config.zig");

pub const Commit = struct {
    allocator: std.mem.Allocator,
    id: []const u8,

    pub const Body = struct {
        hostname: ?[]const u8 = null,
        domain_name: ?[]const u8 = null,
        user: ?[]const u8 = null,
        attach_stdin: ?bool = null,
        attach_stdout: ?bool = null,
        attach_stderr: ?bool = null,
        exposed_ports: ?create_config.ObjectSet = null,
        tty: ?bool = null,
        open_stdin: ?bool = null,
        stdin_once: ?bool = null,
        env: ?[]const []const u8 = null,
        cmd: ?[]const []const u8 = null,
        healthcheck: ?std.json.Value = null,
        args_escaped: ?bool = null,
        image: ?[]const u8 = null,
        volumes: ?create_config.ObjectSet = null,
        working_dir: ?[]const u8 = null,
        entrypoint: ?[]const []const u8 = null,
        network_disabled: ?bool = null,
        on_build: ?[]const []const u8 = null,
        labels: ?create_config.StringMap = null,
        stop_signal: ?[]const u8 = null,
        stop_timeout: ?i64 = null,
        shell: ?[]const []const u8 = null,

        pub fn jsonStringify(self: Body, writer: anytype) !void {
            try writer.write(RawBody{
                .Hostname = self.hostname,
                .Domainname = self.domain_name,
                .User = self.user,
                .AttachStdin = self.attach_stdin,
                .AttachStdout = self.attach_stdout,
                .AttachStderr = self.attach_stderr,
                .ExposedPorts = self.exposed_ports,
                .Tty = self.tty,
                .OpenStdin = self.open_stdin,
                .StdinOnce = self.stdin_once,
                .Env = self.env,
                .Cmd = self.cmd,
                .Healthcheck = self.healthcheck,
                .ArgsEscaped = self.args_escaped,
                .Image = self.image,
                .Volumes = self.volumes,
                .WorkingDir = self.working_dir,
                .Entrypoint = self.entrypoint,
                .NetworkDisabled = self.network_disabled,
                .OnBuild = self.on_build,
                .Labels = self.labels,
                .StopSignal = self.stop_signal,
                .StopTimeout = self.stop_timeout,
                .Shell = self.shell,
            });
        }
    };

    pub fn deinit(self: *Commit) void {
        self.allocator.free(self.id);
        self.* = undefined;
    }
};

pub const CommitOptions = struct {
    container_config: ?Commit.Body = null,
    container: ?[]const u8 = null,
    repo: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    comment: ?[]const u8 = null,
    author: ?[]const u8 = null,
    pause: ?bool = null,
    changes: ?[]const u8 = null,
};

pub fn commit(allocator: std.mem.Allocator, client: *Client, options: CommitOptions) !Commit {
    const path = try commitPath(allocator, options);
    defer allocator.free(path);

    const request_body = if (options.container_config) |body| try commitRequestBody(allocator, body) else null;
    defer if (request_body) |body| allocator.free(body);

    var headers = if (request_body != null) try jsonHeaders(allocator) else null;
    defer if (headers) |*value| value.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = if (headers) |*value| value else null,
        .body = if (request_body) |body| .{ .bytes = body } else .none,
    });
    defer response.deinit();

    switch (response.status()) {
        .created => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const response_body = try response.body() orelse return error.EmptyResponse;
    return parseCommit(allocator, response_body);
}

const RawBody = struct {
    Hostname: ?[]const u8 = null,
    Domainname: ?[]const u8 = null,
    User: ?[]const u8 = null,
    AttachStdin: ?bool = null,
    AttachStdout: ?bool = null,
    AttachStderr: ?bool = null,
    ExposedPorts: ?create_config.ObjectSet = null,
    Tty: ?bool = null,
    OpenStdin: ?bool = null,
    StdinOnce: ?bool = null,
    Env: ?[]const []const u8 = null,
    Cmd: ?[]const []const u8 = null,
    Healthcheck: ?std.json.Value = null,
    ArgsEscaped: ?bool = null,
    Image: ?[]const u8 = null,
    Volumes: ?create_config.ObjectSet = null,
    WorkingDir: ?[]const u8 = null,
    Entrypoint: ?[]const []const u8 = null,
    NetworkDisabled: ?bool = null,
    OnBuild: ?[]const []const u8 = null,
    Labels: ?create_config.StringMap = null,
    StopSignal: ?[]const u8 = null,
    StopTimeout: ?i64 = null,
    Shell: ?[]const []const u8 = null,
};

const RawCommit = struct {
    Id: []const u8,
};

fn commitPath(allocator: std.mem.Allocator, options: CommitOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/commit");
    defer builder.deinit();

    if (options.container) |value| try builder.add("container", value);
    if (options.repo) |value| try builder.add("repo", value);
    if (options.tag) |value| try builder.add("tag", value);
    if (options.comment) |value| try builder.add("comment", value);
    if (options.author) |value| try builder.add("author", value);
    if (options.pause) |value| try builder.addBool("pause", value);
    if (options.changes) |value| try builder.add("changes", value);

    return builder.finish();
}

fn commitRequestBody(allocator: std.mem.Allocator, body: Commit.Body) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, body, .{
        .emit_null_optional_fields = false,
    });
}

fn jsonHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

fn parseCommit(allocator: std.mem.Allocator, body: []const u8) !Commit {
    const parsed = try std.json.parseFromSlice(RawCommit, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .id = try allocator.dupe(u8, parsed.value.Id),
    };
}

test "commitPath encodes commit query parameters" {
    const path = try commitPath(std.testing.allocator, .{
        .container = "web name",
        .repo = "example/app",
        .tag = "v1",
        .comment = "release",
        .author = "Docker",
        .pause = true,
        .changes = "ENV FOO=bar",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/commit?container=web%20name&repo=example%2Fapp&tag=v1" ++
            "&comment=release&author=Docker&pause=true&changes=ENV%20FOO%3Dbar",
        path,
    );
}

test "commitRequestBody maps ContainerConfig fields" {
    const body = try commitRequestBody(std.testing.allocator, .{
        .image = "ubuntu",
        .cmd = &.{"date"},
        .labels = .{ .entries = &.{
            .{ .name = "org.opencontainers.image.title", .value = "example" },
        } },
        .exposed_ports = .{ .names = &.{"80/tcp"} },
    });
    defer std.testing.allocator.free(body);

    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Image\":\"ubuntu\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Cmd\":[\"date\"]"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"ExposedPorts\":{\"80/tcp\":{}}"));
}

test "parseCommit owns id" {
    var result = try parseCommit(std.testing.allocator,
        \\{"Id":"sha256:new"}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("sha256:new", result.id);
}
