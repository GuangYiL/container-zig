const std = @import("std");

const transport = @import("http_transport.zig");

// TODO: Replace this implementation when Zig provides a client WebSocket API.
// TODO：Zig 提供客户端 WebSocket API 后替换此实现。
// Zig currently exposes only Server.WebSocket, whose frame semantics cannot serve a client.
// Zig 当前只公开 Server.WebSocket，其帧语义无法用于客户端。
pub const Client = struct {
    duplex: transport.Duplex,
    message_arena: std.heap.ArenaAllocator,
    fragmented_type: ?MessageType = null,
    fragmented_data: std.ArrayList(u8) = .empty,
    closed: bool = false,

    pub const max_message_size = 16 * 1024 * 1024;

    pub const MessageType = enum(u4) {
        continuation = 0x0,
        text = 0x1,
        binary = 0x2,
        close = 0x8,
        ping = 0x9,
        pong = 0xA,
        _,
    };

    pub const Message = struct {
        type: MessageType,
        data: []const u8,
        close_code: ?CloseCode = null,
    };

    pub const CloseCode = enum(u16) {
        normal = 1000,
        going_away = 1001,
        protocol_error = 1002,
        unsupported = 1003,
        no_status = 1005,
        abnormal = 1006,
        invalid_payload = 1007,
        policy_violation = 1008,
        too_large = 1009,
        mandatory_extension = 1010,
        internal_error = 1011,
        _,
    };

    pub const Error = error{
        ReservedFlags,
        LargeControlFrame,
        InvalidOpcode,
        UnexpectedContinuation,
        NestedFragment,
        InvalidUtf8,
        MessageTooLarge,
        MaskedServerFrame,
    };

    pub fn init(allocator: std.mem.Allocator, duplex: transport.Duplex) Client {
        return .{
            .duplex = duplex,
            .message_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Client) void {
        self.message_arena.deinit();
        self.duplex.deinit();
        self.* = undefined;
    }

    pub fn send(self: *Client, message_type: MessageType, data: []const u8) !void {
        if (self.closed) return error.EndOfStream;
        if (message_type != .text and message_type != .binary) return Error.InvalidOpcode;
        try self.writeFrame(message_type, data);
    }

    pub fn ping(self: *Client, data: []const u8) !void {
        if (self.closed) return error.EndOfStream;
        if (data.len > 125) return Error.LargeControlFrame;
        try self.writeFrame(.ping, data);
    }

    pub fn close(self: *Client, code: CloseCode, reason: []const u8) !void {
        if (self.closed) return;
        if (reason.len > 123) return Error.LargeControlFrame;
        self.closed = true;
        try self.writeCloseFrame(code, reason);
    }

    pub fn receive(self: *Client) !Message {
        _ = self.message_arena.reset(.retain_capacity);
        self.fragmented_data = .empty;
        self.fragmented_type = null;

        while (true) {
            const frame = try readServerFrame(
                self.message_arena.allocator(),
                self.duplex.reader(),
                max_message_size,
            );
            switch (frame.message_type) {
                .ping => {
                    try self.writeFrame(.pong, frame.payload);
                    continue;
                },
                .pong => continue,
                .close => return self.receiveClose(frame.payload),
                .continuation => {
                    const message_type = self.fragmented_type orelse return Error.UnexpectedContinuation;
                    try self.appendFragment(frame.payload);
                    if (frame.finished) return self.finishFragment(message_type);
                },
                .text, .binary => {
                    if (frame.finished) return completeMessage(frame.message_type, frame.payload);
                    if (self.fragmented_type != null) return Error.NestedFragment;
                    self.fragmented_type = frame.message_type;
                    try self.appendFragment(frame.payload);
                },
                else => return Error.InvalidOpcode,
            }
        }
    }

    fn receiveClose(self: *Client, payload: []const u8) !Message {
        self.closed = true;
        var code: ?CloseCode = null;
        var reason: []const u8 = "";
        if (payload.len == 1) return Error.InvalidOpcode;
        if (payload.len >= 2) {
            code = @enumFromInt(std.mem.readInt(u16, payload[0..2], .big));
            reason = payload[2..];
        }
        try self.writeCloseFrame(code orelse .normal, reason);
        return .{ .type = .close, .data = reason, .close_code = code };
    }

    fn appendFragment(self: *Client, payload: []const u8) !void {
        if (self.fragmented_data.items.len + payload.len > max_message_size) {
            return Error.MessageTooLarge;
        }
        try self.fragmented_data.appendSlice(self.message_arena.allocator(), payload);
    }

    fn finishFragment(self: *Client, message_type: MessageType) !Message {
        const data = try self.fragmented_data.toOwnedSlice(self.message_arena.allocator());
        self.fragmented_type = null;
        return completeMessage(message_type, data);
    }

    fn writeCloseFrame(self: *Client, code: CloseCode, reason: []const u8) !void {
        var payload: [125]u8 = undefined;
        std.mem.writeInt(u16, payload[0..2], @intFromEnum(code), .big);
        @memcpy(payload[2..][0..reason.len], reason);
        try self.writeFrame(.close, payload[0 .. reason.len + 2]);
    }

    fn writeFrame(self: *Client, message_type: MessageType, data: []const u8) !void {
        var mask: [4]u8 = undefined;
        self.duplex.random(&mask);
        try writeMaskedFrame(self.duplex.writer(), message_type, data, mask);
        try self.duplex.writer().flush();
    }
};

const Frame = struct {
    finished: bool,
    message_type: Client.MessageType,
    payload: []const u8,
};

fn completeMessage(message_type: Client.MessageType, payload: []const u8) !Client.Message {
    if (message_type == .text and !std.unicode.utf8ValidateSlice(payload)) {
        return Client.Error.InvalidUtf8;
    }
    return .{ .type = message_type, .data = payload };
}

fn readServerFrame(allocator: std.mem.Allocator, reader: *std.Io.Reader, limit: usize) !Frame {
    var header: [2]u8 = undefined;
    try reader.readSliceAll(&header);
    if (header[0] & 0x70 != 0) return Client.Error.ReservedFlags;
    if (header[1] & 0x80 != 0) return Client.Error.MaskedServerFrame;

    const message_type: Client.MessageType = @enumFromInt(@as(u4, @truncate(header[0])));
    var payload_length: u64 = header[1] & 0x7f;
    if (payload_length == 126) {
        var length: [2]u8 = undefined;
        try reader.readSliceAll(&length);
        payload_length = std.mem.readInt(u16, &length, .big);
    } else if (payload_length == 127) {
        var length: [8]u8 = undefined;
        try reader.readSliceAll(&length);
        payload_length = std.mem.readInt(u64, &length, .big);
    }

    const control = switch (message_type) {
        .close, .ping, .pong => true,
        else => false,
    };
    if (control and header[0] & 0x80 == 0) return Client.Error.InvalidOpcode;
    if (control and payload_length > 125) return Client.Error.LargeControlFrame;
    if (payload_length > limit) return Client.Error.MessageTooLarge;

    const payload = try allocator.alloc(u8, @intCast(payload_length));
    try reader.readSliceAll(payload);
    return .{
        .finished = header[0] & 0x80 != 0,
        .message_type = message_type,
        .payload = payload,
    };
}

fn writeMaskedFrame(
    writer: *std.Io.Writer,
    message_type: Client.MessageType,
    data: []const u8,
    mask: [4]u8,
) !void {
    try writer.writeByte(0x80 | @as(u8, @intFromEnum(message_type)));
    if (data.len < 126) {
        try writer.writeByte(0x80 | @as(u8, @intCast(data.len)));
    } else if (data.len <= std.math.maxInt(u16)) {
        try writer.writeByte(0x80 | 126);
        try writer.writeInt(u16, @intCast(data.len), .big);
    } else {
        try writer.writeByte(0x80 | 127);
        try writer.writeInt(u64, data.len, .big);
    }
    try writer.writeAll(&mask);

    var offset: usize = 0;
    var masked: [1024]u8 = undefined;
    while (offset < data.len) {
        const length = @min(masked.len, data.len - offset);
        for (data[offset..][0..length], 0..) |byte, index| {
            masked[index] = byte ^ mask[(offset + index) % mask.len];
        }
        try writer.writeAll(masked[0..length]);
        offset += length;
    }
}

test "client frame is masked" {
    var bytes: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try writeMaskedFrame(&writer, .text, "Hi", .{ 1, 2, 3, 4 });

    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0x82, 1, 2, 3, 4, 'H' ^ 1, 'i' ^ 2 }, writer.buffered());
}

test "server frame is decoded" {
    var reader = std.Io.Reader.fixed(&.{ 0x82, 0x03, 1, 2, 3 });
    const frame = try readServerFrame(std.testing.allocator, &reader, 16);
    defer std.testing.allocator.free(frame.payload);

    try std.testing.expect(frame.finished);
    try std.testing.expectEqual(Client.MessageType.binary, frame.message_type);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, frame.payload);
}
