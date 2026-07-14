const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const summary_model = @import("summary.zig");
const url = @import("../url.zig");
const wire = @import("inspect_wire.zig");

pub const Mount = summary_model.Summary.Mount;

pub const InspectOptions = struct {
    size: ?bool = null,
};

pub const Inspect = struct {
    allocator: std.mem.Allocator,
    id: ?[]const u8,
    created: ?[]const u8,
    path: ?[]const u8,
    args: []const []const u8,
    state: ?State,
    image: ?[]const u8,
    resolv_conf_path: ?[]const u8,
    hostname_path: ?[]const u8,
    hosts_path: ?[]const u8,
    log_path: ?[]const u8,
    name: ?[]const u8,
    restart_count: ?i64,
    driver: ?[]const u8,
    platform: ?[]const u8,
    mount_label: ?[]const u8,
    process_label: ?[]const u8,
    app_armor_profile: ?[]const u8,
    exec_ids: []const []const u8,
    size_rw: ?i64,
    size_root_fs: ?i64,
    mounts: []const Mount,

    pub const State = struct {
        status: ?summary_model.Summary.State,
        running: ?bool,
        paused: ?bool,
        restarting: ?bool,
        oom_killed: ?bool,
        dead: ?bool,
        pid: ?i64,
        exit_code: ?i64,
        error_message: ?[]const u8,
        started_at: ?[]const u8,
        finished_at: ?[]const u8,
        health: ?summary_model.Summary.Health,
    };

    pub fn deinit(self: *Inspect) void {
        freeOptionalString(self.allocator, self.id);
        freeOptionalString(self.allocator, self.created);
        freeOptionalString(self.allocator, self.path);
        freeStringList(self.allocator, self.args);
        if (self.state) |state| {
            freeOptionalString(self.allocator, state.error_message);
            freeOptionalString(self.allocator, state.started_at);
            freeOptionalString(self.allocator, state.finished_at);
        }
        freeOptionalString(self.allocator, self.image);
        freeOptionalString(self.allocator, self.resolv_conf_path);
        freeOptionalString(self.allocator, self.hostname_path);
        freeOptionalString(self.allocator, self.hosts_path);
        freeOptionalString(self.allocator, self.log_path);
        freeOptionalString(self.allocator, self.name);
        freeOptionalString(self.allocator, self.driver);
        freeOptionalString(self.allocator, self.platform);
        freeOptionalString(self.allocator, self.mount_label);
        freeOptionalString(self.allocator, self.process_label);
        freeOptionalString(self.allocator, self.app_armor_profile);
        freeStringList(self.allocator, self.exec_ids);
        summary_model.freeMounts(self.allocator, self.mounts);
        self.* = undefined;
    }
};

