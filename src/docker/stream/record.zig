const std = @import("std");

pub const Format = enum {
    ndjson,
    json_sequence,

    pub fn fromContentType(value: ?[]const u8) !Format {
        const content_type = std.mem.trim(u8, value orelse "application/x-ndjson", " \t");
        const media_type = std.mem.trim(u8, std.mem.sliceTo(content_type, ';'), " \t");
        if (std.ascii.eqlIgnoreCase(media_type, "application/x-ndjson") or
            std.ascii.eqlIgnoreCase(media_type, "application/jsonl") or
            std.ascii.eqlIgnoreCase(media_type, "application/json")) return .ndjson;
        if (std.ascii.eqlIgnoreCase(media_type, "application/json-seq")) return .json_sequence;
        return error.UnsupportedStreamContentType;
    }
};

pub const Decoder = struct {
    reader: *std.Io.Reader,
    format: Format,
    max_record_bytes: usize,
    sequence_started: bool = false,

    pub fn init(reader: *std.Io.Reader, format: Format, max_record_bytes: usize) Decoder {
        return .{
            .reader = reader,
            .format = format,
            .max_record_bytes = max_record_bytes,
        };
    }

    pub fn next(self: *Decoder, allocator: std.mem.Allocator) !?[]u8 {
        while (true) {
            const record = switch (self.format) {
                .ndjson => try self.readDelimited(allocator, '\n'),
                .json_sequence => try self.readSequence(allocator),
            } orelse return null;
            const trimmed = std.mem.trim(u8, record, "\r\n \t");
            if (trimmed.len == 0) {
                allocator.free(record);
                continue;
            }
            if (trimmed.ptr == record.ptr and trimmed.len == record.len) return record;
            const result = try allocator.dupe(u8, trimmed);
            allocator.free(record);
            return result;
        }
    }

    fn readSequence(self: *Decoder, allocator: std.mem.Allocator) !?[]u8 {
        if (!self.sequence_started) {
            const marker = self.reader.takeByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => return err,
            };
            if (marker != 0x1e) return error.InvalidJsonSequence;
            self.sequence_started = true;
        }
        const record = try self.readDelimited(allocator, 0x1e);
        if (record != null) self.sequence_started = true;
        return record;
    }

    fn readDelimited(self: *Decoder, allocator: std.mem.Allocator, delimiter: u8) !?[]u8 {
        var writer: std.Io.Writer.Allocating = .init(allocator);
        errdefer writer.deinit();
        const count = self.reader.streamDelimiterLimit(
            &writer.writer,
            delimiter,
            .limited(self.max_record_bytes),
        ) catch |err| switch (err) {
            error.StreamTooLong => return error.StreamRecordTooLarge,
            error.WriteFailed => return error.OutOfMemory,
            else => return err,
        };
        const consumed = consume(self.reader, delimiter) catch |err| switch (err) {
            error.EndOfStream => false,
            else => return err,
        };
        if (count == 0 and !consumed) {
            writer.deinit();
            return null;
        }
        return try writer.toOwnedSlice();
    }
};

fn consume(reader: *std.Io.Reader, delimiter: u8) !bool {
    const byte = reader.peekByte() catch |err| switch (err) {
        error.EndOfStream => return false,
        else => return err,
    };
    if (byte != delimiter) return false;
    reader.toss(1);
    return true;
}

test "record decoder handles NDJSON records" {
    var reader = std.Io.Reader.fixed("{\"id\":1}\n{\"id\":2}\n");
    var decoder = Decoder.init(&reader, .ndjson, 128);
    const first = (try decoder.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(first);
    const second = (try decoder.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings("{\"id\":1}", first);
    try std.testing.expectEqualStrings("{\"id\":2}", second);
    try std.testing.expect((try decoder.next(std.testing.allocator)) == null);
}

test "record decoder handles RFC 7464 JSON sequences" {
    var reader = std.Io.Reader.fixed("\x1e{\"id\":1}\n\x1e{\"id\":2}\n");
    var decoder = Decoder.init(&reader, .json_sequence, 128);
    const first = (try decoder.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(first);
    const second = (try decoder.next(std.testing.allocator)).?;
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings("{\"id\":1}", first);
    try std.testing.expectEqualStrings("{\"id\":2}", second);
}

test "record format validates content type" {
    try std.testing.expectEqual(Format.ndjson, try Format.fromContentType("application/x-ndjson; charset=utf-8"));
    try std.testing.expectEqual(Format.json_sequence, try Format.fromContentType("application/json-seq"));
    try std.testing.expectError(error.UnsupportedStreamContentType, Format.fromContentType("text/plain"));
}
