const std = @import("std");

const record = @import("record.zig");

pub const Message = struct {
    allocator: std.mem.Allocator,
    status: ?[]const u8,
    id: ?[]const u8,
    progress: ?[]const u8,
    stream: ?[]const u8,

    pub fn deinit(self: *Message) void {
        freeOptional(self.allocator, self.status);
        freeOptional(self.allocator, self.id);
        freeOptional(self.allocator, self.progress);
        freeOptional(self.allocator, self.stream);
        self.* = undefined;
    }
};

pub const DaemonError = struct {
    allocator: std.mem.Allocator,
    message: []const u8,

    pub fn deinit(self: *DaemonError) void {
        self.allocator.free(self.message);
        self.* = undefined;
    }
};

pub const Item = union(enum) {
    progress: Message,
    daemon_error: DaemonError,

    pub fn deinit(self: *Item) void {
        switch (self.*) {
            .progress => |*message| message.deinit(),
            .daemon_error => |*daemon_error| daemon_error.deinit(),
        }
        self.* = undefined;
    }
};

pub const Decoder = struct {
    records: record.Decoder,

    pub fn init(reader: *std.Io.Reader, format: record.Format, max_record_bytes: usize) Decoder {
        return .{ .records = .init(reader, format, max_record_bytes) };
    }

    pub fn next(self: *Decoder, allocator: std.mem.Allocator) !?Item {
        const bytes = try self.records.next(allocator) orelse return null;
        defer allocator.free(bytes);
        const parsed = try std.json.parseFromSlice(Wire, allocator, bytes, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });
        defer parsed.deinit();
        const error_message = if (parsed.value.errorDetail) |detail| detail.message else parsed.value.@"error";
        if (error_message) |message| {
            return .{ .daemon_error = .{
                .allocator = allocator,
                .message = try allocator.dupe(u8, message),
            } };
        }
        var message = Message{
            .allocator = allocator,
            .status = null,
            .id = null,
            .progress = null,
            .stream = null,
        };
        errdefer message.deinit();
        message.status = try dupeOptional(allocator, parsed.value.status);
        message.id = try dupeOptional(allocator, parsed.value.id);
        message.progress = try dupeOptional(allocator, parsed.value.progress);
        message.stream = try dupeOptional(allocator, parsed.value.stream);
        return .{ .progress = message };
    }
};

const Wire = struct {
    status: ?[]const u8 = null,
    id: ?[]const u8 = null,
    progress: ?[]const u8 = null,
    stream: ?[]const u8 = null,
    @"error": ?[]const u8 = null,
    errorDetail: ?struct { message: ?[]const u8 = null } = null,
};

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    return if (value) |text| try allocator.dupe(u8, text) else null;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |text| allocator.free(text);
}

test "progress decoder exposes daemon errors after HTTP success" {
    var reader = std.Io.Reader.fixed(
        "{\"status\":\"Downloading\",\"id\":\"layer\"}\n" ++
            "{\"errorDetail\":{\"message\":\"pull access denied\"}}\n",
    );
    var decoder = Decoder.init(&reader, .ndjson, 1024);
    var progress = (try decoder.next(std.testing.allocator)).?;
    defer progress.deinit();
    try std.testing.expectEqualStrings("Downloading", progress.progress.status.?);
    var daemon_error = (try decoder.next(std.testing.allocator)).?;
    defer daemon_error.deinit();
    try std.testing.expectEqualStrings("pull access denied", daemon_error.daemon_error.message);
}

test "progress decoder cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        decodeForAllocationFailure,
        .{},
    );
}

fn decodeForAllocationFailure(allocator: std.mem.Allocator) !void {
    var reader = std.Io.Reader.fixed("{\"status\":\"Downloading\",\"id\":\"layer\"}\n");
    var decoder = Decoder.init(&reader, .ndjson, 1024);
    var item = (try decoder.next(allocator)).?;
    item.deinit();
}
