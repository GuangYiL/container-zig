const std = @import("std");
const docker = @import("docker.zig");

pub const Client = docker.Client;
pub const ApiFailure = docker.ApiFailure;
pub const capability = docker.capability;
pub const Transport = docker.Transport;
pub const config = docker.config;
pub const container = docker.container;
pub const distribution = docker.distribution;
pub const exec = docker.exec;
pub const image = docker.image;
pub const network = docker.network;
pub const node = docker.node;
pub const params = docker.params;
pub const CredentialProvider = docker.CredentialProvider;
pub const RegistryAuth = docker.RegistryAuth;
pub const plugin = docker.plugin;
pub const service = docker.service;
pub const secret = docker.secret;
pub const session = docker.session;
pub const swarm = docker.swarm;
pub const stream = docker.stream;
pub const system = docker.system;
pub const task = docker.task;
pub const volume = docker.volume;

test {
    refAllDeclsRecursive(@This());
}

test "endpoint options are direct resource declarations" {
    _ = docker.container.ArchiveOptions;
    _ = docker.container.AttachOptions;
    _ = docker.container.CreateOptions;
    _ = docker.container.InspectOptions;
    _ = docker.container.KillOptions;
    _ = docker.container.ListOptions;
    _ = docker.container.LogsOptions;
    _ = docker.container.PruneOptions;
    _ = docker.container.PutArchiveOptions;
    _ = docker.container.RemoveOptions;
    _ = docker.container.RenameOptions;
    _ = docker.container.ResizeOptions;
    _ = docker.container.RestartOptions;
    _ = docker.container.StartOptions;
    _ = docker.container.StatsOptions;
    _ = docker.container.StopOptions;
    _ = docker.container.TopOptions;
    _ = docker.container.UpdateOptions;
    _ = docker.container.WaitOptions;
    _ = docker.image.AttestationsOptions;
    _ = docker.image.BuildOptions;
    _ = docker.image.BuildPruneOptions;
    _ = docker.image.CommitOptions;
    _ = docker.image.CreateOptions;
    _ = docker.image.ExportImageOptions;
    _ = docker.image.ExportImagesOptions;
    _ = docker.image.HistoryOptions;
    _ = docker.image.InspectOptions;
    _ = docker.image.ListOptions;
    _ = docker.image.LoadOptions;
    _ = docker.image.PruneOptions;
    _ = docker.image.PushOptions;
    _ = docker.image.RemoveOptions;
    _ = docker.image.SearchOptions;
    _ = docker.image.TagOptions;
    _ = docker.system.AuthOptions;
    _ = docker.system.DataUsageOptions;
    _ = docker.system.EventsOptions;
    _ = docker.exec.CreateOptions;
    _ = docker.exec.ResizeOptions;
    _ = docker.exec.StartOptions;
    _ = docker.network.ConnectOptions;
    _ = docker.network.CreateOptions;
    _ = docker.network.DisconnectOptions;
    _ = docker.network.InspectOptions;
    _ = docker.network.ListOptions;
    _ = docker.network.PruneOptions;
    _ = docker.volume.CreateOptions;
    _ = docker.volume.ListOptions;
    _ = docker.volume.PruneOptions;
    _ = docker.volume.RemoveOptions;
    _ = docker.volume.UpdateOptions;
    _ = docker.node.ListOptions;
    _ = docker.node.RemoveOptions;
    _ = docker.node.UpdateOptions;
    _ = docker.service.CreateOptions;
    _ = docker.service.InspectOptions;
    _ = docker.service.ListOptions;
    _ = docker.service.LogsOptions;
    _ = docker.service.UpdateOptions;
    _ = docker.plugin.CreateOptions;
    _ = docker.plugin.DisableOptions;
    _ = docker.plugin.EnableOptions;
    _ = docker.plugin.ListOptions;
    _ = docker.plugin.PullOptions;
    _ = docker.plugin.RemoveOptions;
    _ = docker.plugin.SetOptions;
    _ = docker.plugin.UpgradeOptions;
    _ = docker.swarm.InitOptions;
    _ = docker.swarm.JoinOptions;
    _ = docker.swarm.LeaveOptions;
    _ = docker.swarm.UnlockOptions;
    _ = docker.swarm.UpdateOptions;
    _ = docker.task.ListOptions;
    _ = docker.task.LogsOptions;
    _ = docker.secret.CreateOptions;
    _ = docker.secret.ListOptions;
    _ = docker.secret.UpdateOptions;
    _ = docker.config.CreateOptions;
    _ = docker.config.ListOptions;
    _ = docker.config.UpdateOptions;
}

fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl_name| {
        const declaration = @field(T, decl_name);
        _ = &declaration;
        if (@TypeOf(declaration) == type and declaration != T) {
            switch (@typeInfo(declaration)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(declaration),
                else => {},
            }
        }
    }
}
