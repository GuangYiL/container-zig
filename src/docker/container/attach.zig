const std = @import("std");

const Client = @import("../client.zig").Client;
const http = @import("../http.zig");
const query = @import("../query.zig");
const Session = @import("../stream/session.zig").Session;
const url = @import("../url.zig");

pub const AttachOptions = struct {
    detach_keys: ?[]const u8 = null,
    logs: ?bool = null,
    stream: ?bool = null,
    stdin: ?bool = null,
    stdout: ?bool = null,
    stderr: ?bool = null,
    tty: bool = false,
    max_frame_bytes: usize = 16 * 1024 * 1024,
};

pub fn attach(
    allocator: std.mem.Allocator,
    client: *Client,
    id: []const u8,
    options: AttachOptions,
) !Session {
    const path = try attachEndpointPath(allocator, id, "/attach", options);
    defer allocator.free(path);

    var headers = try upgradeHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
    });
    errdefer response.deinit();

    switch (response.status()) {
        .ok, .switching_protocols => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const duplex = if (response.status() == .switching_protocols)
        response.takeRawDuplex()
    else
        response.takeBodyDuplex();
    return Session.init(duplex, options.tty, options.max_frame_bytes);
}

pub fn attachWebSocket(
    allocator: std.mem.Allocator,
    client: *Client,
    id: []const u8,
    options: AttachOptions,
) !Client.WebSocket {
    const path = try attachEndpointPath(allocator, id, "/attach/ws", options);
    defer allocator.free(path);

    return client.webSocket(.{ .path = path });
}

fn attachEndpointPath(
    allocator: std.mem.Allocator,
    id: []const u8,
    endpoint_suffix: []const u8,
    options: AttachOptions,
) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, endpoint_suffix);
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.detach_keys) |detach_keys| try builder.add("detachKeys", detach_keys);
    if (options.logs) |logs| try builder.addBool("logs", logs);
    if (options.stream) |stream| try builder.addBool("stream", stream);
    if (options.stdin) |stdin| try builder.addBool("stdin", stdin);
    if (options.stdout) |stdout| try builder.addBool("stdout", stdout);
    if (options.stderr) |stderr| try builder.addBool("stderr", stderr);

    return builder.finish();
}

fn upgradeHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 2);
    errdefer headers.deinit(allocator);
    try headers.put("Connection", "Upgrade");
    try headers.put("Upgrade", "tcp");
    return headers;
}

test "attachPath encodes stream selectors" {
    const path = try attachEndpointPath(std.testing.allocator, "web name", "/attach", .{
        .detach_keys = "ctrl-p,ctrl-q",
        .logs = true,
        .stream = true,
        .stdin = false,
        .stdout = true,
        .stderr = true,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/web%20name/attach?detachKeys=ctrl-p%2Cctrl-q&logs=true" ++
            "&stream=true&stdin=false&stdout=true&stderr=true",
        path,
    );
}

test "attachEndpointPath encodes websocket path" {
    const path = try attachEndpointPath(std.testing.allocator, "web name", "/attach/ws", .{
        .logs = false,
        .stream = true,
        .stdin = true,
        .stdout = true,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/web%20name/attach/ws?logs=false&stream=true&stdin=true&stdout=true",
        path,
    );
}
