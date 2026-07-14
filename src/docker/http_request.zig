const std = @import("std");

const http = @import("http.zig");
const Transport = @import("transport.zig").Transport;

pub const Body = union(enum) {
    none,
    bytes: []const u8,
    stream: Stream,

    pub const Stream = struct {
        reader: *std.Io.Reader,
        content_length: ?u64 = null,
    };
};

pub const Upload = union(enum) {
    bytes: []const u8,
    stream: Body.Stream,

    pub fn body(self: Upload) Body {
        return switch (self) {
            .bytes => |bytes| .{ .bytes = bytes },
            .stream => |stream| .{ .stream = stream },
        };
    }
};

pub const Request = struct {
    method: http.Method,
    path: []const u8,
    transport: Transport,
    headers: ?*const http.Headers,
    body: Body,
    user_agent: ?[]const u8,
};

test "Upload preserves streaming content length" {
    var reader = std.Io.Reader.fixed("tar");
    const upload = Upload{ .stream = .{ .reader = &reader, .content_length = 3 } };
    try std.testing.expectEqual(@as(?u64, 3), upload.body().stream.content_length);
}
