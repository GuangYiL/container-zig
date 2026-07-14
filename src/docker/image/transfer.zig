const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;
const RegistryAuth = @import("../registry_auth.zig").RegistryAuth;
const query = @import("../query.zig");
const url = @import("../url.zig");
const http_status = @import("../status.zig");
const progress = @import("../stream/progress.zig");
const record = @import("../stream/record.zig");

pub const ExportStream = struct {
    response: Client.Response,

    pub fn reader(self: *ExportStream) *std.Io.Reader {
        return self.response.reader();
    }

    pub fn deinit(self: *ExportStream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub const ProgressStream = struct {
    response: Client.Response,
    decoder: progress.Decoder,

    pub fn next(self: *ProgressStream, allocator: std.mem.Allocator) !?progress.Item {
        return self.decoder.next(allocator);
    }

    pub fn deinit(self: *ProgressStream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub const CreateOptions = struct {
    from_image: ?[]const u8 = null,
    from_src: ?[]const u8 = null,
    repo: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    message: ?[]const u8 = null,
    input: ?Client.Upload = null,
    registry_auth: ?RegistryAuth = null,
    changes: ?[]const []const u8 = null,
    platform: ?[]const u8 = null,
    max_progress_bytes: usize = 1024 * 1024,
};

pub const PushOptions = struct {
    tag: ?[]const u8 = null,
    platform: ?[]const u8 = null,
    registry_auth: RegistryAuth,
    max_progress_bytes: usize = 1024 * 1024,
};

pub const ExportImageOptions = struct {
    platforms: ?[]const []const u8 = null,
};

pub const ExportImagesOptions = struct {
    names: ?[]const []const u8 = null,
    platforms: ?[]const []const u8 = null,
};

pub const LoadOptions = struct {
    archive: Client.Upload,
    quiet: ?bool = null,
    platforms: ?[]const []const u8 = null,
    max_progress_bytes: usize = 1024 * 1024,
};

pub fn create(allocator: std.mem.Allocator, client: *Client, options: CreateOptions) !ProgressStream {
    const path = try createPath(allocator, options);
    defer allocator.free(path);

    const encoded_auth = if (options.registry_auth) |auth| try auth.encode(allocator) else null;
    defer if (encoded_auth) |auth| allocator.free(auth);
    const headers = if (encoded_auth) |auth| try registryAuthHeaders(allocator, auth) else null;
    var mutable_headers = headers;
    defer if (mutable_headers) |*value| value.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = if (mutable_headers) |*value| value else null,
        .body = if (options.input) |upload| upload.body() else .none,
    });
    errdefer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ImageNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    return progressStream(response, options.max_progress_bytes);
}

pub fn push(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: PushOptions) !ProgressStream {
    const path = try pushPath(allocator, name, options);
    defer allocator.free(path);

    const encoded_auth = try options.registry_auth.encode(allocator);
    defer allocator.free(encoded_auth);
    var headers = try registryAuthHeaders(allocator, encoded_auth);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
    });
    errdefer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.ImageNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    return progressStream(response, options.max_progress_bytes);
}

pub fn exportImage(
    allocator: std.mem.Allocator,
    client: *Client,
    name: []const u8,
    options: ExportImageOptions,
) !ExportStream {
    const path = try exportPath(allocator, name, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    errdefer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    return .{ .response = response };
}

pub fn exportImages(allocator: std.mem.Allocator, client: *Client, options: ExportImagesOptions) !ExportStream {
    const path = try exportAllPath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    errdefer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    return .{ .response = response };
}

pub fn load(allocator: std.mem.Allocator, client: *Client, options: LoadOptions) !ProgressStream {
    const path = try loadPath(allocator, options);
    defer allocator.free(path);

    var headers = try tarHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = options.archive.body(),
    });
    errdefer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    return progressStream(response, options.max_progress_bytes);
}

pub fn progressStream(response: Client.Response, max_progress_bytes: usize) !ProgressStream {
    var result = ProgressStream{ .response = response, .decoder = undefined };
    const format = try record.Format.fromContentType(result.response.header("Content-Type"));
    result.decoder = .init(result.response.reader(), format, max_progress_bytes);
    return result;
}

