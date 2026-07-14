const std = @import("std");

const http = @import("http.zig");
const json = @import("json.zig");

const Client = @import("client.zig").Client;
const model = @import("node/model.zig");
const parse = @import("node/parse.zig");
const query = @import("query.zig");
const url = @import("url.zig");

pub const Availability = model.Availability;
pub const Description = model.Description;
pub const DiscreteResource = model.DiscreteResource;
pub const Engine = model.Engine;
pub const EnginePlugin = model.EnginePlugin;
pub const GenericResource = model.GenericResource;
pub const ManagerStatus = model.ManagerStatus;
pub const NamedResource = model.NamedResource;
pub const Node = model.Node;
pub const NodeList = model.NodeList;
pub const ListOptions = model.ListOptions;
pub const NodeSpec = model.NodeSpec;
pub const NodeState = model.NodeState;
pub const Pair = model.Pair;
pub const Platform = model.Platform;
pub const Reachability = model.Reachability;
pub const RemoveOptions = model.RemoveOptions;
pub const Resources = model.Resources;
pub const Role = model.Role;
pub const Status = model.Status;
pub const StringMap = model.StringMap;
pub const TlsInfo = model.TlsInfo;
pub const UpdateOptions = model.UpdateOptions;

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !NodeList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parseList(allocator, body);
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, id: []const u8) !Node {
    const path = try url.pathWithSegment(allocator, "/nodes/", id, "");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectNode(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parseNode(allocator, body);
}

pub fn remove(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: RemoveOptions) !void {
    const path = try removePath(allocator, id, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .delete, .path = path });
    defer response.deinit();
    try expectNode(response.status());
}

pub fn update(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: UpdateOptions) !void {
    const path = try updatePath(allocator, id, options.version);
    defer allocator.free(path);
    const body = try json.stringifyAlloc(allocator, options.spec);
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
        .bad_request => return error.BadParameter,
        .not_found => return error.NodeNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/nodes");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    return builder.finish();
}

fn removePath(allocator: std.mem.Allocator, id: []const u8, options: RemoveOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/nodes/", id, "");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.force) |force| try builder.addBool("force", force);
    return builder.finish();
}

fn updatePath(allocator: std.mem.Allocator, id: []const u8, version: i64) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/nodes/", id, "/update");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    try builder.addInt("version", version);
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
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn expectNode(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .not_found => return error.NodeNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

test {
    _ = @import("node/model.zig");
    _ = @import("node/parse.zig");
}

test "node paths encode filters force and version" {
    const list_path = try listPath(std.testing.allocator, .{ .filters = "{\"role\":[\"manager\"]}" });
    defer std.testing.allocator.free(list_path);
    try std.testing.expectEqualStrings("/nodes?filters=%7B%22role%22%3A%5B%22manager%22%5D%7D", list_path);

    const remove_path = try removePath(std.testing.allocator, "node/name", .{ .force = true });
    defer std.testing.allocator.free(remove_path);
    try std.testing.expectEqualStrings("/nodes/node%2Fname?force=true", remove_path);

    const update_path = try updatePath(std.testing.allocator, "node-id", 42);
    defer std.testing.allocator.free(update_path);
    try std.testing.expectEqualStrings("/nodes/node-id/update?version=42", update_path);
}

test "node headers are explicit" {
    var headers = try jsonHeaders(std.testing.allocator);
    defer headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

test "node parsing owns node fields" {
    var node = try parse.parseNode(std.testing.allocator, nodeFixture());
    defer node.deinit();
    try std.testing.expectEqualStrings("node-id", node.id);
    try std.testing.expectEqual(@as(u64, 7), node.version_index.?);
    try std.testing.expectEqualStrings("worker-1", node.spec.?.name.?);
    try std.testing.expectEqual(.manager, node.spec.?.role.?);
    try std.testing.expectEqual(.ready, node.status.?.state.?);
    try std.testing.expectEqual(.reachable, node.manager_status.?.reachability.?);
    try std.testing.expectEqualStrings("GPU", node.description.?.resources.?.generic_resources[0].named.kind);
    try std.testing.expectEqualStrings("bridge", node.description.?.engine.?.plugins[0].name.?);

    var nodes = try parse.parseList(std.testing.allocator, "[{\"ID\":\"node-id\"}]");
    defer nodes.deinit();
    try std.testing.expectEqualStrings("node-id", nodes.items[0].id);
}

fn nodeFixture() []const u8 {
    return (
        \\{
        \\  "ID": "node-id",
        \\  "Version": {"Index": 7},
        \\  "CreatedAt": "2026-07-02T17:28:47Z",
        \\  "UpdatedAt": "2026-07-02T17:29:47Z",
        \\  "Spec": {"Name":"worker-1","Labels":{"zone":"east"},"Role":"manager","Availability":"active"},
        \\  "Description": {
        \\    "Hostname": "worker-1",
        \\    "Platform": {"Architecture":"aarch64","OS":"linux"},
        \\    "Resources": {
        \\      "NanoCPUs": 4000000000,
        \\      "MemoryBytes": 8272408576,
        \\      "GenericResources": [
        \\        {"NamedResourceSpec": {"Kind": "GPU", "Value": "UUID1"}},
        \\        {"DiscreteResourceSpec": {"Kind": "SSD", "Value": 3}}
        \\      ]
        \\    },
        \\    "Engine": {
        \\      "EngineVersion": "26.0.0",
        \\      "Labels": {"engine": "docker"},
        \\      "Plugins": [{"Type": "Network", "Name": "bridge"}]
        \\    },
        \\    "TLSInfo": {"TrustRoot":"root","CertIssuerSubject":"subject","CertIssuerPublicKey":"key"}
        \\  },
        \\  "Status": {"State":"ready","Message":"","Addr":"172.17.0.2"},
        \\  "ManagerStatus": {"Leader":true,"Reachability":"reachable","Addr":"10.0.0.46:2377"}
        \\}
    );
}
