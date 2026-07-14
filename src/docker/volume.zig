const std = @import("std");

const http = @import("http.zig");
const json = @import("json.zig");

const Client = @import("client.zig").Client;
const model = @import("volume/model.zig");
const query = @import("query.zig");
const url = @import("url.zig");
const http_status = @import("status.zig");

pub const ClusterVolumeSpec = model.ClusterVolumeSpec;
pub const CreateOptions = model.CreateOptions;
pub const ListOptions = model.ListOptions;
pub const Pair = model.Pair;
pub const Prune = model.Prune;
pub const PruneOptions = model.PruneOptions;
pub const RemoveOptions = model.RemoveOptions;
pub const StringMap = model.StringMap;
pub const UpdateOptions = model.UpdateOptions;
pub const Volume = model.Volume;
pub const VolumeList = model.VolumeList;

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !VolumeList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return model.parseList(allocator, body);
}

pub fn create(allocator: std.mem.Allocator, client: *Client, options: CreateOptions) !Volume {
    const body = try json.stringifyAlloc(allocator, options);
    defer allocator.free(body);

    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = "/volumes/create",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();

    switch (response.status()) {
        .created => {},
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const response_body = try response.body() orelse return error.EmptyResponse;
    return model.parseVolume(allocator, response_body);
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, name: []const u8) !Volume {
    const path = try url.pathWithSegment(allocator, "/volumes/", name, "");
    defer allocator.free(path);

    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .not_found => return error.VolumeNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }

    const body = try response.body() orelse return error.EmptyResponse;
    return model.parseVolume(allocator, body);
}

pub fn update(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: UpdateOptions) !void {
    const path = try updatePath(allocator, name, options.version);
    defer allocator.free(path);

    const body = try model.updateBody(allocator, options.spec);
    defer allocator.free(body);

    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .put,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();

    switch (response.status()) {
        .ok => {},
        .bad_request => return error.BadParameter,
        .not_found => return error.VolumeNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

pub fn remove(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: RemoveOptions) !void {
    const path = try removePath(allocator, name, options);
    defer allocator.free(path);

    var response = try client.request(.{ .method = .delete, .path = path });
    defer response.deinit();

    switch (response.status()) {
        .no_content => {},
        .not_found => return error.VolumeNotFound,
        .conflict => return error.VolumeInUse,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn prune(allocator: std.mem.Allocator, client: *Client, options: PruneOptions) !Prune {
    const path = try prunePath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{ .method = .post, .path = path });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return model.parsePrune(allocator, body);
}

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/volumes");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    return builder.finish();
}

fn updatePath(allocator: std.mem.Allocator, name: []const u8, version: i64) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/volumes/", name, "");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    try builder.addInt("version", version);
    return builder.finish();
}

fn removePath(allocator: std.mem.Allocator, name: []const u8, options: RemoveOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/volumes/", name, "");
    defer allocator.free(base_path);

    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.force) |value| try builder.addBool("force", value);
    return builder.finish();
}

fn prunePath(allocator: std.mem.Allocator, options: PruneOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/volumes/prune");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    return builder.finish();
}

fn jsonHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

test {
    _ = @import("volume/model.zig");
}

test "volume paths encode filters version and force" {
    const list_path = try listPath(std.testing.allocator, .{ .filters = "{\"driver\":[\"local\"]}" });
    defer std.testing.allocator.free(list_path);
    try std.testing.expectEqualStrings("/volumes?filters=%7B%22driver%22%3A%5B%22local%22%5D%7D", list_path);

    const update_path = try updatePath(std.testing.allocator, "data volume", 7);
    defer std.testing.allocator.free(update_path);
    try std.testing.expectEqualStrings("/volumes/data%20volume?version=7", update_path);

    const remove_path = try removePath(std.testing.allocator, "data volume", .{ .force = true });
    defer std.testing.allocator.free(remove_path);
    try std.testing.expectEqualStrings("/volumes/data%20volume?force=true", remove_path);
}
