const std = @import("std");

const http = @import("http.zig");
const request_types = @import("http_request.zig");
const Transport = @import("transport.zig").Transport;

const read_buffer_size = 8192;
const write_buffer_size = 1024;
const max_response_size = 10 * 1024 * 1024;

pub const Exchange = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: *std.http.Client,
    url: []u8,
    extra_headers: []std.http.Header,
    stream: ?std.Io.net.Stream = null,
    read_buffer: []u8 = &.{},
    write_buffer: []u8 = &.{},
    connection: std.http.Client.Connection = undefined,
    request: std.http.Client.Request = undefined,
    response: std.http.Client.Response = undefined,
    header_bytes: []u8 = &.{},
    transfer_buffer: [64]u8 = undefined,
    cached_reader: std.Io.Reader = undefined,
    body: ?[]u8 = null,
    body_read: bool = false,
    request_initialized: bool = false,
    reader_initialized: bool = false,
    manual_connection: bool = false,

    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        client: *std.http.Client,
        spec: request_types.Request,
    ) !*Exchange {
        try spec.transport.validate();
        const url = try allocUrl(allocator, spec.transport, spec.path);
        var resources_transferred = false;
        errdefer if (!resources_transferred) allocator.free(url);
        const extra_headers = try copyExtraHeaders(allocator, spec.headers);
        errdefer if (!resources_transferred) allocator.free(extra_headers);

        const exchange = try allocator.create(Exchange);
        exchange.* = .{
            .allocator = allocator,
            .io = io,
            .client = client,
            .url = url,
            .extra_headers = extra_headers,
        };
        resources_transferred = true;
        errdefer exchange.deinit();

        const supplied_connection = switch (spec.transport) {
            .unix_socket => |config| try exchange.connectUnix(config.path),
            .tcp, .tls => null,
            else => return error.InvalidStandardTransport,
        };
        const uri = try std.Uri.parse(url);
        exchange.request = try client.request(spec.method.toStd(), uri, .{
            .connection = supplied_connection,
            .keep_alive = false,
            .redirect_behavior = .unhandled,
            .headers = standardHeaders(spec.headers, spec.user_agent),
            .extra_headers = exchange.extra_headers,
        });
        exchange.request_initialized = true;
        try exchange.send(spec.body);
        exchange.response = try exchange.request.receiveHead(&.{});
        exchange.header_bytes = try allocator.dupe(u8, exchange.response.head.bytes);
        exchange.request.extra_headers = &.{};
        exchange.request.privileged_headers = &.{};
        exchange.request.headers = .{};
        return exchange;
    }

    fn connectUnix(self: *Exchange, path: []const u8) !*std.http.Client.Connection {
        self.read_buffer = try self.allocator.alloc(u8, read_buffer_size);
        self.write_buffer = try self.allocator.alloc(u8, write_buffer_size);
        const address = try std.Io.net.UnixAddress.init(path);
        self.stream = try address.connect(self.io);
        const stream = self.stream.?;

        // Zig 0.16 and the target 0.17 snapshot cannot compile connectUnix.
        // Zig 0.16 和目标 0.17 快照中的 connectUnix 当前无法编译。
        // Keep explicit std.Io connection injection until the upstream API is fixed.
        // 上游修复前，保留显式 std.Io 连接注入。
        self.connection = .{
            .client = self.client,
            .stream_writer = stream.writer(self.io, self.write_buffer),
            .stream_reader = stream.reader(self.io, self.read_buffer),
            .pool_node = .{},
            .port = 0,
            .host_len = 0,
            .proxied = false,
            .closing = true,
            .protocol = .plain,
        };
        self.manual_connection = true;
        return &self.connection;
    }

    fn send(self: *Exchange, body: request_types.Body) !void {
        if (!self.request.method.requestHasBody()) {
            switch (body) {
                .none => {},
                else => return error.MethodCannotHaveBody,
            }
            return self.request.sendBodiless();
        }

        switch (body) {
            .none => self.request.transfer_encoding = .{ .content_length = 0 },
            .bytes => |bytes| self.request.transfer_encoding = .{ .content_length = bytes.len },
            .stream => |stream| self.request.transfer_encoding = if (stream.content_length) |length|
                .{ .content_length = length }
            else
                .chunked,
        }

        var body_writer = try self.request.sendBodyUnflushed(&.{});
        switch (body) {
            .none => {},
            .bytes => |bytes| try body_writer.writer.writeAll(bytes),
            .stream => |stream| {
                if (stream.content_length) |expected| {
                    try stream.reader.streamExact64(&body_writer.writer, expected);
                } else {
                    _ = try stream.reader.streamRemaining(&body_writer.writer);
                }
            },
        }
        try body_writer.end();
        try self.request.connection.?.flush();
    }

    pub fn status(self: *const Exchange) http.Status {
        return self.response.head.status;
    }

    pub fn header(self: *const Exchange, name: []const u8) ?[]const u8 {
        return findHeader(self.header_bytes, name);
    }

    pub fn bodyBytes(self: *Exchange) !?[]const u8 {
        if (self.body_read) return self.body;
        const response_body = self.bodyReader().allocRemaining(
            self.allocator,
            .limited(max_response_size),
        ) catch |err| switch (err) {
            error.StreamTooLong => return error.ResponseTooLarge,
            error.ReadFailed => return self.response.bodyErr() orelse error.ReadFailed,
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
        if (self.response.head.status == .switching_protocols) return self.rawReader();
        if (!self.reader_initialized) {
            _ = self.response.reader(&self.transfer_buffer);
            self.reader_initialized = true;
        }
        return &self.request.reader.interface;
    }

    pub fn rawReader(self: *Exchange) *std.Io.Reader {
        return self.request.connection.?.reader();
    }

    pub fn rawWriter(self: *Exchange) *std.Io.Writer {
        return self.request.connection.?.writer();
    }

    pub fn closeWrite(self: *Exchange) !void {
        const connection = self.request.connection.?;
        if (connection.protocol == .tls) return error.HalfCloseUnsupported;
        try connection.stream_writer.stream.shutdown(self.io, .send);
    }

    pub fn deinit(self: *Exchange) void {
        if (self.body) |body| self.allocator.free(body);
        if (self.header_bytes.len > 0) self.allocator.free(self.header_bytes);
        if (self.request_initialized) {
            if (self.manual_connection) self.request.connection = null;
            self.request.deinit();
        }
        if (self.stream) |stream| stream.close(self.io);
        if (self.write_buffer.len > 0) self.allocator.free(self.write_buffer);
        if (self.read_buffer.len > 0) self.allocator.free(self.read_buffer);
        self.allocator.free(self.extra_headers);
        self.allocator.free(self.url);
        self.allocator.destroy(self);
    }
};

