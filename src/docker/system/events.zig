const std = @import("std");

const http = @import("../http.zig");
const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const record = @import("../stream/record.zig");

pub const EventsOptions = struct {
    since: ?[]const u8 = null,
    until: ?[]const u8 = null,
    filters: ?[]const u8 = null,
    max_event_bytes: usize = 1024 * 1024,
};

pub const Event = struct {
    allocator: std.mem.Allocator,
    object_type: ?[]const u8,
    action: ?[]const u8,
    actor: Actor,
    scope: ?[]const u8,
    time: ?i64,
    time_nano: ?i64,

    pub const Actor = struct {
        id: ?[]const u8,
        attributes: ?[]const Attribute,
    };

    pub const Attribute = struct {
        name: []const u8,
        value: []const u8,
    };

    fn init(allocator: std.mem.Allocator, raw: RawEvent) !Event {
        var result = Event{
            .allocator = allocator,
            .object_type = null,
            .action = null,
            .actor = .{
                .id = null,
                .attributes = null,
            },
            .scope = null,
            .time = raw.time,
            .time_nano = raw.timeNano,
        };
        errdefer result.deinit();

        result.object_type = try dupeOptionalString(allocator, raw.Type);
        result.action = try dupeOptionalString(allocator, raw.Action);
        if (raw.Actor) |actor| {
            result.actor.id = try dupeOptionalString(allocator, actor.ID);
            result.actor.attributes = try dupeAttributes(allocator, actor.Attributes);
        }
        result.scope = try dupeOptionalString(allocator, raw.scope);

        return result;
    }

    pub fn deinit(self: *Event) void {
        freeOptionalString(self.allocator, self.object_type);
        freeOptionalString(self.allocator, self.action);
        freeOptionalString(self.allocator, self.actor.id);
        if (self.actor.attributes) |attributes| freeAttributes(self.allocator, attributes);
        freeOptionalString(self.allocator, self.scope);
        self.* = undefined;
    }
};

pub const EventStream = struct {
    response: Client.Response,
    decoder: record.Decoder,

    pub fn next(self: *EventStream, allocator: std.mem.Allocator) !?Event {
        const bytes = try self.decoder.next(allocator) orelse return null;
        defer allocator.free(bytes);
        return try parseEvent(allocator, bytes);
    }

    pub fn deinit(self: *EventStream) void {
        self.response.deinit();
        self.* = undefined;
    }
};

pub fn events(allocator: std.mem.Allocator, client: *Client, options: EventsOptions) !EventStream {
    const path = try eventsPath(allocator, options);
    defer allocator.free(path);

    var headers = try eventHeaders(allocator);
    defer headers.deinit(allocator);

    var response = try client.request(.{
        .method = .get,
        .path = path,
        .headers = &headers,
    });
    errdefer response.deinit();

    switch (response.status()) {
        .ok => {},
        .bad_request => return error.BadParameter,
        else => return error.UnexpectedStatus,
    }

    var result = EventStream{
        .response = response,
        .decoder = undefined,
    };
    const format = try record.Format.fromContentType(result.response.header("Content-Type"));
    result.decoder = .init(result.response.reader(), format, options.max_event_bytes);
    return result;
}

const RawEvent = struct {
    Type: ?[]const u8 = null,
    Action: ?[]const u8 = null,
    Actor: ?RawActor = null,
    scope: ?[]const u8 = null,
    time: ?i64 = null,
    timeNano: ?i64 = null,
};

const RawActor = struct {
    ID: ?[]const u8 = null,
    Attributes: ?std.json.ArrayHashMap([]const u8) = null,
};

fn eventsPath(allocator: std.mem.Allocator, options: EventsOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/events");
    defer builder.deinit();

    if (options.since) |since| try builder.add("since", since);
    if (options.until) |until| try builder.add("until", until);
    if (options.filters) |filters| try builder.add("filters", filters);

    return builder.finish();
}

