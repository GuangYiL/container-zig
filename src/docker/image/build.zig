const std = @import("std");

const http = @import("../http.zig");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const transfer = @import("transfer.zig");
const http_status = @import("../status.zig");

pub const BuildOptions = struct {
    context: Client.Upload,
    dockerfile: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    extra_hosts: ?[]const u8 = null,
    remote: ?[]const u8 = null,
    quiet: ?bool = null,
    no_cache: ?bool = null,
    cache_from: ?[]const u8 = null,
    pull: ?[]const u8 = null,
    remove_intermediate: ?bool = null,
    force_remove_intermediate: ?bool = null,
    memory: ?i64 = null,
    memory_swap: ?i64 = null,
    cpu_shares: ?i64 = null,
    cpuset_cpus: ?[]const u8 = null,
    cpu_period: ?i64 = null,
    cpu_quota: ?i64 = null,
    build_args: ?[]const u8 = null,
    shm_size: ?i64 = null,
    squash: ?bool = null,
    labels: ?[]const u8 = null,
    network_mode: ?[]const u8 = null,
    content_type: []const u8 = "application/x-tar",
    registry_config: ?[]const u8 = null,
    platform: ?[]const u8 = null,
    target: ?[]const u8 = null,
    outputs: ?[]const u8 = null,
    version: ?[]const u8 = null,
    max_progress_bytes: usize = 1024 * 1024,
};

pub fn build(allocator: std.mem.Allocator, client: *Client, options: BuildOptions) !transfer.ProgressStream {
    const path = try buildPath(allocator, options);
    defer allocator.free(path);

    var headers = try buildHeaders(allocator, options);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = options.context.body(),
    });
    errdefer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    return transfer.progressStream(response, options.max_progress_bytes);
}

fn buildPath(allocator: std.mem.Allocator, options: BuildOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/build");
    defer builder.deinit();

    if (options.dockerfile) |value| try builder.add("dockerfile", value);
    if (options.tag) |value| try builder.add("t", value);
    if (options.extra_hosts) |value| try builder.add("extrahosts", value);
    if (options.remote) |value| try builder.add("remote", value);
    if (options.quiet) |value| try builder.addBool("q", value);
    if (options.no_cache) |value| try builder.addBool("nocache", value);
    if (options.cache_from) |value| try builder.add("cachefrom", value);
    if (options.pull) |value| try builder.add("pull", value);
    if (options.remove_intermediate) |value| try builder.addBool("rm", value);
    if (options.force_remove_intermediate) |value| try builder.addBool("forcerm", value);
    if (options.memory) |value| try builder.addInt("memory", value);
    if (options.memory_swap) |value| try builder.addInt("memswap", value);
    if (options.cpu_shares) |value| try builder.addInt("cpushares", value);
    if (options.cpuset_cpus) |value| try builder.add("cpusetcpus", value);
    if (options.cpu_period) |value| try builder.addInt("cpuperiod", value);
    if (options.cpu_quota) |value| try builder.addInt("cpuquota", value);
    if (options.build_args) |value| try builder.add("buildargs", value);
    if (options.shm_size) |value| try builder.addInt("shmsize", value);
    if (options.squash) |value| try builder.addBool("squash", value);
    if (options.labels) |value| try builder.add("labels", value);
    if (options.network_mode) |value| try builder.add("networkmode", value);
    if (options.platform) |value| try builder.add("platform", value);
    if (options.target) |value| try builder.add("target", value);
    if (options.outputs) |value| try builder.add("outputs", value);
    if (options.version) |value| try builder.add("version", value);

    return builder.finish();
}

fn buildHeaders(allocator: std.mem.Allocator, options: BuildOptions) !http.Headers {
    var headers = try http.Headers.init(allocator, 2);
    errdefer headers.deinit(allocator);

    try headers.put("Content-Type", options.content_type);
    if (options.registry_config) |value| try headers.put("X-Registry-Config", value);

    return headers;
}

test "buildPath encodes Docker build options" {
    const path = try buildPath(std.testing.allocator, .{
        .context = .{ .bytes = "tar bytes" },
        .dockerfile = "Dockerfile.prod",
        .tag = "example/app:v1",
        .quiet = true,
        .no_cache = false,
        .remove_intermediate = true,
        .memory = 1024,
        .cpu_quota = 50000,
        .build_args = "{\"FOO\":\"bar\"}",
        .network_mode = "host",
        .platform = "linux/amd64",
        .target = "release",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/build?dockerfile=Dockerfile.prod&t=example%2Fapp%3Av1&q=true&nocache=false" ++
            "&rm=true&memory=1024&cpuquota=50000" ++
            "&buildargs=%7B%22FOO%22%3A%22bar%22%7D" ++
            "&networkmode=host&platform=linux%2Famd64&target=release",
        path,
    );
}

test "buildHeaders sets tar and registry headers" {
    var headers = try buildHeaders(std.testing.allocator, .{
        .context = .{ .bytes = "tar bytes" },
        .registry_config = "registry-config",
    });
    defer headers.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("application/x-tar", headers.get("Content-Type").?);
    try std.testing.expectEqualStrings("registry-config", headers.get("X-Registry-Config").?);
}
