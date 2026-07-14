const std = @import("std");

const http = @import("http.zig");
const json = @import("json.zig");

const Client = @import("client.zig").Client;
const model = @import("swarm/model.zig");
const parse = @import("swarm/parse.zig");
const query = @import("query.zig");

pub const CaConfig = model.CaConfig;
pub const Dispatcher = model.Dispatcher;
pub const EncryptionConfig = model.EncryptionConfig;
pub const ExternalCa = model.ExternalCa;
pub const Init = model.Init;
pub const InitOptions = model.InitOptions;
pub const JoinOptions = model.JoinOptions;
pub const JoinTokens = model.JoinTokens;
pub const LeaveOptions = model.LeaveOptions;
pub const LogDriver = model.LogDriver;
pub const Orchestration = model.Orchestration;
pub const Pair = model.Pair;
pub const Raft = model.Raft;
pub const Spec = model.Spec;
pub const StringMap = model.StringMap;
pub const Swarm = model.Swarm;
pub const TaskDefaults = model.TaskDefaults;
pub const TlsInfo = model.TlsInfo;
pub const UnlockOptions = model.UnlockOptions;
pub const UnlockKey = model.UnlockKey;
pub const UpdateOptions = model.UpdateOptions;

pub fn inspect(allocator: std.mem.Allocator, client: *Client) !Swarm {
    var response = try client.request(.{ .method = .get, .path = "/swarm" });
    defer response.deinit();
    try expectSwarm(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parseSwarm(allocator, body);
}

pub fn init(allocator: std.mem.Allocator, client: *Client, options: InitOptions) !Init {
    const body = try json.stringifyAlloc(allocator, options);
    defer allocator.free(body);
    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = "/swarm/init",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    try expectJoinOrInit(response.status());
    const response_body = try response.body() orelse return error.EmptyResponse;
    return parse.parseInit(allocator, response_body);
}

pub fn join(allocator: std.mem.Allocator, client: *Client, options: JoinOptions) !void {
    const body = try json.stringifyAlloc(allocator, options);
    defer allocator.free(body);
    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = "/swarm/join",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    try expectJoinOrInit(response.status());
}

pub fn leave(allocator: std.mem.Allocator, client: *Client, options: LeaveOptions) !void {
    const path = try leavePath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .post, .path = path });
    defer response.deinit();
    try expectActiveSwarm(response.status());
}

