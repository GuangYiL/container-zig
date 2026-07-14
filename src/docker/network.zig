const std = @import("std");

const http = @import("http.zig");
const json = @import("json.zig");

const Client = @import("client.zig").Client;
const model = @import("network/model.zig");
const query = @import("query.zig");
const url = @import("url.zig");

pub const Create = model.Create;
pub const ConnectOptions = model.ConnectOptions;
pub const CreateOptions = model.CreateOptions;
pub const DisconnectOptions = model.DisconnectOptions;
pub const EndpointConfig = model.EndpointConfig;
pub const InspectOptions = model.InspectOptions;
pub const ListOptions = model.ListOptions;
pub const Network = model.Network;
pub const NetworkList = model.NetworkList;
pub const Pair = model.Pair;
pub const Prune = model.Prune;
pub const PruneOptions = model.PruneOptions;
pub const StringMap = model.StringMap;

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !NetworkList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return model.parseList(allocator, body);
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: InspectOptions) !Network {
    const path = try inspectPath(allocator, id, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    switch (response.status()) {
        .ok => {},
        .not_found => return error.NetworkNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
    const body = try response.body() orelse return error.EmptyResponse;
    return model.parseNetwork(allocator, body);
}

pub fn remove(allocator: std.mem.Allocator, client: *Client, id: []const u8) !void {
    const path = try url.pathWithSegment(allocator, "/networks/", id, "");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .delete, .path = path });
    defer response.deinit();
    switch (response.status()) {
        .no_content => {},
        .forbidden => return error.OperationForbidden,
        .not_found => return error.NetworkNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn create(allocator: std.mem.Allocator, client: *Client, options: CreateOptions) !Create {
    const body = try json.stringifyAlloc(allocator, options);
    defer allocator.free(body);
    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = "/networks/create",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    switch (response.status()) {
        .created => {},
        .bad_request => return error.BadParameter,
        .forbidden => return error.OperationForbidden,
        .not_found => return error.PluginNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
    const response_body = try response.body() orelse return error.EmptyResponse;
    return model.parseCreate(allocator, response_body);
}

pub fn connect(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: ConnectOptions) !void {
    try networkBodyAction(allocator, client, id, "/connect", options, true);
}

pub fn disconnect(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: DisconnectOptions) !void {
    try networkBodyAction(allocator, client, id, "/disconnect", options, false);
}

pub fn prune(allocator: std.mem.Allocator, client: *Client, options: PruneOptions) !Prune {
    const path = try prunePath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .post, .path = path });
    defer response.deinit();
    try expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return model.parsePrune(allocator, body);
}

fn networkBodyAction(
    allocator: std.mem.Allocator,
    client: *Client,
    id: []const u8,
    suffix: []const u8,
    options: anytype,
    bad_request: bool,
) !void {
    const path = try url.pathWithSegment(allocator, "/networks/", id, suffix);
    defer allocator.free(path);
    const body = try json.stringifyAlloc(allocator, options);
    defer allocator.free(body);
    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    switch (response.status()) {
        .ok => {},
        .bad_request => if (bad_request) return error.BadParameter else return error.UnexpectedStatus,
        .forbidden => return error.OperationForbidden,
        .not_found => return error.NetworkOrContainerNotFound,
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/networks");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    return builder.finish();
}

fn inspectPath(allocator: std.mem.Allocator, id: []const u8, options: InspectOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/networks/", id, "");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.verbose) |value| try builder.addBool("verbose", value);
    if (options.scope) |scope| try builder.add("scope", scope);
    return builder.finish();
}

fn prunePath(allocator: std.mem.Allocator, options: PruneOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/networks/prune");
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

fn expectOk(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

test {
    _ = @import("network/model.zig");
}

test "network paths encode filters and inspect options" {
    const list_path = try listPath(std.testing.allocator, .{ .filters = "{\"driver\":[\"bridge\"]}" });
    defer std.testing.allocator.free(list_path);
    try std.testing.expectEqualStrings("/networks?filters=%7B%22driver%22%3A%5B%22bridge%22%5D%7D", list_path);

    const inspect_path = try inspectPath(std.testing.allocator, "app net", .{ .verbose = true, .scope = "local" });
    defer std.testing.allocator.free(inspect_path);
    try std.testing.expectEqualStrings("/networks/app%20net?verbose=true&scope=local", inspect_path);

    const prune_path = try prunePath(std.testing.allocator, .{ .filters = "{\"until\":[\"10m\"]}" });
    defer std.testing.allocator.free(prune_path);
    try std.testing.expectEqualStrings("/networks/prune?filters=%7B%22until%22%3A%5B%2210m%22%5D%7D", prune_path);
}