fn parseEvent(allocator: std.mem.Allocator, line: []const u8) !Event {
    const parsed = try std.json.parseFromSlice(RawEvent, allocator, line, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    return Event.init(allocator, parsed.value);
}

fn eventHeaders(allocator: std.mem.Allocator) !http.Headers {
    var headers = try http.Headers.init(allocator, 1);
    errdefer headers.deinit(allocator);
    try headers.put("Accept", "application/json-seq, application/x-ndjson");
    return headers;
}

fn dupeOptionalString(allocator: std.mem.Allocator, bytes: ?[]const u8) !?[]const u8 {
    if (bytes) |string| {
        return try allocator.dupe(u8, string);
    }
    return null;
}

fn freeOptionalString(allocator: std.mem.Allocator, string: ?[]const u8) void {
    if (string) |owned| allocator.free(owned);
}

fn dupeAttributes(
    allocator: std.mem.Allocator,
    attributes: ?std.json.ArrayHashMap([]const u8),
) !?[]const Event.Attribute {
    const source = attributes orelse return null;
    const owned = try allocator.alloc(Event.Attribute, source.map.count());
    var filled: usize = 0;
    errdefer {
        freeAttributeItems(allocator, owned[0..filled]);
        allocator.free(owned);
    }

    var iterator = source.map.iterator();
    while (iterator.next()) |entry| {
        const name = try allocator.dupe(u8, entry.key_ptr.*);
        const value = allocator.dupe(u8, entry.value_ptr.*) catch |err| {
            allocator.free(name);
            return err;
        };
        owned[filled] = .{
            .name = name,
            .value = value,
        };
        filled += 1;
    }

    return owned;
}

fn freeAttributes(allocator: std.mem.Allocator, attributes: []const Event.Attribute) void {
    freeAttributeItems(allocator, attributes);
    allocator.free(attributes);
}

fn freeAttributeItems(allocator: std.mem.Allocator, attributes: []const Event.Attribute) void {
    for (attributes) |attribute| {
        allocator.free(attribute.name);
        allocator.free(attribute.value);
    }
}

test "eventsPath encodes filters" {
    const path = try eventsPath(std.testing.allocator, .{
        .since = "1629574695",
        .until = "1629574700",
        .filters = "{\"type\":[\"container\"]}",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/events?since=1629574695&until=1629574700&filters=%7B%22type%22%3A%5B%22container%22%5D%7D",
        path,
    );
}

test "event headers negotiate both Docker streaming formats" {
    var headers = try eventHeaders(std.testing.allocator);
    defer headers.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(
        "application/json-seq, application/x-ndjson",
        headers.get("Accept").?,
    );
}

test "parseEvent owns JSONL event fields" {
    var event = try parseEvent(std.testing.allocator,
        \\{
        \\  "Type": "container",
        \\  "Action": "create",
        \\  "Actor": {
        \\    "ID": "ede54ee1afda366ab42f824e8a5ffd195155d853ceaec74a927f249ea270c743",
        \\    "Attributes": {"name": "web", "image": "nginx:latest"}
        \\  },
        \\  "scope": "local",
        \\  "time": 1629574695,
        \\  "timeNano": 1629574695515050000
        \\}
    );
    defer event.deinit();

    try std.testing.expectEqualStrings("container", event.object_type.?);
    try std.testing.expectEqualStrings("create", event.action.?);
    try std.testing.expectEqualStrings(
        "ede54ee1afda366ab42f824e8a5ffd195155d853ceaec74a927f249ea270c743",
        event.actor.id.?,
    );
    try std.testing.expectEqual(@as(usize, 2), event.actor.attributes.?.len);
    try std.testing.expectEqualStrings("name", event.actor.attributes.?[0].name);
    try std.testing.expectEqualStrings("web", event.actor.attributes.?[0].value);
    try std.testing.expectEqualStrings("local", event.scope.?);
    try std.testing.expectEqual(@as(i64, 1629574695), event.time.?);
    try std.testing.expectEqual(@as(i64, 1629574695515050000), event.time_nano.?);
}

test "parseEvent cleans up allocation failures" {
    const line =
        \\{
        \\  "Type": "container",
        \\  "Action": "create",
        \\  "Actor": {"ID": "id", "Attributes": {"name": "web"}},
        \\  "scope": "local"
        \\}
    ;

    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseEventForAllocationFailure,
        .{line},
    );
}

test "EventStream.next keeps the receiver first" {
    const Next = *const fn (*EventStream, std.mem.Allocator) anyerror!?Event;
    const next: Next = EventStream.next;
    _ = next;
}

fn parseEventForAllocationFailure(allocator: std.mem.Allocator, line: []const u8) !void {
    var event = try parseEvent(allocator, line);
    event.deinit();
}
