const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");

pub const Start = enum {
    started,
    already_started,
};

pub const Stop = enum {
    stopped,
    already_stopped,
};

pub const StartOptions = struct {
    detach_keys: ?[]const u8 = null,
};

pub const StopOptions = struct {
    signal: ?[]const u8 = null,
    timeout_seconds: ?i64 = null,
};

pub const RestartOptions = struct {
    signal: ?[]const u8 = null,
    timeout_seconds: ?i64 = null,
};

pub const KillOptions = struct {
    signal: ?[]const u8 = null,
};

pub const RenameOptions = struct {
    name: []const u8,
};

pub const ResizeOptions = struct {
    height: u32,
    width: u32,
};

pub const RemoveOptions = struct {
    volumes: ?bool = null,
    force: ?bool = null,
    link: ?bool = null,
};

pub fn start(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: StartOptions) !Start {
    const path = try startPath(allocator, id, options);
    defer allocator.free(path);

    var response = try request(client, .post, path);
    defer response.deinit();

    return startResult(response.status());
}

pub fn stop(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: StopOptions) !Stop {
    const path = try stopPath(allocator, id, options);
    defer allocator.free(path);

    var response = try request(client, .post, path);
    defer response.deinit();

    return stopResult(response.status());
}

pub fn restart(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: RestartOptions) !void {
    const path = try stopLikePath(allocator, id, "/restart", options.signal, options.timeout_seconds);
    defer allocator.free(path);

    var response = try request(client, .post, path);
    defer response.deinit();

    try expectNoContent(response.status());
}

