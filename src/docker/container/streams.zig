const std = @import("std");

const Client = @import("../client.zig").Client;
const http = @import("../http.zig");
const query = @import("../query.zig");
const record = @import("../stream/record.zig");
const url = @import("../url.zig");

pub const ExportStream = struct {
    response: Client.Response,

    pub fn reader(self: *ExportStream) *std.Io.Reader {
        return self.response.reader();
    }

    pub fn deinit(self: *ExportStream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub const StatsOptions = struct {
    stream: ?bool = null,
    one_shot: ?bool = null,
    max_record_bytes: usize = 4 * 1024 * 1024,
};

pub const StatsStream = struct {
    response: Client.Response,
    decoder: ?record.Decoder,
    format: record.Format,
    max_record_bytes: usize,

    pub fn reader(self: *StatsStream) *std.Io.Reader {
        return self.response.reader();
    }

    pub fn next(self: *StatsStream, allocator: std.mem.Allocator) !?[]u8 {
        if (self.decoder == null) {
            self.decoder = .init(self.response.reader(), self.format, self.max_record_bytes);
        }
        return self.decoder.?.next(allocator);
    }

    pub fn deinit(self: *StatsStream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub fn exportArchive(allocator: std.mem.Allocator, client: *Client, id: []const u8) !ExportStream {
    const path = try url.pathWithSegment(allocator, "/containers/", id, "/export");
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    errdefer response.deinit();

    try expectStreamStatus(response.status());

    return .{ .response = response };
}

pub fn stats(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: StatsOptions) !StatsStream {
    const path = try statsPath(allocator, id, options);
    defer allocator.free(path);

    var headers = try statsHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .get,
        .path = path,
        .headers = &headers,
    });
    errdefer response.deinit();

    try expectStreamStatus(response.status());

    return .{
        .response = response,
        .decoder = null,
        .format = try record.Format.fromContentType(response.header("Content-Type")),
        .max_record_bytes = options.max_record_bytes,
    };
}

fn statsHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Accept", "application/x-ndjson");
    return headers;
}

fn statsPath(allocator: std.mem.Allocator, id: []const u8, options: StatsOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/stats");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.stream) |stream| try builder.addBool("stream", stream);
    if (options.one_shot) |one_shot| try builder.addBool("one-shot", one_shot);

    return builder.finish();
}

fn expectStreamStatus(status: @import("../http.zig").Status) !void {
    switch (status) {
        .ok => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

test "statsPath encodes stream and one-shot options" {
    const path = try statsPath(std.testing.allocator, "web name", .{
        .stream = false,
        .one_shot = true,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/web%20name/stats?stream=false&one-shot=true", path);
}

test "expectStreamStatus maps Docker stream errors" {
    try expectStreamStatus(.ok);
    try std.testing.expectError(error.ContainerNotFound, expectStreamStatus(.not_found));
    try std.testing.expectError(error.ServerError, expectStreamStatus(.internal_server_error));
}