fn allocUrl(allocator: std.mem.Allocator, transport: Transport, path: []const u8) ![]u8 {
    return switch (transport) {
        .unix_socket => std.fmt.allocPrint(allocator, "http://localhost{s}", .{path}),
        .tcp => |config| allocNetworkUrl(allocator, "http", config.host, config.port, path),
        .tls => |config| allocNetworkUrl(allocator, "https", config.host, config.port, path),
        else => error.InvalidStandardTransport,
    };
}

fn allocNetworkUrl(
    allocator: std.mem.Allocator,
    scheme: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
) ![]u8 {
    const bracketed = std.mem.indexOfScalar(u8, host, ':') != null and host[0] != '[';
    return if (bracketed)
        std.fmt.allocPrint(allocator, "{s}://[{s}]:{d}{s}", .{ scheme, host, port, path })
    else
        std.fmt.allocPrint(allocator, "{s}://{s}:{d}{s}", .{ scheme, host, port, path });
}

fn standardHeaders(source: ?*const http.Headers, user_agent: ?[]const u8) std.http.Client.Request.Headers {
    const headers = source orelse return .{
        .user_agent = if (user_agent) |value| .{ .override = value } else .omit,
        .connection = .{ .override = "close" },
    };
    return .{
        .host = overrideOrDefault(headers.get("Host")),
        .authorization = overrideOrDefault(headers.get("Authorization")),
        .user_agent = if (headers.get("User-Agent")) |value|
            .{ .override = value }
        else if (user_agent) |value|
            .{ .override = value }
        else
            .omit,
        .connection = if (headers.get("Connection")) |value|
            .{ .override = value }
        else
            .{ .override = "close" },
        .accept_encoding = overrideOrDefault(headers.get("Accept-Encoding")),
        .content_type = overrideOrDefault(headers.get("Content-Type")),
    };
}

fn overrideOrDefault(value: ?[]const u8) std.http.Client.Request.Headers.Value {
    return if (value) |header_value| .{ .override = header_value } else .default;
}

fn copyExtraHeaders(allocator: std.mem.Allocator, source: ?*const http.Headers) ![]std.http.Header {
    const headers = source orelse return try allocator.alloc(std.http.Header, 0);
    var count: usize = 0;
    for (headers.slice()) |entry| {
        try validateHeader(entry);
        if (!isStandardHeader(entry.name)) count += 1;
    }
    const result = try allocator.alloc(std.http.Header, count);
    var index: usize = 0;
    for (headers.slice()) |entry| if (!isStandardHeader(entry.name)) {
        result[index] = entry;
        index += 1;
    };
    return result;
}

fn isStandardHeader(name: []const u8) bool {
    inline for (.{ "Host", "Authorization", "User-Agent", "Connection", "Accept-Encoding", "Content-Type" }) |known| {
        if (std.ascii.eqlIgnoreCase(name, known)) return true;
    }
    return false;
}

fn validateHeader(entry: std.http.Header) !void {
    if (entry.name.len == 0 or std.mem.indexOfScalar(u8, entry.name, ':') != null) return error.InvalidHeader;
    if (std.mem.indexOfAny(u8, entry.name, "\r\n") != null) return error.InvalidHeader;
    if (std.mem.indexOfAny(u8, entry.value, "\r\n") != null) return error.InvalidHeader;
}

fn findHeader(bytes: []const u8, name: []const u8) ?[]const u8 {
    var iterator = std.http.HeaderIterator.init(bytes);
    while (iterator.next()) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
    }
    return null;
}

test "standard transport URLs preserve the selected scheme" {
    const tcp = try allocUrl(std.testing.allocator, .{ .tcp = .{ .host = "127.0.0.1" } }, "/_ping");
    defer std.testing.allocator.free(tcp);
    try std.testing.expectEqualStrings("http://127.0.0.1:2375/_ping", tcp);

    const tls = try allocUrl(std.testing.allocator, .{ .tls = .{ .host = "::1" } }, "/version");
    defer std.testing.allocator.free(tls);
    try std.testing.expectEqualStrings("https://[::1]:2376/version", tls);
}
