const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const multiplex = @import("../stream/multiplex.zig");
const url = @import("../url.zig");

pub const LogsOptions = struct {
    follow: ?bool = null,
    stdout: ?bool = null,
    stderr: ?bool = null,
    since: ?i64 = null,
    until: ?i64 = null,
    timestamps: ?bool = null,
    tail: ?[]const u8 = null,
    tty: bool = false,
    max_frame_bytes: usize = 16 * 1024 * 1024,
};

pub const LogStream = struct {
    response: Client.Response,
    tty: bool,
    decoder: ?multiplex.Decoder,
    max_frame_bytes: usize,

    pub fn reader(self: *LogStream) *std.Io.Reader {
        return self.response.reader();
    }

    pub fn nextFrame(self: *LogStream, allocator: std.mem.Allocator) !?multiplex.Frame {
        if (self.tty) return error.TtyUsesRawStream;
        if (self.decoder == null) {
            self.decoder = .init(self.response.reader(), self.max_frame_bytes);
        }
        return self.decoder.?.next(allocator);
    }

    pub fn deinit(self: *LogStream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub fn logs(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: LogsOptions) !LogStream {
    const path = try logsPath(allocator, id, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    errdefer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    return .{
        .response = response,
        .tty = options.tty,
        .decoder = null,
        .max_frame_bytes = options.max_frame_bytes,
    };
}

fn logsPath(allocator: std.mem.Allocator, id: []const u8, options: LogsOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/logs");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.follow) |follow| try builder.addBool("follow", follow);
    if (options.stdout) |stdout| try builder.addBool("stdout", stdout);
    if (options.stderr) |stderr| try builder.addBool("stderr", stderr);
    if (options.since) |since| try builder.addInt("since", since);
    if (options.until) |until| try builder.addInt("until", until);
    if (options.timestamps) |timestamps| try builder.addBool("timestamps", timestamps);
    if (options.tail) |tail| try builder.add("tail", tail);

    return builder.finish();
}

test "logsPath encodes log options" {
    const path = try logsPath(std.testing.allocator, "web", .{
        .follow = true,
        .stdout = true,
        .stderr = false,
        .since = 1629574695,
        .until = 1629574700,
        .timestamps = true,
        .tail = "100",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/web/logs?follow=true&stdout=true&stderr=false&since=1629574695" ++
            "&until=1629574700&timestamps=true&tail=100",
        path,
    );
}
