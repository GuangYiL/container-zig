const std = @import("std");

const http = @import("http.zig");
const request_types = @import("http_request.zig");
const transport_connection = @import("transport_connection.zig");

const max_response_size = 10 * 1024 * 1024;

pub const Exchange = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    connection: @import("transport.zig").Transport.Connection,
    http_reader: std.http.Reader,
    response_head: std.http.Client.Response.Head = undefined,
    header_bytes: []u8 = &.{},
    transfer_buffer: [64]u8 = undefined,
    cached_reader: std.Io.Reader = undefined,
    body: ?[]u8 = null,
    body_read: bool = false,
    reader_initialized: bool = false,

    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        spec: request_types.Request,
    ) !*Exchange {
        const connection = try transport_connection.connect(allocator, io, spec.transport);
        var connection_transferred = false;
        errdefer if (!connection_transferred) {
            var mutable = connection;
            mutable.close();
        };
        const exchange = try allocator.create(Exchange);
        exchange.* = .{
            .allocator = allocator,
            .io = io,
            .connection = connection,
            .http_reader = .{
                .in = connection.reader,
                .interface = undefined,
                .state = .ready,
                .max_head_len = 8192,
            },
        };
        connection_transferred = true;
        errdefer exchange.deinit();

        try exchange.send(spec);
        const borrowed_head = try exchange.http_reader.receiveHead();
        exchange.header_bytes = try allocator.dupe(u8, borrowed_head);
        exchange.response_head = try std.http.Client.Response.Head.parse(exchange.header_bytes);
        return exchange;
    }

    fn send(self: *Exchange, spec: request_types.Request) !void {
        const writer = self.connection.writer;
        if (spec.headers) |headers| {
            for (headers.slice()) |entry| try validateHeader(entry);
        }
        const host_header = if (spec.headers) |headers| headers.get("Host") orelse "docker" else "docker";
        const connection_header = if (spec.headers) |headers|
            headers.get("Connection") orelse "close"
        else
            "close";
        try writer.print("{s} {s} HTTP/1.1\r\nHost: {s}\r\nConnection: {s}\r\n", .{
            @tagName(spec.method.toStd()),
            spec.path,
            host_header,
            connection_header,
        });
        const user_agent = if (spec.headers) |headers|
            headers.get("User-Agent") orelse spec.user_agent
        else
            spec.user_agent;
        if (user_agent) |value| {
            try writer.print("User-Agent: {s}\r\n", .{value});
        }
        if (spec.headers) |headers| for (headers.slice()) |entry| {
            if (isManagedHeader(entry.name)) continue;
            try writer.print("{s}: {s}\r\n", .{ entry.name, entry.value });
        };

        switch (spec.body) {
            .none => if (spec.method.toStd().requestHasBody()) try writer.writeAll("Content-Length: 0\r\n"),
            .bytes => |bytes| try writer.print("Content-Length: {d}\r\n", .{bytes.len}),
            .stream => |stream| if (stream.content_length) |length|
                try writer.print("Content-Length: {d}\r\n", .{length})
            else
                try writer.writeAll("Transfer-Encoding: chunked\r\n"),
        }
        try writer.writeAll("\r\n");
        try writeBody(writer, spec.body);
        try writer.flush();
    }

    pub fn status(self: *const Exchange) http.Status {
        return self.response_head.status;
    }

    pub fn header(self: *const Exchange, name: []const u8) ?[]const u8 {
        var iterator = std.http.HeaderIterator.init(self.header_bytes);
        while (iterator.next()) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
        }
        return null;
    }

    pub fn bodyBytes(self: *Exchange) !?[]const u8 {
        if (self.body_read) return self.body;
        const response_body = self.bodyReader().allocRemaining(
            self.allocator,
            .limited(max_response_size),
        ) catch |err| switch (err) {
            error.StreamTooLong => return error.ResponseTooLarge,
            else => |read_error| return read_error,
        };
        self.body_read = true;
        if (response_body.len == 0) {
            self.allocator.free(response_body);
            return null;
        }
        self.body = response_body;
        return response_body;
    }

    pub fn bodyReader(self: *Exchange) *std.Io.Reader {
        if (self.body_read) {
            self.cached_reader = .fixed(self.body orelse &.{});
            return &self.cached_reader;
        }
        if (self.response_head.status == .switching_protocols) return self.connection.reader;
        if (!self.reader_initialized) {
            _ = self.http_reader.bodyReader(
                &self.transfer_buffer,
                self.response_head.transfer_encoding,
                self.response_head.content_length,
            );
            self.reader_initialized = true;
        }
        return &self.http_reader.interface;
    }

    pub fn rawReader(self: *Exchange) *std.Io.Reader {
        return self.connection.reader;
    }

    pub fn rawWriter(self: *Exchange) *std.Io.Writer {
        return self.connection.writer;
    }

    pub fn closeWrite(self: *Exchange) !void {
        try self.connection.closeWrite();
    }

    pub fn deinit(self: *Exchange) void {
        if (self.body) |body| self.allocator.free(body);
        if (self.header_bytes.len > 0) self.allocator.free(self.header_bytes);
        self.connection.close();
        self.allocator.destroy(self);
    }
};