pub fn update(allocator: std.mem.Allocator, client: *Client, options: UpdateOptions) !void {
    const path = try updatePath(allocator, options);
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
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

pub fn unlockKey(allocator: std.mem.Allocator, client: *Client) !UnlockKey {
    var response = try client.request(.{ .method = .get, .path = "/swarm/unlockkey" });
    defer response.deinit();
    try expectActiveSwarm(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parseUnlockKey(allocator, body);
}

pub fn unlock(allocator: std.mem.Allocator, client: *Client, options: UnlockOptions) !void {
    const body = try json.stringifyAlloc(allocator, options);
    defer allocator.free(body);
    var headers = try jsonHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = "/swarm/unlock",
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    try expectActiveSwarm(response.status());
}

fn leavePath(allocator: std.mem.Allocator, options: LeaveOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/swarm/leave");
    defer builder.deinit();
    if (options.force) |force| try builder.addBool("force", force);
    return builder.finish();
}

fn updatePath(allocator: std.mem.Allocator, options: UpdateOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/swarm/update");
    defer builder.deinit();
    try builder.addInt("version", options.version);
    if (options.rotate_worker_token) |value| try builder.addBool("rotateWorkerToken", value);
    if (options.rotate_manager_token) |value| try builder.addBool("rotateManagerToken", value);
    if (options.rotate_manager_unlock_key) |value| try builder.addBool("rotateManagerUnlockKey", value);
    return builder.finish();
}

fn jsonHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Content-Type", "application/json");
    return headers;
}

fn expectSwarm(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .not_found => return error.SwarmNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn expectJoinOrInit(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .bad_request => return error.BadParameter,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.AlreadyInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn expectActiveSwarm(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

test {
    _ = @import("swarm/model.zig");
    _ = @import("swarm/parse.zig");
}

test "swarm paths encode leave and update options" {
    const leave_path = try leavePath(std.testing.allocator, .{ .force = true });
    defer std.testing.allocator.free(leave_path);
    try std.testing.expectEqualStrings("/swarm/leave?force=true", leave_path);

    const update_path = try updatePath(std.testing.allocator, .{
        .version = 9,
        .spec = .{ .name = "default" },
        .rotate_worker_token = true,
        .rotate_manager_token = false,
        .rotate_manager_unlock_key = true,
    });
    defer std.testing.allocator.free(update_path);
    try std.testing.expectEqualStrings(
        "/swarm/update?version=9&rotateWorkerToken=true&rotateManagerToken=false&rotateManagerUnlockKey=true",
        update_path,
    );
}

test "swarm bodies and headers use explicit Docker fields" {
    const init_body = try json.stringifyAlloc(std.testing.allocator, InitOptions{
        .listen_addr = "0.0.0.0:2377",
        .force_new_cluster = false,
        .spec = .{ .name = "default", .encryption_config = .{ .auto_lock_managers = true } },
    });
    defer std.testing.allocator.free(init_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, init_body, 1, "\"ListenAddr\":\"0.0.0.0:2377\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, init_body, 1, "\"AutoLockManagers\":true"));

    const join_body = try json.stringifyAlloc(std.testing.allocator, JoinOptions{
        .listen_addr = "0.0.0.0:2377",
        .remote_addrs = &.{"manager:2377"},
        .join_token = "token",
    });
    defer std.testing.allocator.free(join_body);
    try std.testing.expect(std.mem.containsAtLeast(u8, join_body, 1, "\"JoinToken\":\"token\""));

    var headers = try jsonHeaders(std.testing.allocator);
    defer headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("application/json", headers.get("Content-Type").?);
}

test "swarm parsing owns inspect init and unlock fields" {
    var swarm = try parse.parseSwarm(std.testing.allocator, swarmFixture());
    defer swarm.deinit();
    try std.testing.expectEqualStrings("swarm-id", swarm.id);
    try std.testing.expectEqual(@as(u64, 11), swarm.version_index.?);
    try std.testing.expectEqualStrings("default", swarm.spec.?.name.?);
    try std.testing.expectEqualStrings("10.10.0.0/16", swarm.default_addr_pool[0]);
    try std.testing.expectEqualStrings("worker-token", swarm.join_tokens.?.worker.?);

    var init_result = try parse.parseInit(std.testing.allocator, "\"node-id\"");
    defer init_result.deinit();
    try std.testing.expectEqualStrings("node-id", init_result.node_id);

    var unlock_key = try parse.parseUnlockKey(std.testing.allocator, "{\"UnlockKey\":\"SWMKEY\"}");
    defer unlock_key.deinit();
    try std.testing.expectEqualStrings("SWMKEY", unlock_key.value);
}

fn swarmFixture() []const u8 {
    return (
        \\{
        \\  "ID": "swarm-id",
        \\  "Version": {"Index": 11},
        \\  "CreatedAt": "2026-07-02T17:35:35Z",
        \\  "UpdatedAt": "2026-07-02T17:36:35Z",
        \\  "Spec": {
        \\    "Name": "default",
        \\    "Labels": {"env":"test"},
        \\    "Orchestration": {"TaskHistoryRetentionLimit": 10},
        \\    "Raft": {
        \\      "SnapshotInterval": 10000,
        \\      "KeepOldSnapshots": 2,
        \\      "LogEntriesForSlowFollowers": 500,
        \\      "ElectionTick": 3,
        \\      "HeartbeatTick": 1
        \\    },
        \\    "Dispatcher": {"HeartbeatPeriod": 5000000000},
        \\    "CAConfig": {
        \\      "NodeCertExpiry": 7776000000000000,
        \\      "ExternalCAs": [{
        \\        "Protocol": "cfssl",
        \\        "URL": "https://ca.example",
        \\        "Options": {"profile": "docker"},
        \\        "CACert": "cert"
        \\      }],
        \\      "SigningCACert": "sign-cert",
        \\      "SigningCAKey": "sign-key",
        \\      "ForceRotate": 1
        \\    },
        \\    "EncryptionConfig": {"AutoLockManagers": true},
        \\    "TaskDefaults": {"LogDriver": {"Name": "json-file", "Options": {"max-file": "10"}}}
        \\  },
        \\  "TLSInfo": {"TrustRoot":"root","CertIssuerSubject":"subject","CertIssuerPublicKey":"key"},
        \\  "RootRotationInProgress": false,
        \\  "DataPathPort": 4789,
        \\  "DefaultAddrPool": ["10.10.0.0/16"],
        \\  "SubnetSize": 24,
        \\  "JoinTokens": {"Worker":"worker-token","Manager":"manager-token"}
        \\}
    );
}
