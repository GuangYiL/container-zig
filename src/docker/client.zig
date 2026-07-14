const std = @import("std");

const api_version = @import("api_version.zig");
const api_error = @import("api_error.zig");
const capability = @import("capability.zig");
const http = @import("http.zig");
const http_transport = @import("http_transport.zig");
const Transport = @import("transport.zig").Transport;
const websocket = @import("websocket.zig");

pub const Client = struct {
    allocator: std.mem.Allocator,
    http: http_transport.Transport,
    transport: Transport,
    config: Config,
    negotiated_version: ?api_version.Version = null,
    daemon_os: ?capability.OperatingSystem = null,

    pub const Headers = http.Headers;
    pub const Method = http.Method;
    pub const Status = http.Status;
    pub const Upload = http_transport.Upload;

    pub const Config = struct {
        transport: Transport = .{
            .unix_socket = .{
                .path = Transport.default_unix_socket_path,
            },
        },
        api_version: ApiVersion = .auto,
        user_agent: ?[]const u8 = "container-zig/1.0.0",
        api_error_handler: ?api_error.Handler = null,
        retry_policy: RetryPolicy = .{},
    };

    pub const RetryPolicy = struct {
        max_attempts: u8 = 1,
        backoff_milliseconds: u32 = 100,
        jitter_milliseconds: u32 = 0,
    };

    pub const ApiVersion = api_version.Selection;
    pub const ApiVersionNumber = api_version.Version;
    pub const ApiFailure = api_error.ApiFailure;
    pub const ApiErrorHandler = api_error.Handler;
    pub const Capability = capability.Requirement;
    pub const OperatingSystem = capability.OperatingSystem;
    pub const supported_api_versions = api_version.Range{
        .minimum = .{ .major = 1, .minor = 40 },
        .maximum = .{ .major = 1, .minor = 55 },
    };

    pub const Request = struct {
        method: Method,
        path: []const u8,
        headers: ?*const Headers = null,
        body: http_transport.Body = .none,
        versioned: bool = true,
        resource_id: ?[]const u8 = null,
    };

    pub const WebSocketRequest = struct {
        path: []const u8,
        headers: ?*const Headers = null,
        versioned: bool = true,
    };

    pub const Response = http_transport.Response;
    pub const Duplex = http_transport.Duplex;
    pub const WebSocket = websocket.Client;

    pub fn init(allocator: std.mem.Allocator, config: Config) !Client {
        try config.transport.validate();
        if (config.retry_policy.max_attempts == 0) return error.InvalidRetryPolicy;
        return .{
            .allocator = allocator,
            .http = http_transport.Transport.init(allocator),
            .transport = config.transport,
            .config = config,
            .negotiated_version = null,
            .daemon_os = null,
        };
    }

    pub fn connect(self: *Client) !void {
        var response = try self.request(.{
            .method = .get,
            .path = "/version",
            .versioned = false,
        });
        defer response.deinit();
        if (response.status() != .ok) return error.VersionRequestFailed;
        const body = try response.body() orelse return error.EmptyResponse;
        const parsed = try std.json.parseFromSlice(DaemonVersion, self.allocator, body, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const maximum = try api_version.Version.parse(parsed.value.ApiVersion);
        const minimum = if (parsed.value.MinAPIVersion) |value|
            try api_version.Version.parse(value)
        else
            api_version.Version{ .major = 1, .minor = 0 };
        self.negotiated_version = try api_version.select(
            self.config.api_version,
            supported_api_versions,
            .{ .minimum = minimum, .maximum = maximum },
        );
        self.daemon_os = if (parsed.value.Os) |value| .parse(value) else null;
    }

    pub fn negotiatedVersion(self: *const Client) ?api_version.Version {
        return self.negotiated_version;
    }

    pub fn supports(self: *const Client, requirement: Capability) bool {
        const version = self.negotiated_version orelse return false;
        return requirement.supported(version, self.daemon_os);
    }

    pub fn require(self: *const Client, requirement: Capability) !void {
        if (!self.supports(requirement)) return error.UnsupportedFeature;
    }

    pub fn request(self: *Client, request_spec: Request) !Response {
        const target_path = try self.allocPath(request_spec.path, request_spec.versioned);
        defer self.allocator.free(target_path);

        var attempt: u8 = 1;
        var response = while (true) {
            break self.http.request(.{
                .method = request_spec.method,
                .path = target_path,
                .transport = self.transport,
                .headers = request_spec.headers,
                .body = request_spec.body,
                .user_agent = self.config.user_agent,
            }) catch |err| {
                if (!self.shouldRetry(request_spec, err, attempt)) return err;
                try self.retryDelay();
                attempt += 1;
                continue;
            };
        };
        errdefer response.deinit();
        if (@intFromEnum(response.status()) >= 400) {
            if (self.config.api_error_handler) |handler| {
                var failure = try api_error.ApiFailure.read(
                    self.allocator,
                    &response,
                    request_spec.method,
                    target_path,
                    self.negotiated_version,
                    request_spec.resource_id,
                );
                defer failure.deinit();
                handler.handle(&failure);
            }
        }
        return response;
    }

    fn shouldRetry(self: *const Client, request_spec: Request, err: anyerror, attempt: u8) bool {
        if (attempt >= self.config.retry_policy.max_attempts) return false;
        if (request_spec.method != .get and request_spec.method != .head) return false;
        if (request_spec.body != .none) return false;
        return switch (err) {
            error.ConnectionRefused,
            error.ConnectionTimedOut,
            error.ConnectionResetByPeer,
            error.NetworkUnreachable,
            error.HostUnreachable,
            => true,
            else => false,
        };
    }

    fn retryDelay(self: *Client) !void {
        var milliseconds: u64 = self.config.retry_policy.backoff_milliseconds;
        const jitter_limit = self.config.retry_policy.jitter_milliseconds;
        if (jitter_limit > 0) {
            var random: [4]u8 = undefined;
            std.crypto.random.bytes(&random);
            const random_value = std.mem.readInt(u32, &random, .little);
            const jitter = if (jitter_limit == std.math.maxInt(u32))
                random_value
            else
                random_value % (jitter_limit + 1);
            milliseconds += jitter;
        }
        if (milliseconds > 0) {
            std.Thread.sleep(milliseconds * std.time.ns_per_ms);
        }
    }

    pub fn webSocket(self: *Client, request_spec: WebSocketRequest) !WebSocket {
        const target_path = try self.allocPath(request_spec.path, request_spec.versioned);
        defer self.allocator.free(target_path);

        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);
        var key_buffer: [24]u8 = undefined;
        const key = std.base64.standard.Encoder.encode(&key_buffer, &key_bytes);

        var headers = try webSocketHeaders(self.allocator, request_spec.headers, key);
        defer headers.deinit(self.allocator);

        var response = try self.http.request(.{
            .method = .get,
            .path = target_path,
            .transport = self.transport,
            .headers = &headers,
            .body = .none,
            .user_agent = self.config.user_agent,
        });
        errdefer response.deinit();
        if (response.status() != .switching_protocols) return error.WebSocketUpgradeFailed;

        const actual_accept = response.header("Sec-WebSocket-Accept") orelse
            return error.WebSocketAcceptMissing;
        var expected_accept: [28]u8 = undefined;
        webSocketAccept(key, &expected_accept);
        if (!std.mem.eql(u8, actual_accept, &expected_accept)) {
            return error.WebSocketAcceptInvalid;
        }

        return websocket.Client.init(self.allocator, response.takeRawDuplex());
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
        self.* = undefined;
    }

    fn allocPath(self: *Client, path: []const u8, versioned: bool) ![]const u8 {
        try validatePath(path);

        if (!versioned) {
            return try self.allocator.dupe(u8, path);
        }

        const version = self.negotiated_version orelse return error.VersionNotNegotiated;
        return std.fmt.allocPrint(self.allocator, "/v{d}.{d}{s}", .{ version.major, version.minor, path });
    }
};

