const std = @import("std");

pub const Version = struct {
    major: u16,
    minor: u16,

    pub fn parse(text: []const u8) !Version {
        const separator = std.mem.indexOfScalar(u8, text, '.') orelse return error.InvalidApiVersion;
        if (separator == 0 or separator + 1 == text.len) return error.InvalidApiVersion;
        if (std.mem.indexOfScalarPos(u8, text, separator + 1, '.') != null) return error.InvalidApiVersion;

        return .{
            .major = std.fmt.parseInt(u16, text[0..separator], 10) catch return error.InvalidApiVersion,
            .minor = std.fmt.parseInt(u16, text[separator + 1 ..], 10) catch return error.InvalidApiVersion,
        };
    }

    pub fn write(self: Version, writer: *std.Io.Writer) !void {
        try writer.print("{d}.{d}", .{ self.major, self.minor });
    }

    pub fn lessThan(left: Version, right: Version) bool {
        return left.major < right.major or (left.major == right.major and left.minor < right.minor);
    }
};

pub const Range = struct {
    minimum: Version,
    maximum: Version,
};

pub const Selection = union(enum) {
    auto,
    fixed: Version,
};

pub fn select(selection: Selection, client: Range, daemon: Range) !Version {
    if (client.maximum.lessThan(client.minimum) or daemon.maximum.lessThan(daemon.minimum)) {
        return error.InvalidApiVersionRange;
    }

    const shared_minimum = if (client.minimum.lessThan(daemon.minimum)) daemon.minimum else client.minimum;
    const shared_maximum = if (client.maximum.lessThan(daemon.maximum)) client.maximum else daemon.maximum;
    if (shared_maximum.lessThan(shared_minimum)) return error.IncompatibleApiVersion;

    return switch (selection) {
        .auto => shared_maximum,
        .fixed => |version| {
            if (version.lessThan(shared_minimum) or shared_maximum.lessThan(version)) {
                return error.UnsupportedApiVersion;
            }
            return version;
        },
    };
}

test "API version parser accepts Docker version syntax" {
    try std.testing.expectEqual(Version{ .major = 1, .minor = 55 }, try Version.parse("1.55"));
    try std.testing.expectError(error.InvalidApiVersion, Version.parse("v1.55"));
    try std.testing.expectError(error.InvalidApiVersion, Version.parse("1"));
    try std.testing.expectError(error.InvalidApiVersion, Version.parse("1.latest"));
}

test "automatic API negotiation selects the highest shared version" {
    const client = Range{
        .minimum = .{ .major = 1, .minor = 40 },
        .maximum = .{ .major = 1, .minor = 55 },
    };

    try std.testing.expectEqual(
        Version{ .major = 1, .minor = 54 },
        try select(.auto, client, .{
            .minimum = .{ .major = 1, .minor = 24 },
            .maximum = .{ .major = 1, .minor = 54 },
        }),
    );
    try std.testing.expectEqual(
        Version{ .major = 1, .minor = 55 },
        try select(.auto, client, .{
            .minimum = .{ .major = 1, .minor = 40 },
            .maximum = .{ .major = 1, .minor = 60 },
        }),
    );
}

test "API negotiation rejects ranges without an intersection" {
    const client = Range{
        .minimum = .{ .major = 1, .minor = 40 },
        .maximum = .{ .major = 1, .minor = 55 },
    };

    try std.testing.expectError(error.IncompatibleApiVersion, select(.auto, client, .{
        .minimum = .{ .major = 1, .minor = 56 },
        .maximum = .{ .major = 1, .minor = 60 },
    }));
    try std.testing.expectError(error.IncompatibleApiVersion, select(.auto, client, .{
        .minimum = .{ .major = 1, .minor = 20 },
        .maximum = .{ .major = 1, .minor = 39 },
    }));
}

test "fixed API version must belong to the shared range" {
    const client = Range{
        .minimum = .{ .major = 1, .minor = 40 },
        .maximum = .{ .major = 1, .minor = 55 },
    };
    const daemon = Range{
        .minimum = .{ .major = 1, .minor = 40 },
        .maximum = .{ .major = 1, .minor = 54 },
    };

    try std.testing.expectEqual(
        Version{ .major = 1, .minor = 51 },
        try select(.{ .fixed = .{ .major = 1, .minor = 51 } }, client, daemon),
    );
    try std.testing.expectError(
        error.UnsupportedApiVersion,
        select(.{ .fixed = .{ .major = 1, .minor = 55 } }, client, daemon),
    );
}
