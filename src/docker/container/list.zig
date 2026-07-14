const std = @import("std");

const Client = @import("../client.zig").Client;
const query = @import("../query.zig");
const summary = @import("summary.zig");
const summary_parse = @import("summary_parse.zig");
const http_status = @import("../status.zig");

pub const SummaryList = summary.SummaryList;
pub const Summary = summary.Summary;
pub const ListOptions = summary.ListOptions;

pub fn list(allocator: std.mem.Allocator, client: *Client, options: ListOptions) !SummaryList {
    const path = try listPath(allocator, options);
    defer allocator.free(path);

    var response = try client.request(.{
        .method = .get,
        .path = path,
    });
    defer response.deinit();

    try http_status.expect(response.status(), .{.ok});

    const body = try response.body() orelse return error.EmptyResponse;
    return summary_parse.parseSummaryList(allocator, body);
}

fn listPath(allocator: std.mem.Allocator, options: ListOptions) ![]u8 {
    var builder = try query.Builder.init(allocator, "/containers/json");
    defer builder.deinit();

    if (options.all) |all| try builder.addBool("all", all);
    if (options.limit) |limit| try builder.addInt("limit", limit);
    if (options.size) |size| try builder.addBool("size", size);
    if (options.filters) |filters| try builder.add("filters", filters);

    return builder.finish();
}

test "listPath encodes container list filters" {
    const path = try listPath(std.testing.allocator, .{
        .all = true,
        .limit = 5,
        .size = true,
        .filters = "{\"status\":[\"running\"]}",
    });
    defer std.testing.allocator.free(path);

    try std.testing.expectEqualStrings(
        "/containers/json?all=true&limit=5&size=true&filters=%7B%22status%22%3A%5B%22running%22%5D%7D",
        path,
    );
}
