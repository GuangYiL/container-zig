const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const url = @import("../url.zig");

const path_stat_header = "X-Docker-Container-Path-Stat";

pub const ArchiveOptions = struct {
    path: []const u8,
};

pub const PutArchiveOptions = struct {
    path: []const u8,
    archive: Client.Upload,
    no_overwrite_dir_non_dir: ?bool = null,
    copy_uid_gid: ?bool = null,
};

pub const ArchiveStream = struct {
    response: Client.Response,

    pub fn reader(self: *ArchiveStream) *std.Io.Reader {
        return self.response.reader();
    }

    pub fn deinit(self: *ArchiveStream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub const ArchiveInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    size: i64,
    mode: i64,
    modified_time: []const u8,
    link_target: ?[]const u8,

    pub fn deinit(self: *ArchiveInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.modified_time);
        if (self.link_target) |link_target| self.allocator.free(link_target);
        self.* = undefined;
    }
};

pub fn archiveInfo(
    allocator: std.mem.Allocator,
    client: *Client,
    id: []const u8,
    options: ArchiveOptions,
) !ArchiveInfo {
    const path = try archiveQueryPath(allocator, id, options.path, null, null);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .head,
        .path = path,
    });
    defer response.deinit();

    try expectArchiveStatus(response.status());

    const encoded = response.header(path_stat_header) orelse return error.MissingPathStat;
    return parseArchiveInfo(allocator, encoded);
}

pub fn archive(
    allocator: std.mem.Allocator,
    client: *Client,
    id: []const u8,
    options: ArchiveOptions,
) !ArchiveStream {
    const path = try archiveQueryPath(allocator, id, options.path, null, null);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    errdefer response.deinit();

    try expectArchiveStatus(response.status());

    return .{ .response = response };
}

pub fn putArchive(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: PutArchiveOptions) !void {
    const path = try archiveQueryPath(
        allocator,
        id,
        options.path,
        options.no_overwrite_dir_non_dir,
        options.copy_uid_gid,
    );
    defer allocator.free(path);

    var headers = try tarHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .put,
        .path = path,
        .headers = &headers,
        .body = options.archive.body(),
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .bad_request => return error.BadParameter,
        .forbidden => return error.PermissionDenied,
        .not_found => return error.ContainerPathNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

const RawArchiveInfo = struct {
    name: []const u8,
    size: i64,
    mode: i64,
    mtime: []const u8,
    linkTarget: ?[]const u8 = null,
};

fn archiveQueryPath(
    allocator: std.mem.Allocator,
    id: []const u8,
    container_path: []const u8,
    no_overwrite_dir_non_dir: ?bool,
    copy_uid_gid: ?bool,
) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/containers/", id, "/archive");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    try builder.add("path", container_path);
    if (no_overwrite_dir_non_dir) |value| try builder.addBool("noOverwriteDirNonDir", value);
    if (copy_uid_gid) |value| try builder.addBool("copyUIDGID", value);

    return builder.finish();
}

fn parseArchiveInfo(allocator: std.mem.Allocator, encoded: []const u8) !ArchiveInfo {
    const decoded_size = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
    const decoded = try allocator.alloc(u8, decoded_size);
    defer allocator.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, encoded);

    const parsed = try std.json.parseFromSlice(RawArchiveInfo, allocator, decoded, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    var result = ArchiveInfo{
        .allocator = allocator,
        .name = &.{},
        .size = parsed.value.size,
        .mode = parsed.value.mode,
        .modified_time = &.{},
        .link_target = null,
    };
    errdefer result.deinit();

    result.name = try allocator.dupe(u8, parsed.value.name);
    result.modified_time = try allocator.dupe(u8, parsed.value.mtime);
    if (parsed.value.linkTarget) |link_target| {
        result.link_target = try allocator.dupe(u8, link_target);
    }

    return result;
}

fn tarHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/x-tar");
    return headers;
}

fn expectArchiveStatus(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.ContainerPathNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

test "archivePath encodes container path" {
    const path = try archiveQueryPath(std.testing.allocator, "web name", "/var/log/app.log", null, null);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/web%20name/archive?path=%2Fvar%2Flog%2Fapp.log",
        path,
    );
}

test "archiveQueryPath encodes put archive options" {
    const path = try archiveQueryPath(std.testing.allocator, "web name", "/opt/app", true, false);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/web%20name/archive?path=%2Fopt%2Fapp&noOverwriteDirNonDir=true&copyUIDGID=false",
        path,
    );
}

test "tarHeaders sets archive upload content type" {
    var headers = try tarHeaders(std.testing.allocator);
    defer headers.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("application/x-tar", headers.get("Content-Type").?);
}

test "parseArchiveInfo decodes Docker path stat header" {
    var info = try parseArchiveInfo(
        std.testing.allocator,
        "eyJuYW1lIjoiYXBwLmxvZyIsInNpemUiOjEyMywibW9kZSI6NDIwLCJtdGltZSI6" ++
            "IjIwMjYtMDctMDJUMTU6NTc6MDJaIiwibGlua1RhcmdldCI6IiJ9",
    );
    defer info.deinit();

    try std.testing.expectEqualStrings("app.log", info.name);
    try std.testing.expectEqual(@as(i64, 123), info.size);
    try std.testing.expectEqual(@as(i64, 420), info.mode);
    try std.testing.expectEqualStrings("2026-07-02T15:57:02Z", info.modified_time);
    try std.testing.expectEqualStrings("", info.link_target.?);
}
