const std = @import("std");

const json = @import("../json.zig");

const model = @import("model.zig");
const wire = @import("wire.zig");

pub fn parseList(allocator: std.mem.Allocator, body: []const u8) !model.PluginList {
    const parsed = try std.json.parseFromSlice([]wire.Plugin, allocator, body, json.owned_parse_options);
    defer parsed.deinit();

    const items = try allocator.alloc(model.Plugin, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit();
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        items[filled] = try pluginFromRaw(allocator, raw);
        filled += 1;
    }

    return .{ .allocator = allocator, .items = items };
}

pub fn parsePlugin(allocator: std.mem.Allocator, body: []const u8) !model.Plugin {
    const parsed = try std.json.parseFromSlice(wire.Plugin, allocator, body, json.owned_parse_options);
    defer parsed.deinit();
    return pluginFromRaw(allocator, parsed.value);
}

pub fn parsePrivileges(allocator: std.mem.Allocator, body: []const u8) !model.PrivilegeList {
    const parsed = try std.json.parseFromSlice([]wire.Privilege, allocator, body, json.owned_parse_options);
    defer parsed.deinit();

    const items = try allocator.alloc(model.Privilege, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit(allocator);
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        items[filled] = try privilegeFromRaw(allocator, raw);
        filled += 1;
    }

    return .{ .allocator = allocator, .items = items };
}

fn pluginFromRaw(allocator: std.mem.Allocator, raw: wire.Plugin) !model.Plugin {
    const id = try dupeOptional(allocator, raw.Id);
    errdefer model.freeOptional(allocator, id);
    const name = try allocator.dupe(u8, raw.Name);
    errdefer allocator.free(name);
    var settings = try settingsFromRaw(allocator, raw.Settings);
    errdefer settings.deinit(allocator);
    const plugin_reference = try dupeOptional(allocator, raw.PluginReference);
    errdefer model.freeOptional(allocator, plugin_reference);
    var config = try configFromRaw(allocator, raw.Config);
    errdefer config.deinit(allocator);

    return .{
        .allocator = allocator,
        .id = id,
        .name = name,
        .enabled = raw.Enabled,
        .settings = settings,
        .plugin_reference = plugin_reference,
        .config = config,
    };
}

fn settingsFromRaw(allocator: std.mem.Allocator, raw: wire.Settings) !model.Settings {
    const mounts = try mountsFromRaw(allocator, raw.Mounts);
    errdefer freeMounts(allocator, mounts);
    const env = try dupeStrings(allocator, raw.Env);
    errdefer freeStrings(allocator, env);
    const args = try dupeStrings(allocator, raw.Args);
    errdefer freeStrings(allocator, args);
    const devices = try devicesFromRaw(allocator, raw.Devices);
    errdefer freeDevices(allocator, devices);

    return .{ .mounts = mounts, .env = env, .args = args, .devices = devices };
}

fn configFromRaw(allocator: std.mem.Allocator, raw: wire.PluginConfig) !model.PluginConfig {
    const description = try allocator.dupe(u8, raw.Description);
    errdefer allocator.free(description);
    const documentation = try allocator.dupe(u8, raw.Documentation);
    errdefer allocator.free(documentation);
    var interface = try interfaceFromRaw(allocator, raw.Interface);
    errdefer interface.deinit(allocator);
    const entrypoint = try dupeStrings(allocator, raw.Entrypoint);
    errdefer freeStrings(allocator, entrypoint);
    const work_dir = try allocator.dupe(u8, raw.WorkDir);
    errdefer allocator.free(work_dir);
    var network = try networkFromRaw(allocator, raw.Network);
    errdefer network.deinit(allocator);
    var linux = try linuxFromRaw(allocator, raw.Linux);
    errdefer linux.deinit(allocator);
    const propagated_mount = try allocator.dupe(u8, raw.PropagatedMount);
    errdefer allocator.free(propagated_mount);
    const mounts = try mountsFromRaw(allocator, raw.Mounts);
    errdefer freeMounts(allocator, mounts);
    const env = try envsFromRaw(allocator, raw.Env);
    errdefer freeEnvs(allocator, env);
    var args = try argsFromRaw(allocator, raw.Args);
    errdefer args.deinit(allocator);
    const rootfs = try rootfsFromRaw(allocator, raw.rootfs);
    errdefer if (rootfs) |*value| value.deinit(allocator);

    return .{
        .description = description,
        .documentation = documentation,
        .interface = interface,
        .entrypoint = entrypoint,
        .work_dir = work_dir,
        .user = if (raw.User) |user| .{ .uid = user.UID, .gid = user.GID } else null,
        .network = network,
        .linux = linux,
        .propagated_mount = propagated_mount,
        .ipc_host = raw.IpcHost,
        .pid_host = raw.PidHost,
        .mounts = mounts,
        .env = env,
        .args = args,
        .rootfs = rootfs,
    };
}

