const std = @import("std");

pub const ListOptions = struct {
    all: ?bool = null,
    limit: ?u32 = null,
    size: ?bool = null,
    filters: ?[]const u8 = null,
};

pub const SummaryList = struct {
    allocator: std.mem.Allocator,
    items: []Summary,

    pub fn deinit(self: *SummaryList) void {
        for (self.items) |*item| item.deinit();
        self.allocator.free(self.items);
        self.* = undefined;
    }
};

pub const Summary = struct {
    allocator: std.mem.Allocator,
    id: ?[]const u8,
    names: []const []const u8,
    image: ?[]const u8,
    image_id: ?[]const u8,
    command: ?[]const u8,
    created: ?i64,
    ports: []const Port,
    size_rw: ?i64,
    size_root_fs: ?i64,
    labels: []const Pair,
    state: ?State,
    status: ?[]const u8,
    host_config: HostConfig,
    network_settings: NetworkSettings,
    mounts: []const Mount,
    health: ?Health,

    pub const State = enum {
        created,
        running,
        paused,
        restarting,
        exited,
        removing,
        dead,
    };

    pub const Pair = struct {
        name: []const u8,
        value: []const u8,
    };

    pub const Port = struct {
        ip: ?[]const u8,
        private_port: u16,
        public_port: ?u16,
        protocol: Protocol,

        pub const Protocol = enum {
            tcp,
            udp,
            sctp,
        };
    };

    pub const HostConfig = struct {
        network_mode: ?[]const u8,
        annotations: []const Pair,
    };

    pub const NetworkSettings = struct {
        networks: []const Network,
    };

    pub const Network = struct {
        name: []const u8,
        endpoint: Endpoint,
    };

    pub const Endpoint = struct {
        network_id: ?[]const u8,
        endpoint_id: ?[]const u8,
        gateway: ?[]const u8,
        ip_address: ?[]const u8,
        ip_prefix_len: ?i64,
        ipv6_gateway: ?[]const u8,
        global_ipv6_address: ?[]const u8,
        global_ipv6_prefix_len: ?i64,
        mac_address: ?[]const u8,
        dns_names: []const []const u8,
    };

    pub const Mount = struct {
        mount_type: ?MountType,
        name: ?[]const u8,
        source: ?[]const u8,
        destination: ?[]const u8,
        driver: ?[]const u8,
        mode: ?[]const u8,
        read_write: ?bool,
        propagation: ?[]const u8,

        pub const MountType = enum {
            bind,
            cluster,
            image,
            npipe,
            tmpfs,
            volume,
        };
    };

    pub const Health = struct {
        status: ?Status,
        failing_streak: ?i64,

        pub const Status = enum {
            none,
            starting,
            healthy,
            unhealthy,
        };
    };

    pub fn deinit(self: *Summary) void {
        freeOptionalString(self.allocator, self.id);
        freeStringList(self.allocator, self.names);
        freeOptionalString(self.allocator, self.image);
        freeOptionalString(self.allocator, self.image_id);
        freeOptionalString(self.allocator, self.command);
        freePorts(self.allocator, self.ports);
        freePairs(self.allocator, self.labels);
        freeOptionalString(self.allocator, self.status);
        freeOptionalString(self.allocator, self.host_config.network_mode);
        freePairs(self.allocator, self.host_config.annotations);
        freeNetworks(self.allocator, self.network_settings.networks);
        freeMounts(self.allocator, self.mounts);
        self.* = undefined;
    }
};

pub fn freePorts(allocator: std.mem.Allocator, ports: []const Summary.Port) void {
    freePortItems(allocator, ports);
    allocator.free(ports);
}

pub fn freePortItems(allocator: std.mem.Allocator, ports: []const Summary.Port) void {
    for (ports) |port| freeOptionalString(allocator, port.ip);
}

pub fn freeNetworks(allocator: std.mem.Allocator, networks: []const Summary.Network) void {
    freeNetworkItems(allocator, networks);
    allocator.free(networks);
}

pub fn freeNetworkItems(allocator: std.mem.Allocator, networks: []const Summary.Network) void {
    for (networks) |network| {
        allocator.free(network.name);
        freeEndpoint(allocator, network.endpoint);
    }
}

pub fn freeEndpoint(allocator: std.mem.Allocator, endpoint: Summary.Endpoint) void {
    freeOptionalString(allocator, endpoint.network_id);
    freeOptionalString(allocator, endpoint.endpoint_id);
    freeOptionalString(allocator, endpoint.gateway);
    freeOptionalString(allocator, endpoint.ip_address);
    freeOptionalString(allocator, endpoint.ipv6_gateway);
    freeOptionalString(allocator, endpoint.global_ipv6_address);
    freeOptionalString(allocator, endpoint.mac_address);
    freeStringList(allocator, endpoint.dns_names);
}

pub fn freeMounts(allocator: std.mem.Allocator, mounts: []const Summary.Mount) void {
    freeMountItems(allocator, mounts);
    allocator.free(mounts);
}

pub fn freeMountItems(allocator: std.mem.Allocator, mounts: []const Summary.Mount) void {
    for (mounts) |mount| {
        freeOptionalString(allocator, mount.name);
        freeOptionalString(allocator, mount.source);
        freeOptionalString(allocator, mount.destination);
        freeOptionalString(allocator, mount.driver);
        freeOptionalString(allocator, mount.mode);
        freeOptionalString(allocator, mount.propagation);
    }
}

pub fn freePairs(allocator: std.mem.Allocator, pairs: []const Summary.Pair) void {
    freePairItems(allocator, pairs);
    allocator.free(pairs);
}

pub fn freePairItems(allocator: std.mem.Allocator, pairs: []const Summary.Pair) void {
    for (pairs) |pair| {
        allocator.free(pair.name);
        allocator.free(pair.value);
    }
}

pub fn freeStringList(allocator: std.mem.Allocator, strings: []const []const u8) void {
    freeStringItems(allocator, strings);
    allocator.free(strings);
}

pub fn freeStringItems(allocator: std.mem.Allocator, strings: []const []const u8) void {
    for (strings) |string| allocator.free(string);
}

pub fn freeOptionalString(allocator: std.mem.Allocator, string: ?[]const u8) void {
    if (string) |owned| allocator.free(owned);
}
