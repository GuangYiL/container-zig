const std = @import("std");

const request_types = @import("http_request.zig");
const raw = @import("http_transport_raw.zig");
const standard = @import("http_transport_std.zig");

pub const Body = request_types.Body;
pub const Upload = request_types.Upload;
pub const Request = request_types.Request;

pub const Transport = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Transport {
        return .{
            .allocator = allocator,
            .io = io,
            .client = .{ .allocator = allocator, .io = io },
        };
    }

    pub fn deinit(self: *Transport) void {
        self.client.deinit();
        self.* = undefined;
    }

    pub fn request(self: *Transport, spec: Request) !Response {
        const exchange: Exchange = switch (spec.transport) {
            .unix_socket, .tcp, .tls => .{
                .standard = try standard.Exchange.create(
                    self.allocator,
                    self.io,
                    &self.client,
                    spec,
                ),
            },
            .named_pipe, .ssh, .custom => .{
                .raw = try raw.Exchange.create(self.allocator, self.io, spec),
            },
        };
        return .{ .exchange = exchange };
    }
};

const Exchange = union(enum) {
    standard: *standard.Exchange,
    raw: *raw.Exchange,

    fn deinit(self: *Exchange) void {
        switch (self.*) {
            .standard => |exchange| exchange.deinit(),
            .raw => |exchange| exchange.deinit(),
        }
        self.* = undefined;
    }

    fn status(self: *const Exchange) std.http.Status {
        return switch (self.*) {
            .standard => |exchange| exchange.status(),
            .raw => |exchange| exchange.status(),
        };
    }

    fn header(self: *const Exchange, name: []const u8) ?[]const u8 {
        return switch (self.*) {
            .standard => |exchange| exchange.header(name),
            .raw => |exchange| exchange.header(name),
        };
    }

    fn body(self: *Exchange) !?[]const u8 {
        return switch (self.*) {
            .standard => |exchange| exchange.bodyBytes(),
            .raw => |exchange| exchange.bodyBytes(),
        };
    }

    fn reader(self: *Exchange) *std.Io.Reader {
        return switch (self.*) {
            .standard => |exchange| exchange.bodyReader(),
            .raw => |exchange| exchange.bodyReader(),
        };
    }

    fn rawReader(self: *Exchange) *std.Io.Reader {
        return switch (self.*) {
            .standard => |exchange| exchange.rawReader(),
            .raw => |exchange| exchange.rawReader(),
        };
    }

    fn rawWriter(self: *Exchange) *std.Io.Writer {
        return switch (self.*) {
            .standard => |exchange| exchange.rawWriter(),
            .raw => |exchange| exchange.rawWriter(),
        };
    }

    fn closeWrite(self: *Exchange) !void {
        return switch (self.*) {
            .standard => |exchange| exchange.closeWrite(),
            .raw => |exchange| exchange.closeWrite(),
        };
    }

    fn random(self: *Exchange, bytes: []u8) void {
        switch (self.*) {
            .standard => |exchange| exchange.io.random(bytes),
            .raw => |exchange| exchange.io.random(bytes),
        }
    }
};

pub const Response = struct {
    exchange: ?Exchange,

    pub fn deinit(self: *Response) void {
        if (self.exchange) |*exchange| exchange.deinit();
        self.* = undefined;
    }

    pub fn status(self: *const Response) std.http.Status {
        return self.exchange.?.status();
    }

    pub fn header(self: *const Response, name: []const u8) ?[]const u8 {
        return self.exchange.?.header(name);
    }

    pub fn body(self: *Response) !?[]const u8 {
        return self.exchange.?.body();
    }

    pub fn reader(self: *Response) *std.Io.Reader {
        return self.exchange.?.reader();
    }

    pub fn takeBodyDuplex(self: *Response) Duplex {
        const exchange = self.exchange.?;
        self.exchange = null;
        return .{ .exchange = exchange, .read_mode = .body };
    }

    pub fn takeRawDuplex(self: *Response) Duplex {
        const exchange = self.exchange.?;
        self.exchange = null;
        return .{ .exchange = exchange, .read_mode = .raw };
    }
};

pub const Duplex = struct {
    exchange: Exchange,
    read_mode: ReadMode,

    const ReadMode = enum { body, raw };

    pub fn reader(self: *Duplex) *std.Io.Reader {
        return switch (self.read_mode) {
            .body => self.exchange.reader(),
            .raw => self.exchange.rawReader(),
        };
    }

    pub fn writer(self: *Duplex) *std.Io.Writer {
        return self.exchange.rawWriter();
    }

    pub fn closeWrite(self: *Duplex) !void {
        return self.exchange.closeWrite();
    }

    pub fn random(self: *Duplex, bytes: []u8) void {
        self.exchange.random(bytes);
    }

    pub fn deinit(self: *Duplex) void {
        self.exchange.deinit();
        self.* = undefined;
    }
};