pub fn kill(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: KillOptions) !void {
    const path = try killPath(allocator, id, options);
    defer allocator.free(path);

    var response = try request(client, .post, path);
    defer response.deinit();

    switch (response.status()) {
        .no_content => {},
        .not_found => return error.ContainerNotFound,
        .conflict => return error.ContainerNotRunning,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn rename(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: RenameOptions) !void {
    const path = try renamePath(allocator, id, options);
    defer allocator.free(path);

    var response = try request(client, .post, path);
    defer response.deinit();

    switch (response.status()) {
        .no_content => {},
        .not_found => return error.ContainerNotFound,
        .conflict => return error.NameAlreadyInUse,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn pause(allocator: std.mem.Allocator, client: *Client, id: []const u8) !void {
    try postIdPath(allocator, client, id, "/pause");
}

pub fn unpause(allocator: std.mem.Allocator, client: *Client, id: []const u8) !void {
    try postIdPath(allocator, client, id, "/unpause");
}

pub fn resize(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: ResizeOptions) !void {
    const path = try resizePath(allocator, id, options);
    defer allocator.free(path);

    var response = try request(client, .post, path);
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ResizeFailed,
        else => return error.UnexpectedStatus,
    }
}

pub fn remove(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: RemoveOptions) !void {
    const path = try removePath(allocator, id, options);
    defer allocator.free(path);

    var response = try request(client, .delete, path);
    defer response.deinit();

    switch (response.status()) {
        .no_content => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ContainerNotFound,
        .conflict => return error.ContainerConflict,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

fn postIdPath(allocator: std.mem.Allocator, client: *Client, id: []const u8, suffix: []const u8) !void {
    const path = try url.pathWithSegment(allocator, "/containers/", id, suffix);
    defer allocator.free(path);

    var response = try request(client, .post, path);
    defer response.deinit();

    try expectNoContent(response.status());
}

fn request(client: *Client, method: @import("../http.zig").Method, path: []const u8) !Client.Response {
    return client.request(.{
        .method = method,
        .path = path,
    });
}

fn startPath(allocator: std.mem.Allocator, id: []const u8, options: StartOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/start");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.detach_keys) |detach_keys| try builder.add("detachKeys", detach_keys);

    return builder.finish();
}

fn stopPath(allocator: std.mem.Allocator, id: []const u8, options: StopOptions) ![]u8 {
    return stopLikePath(allocator, id, "/stop", options.signal, options.timeout_seconds);
}

fn stopLikePath(
    allocator: std.mem.Allocator,
    id: []const u8,
    suffix: []const u8,
    signal: ?[]const u8,
    timeout_seconds: ?i64,
) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, suffix);
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (signal) |value| try builder.add("signal", value);
    if (timeout_seconds) |value| try builder.addInt("t", value);

    return builder.finish();
}

fn killPath(allocator: std.mem.Allocator, id: []const u8, options: KillOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/kill");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.signal) |signal| try builder.add("signal", signal);

    return builder.finish();
}

fn renamePath(allocator: std.mem.Allocator, id: []const u8, options: RenameOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/rename");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    try builder.add("name", options.name);

    return builder.finish();
}

fn resizePath(allocator: std.mem.Allocator, id: []const u8, options: ResizeOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/resize");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    try builder.addInt("h", options.height);
    try builder.addInt("w", options.width);

    return builder.finish();
}

fn removePath(allocator: std.mem.Allocator, id: []const u8, options: RemoveOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.volumes) |volumes| try builder.addBool("v", volumes);
    if (options.force) |force| try builder.addBool("force", force);
    if (options.link) |link| try builder.addBool("link", link);

    return builder.finish();
}

fn startResult(status: @import("../http.zig").Status) !Start {
    return switch (status) {
        .no_content => .started,
        .not_modified => .already_started,
        .not_found => error.ContainerNotFound,
        .internal_server_error => error.ServerError,
        else => error.UnexpectedStatus,
    };
}

fn stopResult(status: @import("../http.zig").Status) !Stop {
    return switch (status) {
        .no_content => .stopped,
        .not_modified => .already_stopped,
        .not_found => error.ContainerNotFound,
        .internal_server_error => error.ServerError,
        else => error.UnexpectedStatus,
    };
}

fn expectNoContent(status: @import("../http.zig").Status) !void {
    switch (status) {
        .no_content => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

test "startPath encodes container id and detach keys" {
    const path = try startPath(std.testing.allocator, "web name", .{
        .detach_keys = "ctrl-p,ctrl-q",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/web%20name/start?detachKeys=ctrl-p%2Cctrl-q", path);
}

test "stop and restart paths encode signal and timeout" {
    const stop_path = try stopPath(std.testing.allocator, "web", .{
        .signal = "SIGINT",
        .timeout_seconds = 10,
    });
    defer std.testing.allocator.free(stop_path);

    const restart_path = try stopLikePath(std.testing.allocator, "web", "/restart", "SIGTERM", 3);
    defer std.testing.allocator.free(restart_path);

    try std.testing.expectEqualStrings("/containers/web/stop?signal=SIGINT&t=10", stop_path);
    try std.testing.expectEqualStrings("/containers/web/restart?signal=SIGTERM&t=3", restart_path);
}

test "kill rename resize and remove paths encode required query parameters" {
    const kill_path = try killPath(std.testing.allocator, "web", .{ .signal = "SIGKILL" });
    defer std.testing.allocator.free(kill_path);
    const rename_path = try renamePath(std.testing.allocator, "web", .{ .name = "new web" });
    defer std.testing.allocator.free(rename_path);
    const resize_path = try resizePath(std.testing.allocator, "web", .{ .height = 40, .width = 120 });
    defer std.testing.allocator.free(resize_path);
    const remove_path = try removePath(std.testing.allocator, "web", .{
        .volumes = true,
        .force = true,
        .link = false,
    });
    defer std.testing.allocator.free(remove_path);

    try std.testing.expectEqualStrings("/containers/web/kill?signal=SIGKILL", kill_path);
    try std.testing.expectEqualStrings("/containers/web/rename?name=new%20web", rename_path);
    try std.testing.expectEqualStrings("/containers/web/resize?h=40&w=120", resize_path);
    try std.testing.expectEqualStrings("/containers/web?v=true&force=true&link=false", remove_path);
}

test "start and stop preserve not-modified as business result" {
    try std.testing.expectEqual(Start.started, try startResult(.no_content));
    try std.testing.expectEqual(Start.already_started, try startResult(.not_modified));
    try std.testing.expectEqual(Stop.stopped, try stopResult(.no_content));
    try std.testing.expectEqual(Stop.already_stopped, try stopResult(.not_modified));
}
