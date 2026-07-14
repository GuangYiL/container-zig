const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const http_status = @import("../status.zig");

pub const DataUsage = struct {
    image_usage: ?ResourceUsage,
    container_usage: ?ResourceUsage,
    volume_usage: ?ResourceUsage,
    build_cache_usage: ?ResourceUsage,

    pub const ResourceType = enum {
        container,
        image,
        volume,
        build_cache,

        fn queryValue(self: ResourceType) []const u8 {
            return switch (self) {
                .container => "container",
                .image => "image",
                .volume => "volume",
                .build_cache => "build-cache",
            };
        }
    };

    pub const ResourceUsage = struct {
        active_count: ?u64,
        total_count: ?u64,
        reclaimable: ?i64,
        total_size: ?i64,
    };
};

pub const DataUsageOptions = struct {
    types: []const DataUsage.ResourceType = &.{},
    verbose: ?bool = null,
};

pub fn dataUsage(allocator: std.mem.Allocator, client: *Client, options: DataUsageOptions) !DataUsage {
    const path = try dataUsagePath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return parseDataUsage(allocator, body);
}

const RawDataUsage = struct {
    ImageUsage: ?RawResourceUsage = null,
    ContainerUsage: ?RawResourceUsage = null,
    VolumeUsage: ?RawResourceUsage = null,
    BuildCacheUsage: ?RawResourceUsage = null,
};

const RawResourceUsage = struct {
    ActiveCount: ?u64 = null,
    TotalCount: ?u64 = null,
    Reclaimable: ?i64 = null,
    TotalSize: ?i64 = null,
};

fn dataUsagePath(allocator: std.mem.Allocator, options: DataUsageOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/system/df");
    defer builder.deinit();

    for (options.types) |resource_type| {
        try builder.add("type", resource_type.queryValue());
    }
    if (options.verbose) |verbose| {
        try builder.addBool("verbose", verbose);
    }

    return builder.finish();
}

fn parseDataUsage(allocator: std.mem.Allocator, body: []const u8) !DataUsage {
    const parsed = try std.json.parseFromSlice(RawDataUsage, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return .{
        .image_usage = resourceUsage(parsed.value.ImageUsage),
        .container_usage = resourceUsage(parsed.value.ContainerUsage),
        .volume_usage = resourceUsage(parsed.value.VolumeUsage),
        .build_cache_usage = resourceUsage(parsed.value.BuildCacheUsage),
    };
}

fn resourceUsage(raw: ?RawResourceUsage) ?DataUsage.ResourceUsage {
    const value = raw orelse return null;
    return .{
        .active_count = value.ActiveCount,
        .total_count = value.TotalCount,
        .reclaimable = value.Reclaimable,
        .total_size = value.TotalSize,
    };
}

test "dataUsagePath encodes repeated type parameters" {
    const path = try dataUsagePath(std.testing.allocator, .{
        .types = &.{ .container, .image, .build_cache },
        .verbose = true,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/system/df?type=container&type=image&type=build-cache&verbose=true",
        path,
    );
}

test "parseDataUsage reads aggregate usage fields" {
    const result = try parseDataUsage(std.testing.allocator,
        \\{
        \\  "ImageUsage": {
        \\    "ActiveCount": 1,
        \\    "TotalCount": 4,
        \\    "Reclaimable": 12345678,
        \\    "TotalSize": 98765432,
        \\    "Items": []
        \\  },
        \\  "ContainerUsage": {"ActiveCount": 2, "TotalCount": 5, "Reclaimable": 23, "TotalSize": 45, "Items": []},
        \\  "VolumeUsage": {"ActiveCount": 3, "TotalCount": 6, "Reclaimable": 67, "TotalSize": 89, "Items": []},
        \\  "BuildCacheUsage": {"ActiveCount": 4, "TotalCount": 7, "Reclaimable": 10, "TotalSize": 11, "Items": []}
        \\}
    );

    try std.testing.expectEqual(@as(u64, 1), result.image_usage.?.active_count.?);
    try std.testing.expectEqual(@as(u64, 4), result.image_usage.?.total_count.?);
    try std.testing.expectEqual(@as(i64, 12345678), result.image_usage.?.reclaimable.?);
    try std.testing.expectEqual(@as(i64, 98765432), result.image_usage.?.total_size.?);
    try std.testing.expectEqual(@as(u64, 2), result.container_usage.?.active_count.?);
    try std.testing.expectEqual(@as(u64, 3), result.volume_usage.?.active_count.?);
    try std.testing.expectEqual(@as(u64, 4), result.build_cache_usage.?.active_count.?);
}