fn interfaceFromRaw(allocator: std.mem.Allocator, raw: wire.Interface) !model.Interface {
    const types = try dupeStrings(allocator, raw.Types);
    errdefer freeStrings(allocator, types);
    const socket = try allocator.dupe(u8, raw.Socket);
    errdefer allocator.free(socket);
    const protocol_scheme = try dupeOptional(allocator, raw.ProtocolScheme);
    errdefer model.freeOptional(allocator, protocol_scheme);
    return .{ .types = types, .socket = socket, .protocol_scheme = protocol_scheme };
}

fn networkFromRaw(allocator: std.mem.Allocator, raw: wire.NetworkConfig) !model.NetworkConfig {
    return .{ .type = try allocator.dupe(u8, raw.Type) };
}

fn linuxFromRaw(allocator: std.mem.Allocator, raw: wire.LinuxConfig) !model.LinuxConfig {
    const capabilities = try dupeStrings(allocator, raw.Capabilities);
    errdefer freeStrings(allocator, capabilities);
    const devices = try devicesFromRaw(allocator, raw.Devices);
    errdefer freeDevices(allocator, devices);
    return .{ .capabilities = capabilities, .allow_all_devices = raw.AllowAllDevices, .devices = devices };
}

fn rootfsFromRaw(allocator: std.mem.Allocator, raw: ?wire.Rootfs) !?model.Rootfs {
    const value = raw orelse return null;
    const type_name = try dupeOptional(allocator, value.type);
    errdefer model.freeOptional(allocator, type_name);
    const diff_ids = try dupeOptionalStrings(allocator, value.diff_ids);
    errdefer freeStrings(allocator, diff_ids);
    return .{ .type = type_name, .diff_ids = diff_ids };
}

