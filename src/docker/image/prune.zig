const std = @import("std");

const Client = @import("../client.zig").Client;
const http_status = @import("../status.zig");
const query = @import("../query.zig");
const strings = @import("strings.zig");

pub const PruneOptions = struct {
    filters: ?[]const u8 = null,
};

pub const BuildPruneOptions = struct {
    reserved_space: ?i64 = null,
    max_used_space: ?i64 = null,
    min_free_space: ?i64 = null,
    all: ?bool = null,
    filters: ?[]const u8 = null,
};

pub const ImagePrune = struct {
    allocator: std.mem.Allocator,
    images_deleted: []DeletedImage,
    space_reclaimed: ?i64,

    pub fn deinit(self: *ImagePrune) void {
        for (self.images_deleted) |*item| item.deinit(self.allocator);
        self.allocator.free(self.images_deleted);
        self.* = undefined;
    }
};

pub const BuildPrune = struct {
    allocator: std.mem.Allocator,
    caches_deleted: []const []const u8,
    space_reclaimed: ?i64,

    pub fn deinit(self: *BuildPrune) void {
        strings.freeList(self.allocator, self.caches_deleted);
        self.allocator.free(self.caches_deleted);
        self.* = undefined;
    }
};

pub const DeletedImage = struct {
    untagged: ?[]const u8,
    deleted: ?[]const u8,

    fn deinit(self: *DeletedImage, allocator: std.mem.Allocator) void {
        strings.freeOptional(allocator, self.untagged);
        strings.freeOptional(allocator, self.deleted);
        self.* = undefined;
    }
};

pub fn prune(allocator: std.mem.Allocator, client: *Client, options: PruneOptions) !ImagePrune {
    const path = try imagePrunePath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .post,
        .path = path,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return parseImagePrune(allocator, body);
}

pub fn buildPrune(allocator: std.mem.Allocator, client: *Client, options: BuildPruneOptions) !BuildPrune {
    const path = try buildPrunePath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .post,
        .path = path,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return parseBuildPrune(allocator, body);
}

const RawImagePrune = struct {
    ImagesDeleted: ?[]const RawDeletedImage = null,
    SpaceReclaimed: ?i64 = null,
};

const RawBuildPrune = struct {
    CachesDeleted: ?[]const []const u8 = null,
    SpaceReclaimed: ?i64 = null,
};

const RawDeletedImage = struct {
    Untagged: ?[]const u8 = null,
    Deleted: ?[]const u8 = null,
};

fn imagePrunePath(allocator: std.mem.Allocator, options: PruneOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/images/prune");
    defer builder.deinit();

    if (options.filters) |filters| try builder.add("filters", filters);

    return builder.finish();
}

fn buildPrunePath(allocator: std.mem.Allocator, options: BuildPruneOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/build/prune");
    defer builder.deinit();

    if (options.reserved_space) |value| try builder.addInt("reserved-space", value);
    if (options.max_used_space) |value| try builder.addInt("max-used-space", value);
    if (options.min_free_space) |value| try builder.addInt("min-free-space", value);
    if (options.all) |value| try builder.addBool("all", value);
    if (options.filters) |filters| try builder.add("filters", filters);

    return builder.finish();
}

fn parseImagePrune(allocator: std.mem.Allocator, body: []const u8) !ImagePrune {
    const parsed = try std.json.parseFromSlice(RawImagePrune, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .images_deleted = try dupeDeletedImages(allocator, parsed.value.ImagesDeleted),
        .space_reclaimed = parsed.value.SpaceReclaimed,
    };
}

fn parseBuildPrune(allocator: std.mem.Allocator, body: []const u8) !BuildPrune {
    const parsed = try std.json.parseFromSlice(RawBuildPrune, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .allocator = allocator,
        .caches_deleted = try strings.dupeList(allocator, parsed.value.CachesDeleted),
        .space_reclaimed = parsed.value.SpaceReclaimed,
    };
}

fn dupeDeletedImages(allocator: std.mem.Allocator, raw_items: ?[]const RawDeletedImage) ![]DeletedImage {
    const source = raw_items orelse return try allocator.alloc(DeletedImage, 0);
    const owned = try allocator.alloc(DeletedImage, source.len);
    var filled: usize = 0;
    errdefer {
        for (owned[0..filled]) |*item| item.deinit(allocator);
        allocator.free(owned);
    }

    for (source) |raw| {
        owned[filled] = .{
            .untagged = try strings.dupeOptional(allocator, raw.Untagged),
            .deleted = try strings.dupeOptional(allocator, raw.Deleted),
        };
        filled += 1;
    }

    return owned;
}

test "prune paths encode filters and space limits" {
    const image_path = try imagePrunePath(std.testing.allocator, .{
        .filters = "{\"dangling\":[\"true\"]}",
    });
    defer std.testing.allocator.free(image_path);
    try std.testing.expectEqualStrings(
        "/images/prune?filters=%7B%22dangling%22%3A%5B%22true%22%5D%7D",
        image_path,
    );

    const build_path = try buildPrunePath(std.testing.allocator, .{
        .reserved_space = 1024,
        .max_used_space = 2048,
        .min_free_space = 512,
        .all = true,
    });
    defer std.testing.allocator.free(build_path);
    try std.testing.expectEqualStrings(
        "/build/prune?reserved-space=1024&max-used-space=2048&min-free-space=512&all=true",
        build_path,
    );
}

test "parse prune responses own returned IDs" {
    var image_result = try parseImagePrune(std.testing.allocator,
        \\{
        \\  "ImagesDeleted": [{"Untagged": "ubuntu:latest"}, {"Deleted": "sha256:abc"}],
        \\  "SpaceReclaimed": 4096
        \\}
    );
    defer image_result.deinit();
    try std.testing.expectEqualStrings("ubuntu:latest", image_result.images_deleted[0].untagged.?);
    try std.testing.expectEqual(@as(i64, 4096), image_result.space_reclaimed.?);

    var build_result = try parseBuildPrune(std.testing.allocator,
        \\{
        \\  "CachesDeleted": ["cache-a"],
        \\  "SpaceReclaimed": 2048
        \\}
    );
    defer build_result.deinit();
    try std.testing.expectEqualStrings("cache-a", build_result.caches_deleted[0]);
    try std.testing.expectEqual(@as(i64, 2048), build_result.space_reclaimed.?);
}