pub fn inspect(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: InspectOptions) !Inspect {
    const path = try inspectPath(allocator, id, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseInspect(allocator, body);
}

fn inspectPath(allocator: std.mem.Allocator, id: []const u8, options: InspectOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/json");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.size) |size| try builder.addBool("size", size);

    return builder.finish();
}

pub fn parseInspect(allocator: std.mem.Allocator, body: []const u8) !Inspect {
    const parsed = try std.json.parseFromSlice(wire.Inspect, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var result = Inspect{
        .allocator = allocator,
        .id = null,
        .created = null,
        .path = null,
        .args = &.{},
        .state = null,
        .image = null,
        .resolv_conf_path = null,
        .hostname_path = null,
        .hosts_path = null,
        .log_path = null,
        .name = null,
        .restart_count = parsed.value.RestartCount,
        .driver = null,
        .platform = null,
        .mount_label = null,
        .process_label = null,
        .app_armor_profile = null,
        .exec_ids = &.{},
        .size_rw = parsed.value.SizeRw,
        .size_root_fs = parsed.value.SizeRootFs,
        .mounts = &.{},
    };
    errdefer result.deinit();

    result.id = try dupeOptionalString(allocator, parsed.value.Id);
    result.created = try dupeOptionalString(allocator, parsed.value.Created);
    result.path = try dupeOptionalString(allocator, parsed.value.Path);
    result.args = try dupeStringList(allocator, parsed.value.Args);
    result.state = try initState(allocator, parsed.value.State);
    result.image = try dupeOptionalString(allocator, parsed.value.Image);
    result.resolv_conf_path = try dupeOptionalString(allocator, parsed.value.ResolvConfPath);
    result.hostname_path = try dupeOptionalString(allocator, parsed.value.HostnamePath);
    result.hosts_path = try dupeOptionalString(allocator, parsed.value.HostsPath);
    result.log_path = try dupeOptionalString(allocator, parsed.value.LogPath);
    result.name = try dupeOptionalString(allocator, parsed.value.Name);
    result.driver = try dupeOptionalString(allocator, parsed.value.Driver);
    result.platform = try dupeOptionalString(allocator, parsed.value.Platform);
    result.mount_label = try dupeOptionalString(allocator, parsed.value.MountLabel);
    result.process_label = try dupeOptionalString(allocator, parsed.value.ProcessLabel);
    result.app_armor_profile = try dupeOptionalString(allocator, parsed.value.AppArmorProfile);
    result.exec_ids = try dupeStringList(allocator, parsed.value.ExecIDs);
    result.mounts = try dupeMounts(allocator, parsed.value.Mounts);

    return result;
}

fn initState(allocator: std.mem.Allocator, raw: ?wire.StateValue) !?Inspect.State {
    const state = raw orelse return null;
    var result = Inspect.State{
        .status = state.Status,
        .running = state.Running,
        .paused = state.Paused,
        .restarting = state.Restarting,
        .oom_killed = state.OOMKilled,
        .dead = state.Dead,
        .pid = state.Pid,
        .exit_code = state.ExitCode,
        .error_message = null,
        .started_at = null,
        .finished_at = null,
        .health = if (state.Health) |health| .{
            .status = health.Status,
            .failing_streak = health.FailingStreak,
        } else null,
    };
    errdefer {
        freeOptionalString(allocator, result.error_message);
        freeOptionalString(allocator, result.started_at);
        freeOptionalString(allocator, result.finished_at);
    }

    result.error_message = try dupeOptionalString(allocator, state.Error);
    result.started_at = try dupeOptionalString(allocator, state.StartedAt);
    result.finished_at = try dupeOptionalString(allocator, state.FinishedAt);

    return result;
}

fn dupeMounts(allocator: std.mem.Allocator, raw_mounts: ?[]const wire.Mount) ![]Mount {
    const mounts = raw_mounts orelse return try allocator.alloc(Mount, 0);
    const owned = try allocator.alloc(Mount, mounts.len);
    var filled: usize = 0;
    errdefer {
        summary_model.freeMountItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    for (mounts) |mount| {
        owned[filled] = try initMount(allocator, mount);
        filled += 1;
    }

    return owned;
}

fn initMount(allocator: std.mem.Allocator, raw: wire.Mount) !Mount {
    var mount = Mount{
        .mount_type = raw.Type,
        .name = null,
        .source = null,
        .destination = null,
        .driver = null,
        .mode = null,
        .read_write = raw.RW,
        .propagation = null,
    };
    errdefer freeMountFields(allocator, mount);

    mount.name = try dupeOptionalString(allocator, raw.Name);
    mount.source = try dupeOptionalString(allocator, raw.Source);
    mount.destination = try dupeOptionalString(allocator, raw.Destination);
    mount.driver = try dupeOptionalString(allocator, raw.Driver);
    mount.mode = try dupeOptionalString(allocator, raw.Mode);
    mount.propagation = try dupeOptionalString(allocator, raw.Propagation);

    return mount;
}

fn freeMountFields(allocator: std.mem.Allocator, mount: Mount) void {
    freeOptionalString(allocator, mount.name);
    freeOptionalString(allocator, mount.source);
    freeOptionalString(allocator, mount.destination);
    freeOptionalString(allocator, mount.driver);
    freeOptionalString(allocator, mount.mode);
    freeOptionalString(allocator, mount.propagation);
}

fn dupeStringList(allocator: std.mem.Allocator, raw_strings: ?[]const []const u8) ![]const []const u8 {
    const strings = raw_strings orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, strings.len);
    var filled: usize = 0;
    errdefer {
        summary_model.freeStringItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    for (strings) |string| {
        owned[filled] = try allocator.dupe(u8, string);
        filled += 1;
    }

    return owned;
}

fn dupeOptionalString(allocator: std.mem.Allocator, bytes: ?[]const u8) !?[]const u8 {
    if (bytes) |string| return try allocator.dupe(u8, string);
    return null;
}

fn freeStringList(allocator: std.mem.Allocator, strings: []const []const u8) void {
    summary_model.freeStringList(allocator, strings);
}

fn freeOptionalString(allocator: std.mem.Allocator, string: ?[]const u8) void {
    summary_model.freeOptionalString(allocator, string);
}

test "inspectPath encodes id and size query" {
    const path = try inspectPath(std.testing.allocator, "web name", .{ .size = true });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/web%20name/json?size=true", path);
}

test "parseInspect owns base inspect fields" {
    var result = try parseInspect(std.testing.allocator,
        \\{
        \\  "Id": "aa86eacfb3b3ed4cd362c1e88fc89a53908ad05fb3a4103bca3f9b28292d14bf",
        \\  "Created": "2025-02-17T17:43:39.64001363Z",
        \\  "Path": "/bin/sh",
        \\  "Args": ["-c", "exit 9"],
        \\  "State": {
        \\    "Status": "running",
        \\    "Running": true,
        \\    "Paused": false,
        \\    "Restarting": false,
        \\    "OOMKilled": false,
        \\    "Dead": false,
        \\    "Pid": 1234,
        \\    "ExitCode": 0,
        \\    "Error": "",
        \\    "StartedAt": "2020-01-06T09:06:59.461876391Z",
        \\    "FinishedAt": "2020-01-06T09:07:59.461876391Z",
        \\    "Health": {"Status": "healthy", "FailingStreak": 0}
        \\  },
        \\  "Image": "sha256:72297848456d5d37d1262630108ab308d3e9ec7ed1c3286a32fe09856619a782",
        \\  "Name": "/web",
        \\  "RestartCount": 1,
        \\  "Driver": "overlayfs",
        \\  "Platform": "linux",
        \\  "ExecIDs": ["exec-1"],
        \\  "SizeRw": 122880,
        \\  "SizeRootFs": 1653948416,
        \\  "Mounts": [{"Type": "bind", "Source": "/host", "Destination": "/ctr", "RW": true}]
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("aa86eacfb3b3ed4cd362c1e88fc89a53908ad05fb3a4103bca3f9b28292d14bf", result.id.?);
    try std.testing.expectEqualStrings("/bin/sh", result.path.?);
    try std.testing.expectEqualStrings("-c", result.args[0]);
    try std.testing.expectEqual(summary_model.Summary.State.running, result.state.?.status.?);
    try std.testing.expect(result.state.?.running.?);
    try std.testing.expectEqual(@as(i64, 1234), result.state.?.pid.?);
    try std.testing.expectEqual(summary_model.Summary.Health.Status.healthy, result.state.?.health.?.status.?);
    try std.testing.expectEqualStrings("/web", result.name.?);
    try std.testing.expectEqual(@as(i64, 1), result.restart_count.?);
    try std.testing.expectEqualStrings("exec-1", result.exec_ids[0]);
    try std.testing.expectEqual(@as(i64, 122880), result.size_rw.?);
    try std.testing.expectEqual(Mount.MountType.bind, result.mounts[0].mount_type.?);
    try std.testing.expectEqualStrings("/ctr", result.mounts[0].destination.?);
}

test "parseInspect cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseInspectForAllocationFailure,
        .{inspectBody()},
    );
}

fn parseInspectForAllocationFailure(allocator: std.mem.Allocator, body: []const u8) !void {
    var result = try parseInspect(allocator, body);
    result.deinit();
}

fn inspectBody() []const u8 {
    return (
        \\{
        \\  "Id": "container-id",
        \\  "Created": "2025-02-17T17:43:39.64001363Z",
        \\  "Path": "/bin/sh",
        \\  "Args": ["-c", "exit 9"],
        \\  "State": {
        \\    "Status": "running",
        \\    "Error": "",
        \\    "StartedAt": "2020-01-06T09:06:59.461876391Z",
        \\    "FinishedAt": "2020-01-06T09:07:59.461876391Z"
        \\  },
        \\  "Image": "sha256:72297848456d5d37d1262630108ab308d3e9ec7ed1c3286a32fe09856619a782",
        \\  "Name": "/web",
        \\  "ExecIDs": ["exec-1", "exec-2"],
        \\  "Mounts": [{
        \\    "Type": "bind",
        \\    "Name": "bind-mount",
        \\    "Source": "/host",
        \\    "Destination": "/ctr",
        \\    "Driver": "local",
        \\    "Mode": "rw",
        \\    "RW": true,
        \\    "Propagation": "rprivate"
        \\  }]
        \\}
    );
}
