const std = @import("std");

pub const Status = std.http.Status;

pub const Method = enum {
    get,
    head,
    post,
    put,
    delete,
    connect,
    options,
    trace,
    patch,

    pub fn toStd(self: Method) std.http.Method {
        return switch (self) {
            .get => .GET,
            .head => .HEAD,
            .post => .POST,
            .put => .PUT,
            .delete => .DELETE,
            .connect => .CONNECT,
            .options => .OPTIONS,
            .trace => .TRACE,
            .patch => .PATCH,
        };
    }
};

pub const Headers = struct {
    entries: []std.http.Header = &.{},
    len: usize = 0,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Headers {
        if (capacity == 0) return .{};
        return .{ .entries = try allocator.alloc(std.http.Header, capacity) };
    }

    pub fn deinit(self: *Headers, allocator: std.mem.Allocator) void {
        if (self.entries.len > 0) allocator.free(self.entries);
        self.* = .{};
    }

    pub fn put(self: *Headers, name: []const u8, value: []const u8) !void {
        for (self.entries[0..self.len]) |*entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) {
                entry.value = value;
                return;
            }
        }
        if (self.len == self.entries.len) return error.TooManyHeaders;
        self.entries[self.len] = .{ .name = name, .value = value };
        self.len += 1;
    }

    pub fn get(self: *const Headers, name: []const u8) ?[]const u8 {
        for (self.entries[0..self.len]) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
        }
        return null;
    }

    pub fn slice(self: *const Headers) []const std.http.Header {
        return self.entries[0..self.len];
    }
};

test "Headers stores and replaces values case-insensitively" {
    var headers = try Headers.init(std.testing.allocator, 2);
    defer headers.deinit(std.testing.allocator);

    try headers.put("Content-Type", "text/plain");
    try headers.put("content-type", "application/json");
    try headers.put("X-Test", "1");

    try std.testing.expectEqual(@as(usize, 2), headers.slice().len);
    try std.testing.expectEqualStrings("application/json", headers.get("CONTENT-TYPE").?);
    try std.testing.expectEqualStrings("1", headers.get("x-test").?);
}

test "Method maps to std HTTP method" {
    try std.testing.expectEqual(std.http.Method.GET, Method.get.toStd());
    try std.testing.expectEqual(std.http.Method.POST, Method.post.toStd());
    try std.testing.expectEqual(std.http.Method.DELETE, Method.delete.toStd());
}