fn createPath(allocator: std.mem.Allocator, options: CreateOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/images/create");
    defer builder.deinit();

    if (options.from_image) |value| try builder.add("fromImage", value);
    if (options.from_src) |value| try builder.add("fromSrc", value);
    if (options.repo) |value| try builder.add("repo", value);
    if (options.tag) |value| try builder.add("tag", value);
    if (options.message) |value| try builder.add("message", value);
    if (options.changes) |changes| for (changes) |change| try builder.add("changes", change);
    if (options.platform) |value| try builder.add("platform", value);

    return builder.finish();
}

fn pushPath(allocator: std.mem.Allocator, name: []const u8, options: PushOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/images/", name, "/push");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();

    if (options.tag) |value| try builder.add("tag", value);
    if (options.platform) |value| try builder.add("platform", value);

    return builder.finish();
}

fn exportPath(allocator: std.mem.Allocator, name: []const u8, options: ExportImageOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/images/", name, "/get");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.platforms) |platforms| for (platforms) |platform| try builder.add("platform", platform);
    return builder.finish();
}

fn exportAllPath(allocator: std.mem.Allocator, options: ExportImagesOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/images/get");
    defer builder.deinit();

    if (options.names) |names| for (names) |name| try builder.add("names", name);
    if (options.platforms) |platforms| for (platforms) |platform| try builder.add("platform", platform);

    return builder.finish();
}

fn loadPath(allocator: std.mem.Allocator, options: LoadOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/images/load");
    defer builder.deinit();

    if (options.quiet) |value| try builder.addBool("quiet", value);
    if (options.platforms) |platforms| for (platforms) |platform| try builder.add("platform", platform);

    return builder.finish();
}

fn registryAuthHeaders(allocator: std.mem.Allocator, registry_auth: []const u8) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("X-Registry-Auth", registry_auth);
    return headers;
}

fn tarHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/x-tar");
    return headers;
}

test "image create and push paths encode query parameters" {
    const create_path = try createPath(std.testing.allocator, .{
        .from_image = "ubuntu",
        .tag = "latest",
        .changes = &.{ "ENV FOO=bar", "CMD date" },
        .platform = "linux/amd64",
    });
    defer std.testing.allocator.free(create_path);
    try std.testing.expectEqualStrings(
        "/images/create?fromImage=ubuntu&tag=latest&changes=ENV%20FOO%3Dbar&changes=CMD%20date&platform=linux%2Famd64",
        create_path,
    );

    const push_path = try pushPath(std.testing.allocator, "repo/image", .{
        .tag = "v1",
        .platform = "linux/arm64",
        .registry_auth = .{ .auth = "auth" },
    });
    defer std.testing.allocator.free(push_path);
    try std.testing.expectEqualStrings("/images/repo%2Fimage/push?tag=v1&platform=linux%2Farm64", push_path);
}

test "image export and load paths encode multi-value platforms" {
    const export_path = try exportPath(std.testing.allocator, "repo/image:tag", .{
        .platforms = &.{"{\"os\":\"linux\"}"},
    });
    defer std.testing.allocator.free(export_path);
    try std.testing.expectEqualStrings(
        "/images/repo%2Fimage%3Atag/get?platform=%7B%22os%22%3A%22linux%22%7D",
        export_path,
    );

    const all_path = try exportAllPath(std.testing.allocator, .{
        .names = &.{ "ubuntu:latest", "alpine:latest" },
        .platforms = &.{"linux/amd64"},
    });
    defer std.testing.allocator.free(all_path);
    try std.testing.expectEqualStrings(
        "/images/get?names=ubuntu%3Alatest&names=alpine%3Alatest&platform=linux%2Famd64",
        all_path,
    );

    const load_path = try loadPath(std.testing.allocator, .{
        .archive = .{ .bytes = "tar bytes" },
        .quiet = true,
        .platforms = &.{"linux/amd64"},
    });
    defer std.testing.allocator.free(load_path);
    try std.testing.expectEqualStrings("/images/load?quiet=true&platform=linux%2Famd64", load_path);
}

test "image transfer headers are explicit" {
    var auth_headers = try registryAuthHeaders(std.testing.allocator, "auth");
    defer auth_headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("auth", auth_headers.get("X-Registry-Auth").?);

    var content_headers = try tarHeaders(std.testing.allocator);
    defer content_headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("application/x-tar", content_headers.get("Content-Type").?);
}
