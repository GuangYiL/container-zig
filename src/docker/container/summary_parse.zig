const std = @import("std");

const model = @import("summary.zig");
const wire = @import("summary_wire.zig");

const Summary = model.Summary;
const SummaryList = model.SummaryList;

pub fn parseSummaryList(allocator: std.mem.Allocator, body: []const u8) !SummaryList {
    const parsed = try std.json.parseFromSlice([]wire.Summary, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const items = try allocator.alloc(Summary, parsed.value.len);
    var filled: usize = 0;
    errdefer {
        for (items[0..filled]) |*item| item.deinit();
        allocator.free(items);
    }

    for (parsed.value) |raw| {
        items[filled] = try initSummary(allocator, raw);
        filled += 1;
    }

    return .{
        .allocator = allocator,
        .items = items,
    };
}

fn initSummary(allocator: std.mem.Allocator, raw: wire.Summary) !Summary {
    const id = try dupeOptionalString(allocator, raw.Id);
    errdefer model.freeOptionalString(allocator, id);
    const names = try dupeStringList(allocator, raw.Names);
    errdefer model.freeStringList(allocator, names);
    const image = try dupeOptionalString(allocator, raw.Image);
    errdefer model.freeOptionalString(allocator, image);
    const image_id = try dupeOptionalString(allocator, raw.ImageID);
    errdefer model.freeOptionalString(allocator, image_id);
    const command = try dupeOptionalString(allocator, raw.Command);
    errdefer model.freeOptionalString(allocator, command);
    const ports = try dupePorts(allocator, raw.Ports);
    errdefer model.freePorts(allocator, ports);
    const labels = try dupePairs(allocator, raw.Labels);
    errdefer model.freePairs(allocator, labels);
    const status = try dupeOptionalString(allocator, raw.Status);
    errdefer model.freeOptionalString(allocator, status);
    const host_config = try initHostConfig(allocator, raw.HostConfig);
    errdefer freeHostConfig(allocator, host_config);
    const network_settings = try initNetworkSettings(allocator, raw.NetworkSettings);
    errdefer freeNetworkSettings(allocator, network_settings);
    const mounts = try dupeMounts(allocator, raw.Mounts);
    errdefer model.freeMounts(allocator, mounts);

    return .{
        .allocator = allocator,
        .id = id,
        .names = names,
        .image = image,
        .image_id = image_id,
        .command = command,
        .created = raw.Created,
        .ports = ports,
        .size_rw = raw.SizeRw,
        .size_root_fs = raw.SizeRootFs,
        .labels = labels,
        .state = raw.State,
        .status = status,
        .host_config = host_config,
        .network_settings = network_settings,
        .mounts = mounts,
        .health = if (raw.Health) |health| .{
            .status = health.Status,
            .failing_streak = health.FailingStreak,
        } else null,
    };
}

fn initHostConfig(allocator: std.mem.Allocator, raw: ?wire.HostConfig) !Summary.HostConfig {
    const host_config = raw orelse return .{
        .network_mode = null,
        .annotations = try emptyPairs(allocator),
    };

    const network_mode = try dupeOptionalString(allocator, host_config.NetworkMode);
    errdefer model.freeOptionalString(allocator, network_mode);
    const annotations = try dupePairs(allocator, host_config.Annotations);
    errdefer model.freePairs(allocator, annotations);

    return .{
        .network_mode = network_mode,
        .annotations = annotations,
    };
}

fn initNetworkSettings(allocator: std.mem.Allocator, raw: ?wire.NetworkSettings) !Summary.NetworkSettings {
    const network_settings = raw orelse return .{
        .networks = try emptyNetworks(allocator),
    };

    return .{
        .networks = try dupeNetworks(allocator, network_settings.Networks),
    };
}

fn freeHostConfig(allocator: std.mem.Allocator, host_config: Summary.HostConfig) void {
    model.freeOptionalString(allocator, host_config.network_mode);
    model.freePairs(allocator, host_config.annotations);
}

fn freeNetworkSettings(allocator: std.mem.Allocator, network_settings: Summary.NetworkSettings) void {
    model.freeNetworks(allocator, network_settings.networks);
}

fn dupePorts(allocator: std.mem.Allocator, raw_ports: ?[]const wire.Port) ![]Summary.Port {
    const ports = raw_ports orelse return try allocator.alloc(Summary.Port, 0);
    const owned = try allocator.alloc(Summary.Port, ports.len);
    var filled: usize = 0;
    errdefer {
        model.freePortItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    for (ports) |port| {
        owned[filled] = .{
            .ip = try dupeOptionalString(allocator, port.IP),
            .private_port = port.PrivatePort,
            .public_port = port.PublicPort,
            .protocol = port.Type,
        };
        filled += 1;
    }

    return owned;
}

fn dupeNetworks(
    allocator: std.mem.Allocator,
    raw_networks: ?std.json.ArrayHashMap(wire.Endpoint),
) ![]Summary.Network {
    const source = raw_networks orelse return emptyNetworks(allocator);
    const owned = try allocator.alloc(Summary.Network, source.map.count());
    var filled: usize = 0;
    errdefer {
        model.freeNetworkItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    var iterator = source.map.iterator();
    while (iterator.next()) |entry| {
        const name = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(name);
        const endpoint = try initEndpoint(allocator, entry.value_ptr.*);
        owned[filled] = .{
            .name = name,
            .endpoint = endpoint,
        };
        filled += 1;
    }

    return owned;
}

fn initEndpoint(allocator: std.mem.Allocator, raw: wire.Endpoint) !Summary.Endpoint {
    const network_id = try dupeOptionalString(allocator, raw.NetworkID);
    errdefer model.freeOptionalString(allocator, network_id);
    const endpoint_id = try dupeOptionalString(allocator, raw.EndpointID);
    errdefer model.freeOptionalString(allocator, endpoint_id);
    const gateway = try dupeOptionalString(allocator, raw.Gateway);
    errdefer model.freeOptionalString(allocator, gateway);
    const ip_address = try dupeOptionalString(allocator, raw.IPAddress);
    errdefer model.freeOptionalString(allocator, ip_address);
    const ipv6_gateway = try dupeOptionalString(allocator, raw.IPv6Gateway);
    errdefer model.freeOptionalString(allocator, ipv6_gateway);
    const global_ipv6_address = try dupeOptionalString(allocator, raw.GlobalIPv6Address);
    errdefer model.freeOptionalString(allocator, global_ipv6_address);
    const mac_address = try dupeOptionalString(allocator, raw.MacAddress);
    errdefer model.freeOptionalString(allocator, mac_address);
    const dns_names = try dupeStringList(allocator, raw.DNSNames);
    errdefer model.freeStringList(allocator, dns_names);

    return .{
        .network_id = network_id,
        .endpoint_id = endpoint_id,
        .gateway = gateway,
        .ip_address = ip_address,
        .ip_prefix_len = raw.IPPrefixLen,
        .ipv6_gateway = ipv6_gateway,
        .global_ipv6_address = global_ipv6_address,
        .global_ipv6_prefix_len = raw.GlobalIPv6PrefixLen,
        .mac_address = mac_address,
        .dns_names = dns_names,
    };
}

fn dupeMounts(allocator: std.mem.Allocator, raw_mounts: ?[]const wire.Mount) ![]Summary.Mount {
    const mounts = raw_mounts orelse return try allocator.alloc(Summary.Mount, 0);
    const owned = try allocator.alloc(Summary.Mount, mounts.len);
    var filled: usize = 0;
    errdefer {
        model.freeMountItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    for (mounts) |mount| {
        owned[filled] = try mountFromRaw(allocator, mount);
        filled += 1;
    }

    return owned;
}

fn mountFromRaw(allocator: std.mem.Allocator, raw: wire.Mount) !Summary.Mount {
    const name = try dupeOptionalString(allocator, raw.Name);
    errdefer model.freeOptionalString(allocator, name);
    const source = try dupeOptionalString(allocator, raw.Source);
    errdefer model.freeOptionalString(allocator, source);
    const destination = try dupeOptionalString(allocator, raw.Destination);
    errdefer model.freeOptionalString(allocator, destination);
    const driver = try dupeOptionalString(allocator, raw.Driver);
    errdefer model.freeOptionalString(allocator, driver);
    const mode = try dupeOptionalString(allocator, raw.Mode);
    errdefer model.freeOptionalString(allocator, mode);
    const propagation = try dupeOptionalString(allocator, raw.Propagation);
    errdefer model.freeOptionalString(allocator, propagation);

    return .{
        .mount_type = raw.Type,
        .name = name,
        .source = source,
        .destination = destination,
        .driver = driver,
        .mode = mode,
        .read_write = raw.RW,
        .propagation = propagation,
    };
}

fn dupePairs(allocator: std.mem.Allocator, raw_pairs: ?std.json.ArrayHashMap([]const u8)) ![]Summary.Pair {
    const source = raw_pairs orelse return emptyPairs(allocator);
    const owned = try allocator.alloc(Summary.Pair, source.map.count());
    var filled: usize = 0;
    errdefer {
        model.freePairItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    var iterator = source.map.iterator();
    while (iterator.next()) |entry| {
        const name = try allocator.dupe(u8, entry.key_ptr.*);
        const value = allocator.dupe(u8, entry.value_ptr.*) catch |err| {
            allocator.free(name);
            return err;
        };
        owned[filled] = .{ .name = name, .value = value };
        filled += 1;
    }

    return owned;
}

fn dupeStringList(allocator: std.mem.Allocator, raw_strings: ?[]const []const u8) ![]const []const u8 {
    const strings = raw_strings orelse return try allocator.alloc([]const u8, 0);
    const owned = try allocator.alloc([]const u8, strings.len);
    var filled: usize = 0;
    errdefer {
        model.freeStringItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    for (strings) |string| {
        owned[filled] = try allocator.dupe(u8, string);
        filled += 1;
    }

    return owned;
}

fn dupeOptionalString(allocator: std.mem.Allocator, bytes: ?[]const u8) !?[]const u8 {
    if (bytes) |string| {
        return try allocator.dupe(u8, string);
    }
    return null;
}

fn emptyPairs(allocator: std.mem.Allocator) ![]Summary.Pair {
    return allocator.alloc(Summary.Pair, 0);
}

fn emptyNetworks(allocator: std.mem.Allocator) ![]Summary.Network {
    return allocator.alloc(Summary.Network, 0);
}

test "parseSummaryList owns container summary fields" {
    var summaries = try parseSummaryList(std.testing.allocator, summaryListBody());
    defer summaries.deinit();

    try std.testing.expectEqual(@as(usize, 1), summaries.items.len);
    const item = summaries.items[0];
    try std.testing.expectEqualStrings("aa86eacfb3b3ed4cd362c1e88fc89a53908ad05fb3a4103bca3f9b28292d14bf", item.id.?);
    try std.testing.expectEqualStrings("/web", item.names[0]);
    try std.testing.expectEqualStrings("nginx:latest", item.image.?);
    try std.testing.expectEqualStrings(
        "sha256:72297848456d5d37d1262630108ab308d3e9ec7ed1c3286a32fe09856619a782",
        item.image_id.?,
    );
    try std.testing.expectEqualStrings("nginx -g daemon off;", item.command.?);
    try std.testing.expectEqual(@as(i64, 1739811096), item.created.?);
    try std.testing.expectEqual(@as(u16, 80), item.ports[0].private_port);
    try std.testing.expectEqual(@as(u16, 8080), item.ports[0].public_port.?);
    try std.testing.expectEqual(Summary.Port.Protocol.tcp, item.ports[0].protocol);
    try std.testing.expectEqualStrings("com.example.vendor", item.labels[0].name);
    try std.testing.expectEqual(Summary.State.running, item.state.?);
    try std.testing.expectEqualStrings("bridge", item.host_config.network_mode.?);
    try std.testing.expectEqualStrings("bridge", item.network_settings.networks[0].name);
    try std.testing.expectEqualStrings("172.17.0.4", item.network_settings.networks[0].endpoint.ip_address.?);
    try std.testing.expectEqualStrings("web", item.network_settings.networks[0].endpoint.dns_names[0]);
    try std.testing.expectEqual(Summary.Mount.MountType.volume, item.mounts[0].mount_type.?);
    try std.testing.expectEqualStrings("/usr/share/nginx/html", item.mounts[0].destination.?);
    try std.testing.expectEqual(Summary.Health.Status.healthy, item.health.?.status.?);
}

test "parseSummaryList cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseSummaryListForAllocationFailure,
        .{summaryListBody()},
    );
}

fn parseSummaryListForAllocationFailure(allocator: std.mem.Allocator, body: []const u8) !void {
    var result = try parseSummaryList(allocator, body);
    result.deinit();
}

fn summaryListBody() []const u8 {
    return
    \\[
    \\  {
    \\    "Id": "aa86eacfb3b3ed4cd362c1e88fc89a53908ad05fb3a4103bca3f9b28292d14bf",
    \\    "Names": ["/web"],
    \\    "Image": "nginx:latest",
    \\    "ImageID": "sha256:72297848456d5d37d1262630108ab308d3e9ec7ed1c3286a32fe09856619a782",
    \\    "Command": "nginx -g daemon off;",
    \\    "Created": 1739811096,
    \\    "Ports": [{"IP": "0.0.0.0", "PrivatePort": 80, "PublicPort": 8080, "Type": "tcp"}],
    \\    "SizeRw": 122880,
    \\    "SizeRootFs": 1653948416,
    \\    "Labels": {"com.example.vendor": "Acme"},
    \\    "State": "running",
    \\    "Status": "Up 4 days",
    \\    "HostConfig": {
    \\      "NetworkMode": "bridge",
    \\      "Annotations": {"io.kubernetes.docker.type": "container"}
    \\    },
    \\    "NetworkSettings": {
    \\      "Networks": {
    \\        "bridge": {
    \\          "NetworkID": "network-id",
    \\          "EndpointID": "endpoint-id",
    \\          "Gateway": "172.17.0.1",
    \\          "IPAddress": "172.17.0.4",
    \\          "IPPrefixLen": 16,
    \\          "IPv6Gateway": "",
    \\          "GlobalIPv6Address": "",
    \\          "GlobalIPv6PrefixLen": 0,
    \\          "MacAddress": "02:42:ac:11:00:04",
    \\          "DNSNames": ["web", "aa86eacfb3b3"]
    \\        }
    \\      }
    \\    },
    \\    "Mounts": [{
    \\      "Type": "volume",
    \\      "Name": "html",
    \\      "Source": "/var/lib/docker/volumes/html/_data",
    \\      "Destination": "/usr/share/nginx/html",
    \\      "Driver": "local",
    \\      "Mode": "z",
    \\      "RW": true,
    \\      "Propagation": ""
    \\    }],
    \\    "Health": {"Status": "healthy", "FailingStreak": 0},
    \\    "FutureField": "ignored"
    \\  }
    \\]
    ;
}
