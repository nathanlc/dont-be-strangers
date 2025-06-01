const std = @import("std");
const builtin = @import("builtin");
const web = @import("web.zig");

const logger = std.log.scoped(.slack);

pub fn sendMessage(alloc: std.mem.Allocator, url: []const u8, message: []const u8) !void {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var header_buffer: [4096]u8 = undefined;
    var request = try client.open(.POST, uri, .{ .server_header_buffer = &header_buffer });
    defer request.deinit();

    const body = try std.fmt.allocPrint(
        alloc,
        "{{\"text\":\"{s}\"}}",
        .{message},
    );

    defer alloc.free(body);
    request.headers.connection = .omit;
    request.headers.content_type = .{
        .override = web.Mime.application_json.toString(),
    };
    request.transfer_encoding = .{ .content_length = body.len };

    try request.send();
    try request.writeAll(body);
    try request.finish();
    try request.wait();

    var response_body_buffer: [2048]u8 = undefined;
    const size = try request.readAll(&response_body_buffer);
    const response_body = response_body_buffer[0..size];

    const response = request.response;
    if (response.status.class() != .success) {
        logger.err("Failed to send Slack message:\n{s}", .{response_body});
        return error.HttpRequestFailed;
    }
}
