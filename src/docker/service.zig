const std = @import("std");

const http = @import("http.zig");
const json = @import("json.zig");

const Client = @import("client.zig").Client;
const model = @import("service/model.zig");
const parse = @import("service/parse.zig");
const query = @import("query.zig");
const multiplex = @import("stream/multiplex.zig");
const url = @import("url.zig");

pub const ContainerSpec = model.ContainerSpec;
pub const Create = model.Create;
pub const CreateOptions = model.CreateOptions;
pub const EmptyObject = model.EmptyObject;
pub const EndpointSpec = model.EndpointSpec;
pub const LogDriver = model.LogDriver;
pub const InspectOptions = model.InspectOptions;
pub const ListOptions = model.ListOptions;
pub const LogsOptions = model.LogsOptions;
pub const Mode = model.Mode;
pub const Pair = model.Pair;
pub const Port = model.Port;
pub const RegistryAuthFrom = model.RegistryAuthFrom;
pub const Replicated = model.Replicated;
pub const ReplicatedJob = model.ReplicatedJob;
pub const Rollback = model.Rollback;
pub const Service = model.Service;
pub const ServiceList = model.ServiceList;
pub const ServiceStatus = model.ServiceStatus;
pub const Spec = model.Spec;
pub const StringMap = model.StringMap;
pub const TaskSpec = model.TaskSpec;
pub const Update = model.Update;
pub const UpdateOptions = model.UpdateOptions;
pub const UpdatePolicy = model.UpdatePolicy;
pub const UpdateStatus = model.UpdateStatus;
pub const VirtualIp = model.VirtualIp;