fn mountsFromRaw(allocator: std.mem.Allocator, raw_values: []wire.Mount) ![]model.Mount {
    const values = try allocator.alloc(model.Mount, raw_values.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (raw_values) |raw| {
        values[filled] = try mountFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn mountFromRaw(allocator: std.mem.Allocator, raw: wire.Mount) !model.Mount {
    const name = try allocator.dupe(u8, raw.Name);
    errdefer allocator.free(name);
    const description = try allocator.dupe(u8, raw.Description);
    errdefer allocator.free(description);
    const settable = try dupeOptionalStrings(allocator, raw.Settable);
    errdefer freeStrings(allocator, settable);
    const source = try allocator.dupe(u8, raw.Source);
    errdefer allocator.free(source);
    const destination = try allocator.dupe(u8, raw.Destination);
    errdefer allocator.free(destination);
    const type_name = try allocator.dupe(u8, raw.Type);
    errdefer allocator.free(type_name);
    const options = try dupeOptionalStrings(allocator, raw.Options);
    errdefer freeStrings(allocator, options);
    return .{
        .name = name,
        .description = description,
        .settable = settable,
        .source = source,
        .destination = destination,
        .type = type_name,
        .options = options,
    };
}

fn devicesFromRaw(allocator: std.mem.Allocator, raw_values: []wire.Device) ![]model.Device {
    const values = try allocator.alloc(model.Device, raw_values.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (raw_values) |raw| {
        values[filled] = try deviceFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn deviceFromRaw(allocator: std.mem.Allocator, raw: wire.Device) !model.Device {
    const name = try allocator.dupe(u8, raw.Name);
    errdefer allocator.free(name);
    const description = try allocator.dupe(u8, raw.Description);
    errdefer allocator.free(description);
    const settable = try dupeOptionalStrings(allocator, raw.Settable);
    errdefer freeStrings(allocator, settable);
    const path = try allocator.dupe(u8, raw.Path);
    errdefer allocator.free(path);
    return .{ .name = name, .description = description, .settable = settable, .path = path };
}

fn envsFromRaw(allocator: std.mem.Allocator, raw_values: []wire.Env) ![]model.Env {
    const values = try allocator.alloc(model.Env, raw_values.len);
    var filled: usize = 0;
    errdefer {
        for (values[0..filled]) |*value| value.deinit(allocator);
        allocator.free(values);
    }
    for (raw_values) |raw| {
        values[filled] = try envFromRaw(allocator, raw);
        filled += 1;
    }
    return values;
}

fn envFromRaw(allocator: std.mem.Allocator, raw: wire.Env) !model.Env {
    const name = try allocator.dupe(u8, raw.Name);
    errdefer allocator.free(name);
    const description = try allocator.dupe(u8, raw.Description);
    errdefer allocator.free(description);
    const settable = try dupeOptionalStrings(allocator, raw.Settable);
    errdefer freeStrings(allocator, settable);
    const value = try allocator.dupe(u8, raw.Value);
    errdefer allocator.free(value);
    return .{ .name = name, .description = description, .settable = settable, .value = value };
}

fn argsFromRaw(allocator: std.mem.Allocator, raw: wire.Args) !model.Args {
    const name = try allocator.dupe(u8, raw.Name);
    errdefer allocator.free(name);
    const description = try allocator.dupe(u8, raw.Description);
    errdefer allocator.free(description);
    const settable = try dupeOptionalStrings(allocator, raw.Settable);
    errdefer freeStrings(allocator, settable);
    const value = try dupeOptionalStrings(allocator, raw.Value);
    errdefer freeStrings(allocator, value);
    return .{ .name = name, .description = description, .settable = settable, .value = value };
}

fn privilegeFromRaw(allocator: std.mem.Allocator, raw: wire.Privilege) !model.Privilege {
    const name = try allocator.dupe(u8, raw.Name);
    errdefer allocator.free(name);
    const description = try dupeOptional(allocator, raw.Description);
    errdefer model.freeOptional(allocator, description);
    const value = try dupeOptionalStrings(allocator, raw.Value);
    errdefer freeStrings(allocator, value);
    return .{ .name = name, .description = description, .value = value };
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |string| return try allocator.dupe(u8, string);
    return null;
}

fn dupeStrings(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    const owned = try allocator.alloc([]const u8, values.len);
    var filled: usize = 0;
    errdefer {
        model.freeStringList(allocator, owned[0..filled]);
        allocator.free(owned);
    }
    for (values) |value| {
        owned[filled] = try allocator.dupe(u8, value);
        filled += 1;
    }
    return owned;
}

fn dupeOptionalStrings(allocator: std.mem.Allocator, values: ?[]const []const u8) ![]const []const u8 {
    if (values) |strings| return try dupeStrings(allocator, strings);
    return try allocator.alloc([]const u8, 0);
}

fn freeStrings(allocator: std.mem.Allocator, values: []const []const u8) void {
    model.freeStringList(allocator, values);
    allocator.free(values);
}

fn freeMounts(allocator: std.mem.Allocator, values: []model.Mount) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

fn freeDevices(allocator: std.mem.Allocator, values: []model.Device) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

fn freeEnvs(allocator: std.mem.Allocator, values: []model.Env) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}
