const std = @import("std");

pub const RegistryAuth = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    auth: ?[]const u8 = null,
    identity_token: ?[]const u8 = null,
    registry_token: ?[]const u8 = null,
    server_address: ?[]const u8 = null,

    pub fn encode(self: RegistryAuth, allocator: std.mem.Allocator) ![]u8 {
        const json = try std.json.Stringify.valueAlloc(allocator, Wire{
            .username = self.username,
            .password = self.password,
            .auth = self.auth,
            .identitytoken = self.identity_token,
            .registrytoken = self.registry_token,
            .serveraddress = self.server_address,
        }, .{ .emit_null_optional_fields = false });
        defer allocator.free(json);

        const size = std.base64.url_safe.Encoder.calcSize(json.len);
        const encoded = try allocator.alloc(u8, size);
        _ = std.base64.url_safe.Encoder.encode(encoded, json);
        return encoded;
    }
};

pub const CredentialProvider = struct {
    context: *anyopaque,
    get_fn: *const fn (*anyopaque, []const u8) anyerror!RegistryAuth,

    pub fn get(self: CredentialProvider, registry_host: []const u8) !RegistryAuth {
        return self.get_fn(self.context, registry_host);
    }
};

const Wire = struct {
    username: ?[]const u8,
    password: ?[]const u8,
    auth: ?[]const u8,
    identitytoken: ?[]const u8,
    registrytoken: ?[]const u8,
    serveraddress: ?[]const u8,
};

test "RegistryAuth encodes Docker header JSON without exposing fields in logs" {
    const encoded = try (RegistryAuth{
        .username = "user",
        .password = "secret",
        .server_address = "registry.example.com",
    }).encode(std.testing.allocator);
    defer std.testing.allocator.free(encoded);

    const size = try std.base64.url_safe.Decoder.calcSizeForSlice(encoded);
    const decoded = try std.testing.allocator.alloc(u8, size);
    defer std.testing.allocator.free(decoded);
    try std.base64.url_safe.Decoder.decode(decoded, encoded);
    try std.testing.expect(std.mem.containsAtLeast(u8, decoded, 1, "\"username\":\"user\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, decoded, 1, "\"serveraddress\""));
    try std.testing.expect(std.mem.indexOf(u8, decoded, "server_address") == null);
}

test "RegistryAuth cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        encodeForAllocationFailure,
        .{},
    );
}

fn encodeForAllocationFailure(allocator: std.mem.Allocator) !void {
    const encoded = try (RegistryAuth{
        .username = "user",
        .password = "secret",
    }).encode(allocator);
    allocator.free(encoded);
}