pub const Stream = struct {
    response: Client.Response,
    decoder: ?multiplex.Decoder,
    max_frame_bytes: usize,

    pub fn reader(self: *Stream) *std.Io.Reader {
        return self.response.reader();
    }

    pub fn nextFrame(self: *Stream, allocator: std.mem.Allocator) !?multiplex.Frame {
        if (self.decoder == null) {
            self.decoder = .init(self.response.reader(), self.max_frame_bytes);
        }
        return self.decoder.?.next(allocator);
    }

    pub fn deinit(self: *Stream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !ServiceList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parseList(allocator, body);
}

pub fn create(allocator: std.mem.Allocator, client: *Client, options: CreateOptions) !Create {
    const body = try json.stringifyAlloc(allocator, options.spec);
    defer allocator.free(body);
    const encoded_auth = if (options.registry_auth) |auth| try auth.encode(allocator) else null;
    defer if (encoded_auth) |auth| allocator.free(auth);
    var headers = try jsonHeaders(allocator, encoded_auth);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = "/services/create",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    switch (response.status()) {
        .created => {},
        .bad_request => return error.BadParameter,
        .forbidden => return error.NetworkNotEligible,
        .conflict => return error.ServiceNameConflict,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
    const response_body = try response.body() orelse return error.EmptyResponse;
    return parse.parseCreate(allocator, response_body);
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: InspectOptions) !Service {
    const path = try inspectPath(allocator, id, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectService(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parseService(allocator, body);
}

pub fn remove(allocator: std.mem.Allocator, client: *Client, id: []const u8) !void {
    const path = try url.pathWithSegment(allocator, "/services/", id, "");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .delete, .path = path });
    defer response.deinit();
    try expectService(response.status());
}

pub fn update(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: UpdateOptions) !Update {
    const path = try updatePath(allocator, id, options);
    defer allocator.free(path);
    const body = try json.stringifyAlloc(allocator, options.spec);
    defer allocator.free(body);
    const encoded_auth = if (options.registry_auth) |auth| try auth.encode(allocator) else null;
    defer if (encoded_auth) |auth| allocator.free(auth);
    var headers = try jsonHeaders(allocator, encoded_auth);
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
        .not_found => return error.ServiceNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
    const response_body = try response.body() orelse return error.EmptyResponse;
    return parse.parseUpdate(allocator, response_body);
}

pub fn logs(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: LogsOptions) !Stream {
    const path = try logsPath(allocator, id, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    errdefer response.deinit();
    try expectService(response.status());
    return .{
        .response = response,
        .decoder = null,
        .max_frame_bytes = options.max_frame_bytes,
    };
}

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/services");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    if (options.status) |status| try builder.addBool("status", status);
    return builder.finish();
}

fn inspectPath(allocator: std.mem.Allocator, id: []const u8, options: InspectOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/services/", id, "");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.insert_defaults) |value| try builder.addBool("insertDefaults", value);
    return builder.finish();
}

fn updatePath(allocator: std.mem.Allocator, id: []const u8, options: UpdateOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/services/", id, "/update");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    try builder.addInt("version", options.version);
    if (options.registry_auth_from) |value| try builder.add("registryAuthFrom", value.text());
    if (options.rollback) |value| try builder.add("rollback", switch (value) {
        .previous => "previous",
    });
    return builder.finish();
}

fn logsPath(allocator: std.mem.Allocator, id: []const u8, options: LogsOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/services/", id, "/logs");
    defer allocator.free(base_path);
    var builder = try query.Builder.init(allocator, base_path);
    defer builder.deinit();
    if (options.details) |value| try builder.addBool("details", value);
    if (options.follow) |value| try builder.addBool("follow", value);
    if (options.stdout) |value| try builder.addBool("stdout", value);
    if (options.stderr) |value| try builder.addBool("stderr", value);
    if (options.since) |value| try builder.addInt("since", value);
    if (options.timestamps) |value| try builder.addBool("timestamps", value);
    if (options.tail) |value| try builder.add("tail", value);
    return builder.finish();
}

fn jsonHeaders(allocator: std.mem.Allocator, registry_auth: ?[]const u8) !http.Headers {
    var headers = try http.Headers.init(allocator, if (registry_auth == null) 1 else 2);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    if (registry_auth) |auth| try headers.put("X-Registry-Auth", auth);
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

fn expectService(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .not_found => return error.ServiceNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

test {
    _ = @import("service/model.zig");
    _ = @import("service/parse.zig");
}

test "service paths encode query parameters" {
    const list_path = try listPath(std.testing.allocator, .{ .filters = "{\"name\":[\"web\"]}", .status = true });
    defer std.testing.allocator.free(list_path);
    try std.testing.expectEqualStrings("/services?filters=%7B%22name%22%3A%5B%22web%22%5D%7D&status=true", list_path);

    const inspect_path = try inspectPath(std.testing.allocator, "web/service", .{ .insert_defaults = true });
    defer std.testing.allocator.free(inspect_path);
    try std.testing.expectEqualStrings("/services/web%2Fservice?insertDefaults=true", inspect_path);

    const update_path = try updatePath(std.testing.allocator, "web", .{
        .version = 5,
        .spec = serviceSpec(),
        .registry_auth_from = .previous_spec,
        .rollback = .previous,
    });
    defer std.testing.allocator.free(update_path);
    try std.testing.expectEqualStrings(
        "/services/web/update?version=5&registryAuthFrom=previous-spec&rollback=previous",
        update_path,
    );
}

test "service logs path and headers are explicit" {
    const path = try logsPath(std.testing.allocator, "web", .{
        .details = true,
        .stdout = true,
        .stderr = true,
        .since = 42,
        .timestamps = true,
        .tail = "all",
    });
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings(
        "/services/web/logs?details=true&stdout=true&stderr=true" ++
            "&since=42&timestamps=true&tail=all",
        path,
    );

    var headers = try jsonHeaders(std.testing.allocator, "auth");
    defer headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
    try std.testing.expectEqualStrings("auth", headers.get("X-Registry-Auth").?);
}

test "service bodies and parsing own core fields" {
    const body = try json.stringifyAlloc(std.testing.allocator, serviceSpec());
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"Image\":\"nginx:alpine\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "\"PublishedPort\":8080"));

    var service = try parse.parseService(std.testing.allocator, serviceFixture());
    defer service.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("service-id", service.id);
    try std.testing.expectEqualStrings("web", service.spec_name.?);
    try std.testing.expectEqual(@as(u16, 80), service.endpoint_ports[0].target_port.?);
    try std.testing.expectEqualStrings("10.0.0.2/24", service.virtual_ips[0].addr.?);

    var created = try parse.parseCreate(std.testing.allocator, "{\"ID\":\"service-id\",\"Warnings\":[\"warn\"]}");
    defer created.deinit();
    try std.testing.expectEqualStrings("warn", created.warnings[0]);

    var updated = try parse.parseUpdate(std.testing.allocator, "{\"Warnings\":[\"updated\"]}");
    defer updated.deinit();
    try std.testing.expectEqualStrings("updated", updated.warnings[0]);
}

fn serviceSpec() Spec {
    return .{
        .name = "web",
        .labels = .{ .entries = &.{.{ .name = "tier", .value = "frontend" }} },
        .task_template = .{
            .container = .{
                .image = "nginx:alpine",
                .env = &.{"MODE=prod"},
            },
            .log_driver = .{ .name = "json-file" },
        },
        .mode = .{ .replicated = .{ .replicas = 2 } },
        .update_config = .{ .parallelism = 1, .failure_action = "pause" },
        .endpoint_spec = .{
            .mode = "vip",
            .ports = &.{.{
                .protocol = "tcp",
                .target_port = 80,
                .published_port = 8080,
            }},
        },
    };
}

fn serviceFixture() []const u8 {
    return
    \\{
    \\  "ID": "service-id",
    \\  "Version": {"Index": 7},
    \\  "CreatedAt": "2026-07-02T17:43:21Z",
    \\  "UpdatedAt": "2026-07-02T17:44:21Z",
    \\  "Spec": {"Name": "web"},
    \\  "ServiceStatus": {"RunningTasks": 1, "DesiredTasks": 2, "CompletedTasks": 0},
    \\  "UpdateStatus": {"State": "completed", "StartedAt": "start", "CompletedAt": "end", "Message": "done"},
    \\  "Endpoint": {
    \\    "Ports": [{"Name":"http","Protocol":"tcp","TargetPort":80,"PublishedPort":8080,"PublishMode":"ingress"}],
    \\    "VirtualIPs": [{"NetworkID":"net-id","Addr":"10.0.0.2/24"}]
    \\  }
    \\}
    ;
}
