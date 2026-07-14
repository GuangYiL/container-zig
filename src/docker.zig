pub const Client = @import("docker/client.zig").Client;
pub const ApiFailure = @import("docker/api_error.zig").ApiFailure;
pub const capability = @import("docker/capability.zig");
pub const Transport = @import("docker/transport.zig").Transport;
pub const config = @import("docker/config.zig");
pub const container = @import("docker/container.zig");
pub const distribution = @import("docker/distribution.zig");
pub const exec = @import("docker/exec.zig");
pub const image = @import("docker/image.zig");
pub const network = @import("docker/network.zig");
pub const node = @import("docker/node.zig");
pub const params = @import("docker/params.zig");
pub const CredentialProvider = @import("docker/registry_auth.zig").CredentialProvider;
pub const RegistryAuth = @import("docker/registry_auth.zig").RegistryAuth;
pub const plugin = @import("docker/plugin.zig");
pub const service = @import("docker/service.zig");
pub const secret = @import("docker/secret.zig");
pub const session = @import("docker/session.zig");
pub const swarm = @import("docker/swarm.zig");
pub const stream = @import("docker/stream.zig");
pub const system = @import("docker/system.zig");
pub const task = @import("docker/task.zig");
pub const volume = @import("docker/volume.zig");

test {
    const std = @import("std");
    _ = @import("docker/api_version.zig");
    _ = @import("docker/capability.zig");
    _ = @import("docker/params.zig");
    _ = @import("docker/query.zig");
    _ = @import("docker/status.zig");
    _ = @import("docker/url.zig");
    std.testing.refAllDecls(@This());
}