fn writeBody(writer: *std.Io.Writer, body: request_types.Body) !void {
    switch (body) {
        .none => {},
        .bytes => |bytes| try writer.writeAll(bytes),
        .stream => |stream| if (stream.content_length) |expected| {
            try stream.reader.streamExact64(writer, expected);
        } else {
            var buffer: [8192]u8 = undefined;
            while (true) {
                const count = try stream.reader.readSliceShort(&buffer);
                if (count == 0) break;
                try writer.print("{x}\r\n", .{count});
                try writer.writeAll(buffer[0..count]);
                try writer.writeAll("\r\n");
            }
            try writer.writeAll("0\r\n\r\n");
        },
    }
}

fn isManagedHeader(name: []const u8) bool {
    inline for (.{ "Host", "User-Agent", "Connection", "Content-Length", "Transfer-Encoding" }) |managed| {
        if (std.ascii.eqlIgnoreCase(name, managed)) return true;
    }
    return false;
}

fn validateHeader(entry: std.http.Header) !void {
    if (entry.name.len == 0 or std.mem.indexOfScalar(u8, entry.name, ':') != null) return error.InvalidHeader;
    if (std.mem.indexOfAny(u8, entry.name, "\r\n") != null) return error.InvalidHeader;
    if (std.mem.indexOfAny(u8, entry.value, "\r\n") != null) return error.InvalidHeader;
}

const TestConnection = struct {
    response: []const u8,
    request_buffer: [4096]u8 = undefined,
    reader: std.Io.Reader = undefined,
    writer: std.Io.Writer = undefined,
    closed: bool = false,

    fn init(response: []const u8) TestConnection {
        var result = TestConnection{ .response = response };
        result.reader = .fixed(response);
        result.writer = .fixed(&result.request_buffer);
        return result;
    }

    fn connect(context: *anyopaque, _: std.mem.Allocator, _: std.Io) !@import("transport.zig").Transport.Connection {
        const state: *TestConnection = @ptrCast(@alignCast(context));
        state.reader = .fixed(state.response);
        state.writer = .fixed(&state.request_buffer);
        return .{
            .context = state,
            .reader = &state.reader,
            .writer = &state.writer,
            .vtable = &.{ .close = close, .close_write = closeWrite },
        };
    }

    fn close(context: *anyopaque) void {
        const state: *TestConnection = @ptrCast(@alignCast(context));
        state.closed = true;
    }

    fn closeWrite(_: *anyopaque) !void {}
};

test "raw transport streams chunked requests and parses responses" {
    var state = TestConnection.init(
        "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Type: text/plain\r\n\r\nOK",
    );
    var source = std.Io.Reader.fixed("abcdef");
    var headers = try http.Headers.init(std.testing.allocator, 4);
    defer headers.deinit(std.testing.allocator);
    try headers.put("Connection", "Upgrade");
    try headers.put("Upgrade", "tcp");
    try headers.put("Host", "docker.test");
    try headers.put("User-Agent", "custom-agent");

    const custom = @import("transport.zig").Transport.Custom{
        .context = &state,
        .connect_fn = TestConnection.connect,
    };
    const exchange = try Exchange.create(std.testing.allocator, std.testing.io, .{
        .method = .post,
        .path = "/v1.55/test",
        .transport = .{ .custom = custom },
        .headers = &headers,
        .body = .{ .stream = .{ .reader = &source } },
        .user_agent = "container-zig/test",
    });
    defer exchange.deinit();

    try std.testing.expectEqual(http.Status.ok, exchange.status());
    try std.testing.expectEqualStrings("OK", (try exchange.bodyBytes()).?);
    const request = state.request_buffer[0..state.writer.end];
    try std.testing.expect(std.mem.containsAtLeast(u8, request, 1, "Host: docker.test\r\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, request, 1, "User-Agent: custom-agent\r\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, request, 1, "Connection: Upgrade\r\n"));
    try std.testing.expect(std.mem.containsAtLeast(u8, request, 1, "Transfer-Encoding: chunked\r\n"));
    try std.testing.expect(std.mem.endsWith(u8, request, "6\r\nabcdef\r\n0\r\n\r\n"));
}
