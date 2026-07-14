const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");
const strings = @import("strings.zig");

pub const InspectOptions = struct {
    manifests: ?bool = null,
    platform: ?[]const u8 = null,
};

pub const Inspect = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    repo_tags: []const []const u8,
    repo_digests: []const []const u8,
    comment: ?[]const u8,
    created: ?[]const u8,
    author: ?[]const u8,
    architecture: []const u8,
    variant: ?[]const u8,
    os: []const u8,
    os_version: ?[]const u8,
    size: i64,
    rootfs: ?RootFs,

    pub const RootFs = struct {
        type: []const u8,
        layers: []const []const u8,

        fn deinit(self: *RootFs, allocator: std.mem.Allocator) void {
            allocator.free(self.type);
            strings.freeList(allocator, self.layers);
            allocator.free(self.layers);
            self.* = undefined;
        }
    };

    pub fn deinit(self: *Inspect) void {
        self.allocator.free(self.id);
        strings.freeList(self.allocator, self.repo_tags);
        self.allocator.free(self.repo_tags);
        strings.freeList(self.allocator, self.repo_digests);
        self.allocator.free(self.repo_digests);
        strings.freeOptional(self.allocator, self.comment);
        strings.freeOptional(self.allocator, self.created);
        strings.freeOptional(self.allocator, self.author);
        self.allocator.free(self.architecture);
        strings.freeOptional(self.allocator, self.variant);
        self.allocator.free(self.os);
        strings.freeOptional(self.allocator, self.os_version);
        if (self.rootfs) |*rootfs| rootfs.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn inspect(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: InspectOptions) !Inspect {
    const path = try inspectPath(allocator, name, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ImageNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseInspect(allocator, body);
}

const RawInspect = struct {
    Id: []const u8,
    RepoTags: ?[]const []const u8 = null,
    RepoDigests: ?[]const []const u8 = null,
    Comment: ?[]const u8 = null,
    Created: ?[]const u8 = null,
    Author: ?[]const u8 = null,
    Architecture: []const u8,
    Variant: ?[]const u8 = null,
    Os: []const u8,
    OsVersion: ?[]const u8 = null,
    Size: i64,
    RootFS: ?RawRootFs = null,
};

const RawRootFs = struct {
    Type: []const u8,
    Layers: ?[]const []const u8 = null,
};

fn inspectPath(allocator: std.mem.Allocator, name: []const u8, options: InspectOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/images/", name, "/json");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.manifests) |value| try builder.addBool("manifests", value);
    if (options.platform) |platform| try builder.add("platform", platform);

    return builder.finish();
}

fn parseInspect(allocator: std.mem.Allocator, body: []const u8) !Inspect {
    const parsed = try std.json.parseFromSlice(RawInspect, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var result = Inspect{
        .allocator = allocator,
        .id = try allocator.dupe(u8, parsed.value.Id),
        .repo_tags = try strings.dupeList(allocator, parsed.value.RepoTags),
        .repo_digests = try strings.dupeList(allocator, parsed.value.RepoDigests),
        .comment = try strings.dupeOptional(allocator, parsed.value.Comment),
        .created = try strings.dupeOptional(allocator, parsed.value.Created),
        .author = try strings.dupeOptional(allocator, parsed.value.Author),
        .architecture = try allocator.dupe(u8, parsed.value.Architecture),
        .variant = try strings.dupeOptional(allocator, parsed.value.Variant),
        .os = try allocator.dupe(u8, parsed.value.Os),
        .os_version = try strings.dupeOptional(allocator, parsed.value.OsVersion),
        .size = parsed.value.Size,
        .rootfs = null,
    };
    errdefer result.deinit();

    if (parsed.value.RootFS) |raw_rootfs| {
        result.rootfs = .{
            .type = try allocator.dupe(u8, raw_rootfs.Type),
            .layers = try strings.dupeList(allocator, raw_rootfs.Layers),
        };
    }

    return result;
}

test "inspectPath encodes image name and platform" {
    const path = try inspectPath(std.testing.allocator, "repo/image:tag", .{
        .manifests = true,
        .platform = "linux/amd64",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/images/repo%2Fimage%3Atag/json?manifests=true&platform=linux%2Famd64",
        path,
    );
}

test "parseInspect owns core image fields" {
    var result = try parseInspect(std.testing.allocator,
        \\{
        \\  "Id": "sha256:abc",
        \\  "RepoTags": ["ubuntu:latest"],
        \\  "RepoDigests": ["ubuntu@sha256:def"],
        \\  "Comment": "",
        \\  "Created": "2022-02-04T21:20:12Z",
        \\  "Author": "Docker",
        \\  "Architecture": "amd64",
        \\  "Variant": null,
        \\  "Os": "linux",
        \\  "OsVersion": "",
        \\  "Size": 123,
        \\  "RootFS": {"Type": "layers", "Layers": ["sha256:layer"]}
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("sha256:abc", result.id);
    try std.testing.expectEqualStrings("ubuntu:latest", result.repo_tags[0]);
    try std.testing.expectEqualStrings("layers", result.rootfs.?.type);
    try std.testing.expectEqualStrings("sha256:layer", result.rootfs.?.layers[0]);
}
