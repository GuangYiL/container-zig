const std = @import("std");

const json = @import("json.zig");

const http = @import("http.zig");

const Client = @import("client.zig").Client;
const url = @import("url.zig");

pub const Inspect = struct {
    allocator: std.mem.Allocator,
    descriptor: Descriptor,
    platforms: []Platform,

    pub fn deinit(self: *Inspect) void {
        self.descriptor.deinit(self.allocator);
        for (self.platforms) |*platform| platform.deinit(self.allocator);
        self.allocator.free(self.platforms);
        self.* = undefined;
    }
};

pub const Descriptor = struct {
    media_type: ?[]const u8,
    digest: ?[]const u8,
    size: ?i64,
    urls: []const []const u8,
    annotations: []Pair,
    data: ?[]const u8,
    platform: ?Platform,
    artifact_type: ?[]const u8,

    fn deinit(self: *Descriptor, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.media_type);
        freeOptional(allocator, self.digest);
        freeStringList(allocator, self.urls);
        allocator.free(self.urls);
        freePairList(allocator, self.annotations);
        freeOptional(allocator, self.data);
        if (self.platform) |*platform| platform.deinit(allocator);
        freeOptional(allocator, self.artifact_type);
        self.* = undefined;
    }
};

pub const Pair = struct {
    name: []const u8,
    value: []const u8,
};

pub const Platform = struct {
    architecture: ?[]const u8,
    os: ?[]const u8,
    os_version: ?[]const u8,
    os_features: []const []const u8,
    variant: ?[]const u8,

    fn deinit(self: *Platform, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.architecture);
        freeOptional(allocator, self.os);
        freeOptional(allocator, self.os_version);
        freeStringList(allocator, self.os_features);
        allocator.free(self.os_features);
        freeOptional(allocator, self.variant);
        self.* = undefined;
    }
};

