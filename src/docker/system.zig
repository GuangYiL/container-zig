pub const Auth = @import("system/auth.zig").Auth;
pub const AuthOptions = @import("system/auth.zig").AuthOptions;
pub const auth = @import("system/auth.zig").auth;

pub const DataUsage = @import("system/data_usage.zig").DataUsage;
pub const DataUsageOptions = @import("system/data_usage.zig").DataUsageOptions;
pub const dataUsage = @import("system/data_usage.zig").dataUsage;

pub const Event = @import("system/events.zig").Event;
pub const EventStream = @import("system/events.zig").EventStream;
pub const EventsOptions = @import("system/events.zig").EventsOptions;
pub const events = @import("system/events.zig").events;

pub const Info = @import("system/info.zig").Info;
pub const info = @import("system/info.zig").info;

pub const Ping = @import("system/ping.zig").Ping;
pub const ping = @import("system/ping.zig").ping;
pub const pingText = @import("system/ping.zig").pingText;

pub const Version = @import("system/version.zig").Version;
pub const version = @import("system/version.zig").version;

test {
    _ = @import("system/auth.zig");
    _ = @import("system/data_usage.zig");
    _ = @import("system/events.zig");
    _ = @import("system/info.zig");
    _ = @import("system/ping.zig");
    _ = @import("system/version.zig");
}
