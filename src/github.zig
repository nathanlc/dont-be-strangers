const std = @import("std");
const builtin = @import("builtin");
const web = @import("web.zig");
const config = if (builtin.is_test) @import("test.zig").Config{} else @import("config");
const tracy = @import("tracy.zig");

const TOKEN_URL = "https://github.com/login/oauth/access_token";
const API_URL = "https://api.github.com";
const USER_URL = API_URL ++ "/user";

const logger = std.log.scoped(.github);

pub const ApiCredentials = struct {
    client_id: []const u8,
    secret: []const u8,

    pub fn testing() ApiCredentials {
        return .{
            .client_id = "test_github_client_id",
            .secret = "test_github_secret",
        };
    }
};

pub const FetchTokenError = error{
    Unauthorized,
    Forbidden,
    NotFound,
};

const GrantType = enum {
    authorization_code,
    refresh_token,
};

pub const AuthorizationCodePayload = struct {
    code: []const u8,
};

pub const RefreshTokenPayload = struct {
    refresh_token: []const u8,
};

pub const FetchTokenPayload = union(GrantType) {
    authorization_code: AuthorizationCodePayload,
    refresh_token: RefreshTokenPayload,
};

pub const AccessToken = struct {
    access_token: []u8,
    expires_in: u32,
    refresh_token: []u8,
    refresh_token_expires_in: u32,
    scope: []u8,
    token_type: []u8,
};

pub fn fetchToken(alloc: std.mem.Allocator, api_credentials: ApiCredentials, payload: FetchTokenPayload) !std.json.Parsed(AccessToken) {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    const uri = try std.Uri.parse(TOKEN_URL);
    var header_buffer: [4096]u8 = undefined;
    var request = try client.open(.POST, uri, .{ .server_header_buffer = &header_buffer });
    defer request.deinit();

    // TODO: Replace allocPrint with bufPrint when known len?
    const body = switch (payload) {
        .authorization_code => |p| try std.fmt.allocPrint(
            alloc,
            "{{\"client_id\":\"{s}\",\"client_secret\":\"{s}\",\"code\":\"{s}\"}}",
            .{api_credentials.client_id, api_credentials.secret, p.code},
        ),
        .refresh_token => |p| try std.fmt.allocPrint(
            alloc,
            "{{\"client_id\":\"{s}\",\"client_secret\":\"{s}\",\"grant_type\":\"refresh_token\",\"refresh_token\":\"{s}\"}}",
            .{api_credentials.client_id, api_credentials.secret, p.refresh_token},
        ),
    };

    defer alloc.free(body);
    request.headers.connection = .omit;
    request.headers.content_type = .{
        .override = web.Mime.application_json.toString(),
    };
    request.extra_headers = &.{
        .{ .name = "Accept", .value = web.Mime.application_json.toString() },
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
        logger.err("Failed to fetch token:\n{s}", .{response_body});
    }

    switch (response.status) {
        .unauthorized => return FetchTokenError.Unauthorized,
        .forbidden => return FetchTokenError.Forbidden,
        .not_found => return FetchTokenError.NotFound,
        else => {},
    }
    if (response.status.class() != .success) {
        return error.Unexpected;
    }

    return try std.json.parseFromSlice(AccessToken, alloc, response_body, .{});
}

pub const User = struct {
    id: i64,
    login: []const u8,
};

// This is used to validate the access token as well.
pub fn fetchUser(alloc: std.mem.Allocator, access_token: []const u8) !std.json.Parsed(User) {
    const tr = tracy.trace(@src());
    defer tr.end();

    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    const uri = try std.Uri.parse(USER_URL);
    var header_buffer: [4096]u8 = undefined;
    var request = try client.open(.GET, uri, .{ .server_header_buffer = &header_buffer });
    defer request.deinit();

    const auth_header = try std.fmt.allocPrint(alloc, "Bearer {s}", .{access_token});
    defer alloc.free(auth_header);
    request.headers.connection = .omit;
    // request.headers.content_type = .{
    //     .override = web.Mime.application_json.toString(),
    // };
    request.headers.authorization = .{ .override = auth_header };
    request.extra_headers = &.{
        .{ .name = "Accept", .value = web.Mime.application_json.toString() },
        .{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" },
    };

    try request.send();
    try request.finish();
    try request.wait();

    var response_body_buffer: [4096]u8 = undefined;
    const size = try request.readAll(&response_body_buffer);
    const response_body = response_body_buffer[0..size];

    const response = request.response;

    if (response.status.class() != .success) {
        logger.warn("Failed to validate token:\n{s}", .{response_body});
        return error.InvalidToken;
    }

    const parsed_user = try std.json.parseFromSlice(
        User,
        alloc,
        response_body,
        .{ .ignore_unknown_fields = true },
    );

    return parsed_user;
}
