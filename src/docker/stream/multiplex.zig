const std = @import("std");

pub const Stream = enum(u8) {
    stdin = 0,
    stdout = 1,
    stderr = 2,
};

pub const Frame = struct {
    allocator: std.mem.Allocator,
    stream: Stream,
    data: []u8,

    pub fn deinit(self: *Frame) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

pub const Decoder = struct {
    reader: *std.Io.Reader,
    max_frame_bytes: usize,

    pub fn init(reader: *std.Io.Reader, max_frame_bytes: usize) Decoder {
        return .{ .reader = reader, .max_frame_bytes = max_frame_bytes };
    }

    pub fn next(self: *Decoder, allocator: std.mem.Allocator) !?Frame {
        var header: [8]u8 = undefined;
        header[0] = self.reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => return null,
            else => return err,
        };
        try self.reader.readSliceAll(header[1..]);
        if (header[1] != 0 or header[2] != 0 or header[3] != 0) return error.InvalidMultiplexFrame;
        const stream: Stream = switch (header[0]) {
            0 => .stdin,
            1 => .stdout,
            2 => .stderr,
            else => return error.InvalidMultiplexStream,
        };
        const length = std.mem.readInt(u32, header[4..8], .big);
        if (length > self.max_frame_bytes) return error.MultiplexFrameTooLarge;
        const data = try allocator.alloc(u8, length);
        errdefer allocator.free(data);
        try self.reader.readSliceAll(data);
        return .{ .allocator = allocator, .stream = stream, .data = data };
    }
};

test "multiplex decoder preserves binary stdout and stderr" {
    var reader = std.Io.Reader.fixed(&.{
        1, 0, 0, 0, 0, 0, 0, 3, 0, 1, 2,
        2, 0, 0, 0, 0, 0, 0, 2, 3, 4,
    });
    var decoder = Decoder.init(&reader, 16);
    var stdout = (try decoder.next(std.testing.allocator)).?;
    defer stdout.deinit();
    var stderr = (try decoder.next(std.testing.allocator)).?;
    defer stderr.deinit();
    try std.testing.expectEqual(Stream.stdout, stdout.stream);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2 }, stdout.data);
    try std.testing.expectEqual(Stream.stderr, stderr.stream);
    try std.testing.expectEqualSlices(u8, &.{ 3, 4 }, stderr.data);
}

test "multiplex decoder rejects incomplete and oversized frames" {
    var incomplete_reader = std.Io.Reader.fixed(&.{ 1, 0, 0, 0, 0, 0, 0 });
    var incomplete = Decoder.init(&incomplete_reader, 16);
    try std.testing.expectError(error.EndOfStream, incomplete.next(std.testing.allocator));

    var large_reader = std.Io.Reader.fixed(&.{ 1, 0, 0, 0, 0, 0, 1, 0 });
    var large = Decoder.init(&large_reader, 16);
    try std.testing.expectError(error.MultiplexFrameTooLarge, large.next(std.testing.allocator));
}
