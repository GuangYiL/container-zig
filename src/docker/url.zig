const std = @import("std");

pub fn appendPercentEncoded(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), value: []const u8) !void {
    for (value) |byte| {
        if (isUnreserved(byte)) {
            try bytes.append(allocator, byte);
        } else {
            try bytes.append(allocator, '%');
            try bytes.append(allocator, hexDigit(byte >> 4));
            try bytes.append(allocator, hexDigit(byte & 0x0f));
        }
    }
}

pub fn pathWithSegment(
    allocator: std.mem.Allocator,
    prefix: []const u8,
    segment: []const u8,
    suffix: []const u8,
) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.appendSlice(allocator, prefix);
    try appendPercentEncoded(allocator, &bytes, segment);
    try bytes.appendSlice(allocator, suffix);

    return bytes.toOwnedSlice(allocator);
}

fn hexDigit(value: u8) u8 {
    return if (value < 10) '0' + value else 'A' + (value - 10);
}

fn isUnreserved(byte: u8) bool {
    return switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

test "pathWithSegment percent-encodes path segment" {
    const path = try pathWithSegment(std.testing.allocator, "/containers/", "name with space", "/json");
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/name%20with%20space/json", path);
}
