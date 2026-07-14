const std = @import("std");

const Client = @import("../client.zig").Client;
const url = @import("../url.zig");

pub const ChangeList = struct {
    allocator: std.mem.Allocator,
    items: []Change,

    pub fn deinit(self: *ChangeList) void {
        for (self.items) |item| self.allocator.free(item.path);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Change = struct {
    path: []const u8,
    kind: Kind,

    pub const Kind = enum(u8) {
        modified = 0,
        added = 1,
        deleted = 2,
    };
};

pub fn changes(allocator: std.mem.Allocator, client: *Client, id: []const u8) !ChangeList {
    const path = try url.pathWithSegment(allocator, "/containers/", id, "/changes");
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseChanges(allocator, body);
}

const RawChange = struct {
    Path: []const u8,
    Kind: u8,
};

fn parseChanges(allocator: std.mem.Allocator, body: []const u8) !ChangeList {
    const parsed = try std.json.parseFromSlice([]RawChange, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const items = try allocator.alloc(Change, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |item| allocator.free(item.path);
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        const kind = try changeKind(raw.Kind);
        items[filled] = .{
            .path = try allocator.dupe(u8, raw.Path),
            .kind = kind,
        };
        filled += 1;
    }

    return .{
        .allocator = allocator,
        .items = items,
    };
}

fn changeKind(value: u8) !Change.Kind {
    return switch (value) {
        0 => .modified,
        1 => .added,
        2 => .deleted,
        else => error.UnknownChangeKind,
    };
}

test "parseChanges owns filesystem changes" {
    var result = try parseChanges(std.testing.allocator,
        \\[
        \\  {"Path": "/dev", "Kind": 0},
        \\  {"Path": "/dev/kmsg", "Kind": 1},
        \\  {"Path": "/test", "Kind": 2}
        \\]
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("/dev", result.items[0].path);
    try std.testing.expectEqual(Change.Kind.modified, result.items[0].kind);
    try std.testing.expectEqual(Change.Kind.added, result.items[1].kind);
    try std.testing.expectEqual(Change.Kind.deleted, result.items[2].kind);
}

test "parseChanges rejects unknown change kind" {
    try std.testing.expectError(error.UnknownChangeKind, parseChanges(std.testing.allocator,
        \\[{"Path": "/bad", "Kind": 7}]
    ));
}
