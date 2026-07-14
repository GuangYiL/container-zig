const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");

pub const TopOptions = struct {
    ps_args: ?[]const u8 = null,
};

pub const Top = struct {
    allocator: std.mem.Allocator,
    titles: []const []const u8,
    processes: []const Process,

    pub const Process = struct {
        columns: []const []const u8,
    };

    pub fn deinit(self: *Top) void {
        freeStringList(self.allocator, self.titles);
        for (self.processes) |process| freeStringList(self.allocator, process.columns);
        self.allocator.free(self.processes);
        self.* = undefined;
    }
};

pub fn top(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: TopOptions) !Top {
    const path = try topPath(allocator, id, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return parseTop(allocator, body);
}

const RawTop = struct {
    Titles: ?[]const []const u8 = null,
    Processes: ?[]const []const []const u8 = null,
};

fn topPath(allocator: std.mem.Allocator, id: []const u8, options: TopOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/top");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.ps_args) |ps_args| try builder.add("ps_args", ps_args);

    return builder.finish();
}

fn parseTop(allocator: std.mem.Allocator, body: []const u8) !Top {
    const parsed = try std.json.parseFromSlice(RawTop, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var result = Top{
        .allocator = allocator,
        .titles = &.{},
        .processes = &.{},
    };
    errdefer result.deinit();

    result.titles = try dupeStringList(allocator, parsed.value.Titles);
    result.processes = try dupeProcesses(allocator, parsed.value.Processes);

    return result;
}

fn dupeProcesses(allocator: std.mem.Allocator, raw_processes: ?[]const []const []const u8) ![]Top.Process {
    const processes = raw_processes orelse return allocator.alloc(Top.Process, 0);
    const owned = try allocator.alloc(Top.Process, processes.len);
    var filled: usize = 0;
    errdefer {
        for (owned[0..filled]) |process| freeStringList(allocator, process.columns);
        allocator.free(owned);
    }

    for (processes) |process| {
        owned[filled] = .{
            .columns = try dupeStringList(allocator, process),
        };
        filled += 1;
    }

    return owned;
}

fn dupeStringList(allocator: std.mem.Allocator, raw_strings: ?[]const []const u8) ![]const []const u8 {
    const strings = raw_strings orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, strings.len);
    var filled: usize = 0;
    errdefer {
        freeStringList(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    for (strings) |string| {
        owned[filled] = try allocator.dupe(u8, string);
        filled += 1;
    }

    return owned;
}

fn freeStringList(allocator: std.mem.Allocator, strings: []const []const u8) void {
    for (strings) |string| allocator.free(string);
    allocator.free(strings);
}

test "topPath encodes id and ps arguments" {
    const path = try topPath(std.testing.allocator, "container name", .{
        .ps_args = "aux",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/containers/container%20name/top?ps_args=aux", path);
}

test "parseTop owns process table" {
    var result = try parseTop(std.testing.allocator,
        \\{
        \\  "Titles": ["UID", "PID", "CMD"],
        \\  "Processes": [["root", "13642", "/bin/bash"]]
        \\}
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("UID", result.titles[0]);
    try std.testing.expectEqualStrings("root", result.processes[0].columns[0]);
    try std.testing.expectEqualStrings("/bin/bash", result.processes[0].columns[2]);
}
