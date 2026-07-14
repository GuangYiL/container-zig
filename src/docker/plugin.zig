const std = @import("std");

const Client = @import("client.zig").Client;
const json = @import("json.zig");
const model = @import("plugin/model.zig");
const parse = @import("plugin/parse.zig");
const request = @import("plugin/request.zig");
const url = @import("url.zig");

pub const Args = model.Args;
pub const CreateOptions = model.CreateOptions;
pub const Device = model.Device;
pub const DisableOptions = model.DisableOptions;
pub const EnableOptions = model.EnableOptions;
pub const Env = model.Env;
pub const Interface = model.Interface;
pub const LinuxConfig = model.LinuxConfig;
pub const Mount = model.Mount;
pub const NetworkConfig = model.NetworkConfig;
pub const Plugin = model.Plugin;
pub const PluginConfig = model.PluginConfig;
pub const PluginList = model.PluginList;
pub const ListOptions = model.ListOptions;
pub const Privilege = model.Privilege;
pub const PrivilegeList = model.PrivilegeList;
pub const PullOptions = model.PullOptions;
pub const RemoveOptions = model.RemoveOptions;
pub const Rootfs = model.Rootfs;
pub const SetOptions = model.SetOptions;
pub const Settings = model.Settings;
pub const UpgradeOptions = model.UpgradeOptions;
pub const User = model.User;

