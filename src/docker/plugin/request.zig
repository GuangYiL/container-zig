const std = @import("std");

const http = @import("../http.zig");
const model = @import("model.zig");
const query = @import("../query.zig");
const url = @import("../url.zig");

pub fn listPath(allocator: std.mem.Allocator, options: model.ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/plugins");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    return builder.finish();
}

pub fn privilegesPath(allocator: std.mem.Allocator, remote: []const u8) ![]u8 {
    var builder = try query.Builder.init(allocator, "/plugins/privileges");
    defer builder.deinit();
    try builder.add("remote", remote);
    return builder.finish();
}

pub fn pullPath(allocator: std.mem.Allocator, options: model.PullOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/plugins/pull");
    defer builder.deinit();
    try builder.add("remote", options.remote);
    if (options.name) |name| try builder.add("name", name);
    return builder.finish();
}

pub fn removePath(
    allocator: std.mem.Allocator,
    name: []const u8,
    options: model.RemoveOptions,
) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/plugins/", name, "");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.force) |force| try builder.addBool("force", force);
    return builder.finish();
}

pub fn enablePath(allocator: std.mem.Allocator, name: []const u8, options: model.EnableOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/plugins/", name, "/enable");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.timeout) |timeout| try builder.addInt("timeout", timeout);
    return builder.finish();
}

pub fn disablePath(allocator: std.mem.Allocator, name: []const u8, options: model.DisableOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/plugins/", name, "/disable");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.force) |force| try builder.addBool("force", force);
    return builder.finish();
}

pub fn upgradePath(allocator: std.mem.Allocator, name: []const u8, options: model.UpgradeOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/plugins/", name, "/upgrade");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    try builder.add("remote", options.remote);
    return builder.finish();
}

pub fn createPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var builder = try query.Builder.init(allocator, "/plugins/create");
    defer builder.deinit();
    try builder.add("name", name);
    return builder.finish();
}

pub fn jsonHeaders(allocator: std.mem.Allocator, registry_auth: ?[]const u8) !http.Headers {
    var headers = try http.Headers.init(allocator, if (registry_auth == null) 1 else 2);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    if (registry_auth) |auth| try headers.put("X-Registry-Auth", auth);
    return headers;
}

pub fn tarHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/x-tar");
    return headers;
}

pub fn expectOk(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn expectPlugin(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .not_found => return error.PluginNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn expectNoContentPlugin(status: http.Status) !void {
    switch (status) {
        .no_content => {},
        .not_found => return error.PluginNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}
