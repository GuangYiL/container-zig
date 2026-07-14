const std = @import("std");

const Client = @import("../client.zig").Client;
const http_status = @import("../status.zig");
const query = @import("../query.zig");

pub const SearchOptions = struct {
    term: []const u8,
    limit: ?u32 = null,
    filters: ?[]const u8 = null,
};

pub const SearchList = struct {
    allocator: std.mem.Allocator,
    items: []Search,

    pub fn deinit(self: *SearchList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Search = struct {
    name: []const u8,
    description: []const u8,
    star_count: i64,
    is_official: bool,
    is_automated: bool,

    fn deinit(self: *Search, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        self.* = undefined;
    }
};

pub fn search(allocator: std.mem.Allocator, client: *Client, options: SearchOptions) !SearchList {
    const path = try searchPath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return parseSearch(allocator, body);
}

const RawSearch = struct {
    name: []const u8,
    description: []const u8,
    star_count: i64,
    is_official: bool,
    is_automated: bool = false,
};

fn searchPath(allocator: std.mem.Allocator, options: SearchOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/images/search");
    defer builder.deinit();

    try builder.add("term", options.term);
    if (options.limit) |limit| try builder.addInt("limit", limit);
    if (options.filters) |filters| try builder.add("filters", filters);

    return builder.finish();
}

fn parseSearch(allocator: std.mem.Allocator, body: []const u8) !SearchList {
    const parsed = try std.json.parseFromSlice([]RawSearch, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const items = try allocator.alloc(Search, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        items[filled] = .{
            .name = try allocator.dupe(u8, raw.name),
            .description = try allocator.dupe(u8, raw.description),
            .star_count = raw.star_count,
            .is_official = raw.is_official,
            .is_automated = raw.is_automated,
        };
        filled += 1;
    }

    return .{ .allocator = allocator, .items = items };
}

test "searchPath encodes term limit and filters" {
    const path = try searchPath(std.testing.allocator, .{
        .term = "ubuntu latest",
        .limit = 5,
        .filters = "{\"is-official\":[\"true\"]}",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/images/search?term=ubuntu%20latest&limit=5&filters=%7B%22is-official%22%3A%5B%22true%22%5D%7D",
        path,
    );
}

test "parseSearch owns search items" {
    var result = try parseSearch(std.testing.allocator,
        \\[
        \\  {
        \\    "name": "ubuntu",
        \\    "description": "Ubuntu base image",
        \\    "star_count": 12000,
        \\    "is_official": true,
        \\    "is_automated": false
        \\  }
        \\]
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("ubuntu", result.items[0].name);
    try std.testing.expect(result.items[0].is_official);
    try std.testing.expectEqual(@as(i64, 12000), result.items[0].star_count);
}