const DaemonVersion = struct {
    ApiVersion: []const u8,
    MinAPIVersion: ?[]const u8 = null,
    Os: ?[]const u8 = null,
};

fn webSocketHeaders(
    allocator: std.mem.Allocator,
    request_headers: ?*const http.Headers,
    key: []const u8,
) !http.Headers {
    const source = if (request_headers) |headers| headers.slice() else &.{};
    var headers = try http.Headers.init(allocator, source.len + 4);
    errdefer headers.deinit(allocator);
    for (source) |entry| try headers.put(entry.name, entry.value);
    try headers.put("Connection", "Upgrade");
    try headers.put("Upgrade", "websocket");
    try headers.put("Sec-WebSocket-Version", "13");
    try headers.put("Sec-WebSocket-Key", key);
    return headers;
}

fn webSocketAccept(key: []const u8, output: *[28]u8) void {
    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(key);
    sha1.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    sha1.final(&digest);
    _ = std.base64.standard.Encoder.encode(output, &digest);
}

fn validatePath(path: []const u8) !void {
    if (path.len == 0 or path[0] != '/') {
        return error.InvalidPath;
    }

    if (std.mem.indexOfAny(u8, path, "\r\n\x00") != null) {
        return error.InvalidPath;
    }
}

test "Client initializes with default socket" {
    var client = try Client.init(std.testing.allocator, .{});
    defer client.deinit();

    try std.testing.expectEqualStrings(
        Transport.default_unix_socket_path,
        client.config.transport.unix_socket.path,
    );
    try std.testing.expectEqualStrings(
        Transport.default_unix_socket_path,
        client.transport.unix_socket.path,
    );
}

