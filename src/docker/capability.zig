const std = @import("std");

const api_version = @import("api_version.zig");

pub const OperatingSystem = enum {
    linux,
    windows,
    other,

    pub fn parse(value: []const u8) OperatingSystem {
        if (std.ascii.eqlIgnoreCase(value, "linux")) return .linux;
        if (std.ascii.eqlIgnoreCase(value, "windows")) return .windows;
        return .other;
    }
};

pub const Requirement = struct {
    name: []const u8,
    minimum_api_version: api_version.Version,
    operating_system: OperatingSystemRequirement = .any,
    experimental: bool = false,

    pub const OperatingSystemRequirement = enum { any, linux, windows };

    pub fn supported(
        self: Requirement,
        selected_version: api_version.Version,
        daemon_os: ?OperatingSystem,
    ) bool {
        if (selected_version.lessThan(self.minimum_api_version)) return false;
        return switch (self.operating_system) {
            .any => true,
            .linux => daemon_os == .linux,
            .windows => daemon_os == .windows,
        };
    }
};

pub const event_json_sequence = Requirement{
    .name = "event_json_sequence",
    .minimum_api_version = .{ .major = 1, .minor = 54 },
};

test "Requirement checks API version and daemon OS" {
    const linux_only = Requirement{
        .name = "linux-only",
        .minimum_api_version = .{ .major = 1, .minor = 50 },
        .operating_system = .linux,
    };
    try std.testing.expect(linux_only.supported(.{ .major = 1, .minor = 55 }, .linux));
    try std.testing.expect(!linux_only.supported(.{ .major = 1, .minor = 49 }, .linux));
    try std.testing.expect(!linux_only.supported(.{ .major = 1, .minor = 55 }, .windows));
}
