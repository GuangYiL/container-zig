const std = @import("std");

pub const Pair = struct {
    name: []const u8,
    value: []const u8,
};

pub fn dupeList(allocator: std.mem.Allocator, raw_strings: ?[]const []const u8) ![]const []const u8 {
    const strings = raw_strings orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, strings.len);
    var filled: usize = 0;
    errdefer {
        freeList(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    for (strings) |string| {
        owned[filled] = try allocator.dupe(u8, string);
        filled += 1;
    }

    return owned;
}

pub fn freeList(allocator: std.mem.Allocator, strings: []const []const u8) void {
    for (strings) |string| allocator.free(string);
}

pub fn dupeOptional(allocator: std.mem.Allocator, raw_string: ?[]const u8) !?[]const u8 {
    if (raw_string) |string| return try allocator.dupe(u8, string);
    return null;
}

pub fn freeOptional(allocator: std.mem.Allocator, string: ?[]const u8) void {
    if (string) |value| allocator.free(value);
}

pub fn dupePairs(allocator: std.mem.Allocator, raw_pairs: ?std.json.ArrayHashMap([]const u8)) ![]Pair {
    const pairs = raw_pairs orelse return try allocator.alloc(Pair, 0);
    const owned = try allocator.alloc(Pair, pairs.map.count());
    var filled: usize = 0;
    errdefer {
        freePairs(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    var iterator = pairs.map.iterator();
    while (iterator.next()) |entry| {
        const name = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(name);
        const value = try allocator.dupe(u8, entry.value_ptr.*);
        owned[filled] = .{
            .name = name,
            .value = value,
        };
        filled += 1;
    }

    return owned;
}

pub fn freePairs(allocator: std.mem.Allocator, pairs: []const Pair) void {
    for (pairs) |pair| {
        allocator.free(pair.name);
        allocator.free(pair.value);
    }
}

test "dupeList owns copied strings" {
    const strings = try dupeList(std.testing.allocator, &.{ "a", "b" });
    defer {
        freeList(std.testing.allocator, strings);
        std.testing.allocator.free(strings);
    }

    try std.testing.expectEqualStrings("a", strings[0]);
    try std.testing.expectEqualStrings("b", strings[1]);
}
