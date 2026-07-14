const std = @import("std");

const json = @import("json.zig");

const http = @import("http.zig");

const Client = @import("client.zig").Client;
const query = @import("query.zig");
const multiplex = @import("stream/multiplex.zig");
const url = @import("url.zig");

pub const ListOptions = struct {
    filters: ?[]const u8 = null,
};

pub const LogsOptions = struct {
    details: ?bool = null,
    follow: ?bool = null,
    stdout: ?bool = null,
    stderr: ?bool = null,
    since: ?i64 = null,
    timestamps: ?bool = null,
    tail: ?[]const u8 = null,
    max_frame_bytes: usize = 16 * 1024 * 1024,
};

pub const TaskList = struct {
    allocator: std.mem.Allocator,
    items: []Task,

    pub fn deinit(self: *TaskList) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Task = struct {
    id: []const u8,
    version_index: ?u64,
    created_at: ?[]const u8,
    updated_at: ?[]const u8,
    name: ?[]const u8,
    service_id: ?[]const u8,
    slot: ?i64,
    node_id: ?[]const u8,
    status: ?Status,
    desired_state: ?[]const u8,

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        freeOptional(allocator, self.created_at);
        freeOptional(allocator, self.updated_at);
        freeOptional(allocator, self.name);
        freeOptional(allocator, self.service_id);
        freeOptional(allocator, self.node_id);
        if (self.status) |*status_value| status_value.deinit(allocator);
        freeOptional(allocator, self.desired_state);
        self.* = undefined;
    }
};

pub const Status = struct {
    timestamp: ?[]const u8,
    state: ?[]const u8,
    message: ?[]const u8,
    err: ?[]const u8,
    container_status: ?ContainerStatus,

    fn deinit(self: *Status, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.timestamp);
        freeOptional(allocator, self.state);
        freeOptional(allocator, self.message);
        freeOptional(allocator, self.err);
        if (self.container_status) |*container_status| container_status.deinit(allocator);
        self.* = undefined;
    }
};

