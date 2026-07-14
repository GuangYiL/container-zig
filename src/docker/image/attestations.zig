const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");

pub const AttestationsOptions = struct {
    platforms: ?[]const Platform = null,
    types: ?[]const []const u8 = null,
    statement: ?bool = null,
};

pub const AttestationList = struct {
    arena: std.heap.ArenaAllocator,
    items: []const Attestation,

    pub fn deinit(self: *AttestationList) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const Attestation = struct {
    descriptor: Descriptor,
    predicate_type: []const u8,
    statement: ?std.json.Value,
};

pub const Descriptor = struct {
    media_type: ?[]const u8,
    digest: ?[]const u8,
    size: ?i64,
    urls: []const []const u8,
    annotations: []const Annotation,
    data: ?[]const u8,
    platform: ?Platform,
    artifact_type: ?[]const u8,
};

pub const Annotation = struct {
    name: []const u8,
    value: []const u8,
};

pub const Platform = struct {
    architecture: ?[]const u8 = null,
    os: ?[]const u8 = null,
    os_version: ?[]const u8 = null,
    os_features: ?[]const []const u8 = null,
    variant: ?[]const u8 = null,

    pub fn jsonStringify(self: Platform, writer: anytype) !void {
        try writer.beginObject();
        try writeOptionalField(writer, "architecture", self.architecture);
        try writeOptionalField(writer, "os", self.os);
        try writeOptionalField(writer, "os.version", self.os_version);
        try writeOptionalField(writer, "os.features", self.os_features);
        try writeOptionalField(writer, "variant", self.variant);
        try writer.endObject();
    }
};

pub fn attestations(
    allocator: std.mem.Allocator,
    client: *Client,
    name: []const u8,
    options: AttestationsOptions,
) !AttestationList {
    const path = try attestationsPath(allocator, name, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ImageNotFound,
        .internal_server_error => return error.ServerError,
        .not_implemented => return error.NotImplemented,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseAttestations(allocator, body);
}

fn attestationsPath(allocator: std.mem.Allocator, name: []const u8, options: AttestationsOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/images/", name, "/attestations");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.platforms) |platforms| for (platforms) |platform| {
        const encoded = try std.json.Stringify.valueAlloc(allocator, platform, .{
            .emit_null_optional_fields = false,
        });
        defer allocator.free(encoded);
        try builder.add("platform", encoded);
    };
    if (options.types) |types| for (types) |predicate_type| try builder.add("type", predicate_type);
    if (options.statement) |value| try builder.addBool("statement", value);

    return builder.finish();
}

const RawAttestation = struct {
    Descriptor: RawDescriptor,
    PredicateType: []const u8,
    Statement: ?std.json.Value = null,
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

fn parseAttestations(allocator: std.mem.Allocator, body: []const u8) !AttestationList {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const owned = arena.allocator();
    const raw_items = try std.json.parseFromSliceLeaky([]RawAttestation, owned, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    const items = try owned.alloc(Attestation, raw_items.len);
    for (raw_items, items) |raw, *item| {
        item.* = .{
            .descriptor = try descriptorFromRaw(owned, raw.Descriptor),
            .predicate_type = raw.PredicateType,
            .statement = raw.Statement,
        };
    }
    return .{ .arena = arena, .items = items };
}

fn descriptorFromRaw(allocator: std.mem.Allocator, raw: RawDescriptor) !Descriptor {
    return .{
        .media_type = raw.mediaType,
        .digest = raw.digest,
        .size = raw.size,
        .urls = raw.urls orelse &.{},
        .annotations = try annotationsFromRaw(allocator, raw.annotations),
        .data = raw.data,
        .platform = platformFromRaw(raw.platform),
        .artifact_type = raw.artifactType,
    };
}

fn annotationsFromRaw(allocator: std.mem.Allocator, raw: ?std.json.ArrayHashMap([]const u8)) ![]Annotation {
    const source = raw orelse return &.{};
    const annotations = try allocator.alloc(Annotation, source.map.count());
    var iterator = source.map.iterator();
    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        annotations[index] = .{
            .name = entry.key_ptr.*,
            .value = entry.value_ptr.*,
        };
    }
    return annotations;
}

fn platformFromRaw(raw: ?RawPlatform) ?Platform {
    const platform = raw orelse return null;
    return .{
        .architecture = platform.architecture,
        .os = platform.os,
        .os_version = platform.@"os.version",
        .os_features = platform.@"os.features",
        .variant = platform.variant,
    };
}

fn writeOptionalField(writer: anytype, name: []const u8, value: anytype) !void {
    if (value) |payload| {
        try writer.objectField(name);
        try writer.write(payload);
    }
}

test "attestationsPath encodes filters" {
    const path = try attestationsPath(std.testing.allocator, "repo/image:tag", .{
        .platforms = &.{.{ .os = "linux", .architecture = "amd64" }},
        .types = &.{"https://slsa.dev/provenance/v0.2"},
        .statement = true,
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/images/repo%2Fimage%3Atag/attestations?platform=" ++
            "%7B%22architecture%22%3A%22amd64%22%2C%22os%22%3A%22linux%22%7D" ++
            "&type=https%3A%2F%2Fslsa.dev%2Fprovenance%2Fv0.2&statement=true",
        path,
    );
}

test "parseAttestations owns descriptor and statement data" {
    var result = try parseAttestations(std.testing.allocator,
        \\[
        \\  {
        \\    "Descriptor": {
        \\      "mediaType": "application/vnd.in-toto+json",
        \\      "digest": "sha256:abc",
        \\      "size": 42,
        \\      "urls": ["https://example.test/statement"],
        \\      "annotations": {"org.example.kind": "provenance"},
        \\      "platform": {"architecture": "amd64", "os": "linux"}
        \\    },
        \\    "PredicateType": "https://slsa.dev/provenance/v0.2",
        \\    "Statement": {"subject": [{"name": "container-zig"}]}
        \\  }
        \\]
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    const item = result.items[0];
    try std.testing.expectEqualStrings("sha256:abc", item.descriptor.digest.?);
    try std.testing.expectEqualStrings("amd64", item.descriptor.platform.?.architecture.?);
    try std.testing.expectEqualStrings("org.example.kind", item.descriptor.annotations[0].name);
    try std.testing.expectEqualStrings("https://slsa.dev/provenance/v0.2", item.predicate_type);
    try std.testing.expect(item.statement != null);
}

test "parseAttestations cleans up allocation failures" {
    const body =
        \\[
        \\  {
        \\    "Descriptor": {
        \\      "digest": "sha256:abc",
        \\      "urls": ["https://example.test/statement"],
        \\      "annotations": {"org.example.kind": "provenance"}
        \\    },
        \\    "PredicateType": "https://slsa.dev/provenance/v0.2",
        \\    "Statement": {"subject": [{"name": "container-zig"}]}
        \\  }
        \\]
    ;

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseAttestationsForAllocationFailure,
        .{body},
    );
}

fn parseAttestationsForAllocationFailure(allocator: std.mem.Allocator, body: []const u8) !void {
    var result = try parseAttestations(allocator, body);
    result.deinit();
}