pub const Stream = struct {
    response: Client.Response,

    pub fn reader(self: *Stream) *std.Io.Reader {
        return self.response.reader();
    }

    pub fn deinit(self: *Stream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !PluginList {
    const path = try request.listPath(allocator, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try request.expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parseList(allocator, body);
}

pub fn privileges(allocator: std.mem.Allocator, client: *Client, remote: []const u8) !PrivilegeList {
    const path = try request.privilegesPath(allocator, remote);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try request.expectOk(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parsePrivileges(allocator, body);
}

pub fn pull(allocator: std.mem.Allocator, client: *Client, options: PullOptions) !void {
    const path = try request.pullPath(allocator, options);
    defer allocator.free(path);
    const body = try json.stringifyAlloc(allocator, options.privileges);
    defer allocator.free(body);
    const encoded_auth = if (options.registry_auth) |auth| try auth.encode(allocator) else null;
    defer if (encoded_auth) |auth| allocator.free(auth);
    var headers = try request.jsonHeaders(allocator, encoded_auth);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    switch (response.status()) {
        .no_content => {},
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn inspect(allocator: std.mem.Allocator, client: *Client, name: []const u8) !Plugin {
    const path = try url.pathWithSegment(allocator, "/plugins/", name, "/json");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .get, .path = path });
    defer response.deinit();
    try request.expectPlugin(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parsePlugin(allocator, body);
}

pub fn remove(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: RemoveOptions) !Plugin {
    const path = try request.removePath(allocator, name, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .delete, .path = path });
    defer response.deinit();
    try request.expectPlugin(response.status());
    const body = try response.body() orelse return error.EmptyResponse;
    return parse.parsePlugin(allocator, body);
}

pub fn enable(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: EnableOptions) !void {
    const path = try request.enablePath(allocator, name, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .post, .path = path });
    defer response.deinit();
    try request.expectPlugin(response.status());
}

pub fn disable(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: DisableOptions) !void {
    const path = try request.disablePath(allocator, name, options);
    defer allocator.free(path);
    var response = try client.request(.{ .method = .post, .path = path });
    defer response.deinit();
    try request.expectPlugin(response.status());
}

pub fn upgrade(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: UpgradeOptions) !void {
    const path = try request.upgradePath(allocator, name, options);
    defer allocator.free(path);
    const body = try json.stringifyAlloc(allocator, options.privileges);
    defer allocator.free(body);
    const encoded_auth = if (options.registry_auth) |auth| try auth.encode(allocator) else null;
    defer if (encoded_auth) |auth| allocator.free(auth);
    var headers = try request.jsonHeaders(allocator, encoded_auth);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    try request.expectNoContentPlugin(response.status());
}

pub fn create(allocator: std.mem.Allocator, client: *Client, options: CreateOptions) !void {
    const path = try request.createPath(allocator, options.name);
    defer allocator.free(path);
    var headers = try request.tarHeaders(allocator);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = options.context.body(),
    });
    defer response.deinit();
    switch (response.status()) {
        .no_content => {},
        .internal_server_error => return error.ServerError,
        else => return error.UnexpectedStatus,
    }
}

pub fn push(allocator: std.mem.Allocator, client: *Client, name: []const u8) !Stream {
    const path = try url.pathWithSegment(allocator, "/plugins/", name, "/push");
    defer allocator.free(path);
    var response = try client.request(.{ .method = .post, .path = path });
    errdefer response.deinit();
    try request.expectPlugin(response.status());
    return .{ .response = response };
}

pub fn set(allocator: std.mem.Allocator, client: *Client, name: []const u8, options: SetOptions) !void {
    const path = try url.pathWithSegment(allocator, "/plugins/", name, "/set");
    defer allocator.free(path);
    const body = try json.stringifyAlloc(allocator, options.values);
    defer allocator.free(body);
    var headers = try request.jsonHeaders(allocator, null);
    defer headers.deinit(allocator);
    var response = try client.request(.{
        .method = .post,
        .path = path,
        .headers = &headers,
        .body = .{ .bytes = body },
    });
    defer response.deinit();
    try request.expectNoContentPlugin(response.status());
}

test {
    _ = @import("plugin/model.zig");
    _ = @import("plugin/parse.zig");
}

test "plugin paths encode query and name segments" {
    const list_path = try request.listPath(std.testing.allocator, .{ .filters = "{\"enable\":[\"true\"]}" });
    defer std.testing.allocator.free(list_path);
    try std.testing.expectEqualStrings("/plugins?filters=%7B%22enable%22%3A%5B%22true%22%5D%7D", list_path);

    const privileges_path = try request.privilegesPath(std.testing.allocator, "repo/plugin:latest");
    defer std.testing.allocator.free(privileges_path);
    try std.testing.expectEqualStrings("/plugins/privileges?remote=repo%2Fplugin%3Alatest", privileges_path);

    const pull_path = try request.pullPath(std.testing.allocator, .{
        .remote = "repo/plugin:latest",
        .name = "local/plugin:dev",
        .privileges = &.{},
    });
    defer std.testing.allocator.free(pull_path);
    try std.testing.expectEqualStrings(
        "/plugins/pull?remote=repo%2Fplugin%3Alatest&name=local%2Fplugin%3Adev",
        pull_path,
    );

    const remove_path = try request.removePath(std.testing.allocator, "repo/plugin:dev", .{ .force = true });
    defer std.testing.allocator.free(remove_path);
    try std.testing.expectEqualStrings("/plugins/repo%2Fplugin%3Adev?force=true", remove_path);
}

test "plugin action paths encode options" {
    const enable_path = try request.enablePath(std.testing.allocator, "sample", .{ .timeout = 30 });
    defer std.testing.allocator.free(enable_path);
    try std.testing.expectEqualStrings("/plugins/sample/enable?timeout=30", enable_path);

    const disable_path = try request.disablePath(std.testing.allocator, "sample", .{ .force = true });
    defer std.testing.allocator.free(disable_path);
    try std.testing.expectEqualStrings("/plugins/sample/disable?force=true", disable_path);

    const upgrade_path = try request.upgradePath(std.testing.allocator, "sample", .{
        .remote = "repo/plugin:v2",
        .privileges = &.{},
    });
    defer std.testing.allocator.free(upgrade_path);
    try std.testing.expectEqualStrings("/plugins/sample/upgrade?remote=repo%2Fplugin%3Av2", upgrade_path);

    const create_path = try request.createPath(std.testing.allocator, "local/plugin:dev");
    defer std.testing.allocator.free(create_path);
    try std.testing.expectEqualStrings("/plugins/create?name=local%2Fplugin%3Adev", create_path);
}

test "plugin headers are explicit" {
    var auth_headers = try request.jsonHeaders(std.testing.allocator, "auth");
    defer auth_headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("application/json", auth_headers.get("Content-Type").?);
    try std.testing.expectEqualStrings("auth", auth_headers.get("X-Registry-Auth").?);

    var content_headers = try request.tarHeaders(std.testing.allocator);
    defer content_headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("application/x-tar", content_headers.get("Content-Type").?);
}

test "plugin parsing owns inspect and privilege fields" {
    var plugin = try parse.parsePlugin(std.testing.allocator, pluginFixture());
    defer plugin.deinit();
    try std.testing.expectEqualStrings("sample/plugin:latest", plugin.name);
    try std.testing.expect(plugin.enabled);
    try std.testing.expectEqualStrings("docker.volumedriver/1.0", plugin.config.interface.types[0]);
    try std.testing.expectEqualStrings("/dev/fuse", plugin.config.linux.devices[0].path);
    try std.testing.expectEqualStrings("sha256:layer", plugin.config.rootfs.?.diff_ids[0]);

    var privileges_result = try parse.parsePrivileges(std.testing.allocator,
        \\[{"Name":"network","Description":"","Value":["host"]}]
    );
    defer privileges_result.deinit();
    try std.testing.expectEqualStrings("network", privileges_result.items[0].name);
    try std.testing.expectEqualStrings("host", privileges_result.items[0].value[0]);
}

fn pluginFixture() []const u8 {
    return (
        \\{
        \\  "Id": "plugin-id",
        \\  "Name": "sample/plugin:latest",
        \\  "Enabled": true,
        \\  "Settings": {
        \\    "Mounts": [{
        \\      "Name": "state",
        \\      "Description": "state",
        \\      "Settable": ["source"],
        \\      "Source": "/var/lib/plugin",
        \\      "Destination": "/mnt/state",
        \\      "Type": "bind",
        \\      "Options": ["rbind", "rw"]
        \\    }],
        \\    "Env": ["DEBUG=0"],
        \\    "Args": ["--debug"],
        \\    "Devices": [{"Name":"fuse","Description":"fuse","Settable":["path"],"Path":"/dev/fuse"}]
        \\  },
        \\  "PluginReference": "repo/sample/plugin:latest",
        \\  "Config": {
        \\    "Description": "sample plugin",
        \\    "Documentation": "https://docs.docker.com/engine/extend/plugins/",
        \\    "Interface": {
        \\      "Types": ["docker.volumedriver/1.0"],
        \\      "Socket": "plugins.sock",
        \\      "ProtocolScheme": "moby.plugins.http/v1"
        \\    },
        \\    "Entrypoint": ["/usr/bin/plugin"],
        \\    "WorkDir": "/",
        \\    "User": {"UID":1000,"GID":1000},
        \\    "Network": {"Type":"host"},
        \\    "Linux": {
        \\      "Capabilities": ["CAP_SYS_ADMIN"],
        \\      "AllowAllDevices": false,
        \\      "Devices": [{
        \\        "Name": "fuse",
        \\        "Description": "fuse",
        \\        "Settable": ["path"],
        \\        "Path": "/dev/fuse"
        \\      }]
        \\    },
        \\    "PropagatedMount": "/mnt/state",
        \\    "IpcHost": false,
        \\    "PidHost": false,
        \\    "Mounts": [{
        \\      "Name": "state",
        \\      "Description": "state",
        \\      "Settable": ["source"],
        \\      "Source": "/var/lib/plugin",
        \\      "Destination": "/mnt/state",
        \\      "Type": "bind",
        \\      "Options": ["rbind", "rw"]
        \\    }],
        \\    "Env": [{"Name":"DEBUG","Description":"debug","Settable":["value"],"Value":"0"}],
        \\    "Args": {"Name":"args","Description":"args","Settable":["value"],"Value":["--debug"]},
        \\    "rootfs": {"type":"layers","diff_ids":["sha256:layer"]}
        \\  }
        \\}
    );
}