pub const ContainerStatus = struct {
    container_id: ?[]const u8,
    pid: ?i64,
    exit_code: ?i64,

    fn deinit(self: *ContainerStatus, allocator: std.mem.Allocator) void {
        freeOptional(allocator, self.container_id);
        self.* = undefined;
    }
};

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

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !TaskList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parseList(allocator, body);
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, id: []const u8) !Task {
    const path = try url.pathWithSegment(allocator, "/tasks/", id, "");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try expectTask(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parseTask(allocator, body);
}

pub fn logs(allocator: std.mem.Allocator, client: *Client, id: []const u8, options: LogsOptions) !Stream {
    const path = try logsPath(allocator, id, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    errdefer response.deinit();
    try expectTask(response.status());
    return .{
        .response = response,
        .decoder = null,
        .max_frame_bytes = options.max_frame_bytes,
    };
}

const RawTask = struct {
    ID: []const u8,
    Version: ?RawVersion = null,
    CreatedAt: ?[]const u8 = null,
    UpdatedAt: ?[]const u8 = null,
    Name: ?[]const u8 = null,
    ServiceID: ?[]const u8 = null,
    Slot: ?i64 = null,
    NodeID: ?[]const u8 = null,
    Status: ?RawStatus = null,
    DesiredState: ?[]const u8 = null,
};

const RawVersion = struct { Index: ?u64 = null };

const RawStatus = struct {
    Timestamp: ?[]const u8 = null,
    State: ?[]const u8 = null,
    Message: ?[]const u8 = null,
    Err: ?[]const u8 = null,
    ContainerStatus: ?RawContainerStatus = null,
};

const RawContainerStatus = struct {
    ContainerID: ?[]const u8 = null,
    PID: ?i64 = null,
    ExitCode: ?i64 = null,
};

fn parseList(allocator: std.mem.Allocator, body: []const u8) !TaskList {
    const parsed = try std.json.parseFromSlice([]RawTask, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    const items = try allocator.alloc(Task, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    for (parsed.value) |raw| {
        items[filled] = try taskFromRaw(allocator, raw);
        filled += 1;
    }
    return .{ .allocator = allocator, .items = items };
}

fn parseTask(allocator: std.mem.Allocator, body: []const u8) !Task {
    const parsed = try std.json.parseFromSlice(RawTask, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return taskFromRaw(allocator, parsed.value);
}

fn taskFromRaw(allocator: std.mem.Allocator, raw: RawTask) !Task {
    const id = try allocator.dupe(u8, raw.ID);
    errdefer allocator.free(id);
    const created_at = try dupeOptional(allocator, raw.CreatedAt);
    errdefer freeOptional(allocator, created_at);
    const updated_at = try dupeOptional(allocator, raw.UpdatedAt);
    errdefer freeOptional(allocator, updated_at);
    const name = try dupeOptional(allocator, raw.Name);
    errdefer freeOptional(allocator, name);
    const service_id = try dupeOptional(allocator, raw.ServiceID);
    errdefer freeOptional(allocator, service_id);
    const node_id = try dupeOptional(allocator, raw.NodeID);
    errdefer freeOptional(allocator, node_id);
    var status = try statusFromRaw(allocator, raw.Status);
    errdefer if (status) |*value| value.deinit(allocator);
    const desired_state = try dupeOptional(allocator, raw.DesiredState);
    errdefer freeOptional(allocator, desired_state);
    return .{
        .id = id,
        .version_index = if (raw.Version) |version| version.Index else null,
        .created_at = created_at,
        .updated_at = updated_at,
        .name = name,
        .service_id = service_id,
        .slot = raw.Slot,
        .node_id = node_id,
        .status = status,
        .desired_state = desired_state,
    };
}

fn statusFromRaw(allocator: std.mem.Allocator, raw: ?RawStatus) !?Status {
    const value = raw orelse return null;
    const timestamp = try dupeOptional(allocator, value.Timestamp);
    errdefer freeOptional(allocator, timestamp);
    const state = try dupeOptional(allocator, value.State);
    errdefer freeOptional(allocator, state);
    const message = try dupeOptional(allocator, value.Message);
    errdefer freeOptional(allocator, message);
    const err = try dupeOptional(allocator, value.Err);
    errdefer freeOptional(allocator, err);
    var container_status = try containerStatusFromRaw(allocator, value.ContainerStatus);
    errdefer if (container_status) |*item| item.deinit(allocator);
    return .{
        .timestamp = timestamp,
        .state = state,
        .message = message,
        .err = err,
        .container_status = container_status,
    };
}

fn containerStatusFromRaw(allocator: std.mem.Allocator, raw: ?RawContainerStatus) !?ContainerStatus {
    const value = raw orelse return null;
    const container_id = try dupeOptional(allocator, value.ContainerID);
    errdefer freeOptional(allocator, container_id);
    return .{ .container_id = container_id, .pid = value.PID, .exit_code = value.ExitCode };
}

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/tasks");
    defer builder.deinit();
    if (options.filters) |filters| try builder.add("filters", filters);
    return builder.finish();
}

fn logsPath(allocator: std.mem.Allocator, id: []const u8, options: LogsOptions) ![]u8 {
    const base_path = try url.pathWithSegment(allocator, "/tasks/", id, "/logs");
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

fn expectOk(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn expectTask(status: http.Status) !void {
    switch (status) {
        .ok => {},
        .not_found => return error.TaskNotFound,
        .internal_server_error => return error.ServerError,
        .service_unavailable => return error.NotInSwarm,
        else => return error.UnexpectedStatus,
    }
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]const u8) void {
    if (value) |string| allocator.free(string);
}

test "task paths encode filters and log options" {
    const list_path = try listPath(std.testing.allocator, .{ .filters = "{\"service\":[\"web\"]}" });
    defer std.testing.allocator.free(list_path);
    try std.testing.expectEqualStrings("/tasks?filters=%7B%22service%22%3A%5B%22web%22%5D%7D", list_path);

    const logs_path = try logsPath(std.testing.allocator, "task/id", .{
        .stdout = true,
        .stderr = true,
        .since = 7,
        .tail = "all",
    });
    defer std.testing.allocator.free(logs_path);
    try std.testing.expectEqualStrings("/tasks/task%2Fid/logs?stdout=true&stderr=true&since=7&tail=all", logs_path);
}

test "task parsing owns core fields" {
    var task = try parseTask(std.testing.allocator,
        \\{
        \\  "ID": "task-id",
        \\  "Version": {"Index": 3},
        \\  "CreatedAt": "created",
        \\  "UpdatedAt": "updated",
        \\  "Name": "web.1",
        \\  "ServiceID": "service-id",
        \\  "Slot": 1,
        \\  "NodeID": "node-id",
        \\  "Status": {
        \\    "Timestamp": "now",
        \\    "State": "running",
        \\    "Message": "started",
        \\    "ContainerStatus": {
        \\      "ContainerID": "container-id",
        \\      "PID": 42,
        \\      "ExitCode": 0
        \\    }
        \\  },
        \\  "DesiredState": "running"
        \\}
    );
    defer task.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("task-id", task.id);
    try std.testing.expectEqual(@as(u64, 3), task.version_index.?);
    try std.testing.expectEqualStrings("container-id", task.status.?.container_status.?.container_id.?);

    var tasks = try parseList(std.testing.allocator, "[{\"ID\":\"task-id\"}]");
    defer tasks.deinit();
    try std.testing.expectEqualStrings("task-id", tasks.items[0].id);
}
