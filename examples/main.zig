const std = @import("std");

const docker = @import("container_zig");
const demo_transport = @import("demo_transport.zig");

test {
    _ = demo_transport;
}

const Containers = struct {
    items: []const docker.container.Summary,

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("[", .{});
        for (self.items) |c| {
            const name = if (c.names.len > 0) c.names[0] else "-";
            try writer.print("\n  {s} {s} ({?s})", .{
                c.id orelse "?",
                name,
                c.status,
            });
        }
        try writer.print("\n]", .{});
    }
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const explicit_host = args.next();
    if (args.next() != null) return error.TooManyArguments;

    var environment = try std.process.getEnvMap(allocator);
    defer environment.deinit();
    var resolved = demo_transport.resolve(allocator, &environment, explicit_host) catch |err| switch (err) {
        error.DockerSocketNotFound => {
            std.log.err(
                "Docker endpoint not found; start Docker or pass a Docker host after --",
                .{},
            );
            return err;
        },
        error.UnsupportedDockerHost => {
            std.log.err(
                "unsupported DOCKER_HOST scheme",
                .{},
            );
            return err;
        },
        error.InvalidDockerHost => {
            std.log.err(
                "invalid DOCKER_HOST",
                .{},
            );
            return err;
        },
        else => return err,
    };
    defer resolved.deinit();

    var client = try docker.Client.init(allocator, .{
        .transport = resolved.transport,
    });
    defer client.deinit();
    try client.connect();

    var ping = try docker.system.ping(allocator, &client);
    defer ping.deinit();

    var con = try docker.container.list(allocator, &client, .{ .all = true });
    defer con.deinit();

    std.log.debug("Docker endpoint {s}", .{resolved.display_name});
    std.log.debug("Docker API {s}", .{ping.api_version});
    std.log.debug("containers: {f}", .{Containers{ .items = con.items }});
}