test "Client builds fixed API path" {
    var client = try Client.init(std.testing.allocator, .{
        .api_version = .{ .fixed = .{ .major = 1, .minor = 54 } },
    });
    defer client.deinit();
    client.negotiated_version = .{ .major = 1, .minor = 54 };

    const path = try client.allocPath("/version", true);
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings("/v1.54/version", path);
}

test "Client requires negotiated version for auto versioned paths" {
    var client = try Client.init(std.testing.allocator, .{});
    defer client.deinit();

    try std.testing.expectError(error.VersionNotNegotiated, client.allocPath("/version", true));
}

test "retry policy is explicit and limited to safe requests" {
    var client = try Client.init(std.testing.allocator, .{
        .retry_policy = .{ .max_attempts = 3 },
    });
    defer client.deinit();

    try std.testing.expect(client.shouldRetry(.{
        .method = .get,
        .path = "/version",
        .versioned = false,
    }, error.ConnectionRefused, 1));
    try std.testing.expect(!client.shouldRetry(.{
        .method = .post,
        .path = "/containers/create",
    }, error.ConnectionRefused, 1));
    try std.testing.expect(!client.shouldRetry(.{
        .method = .get,
        .path = "/version",
        .versioned = false,
    }, error.InvalidJson, 1));
}

test "Client rejects malformed paths" {
    try std.testing.expectError(error.InvalidPath, validatePath("version"));
    try std.testing.expectError(error.InvalidPath, validatePath("/bad\r\nHeader: x"));
}

test "Client exposes standard library HTTP types" {
    const method: Client.Method = .get;
    const status: Client.Status = .ok;
    var headers = try Client.Headers.init(std.testing.allocator, 1);
    defer headers.deinit(std.testing.allocator);

    try headers.put("X-Test", "1");
    try std.testing.expectEqual(http.Method.get, method);
    try std.testing.expectEqual(http.Status.ok, status);
}

test "Client.Request accepts per-request headers" {
    var headers = try http.Headers.init(std.testing.allocator, 1);
    defer headers.deinit(std.testing.allocator);
    try headers.put("Content-Type", "application/json");

    const request_spec = Client.Request{
        .method = .post,
        .path = "/auth",
        .headers = &headers,
        .body = .{ .bytes = "{}" },
    };

    try std.testing.expect(request_spec.headers.? == &headers);
}

test "Client.WebSocketRequest accepts per-request headers" {
    var headers = try http.Headers.init(std.testing.allocator, 1);
    defer headers.deinit(std.testing.allocator);
    try headers.put("X-Test", "1");

    const request_spec = Client.WebSocketRequest{
        .path = "/containers/web/attach/ws",
        .headers = &headers,
    };

    try std.testing.expect(request_spec.headers.? == &headers);
}

test "WebSocket accept matches RFC example" {
    var output: [28]u8 = undefined;
    webSocketAccept("dGhlIHNhbXBsZSBub25jZQ==", &output);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &output);
}