pub fn inspect(allocator: std.mem.Allocator, client: *Client, name: []const u8) !Inspect {
    const path = try url.pathWithSegment(allocator, "/distribution/", name, "/json");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    switch (response.status()) {
        .ok => {},
        .unauthorized => return error.DistributionNotFoundOrUnauthorized,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
    const body = try response.body() orelse return error.EmptyResponse;
    return parseInspect(allocator, body);
}

const RawInspect = struct {
    Descriptor: RawDescriptor,
    Platforms: []RawPlatform,
};

const RawDescriptor = struct {
    mediaType: ?[]const u8 = null,
    digest: ?[]const u8 = null,
    size: ?i64 = null,
    urls: ?[]const []const u8 = null,
    annotations: ?std.json.ArrayHashMap([]const u8) = null,
    data: ?[]const u8 = null,
    platform: ?RawPlatform = null,
    artifactType: ?[]const u8 = null,
};

const RawPlatform = struct {
    architecture: ?[]const u8 = null,
    os: ?[]const u8 = null,
    @"os.version": ?[]const u8 = null,
    @"os.features": ?[]const []const u8 = null,
    variant: ?[]const u8 = null,
};

fn parseInspect(allocator: std.mem.Allocator, body: []const u8) !Inspect {
    const parsed = try std.json.parseFromSlice(RawInspect, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    var descriptor = try descriptorFromRaw(allocator, parsed.value.Descriptor);
    errdefer descriptor.deinit(allocator);
    const platforms = try platformsFromRaw(allocator, parsed.value.Platforms);
    errdefer {
        for (platforms) |*platform| platform.deinit(allocator);
        allocator.free(platforms);
    }
    return .{ .allocator = allocator, .descriptor = descriptor, .platforms = platforms };
}

fn descriptorFromRaw(allocator: std.mem.Allocator, raw: RawDescriptor) !Descriptor {
    const media_type = try dupeOptional(allocator, raw.mediaType);
    errdefer freeOptional(allocator, media_type);
    const digest = try dupeOptional(allocator, raw.digest);
    errdefer freeOptional(allocator, digest);
    const urls = try dupeOptionalStrings(allocator, raw.urls);
    errdefer freeStrings(allocator, urls);
    const annotations = try dupePairs(allocator, raw.annotations);
    errdefer freePairList(allocator, annotations);
    const data = try dupeOptional(allocator, raw.data);
    errdefer freeOptional(allocator, data);
    var platform = try platformFromRaw(allocator, raw.platform);
    errdefer if (platform) |*value| value.deinit(allocator);
    const artifact_type = try dupeOptional(allocator, raw.artifactType);
    errdefer freeOptional(allocator, artifact_type);
    return .{
        .media_type = media_type,
        .digest = digest,
        .size = raw.size,
        .urls = urls,
        .annotations = annotations,
        .data = data,
        .platform = platform,
        .artifact_type = artifact_type,
    };
}

fn platformsFromRaw(allocator: std.mem.Allocator, raw_values: []RawPlatform) ![]Platform {
    const values = try allocator.alloc(Platform, raw_values.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (raw_values) |raw| {
        values[filled] = (try platformFromRaw(allocator, raw)).?;
        filled += 1;
    }
    return values;
}

fn platformFromRaw(allocator: std.mem.Allocator, raw: ?RawPlatform) !?Platform {
    const value = raw orelse return null;
    const architecture = try dupeOptional(allocator, value.architecture);
    errdefer freeOptional(allocator, architecture);
    const os = try dupeOptional(allocator, value.os);
    errdefer freeOptional(allocator, os);
    const os_version = try dupeOptional(allocator, value.@"os.version");
    errdefer freeOptional(allocator, os_version);
    const os_features = try dupeOptionalStrings(allocator, value.@"os.features");
    errdefer freeStrings(allocator, os_features);
    const variant = try dupeOptional(allocator, value.variant);
    errdefer freeOptional(allocator, variant);
    return .{
        .architecture = architecture,
        .os = os,
        .os_version = os_version,
        .os_features = os_features,
        .variant = variant,
    };
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn dupeOptionalStrings(allocator: std.mem.Allocator, values: ?[]const []const u8) ![]const []const u8 {
    const source = values orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, source.len);
    var filled: usize = 0;
    errdefer {
        freeStringList(allocator, owned[0..filled]);
        allocator.free(owned);
    }
    for (source) |value| {
        owned[filled] = try allocator.dupe(u8, value);
        filled += 1;
    }
    return owned;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |string| allocator.free(string);
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}

fn dupePairs(allocator: std.mem.Allocator, raw_pairs: ?std.json.ArrayHashMap([]const u8)) ![]Pair {
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

fn freePairs(allocator: std.mem.Allocator, pairs: []const Pair) void {
    for (pairs) |pair| {
        allocator.free(pair.name);
        allocator.free(pair.value);
    }
}

fn freePairList(allocator: std.mem.Allocator, pairs: []const Pair) void {
    freePairs(allocator, pairs);
    allocator.free(pairs);
}

fn freeStrings(allocator: std.mem.Allocator, values: []const []const u8) void {
    freeStringList(allocator, values);
    allocator.free(values);
}

test "distribution inspect parses descriptor and platforms" {
    var result = try parseInspect(std.testing.allocator,
        \\{
        \\  "Descriptor": {
        \\    "mediaType": "application/vnd.oci.image.manifest.v1+json",
        \\    "digest": "sha256:abc",
        \\    "size": 424,
        \\    "urls": ["https://example.test/blob"],
        \\    "annotations": {"org.opencontainers.image.version": "1.0"},
        \\    "platform": {"architecture": "amd64", "os": "linux"},
        \\    "artifactType": "application/vnd.example"
        \\  },
        \\  "Platforms": [{
        \\    "architecture": "amd64",
        \\    "os": "linux",
        \\    "os.version": "1",
        \\    "os.features": ["feat"],
        \\    "variant": "v1"
        \\  }]
        \\}
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("sha256:abc", result.descriptor.digest.?);
    try std.testing.expectEqualStrings("org.opencontainers.image.version", result.descriptor.annotations[0].name);
    try std.testing.expectEqualStrings("amd64", result.platforms[0].architecture.?);
    try std.testing.expectEqualStrings("feat", result.platforms[0].os_features[0]);
}
