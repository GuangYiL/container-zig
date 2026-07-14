const std = @import("std");

const url = @import("url.zig");

pub const Builder = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    has_query: bool = false,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Builder {
        var bytes: std.ArrayList(u8) = .empty;
        errdefer bytes.deinit(allocator);
        try bytes.appendSlice(allocator, path);
        return .{ .allocator = allocator, .bytes = bytes };
    }

    pub fn add(self: *Builder, name: []const u8, value: []const u8) !void {
        try self.bytes.append(self.allocator, if (self.has_query) '&' else '?');
        self.has_query = true;
        try url.appendPercentEncoded(self.allocator, &self.bytes, name);
        try self.bytes.append(self.allocator, '=');
        try url.appendPercentEncoded(self.allocator, &self.bytes, value);
    }

    pub fn addBool(self: *Builder, name: []const u8, value: bool) !void {
        try self.add(name, if (value) "true" else "false");
    }

    pub fn addInt(self: *Builder, name: []const u8, value: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, "{}", .{value});
        defer self.allocator.free(text);
        try self.add(name, text);
    }

    pub fn finish(self: *Builder) ![]u8 {
        return self.bytes.toOwnedSlice(self.allocator);
    }

    pub fn deinit(self: *Builder) void {
        self.bytes.deinit(self.allocator);
        self.* = undefined;
    }
};

test "Builder percent-encodes query parameters" {
    var builder = try Builder.init(std.testing.allocator, "/events");
    defer builder.deinit();

    try builder.add("since", "2026-07-02T10:11:12+08:00");
    try builder.add("filters", "{\"type\":[\"container\"]}");
    const path = try builder.finish();
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/events?since=2026-07-02T10%3A11%3A12%2B08%3A00&filters=%7B%22type%22%3A%5B%22container%22%5D%7D",
        path,
    );
}

test "Builder formats integer query parameters" {
    var builder = try Builder.init(std.testing.allocator, "/containers/json");
    defer builder.deinit();

    try builder.addInt("limit", @as(u32, 5));
    const path = try builder.finish();
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/json?limit=5", path);
}
