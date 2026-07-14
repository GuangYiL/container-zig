const std = @import("std");

pub const Pair = struct {
    name: []const u8,
    value: []const u8,
};

pub const Filter = struct {
    name: []const u8,
    values: []const []const u8,
};

pub fn stringMap(allocator: std.mem.Allocator, pairs: []const Pair) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.append(allocator, '{');
    for (pairs, 0..) |pair, index| {
        if (index != 0) try bytes.append(allocator, ',');
        try appendJsonString(allocator, &bytes, pair.name);
        try bytes.append(allocator, ':');
        try appendJsonString(allocator, &bytes, pair.value);
    }
    try bytes.append(allocator, '}');

    return bytes.toOwnedSlice(allocator);
}

pub fn filters(allocator: std.mem.Allocator, entries: []const Filter) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.append(allocator, '{');
    for (entries, 0..) |entry, index| {
        if (index != 0) try bytes.append(allocator, ',');
        try appendJsonString(allocator, &bytes, entry.name);
        try bytes.appendSlice(allocator, ":[");
        for (entry.values, 0..) |value, value_index| {
            if (value_index != 0) try bytes.append(allocator, ',');
            try appendJsonString(allocator, &bytes, value);
        }
        try bytes.append(allocator, ']');
    }
    try bytes.append(allocator, '}');

    return bytes.toOwnedSlice(allocator);
}

fn appendJsonString(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), value: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(encoded);
    try bytes.appendSlice(allocator, encoded);
}

test "filters builds Docker filter JSON" {
    const value = try filters(std.testing.allocator, &.{
        .{ .name = "status", .values = &.{ "running", "paused" } },
        .{ .name = "label", .values = &.{"com.example.vendor=Acme"} },
    });
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings(
        "{\"status\":[\"running\",\"paused\"],\"label\":[\"com.example.vendor=Acme\"]}",
        value,
    );
}

test "stringMap builds JSON object parameters" {
    const value = try stringMap(std.testing.allocator, &.{
        .{ .name = "HTTP_PROXY", .value = "http://proxy.example" },
        .{ .name = "quote", .value = "a\"b" },
    });
    defer std.testing.allocator.free(value);

    try std.testing.expectEqualStrings(
        "{\"HTTP_PROXY\":\"http://proxy.example\",\"quote\":\"a\\\"b\"}",
        value,
    );
}
