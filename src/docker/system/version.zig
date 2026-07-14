const std = @import("std");

const Client = @import("../client.zig").Client;
const http_status = @import("../status.zig");

pub const Version = struct {
    allocator: std.mem.Allocator,
    platform_name: ?[]const u8,
    engine_version: []const u8,
    api_version: []const u8,
    min_api_version: ?[]const u8,
    git_commit: ?[]const u8,
    go_version: ?[]const u8,
    os: ?[]const u8,
    arch: ?[]const u8,
    kernel_version: ?[]const u8,
    experimental: bool,
    build_time: ?[]const u8,

    fn init(allocator: std.mem.Allocator, raw: RawVersion) !Version {
        const platform_name = try dupeOptionalString(allocator, if (raw.Platform) |platform| platform.Name else null);
        errdefer freeOptionalString(allocator, platform_name);

        const engine_version = try allocator.dupe(u8, raw.Version);
        errdefer allocator.free(engine_version);

        const api_version = try allocator.dupe(u8, raw.ApiVersion);
        errdefer allocator.free(api_version);

        const min_api_version = try dupeOptionalString(allocator, raw.MinAPIVersion);
        errdefer freeOptionalString(allocator, min_api_version);

        const git_commit = try dupeOptionalString(allocator, raw.GitCommit);
        errdefer freeOptionalString(allocator, git_commit);

        const go_version = try dupeOptionalString(allocator, raw.GoVersion);
        errdefer freeOptionalString(allocator, go_version);

        const os = try dupeOptionalString(allocator, raw.Os);
        errdefer freeOptionalString(allocator, os);

        const arch = try dupeOptionalString(allocator, raw.Arch);
        errdefer freeOptionalString(allocator, arch);

        const kernel_version = try dupeOptionalString(allocator, raw.KernelVersion);
        errdefer freeOptionalString(allocator, kernel_version);

        const build_time = try dupeOptionalString(allocator, raw.BuildTime);
        errdefer freeOptionalString(allocator, build_time);

        return .{
            .allocator = allocator,
            .platform_name = platform_name,
            .engine_version = engine_version,
            .api_version = api_version,
            .min_api_version = min_api_version,
            .git_commit = git_commit,
            .go_version = go_version,
            .os = os,
            .arch = arch,
            .kernel_version = kernel_version,
            .experimental = raw.Experimental orelse false,
            .build_time = build_time,
        };
    }

    pub fn deinit(self: *Version) void {
        freeOptionalString(self.allocator, self.platform_name);
        self.allocator.free(self.engine_version);
        self.allocator.free(self.api_version);
        freeOptionalString(self.allocator, self.min_api_version);
        freeOptionalString(self.allocator, self.git_commit);
        freeOptionalString(self.allocator, self.go_version);
        freeOptionalString(self.allocator, self.os);
        freeOptionalString(self.allocator, self.arch);
        freeOptionalString(self.allocator, self.kernel_version);
        freeOptionalString(self.allocator, self.build_time);
        self.* = undefined;
    }
};

pub fn version(allocator: std.mem.Allocator, client: *Client) !Version {
    var response = try client.request(.{
        .method = .get,
        .path = "/version",
        .versioned = false,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return parseVersion(allocator, body);
}

const RawVersion = struct {
    Platform: ?RawPlatform = null,
    Version: []const u8,
    ApiVersion: []const u8,
    MinAPIVersion: ?[]const u8 = null,
    GitCommit: ?[]const u8 = null,
    GoVersion: ?[]const u8 = null,
    Os: ?[]const u8 = null,
    Arch: ?[]const u8 = null,
    KernelVersion: ?[]const u8 = null,
    Experimental: ?bool = null,
    BuildTime: ?[]const u8 = null,
};

const RawPlatform = struct {
    Name: ?[]const u8 = null,
};

fn parseVersion(allocator: std.mem.Allocator, body: []const u8) !Version {
    const parsed = try std.json.parseFromSlice(RawVersion, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return Version.init(allocator, parsed.value);
}

fn dupeOptionalString(allocator: std.mem.Allocator, bytes: ?[]const u8) !?[]const u8 {
    if (bytes) |string| {
        return try allocator.dupe(u8, string);
    }
    return null;
}

fn freeOptionalString(allocator: std.mem.Allocator, string: ?[]const u8) void {
    if (string) |owned| allocator.free(owned);
}

test "parseVersion owns Docker version fields" {
    var version_result = try parseVersion(std.testing.allocator,
        \\{
        \\  "Platform": {"Name": "Docker Engine - Community"},
        \\  "Components": [{}],
        \\  "Version": "27.0.1",
        \\  "ApiVersion": "1.55",
        \\  "MinAPIVersion": "1.24",
        \\  "GitCommit": "48a66213fe",
        \\  "GoVersion": "go1.22.7",
        \\  "Os": "linux",
        \\  "Arch": "amd64",
        \\  "KernelVersion": "6.8.0-31-generic",
        \\  "Experimental": true,
        \\  "BuildTime": "2020-06-22T15:49:27.000000000+00:00"
        \\}
    );
    defer version_result.deinit();

    try std.testing.expectEqualStrings("Docker Engine - Community", version_result.platform_name.?);
    try std.testing.expectEqualStrings("27.0.1", version_result.engine_version);
    try std.testing.expectEqualStrings("1.55", version_result.api_version);
    try std.testing.expectEqualStrings("1.24", version_result.min_api_version.?);
    try std.testing.expectEqualStrings("48a66213fe", version_result.git_commit.?);
    try std.testing.expectEqualStrings("go1.22.7", version_result.go_version.?);
    try std.testing.expectEqualStrings("linux", version_result.os.?);
    try std.testing.expectEqualStrings("amd64", version_result.arch.?);
    try std.testing.expectEqualStrings("6.8.0-31-generic", version_result.kernel_version.?);
    try std.testing.expect(version_result.experimental);
    try std.testing.expectEqualStrings("2020-06-22T15:49:27.000000000+00:00", version_result.build_time.?);
}
