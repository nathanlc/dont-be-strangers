const std = @import("std");
const builtin = @import("builtin");
const http = @import("http.zig");
const model = @import("model.zig");
const github = @import("github.zig");
const slack = @import("slack.zig");
const tracy = @import("tracy.zig");
const assert = std.debug.assert;

const PUBLIC_PATH = "resource/public/";
const DEFAULT_URL_LENGTH = 2048;
const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 3000;
const TIDY_PERIOD = 1 * std.time.s_per_hour;
// const TIDY_PERIOD = 1 * std.time.s_per_min;
const NOTIFY_PERIOD = 1 * std.time.s_per_day;
// const NOTIFY_PERIOD = 1 * std.time.s_per_min;

const logger = std.log.scoped(.web);

fn logErr(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        logger.err(fmt, args);
    } else {
        logger.info(fmt, args);
    }
}

pub fn runScratch(_: std.mem.Allocator) !void {}

// // TODO: Return a StringHashMap instead?
// fn parseFormUrlEncoded(alloc: std.mem.Allocator, reader: anytype, comptime max_size: usize) ![]Request.BodyParam {
//     var body_buf: [max_size]u8 = undefined;
//     var body_params = std.ArrayList(Request.BodyParam).init(alloc);
//     errdefer body_params.deinit();
//
//     var offset: usize = 0;
//     var len: usize = 0;
//     var body_param = Request.BodyParam{};
//     // We count the occurences of '=' and '&' to validate that the body is complete.
//     var count_equals: usize = 0;
//     var count_ampersands: usize = 0;
//     while (reader.readByte()) |byte| : (len += 1){
//         body_buf[len] = byte;
//
//         if ('%' == byte) {
//             std.debug.panic("TODO: Need to handle UTF-8 URI decoding!\n", .{});
//         } else if ('=' == byte) {
//             count_equals += 1;
//             if (count_equals != count_ampersands + 1) {
//                 return error.FormUrlEncodedIncorrect;
//             }
//             body_param.key = body_buf[offset..len];
//             offset = len + 1;
//         } else if ('&' == byte) {
//             count_ampersands += 1;
//             if (count_ampersands != count_equals) {
//                 return error.FormUrlEncodedIncorrect;
//             }
//             body_param.value = body_buf[offset..len];
//             try body_params.append(body_param);
//             body_param = Request.BodyParam{};
//             offset = len + 1;
//         }
//
//         if (len == max_size) {
//             return error.StreamTooLong;
//         }
//     } else |err| {
//         return switch (err) {
//             error.EndOfStream => blk: {
//                 if (count_equals != count_ampersands + 1) {
//                     break :blk error.FormUrlEncodedIncorrect;
//                 }
//
//                 body_param.value = body_buf[offset..len];
//                 try body_params.append(body_param);
//                 break :blk body_params.toOwnedSlice();
//             },
//             else => err,
//         };
//     }
// }
//
// test parseFormUrlEncoded {
//     const alloc = std.testing.allocator;
//     const expectEqual = std.testing.expectEqual;
//     const expectEqualStrings = std.testing.expectEqualStrings;
//     const expectError = std.testing.expectError;
//     var tmpDir = std.testing.tmpDir(.{});
//     defer tmpDir.cleanup();
//
//     {
//         const message = "full_name=Bob&frequency_days=14";
//         const file = try tmpDir.dir.createFile("request_body_1.txt", .{ .read = true });
//         defer file.close();
//
//         try file.writeAll(message);
//         try file.seekTo(0);
//
//         const reader = file.reader();
//
//         const body_params = try parseFormUrlEncoded(alloc, reader, 1024);
//         defer alloc.free(body_params);
//
//         try expectEqual(2, body_params.len);
//         const first_param = body_params[0];
//         try expectEqualStrings("full_name", first_param.key);
//         try expectEqualStrings("Bob", first_param.value);
//         const second_param = body_params[1];
//         try expectEqualStrings("frequency_days", second_param.key);
//         try expectEqualStrings("14", second_param.value);
//     }
//
//     {
//         const message = "full_name=Bob&frequ";
//         const file = try tmpDir.dir.createFile("request_body_2.txt", .{ .read = true });
//         defer file.close();
//
//         try file.writeAll(message);
//         try file.seekTo(0);
//
//         const reader = file.reader();
//
//         try expectError(error.FormUrlEncodedIncorrect, parseFormUrlEncoded(alloc, reader, 1024));
//     }
//
//     {
//         const message = "full_name=Bob_frequency_days=24";
//         const file = try tmpDir.dir.createFile("request_body_3.txt", .{ .read = true });
//         defer file.close();
//
//         try file.writeAll(message);
//         try file.seekTo(0);
//
//         const reader = file.reader();
//
//         try expectError(error.FormUrlEncodedIncorrect, parseFormUrlEncoded(alloc, reader, 1024));
//     }
//
//     {
//         const message = "full_name=Bob&frequency_days&24";
//         const file = try tmpDir.dir.createFile("request_body_4.txt", .{ .read = true });
//         defer file.close();
//
//         try file.writeAll(message);
//         try file.seekTo(0);
//
//         const reader = file.reader();
//
//         try expectError(error.FormUrlEncodedIncorrect, parseFormUrlEncoded(alloc, reader, 1024));
//     }
// }

const Query = struct {
    allocator: std.mem.Allocator,
    // The query is percent encoded.
    str: []const u8,
    map: std.StringHashMap([]const u8),

    fn fill_map(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8), query_str: []const u8) !void {
        errdefer free_map(allocator, map);

        var part_iter = std.mem.splitScalar(u8, query_str, '&');
        while (part_iter.next()) |item| {
            if (std.mem.eql(u8, "", item)) {
                continue;
            }
            var item_itr = std.mem.splitScalar(u8, item, '=');
            // TODO: key and value (especially) should be url decoded.
            const item_key = item_itr.next();
            const item_value = item_itr.next();
            if (item_key != null and item_value != null) {
                const key = try allocator.alloc(u8, item_key.?.len);
                errdefer allocator.free(key);
                @memcpy(key, item_key.?);
                const value = try allocator.alloc(u8, item_value.?.len);
                errdefer allocator.free(value);
                @memcpy(value, item_value.?);
                try map.put(key, value);
            } else {
                logger.warn("Query item incomplete: {s}", .{item});
            }
        }
    }

    fn free_map(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8)) void {
        var entry_iter = map.iterator();
        while (entry_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    pub fn init(allocator: std.mem.Allocator, query_str: []const u8) !Query {
        var map = std.StringHashMap([]const u8).init(allocator);
        try fill_map(allocator, &map, query_str);

        return .{
            .allocator = allocator,
            .str = query_str,
            .map = map,
        };
    }

    pub fn get(self: *Query, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn deinit(self: *Query) void {
        free_map(self.allocator, &self.map);
    }
};

test Query {
    const alloc = std.testing.allocator;
    const expect = std.testing.expect;

    var query = try Query.init(alloc, "bob=cat&foo=bar123");
    defer query.deinit();

    try expect(std.mem.eql(u8, "cat", query.get("bob").?));
    try expect(std.mem.eql(u8, "bar123", query.get("foo").?));
}

const BodyTag = enum {
    comp,
    alloc,
};

const Body = union(BodyTag) {
    comp: []const u8,
    alloc: []const u8,

    pub fn bodyStr(self: Body) []const u8 {
        return switch (self) {
            .comp, .alloc => |str| str,
        };
    }

    pub fn free(self: Body, alloc: std.mem.Allocator) void {
        switch (self) {
            .comp => |_| {},
            .alloc => |body| alloc.free(body),
        }
    }
};

test Body {
    const alloc = std.testing.allocator;
    const expect = std.testing.expect;

    const comp_body = Body{ .comp = "Comp known body" };
    try expect(std.mem.eql(u8, "Comp known body", comp_body.bodyStr()));

    const body_str = try std.fmt.allocPrint(alloc, "{s}", .{"Allocated body"});
    const alloc_body = Body{ .alloc = body_str };
    defer alloc.free(body_str);
    try expect(std.mem.eql(u8, "Allocated body", alloc_body.bodyStr()));
}

pub const Response = struct {
    body: Body,
    content_type: http.Mime,
    status: std.http.Status = .ok,

    pub fn log(self: *const Response) void {
        // Include \n as it should be the last thing logged for a request.
        logger.info("=> {d} {s}\n", .{
            @intFromEnum(self.status),
            if (self.status.phrase()) |phrase| phrase else "",
        });
    }
};

const Router = struct {
    alloc: std.mem.Allocator,
    path_variables: std.ArrayList([]const u8),

    pub fn init(alloc: std.mem.Allocator) Router {
        var path_variables = std.ArrayList([]const u8).init(alloc);
        _ = &path_variables;

        return .{
            .alloc = alloc,
            .path_variables = path_variables,
        };
    }

    // The complexity of this parsing is not necessary for now.
    // Just splitting path end self.path by '/' and compare the parts would have been simpler.
    // TODO: compare performance of both.
    // This method both checks the path of the endpoint AND populates self.path_variables.
    fn pathMatches(self: *Router, path: []const u8, endpoint_path: []const u8) !bool {
        const ParseStatus = enum {
            InsideBracket,
            OutsideBracket,
        };

        var path_stream = std.io.fixedBufferStream(path);
        const path_reader = path_stream.reader();

        var endpoint_path_index: u32 = 0;
        var parse_status: ParseStatus = .OutsideBracket;
        var path_var_index: u8 = 0;
        var path_var_start_index: u32 = 0;
        var i: u32 = 0;
        while (path_reader.readByte()) |byte| : (i += 1) {
            if (parse_status == .InsideBracket and byte == '/') {
                endpoint_path_index += 2;
                parse_status = .OutsideBracket;
                try self.path_variables.append(path[path_var_start_index..i]);
                path_var_index += 1;
            }

            if (endpoint_path_index >= endpoint_path.len) {
                return false;
            }
            const endpoint_path_byte = endpoint_path[endpoint_path_index];

            if (endpoint_path_byte == '{') {
                assert(endpoint_path_index + 2 < endpoint_path.len);
                assert(endpoint_path[endpoint_path_index + 1] == 's');
                assert(endpoint_path[endpoint_path_index + 2] == '}');
                parse_status = .InsideBracket;
                path_var_start_index = i;
                endpoint_path_index += 1;
            }

            if (parse_status == .OutsideBracket and endpoint_path_byte != byte) {
                return false;
            }

            if (parse_status == .OutsideBracket) {
                endpoint_path_index += 1;
            }
        } else |err| switch (err) {
            // Nothing to do, just listing all the possible errors to be explicit.
            error.EndOfStream => {
                if (parse_status == .InsideBracket) {
                    try self.path_variables.append(path[path_var_start_index..i]);
                }
            },
        }

        // The "path" was read fully but there was more to endpoint_path.
        if (parse_status == .OutsideBracket and endpoint_path_index < endpoint_path.len) {
            return false;
        }

        return true;
    }

    pub fn dispatch(self: *Router, method: std.http.Method, path: []const u8) !DispatchResult {
        for (endpoints) |endpoint| {
            switch (endpoint) {
                .endpoint_without_path_variables => |e| {
                    if (e.method == method and std.mem.eql(u8, e.path, path)) {
                        return DispatchResult{
                            .endpoint = endpoint,
                            .path_variables = try self.path_variables.toOwnedSlice(),
                        };
                    }
                },
                .endpoint_with_path_variables => |e| {
                    if (e.method == method and try self.pathMatches(path, e.path)) {
                        return DispatchResult{
                            .endpoint = endpoint,
                            .path_variables = try self.path_variables.toOwnedSlice(),
                        };
                    }
                },
                .endpoint_public_resource => unreachable,
            }
        }

        if (.GET == method) {
            const static_endpoints = try getStaticEndpoints(self.alloc);
            defer {
                for (static_endpoints) |endpoint| {
                    endpoint.free(self.alloc);
                }
                self.alloc.free(static_endpoints);
            }
            for (static_endpoints) |endpoint| {
                if (try self.pathMatches(path, endpoint.path)) {
                    return DispatchResult{
                        .endpoint = .{ .endpoint_public_resource = endpoint },
                        .path_variables = try self.path_variables.toOwnedSlice(),
                    };
                }
            }
        }

        return DispatchResult{
            .endpoint = .{ .endpoint_without_path_variables = endpointNotFound },
            .path_variables = try self.path_variables.toOwnedSlice(),
        };
    }
};

test Router {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;

    {
        var router = Router.init(alloc);
        const dispatch_result = try router.dispatch(.GET, "/health");
        defer dispatch_result.free(alloc);
        try expectEqualStrings("endpoint_without_path_variables", @tagName(dispatch_result.endpoint));
        try expectEqualStrings("/health", dispatch_result.endpoint.getPath());
    }

    {
        var router = Router.init(alloc);
        const dispatch_result = try router.dispatch(.PATCH, "/api/v0/user/contacts/some_contact_id");
        defer dispatch_result.free(alloc);
        try expectEqualStrings("endpoint_with_path_variables", @tagName(dispatch_result.endpoint));
        try expectEqualStrings("/api/v0/user/contacts/{s}", dispatch_result.endpoint.getPath());
        try expectEqual(1, dispatch_result.path_variables.len);
        try expectEqualStrings("some_contact_id", dispatch_result.path_variables[0]);
    }

    {
        var router = Router.init(alloc);
        const dispatch_result = try router.dispatch(.GET, "/api/v0/user/contacts");
        defer dispatch_result.free(alloc);
        try expectEqualStrings("endpoint_without_path_variables", @tagName(dispatch_result.endpoint));
        try expectEqualStrings("/api/v0/user/contacts", dispatch_result.endpoint.getPath());
    }

    {
        var router = Router.init(alloc);
        const dispatch_result = try router.dispatch(.POST, "/api/v0/user/contacts");
        defer dispatch_result.free(alloc);
        try expectEqualStrings("endpoint_without_path_variables", @tagName(dispatch_result.endpoint));
        try expectEqualStrings("/api/v0/user/contacts", dispatch_result.endpoint.getPath());
    }
}

const DispatchResult = struct {
    endpoint: Endpoint,
    path_variables: [][]const u8,

    pub fn free(self: *const DispatchResult, alloc: std.mem.Allocator) void {
        alloc.free(self.path_variables);
    }
};

const EndpointTag = enum {
    endpoint_without_path_variables,
    endpoint_with_path_variables,
    endpoint_public_resource,
};
const Endpoint = union(EndpointTag) {
    endpoint_without_path_variables: EndpointWithoutPathVariables,
    endpoint_with_path_variables: EndpointWithPathVariables,
    endpoint_public_resource: EndpointPublicResource,

    pub fn getPath(self: Endpoint) []const u8 {
        return switch (self) {
            .endpoint_without_path_variables => |e| e.path,
            .endpoint_with_path_variables => |e| e.path,
            .endpoint_public_resource => |e| e.path,
        };
    }
};

const EndpointWithoutPathVariables = struct {
    method: std.http.Method,
    path: []const u8,
    respond: *const fn (*Request) anyerror!Response,
};
const EndpointWithPathVariables = struct {
    method: std.http.Method,
    path: []const u8,
    respond: *const fn (*Request, [][]const u8) anyerror!Response,
};
const EndpointPublicResource = struct {
    // method must be .GET.
    path: []const u8,

    pub fn free(self: *const EndpointPublicResource, alloc: std.mem.Allocator) void {
        alloc.free(self.path);
    }
};

fn respondHealth(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "Hello!" },
        .content_type = http.Mime.text_plain,
    };
}

fn respondGithubLoginParams(request: *Request) !Response {
    const state = try request.app.nonce_map.new();
    const body = try std.fmt.allocPrint(
        request.arena,
        "{{\"github_client_id\":\"{s}\",\"state\":\"{s}\"}}",
        .{request.app.github_creds.client_id, state},
    );
    errdefer request.arena.free(body);

    return Response{
        .body = Body{ .alloc = body },
        .content_type = http.Mime.application_json,
    };
}

// test respondGithubLoginParams {
//     const allocator = std.testing.allocator;
//
//     try model.Sqlite.setupTest();
//
//     var app = try App.init(.{
//         .alloc = allocator,
//         .env = App.Env.testing,
//         .github_creds = github.ApiCredentials.testing(),
//     });
//     defer app.deinit();
//
//     const ip = "127.0.0.1";
//     const port = 3011;
//
//     const server_thread = try std.Thread.spawn(.{}, (struct {
//         fn apply(app_ptr: *App) !void {
//             const address = try std.net.Address.resolveIp(ip, port);
//             var net_server = try address.listen(.{ .reuse_address = true });
//             defer net_server.deinit();
//
//             const connection = try net_server.accept();
//             defer connection.stream.close();
//
//             var server_buffer: [2048]u8 = undefined;
//             var server = std.http.Server.init(connection, &server_buffer);
//             var http_request = try server.receiveHead();
//             var request = try Request.init(allocator, app_ptr, &http_request);
//             defer request.deinit();
//
//             const response = try request.respond();
//
//             const body_str = response.body.bodyStr();
//             try std.testing.expectEqual(87, body_str.len);
//             try std.testing.expectEqual(http.Mime.application_json, response.content_type);
//             try std.testing.expectEqual(.ok, response.status);
//         }
//     }).apply, .{&app});
//
//     const request_bytes =
//         "GET /auth/github/login_params HTTP/1.1\r\n" ++
//         "Accept: */*\r\n" ++
//         "\r\n";
//
//     // Pause for 0.01s otherwise connection is refused in github actions...
//     std.posix.nanosleep(0, 10_000_000);
//
//     const stream = try std.net.tcpConnectToHost(allocator, ip, port);
//     defer stream.close();
//     _ = try stream.writeAll(request_bytes[0..]);
//
//     server_thread.join();
// }

fn respondGithubCallback(request: *Request) !Response {
    var query = try request.getQuery();
    defer query.deinit();

    _ = query.get("code") orelse {
        return Response{
            .body = Body{ .comp = "Missing expected query param `code`" },
            .content_type = http.Mime.text_plain,
            .status = .bad_request,
        };
    };

    return respondIndex(request);
}

pub const GrantType = enum {
    authorization_code,
    refresh_token,
};

fn handleFetchedToken(request: *Request, parsed_token_or_error: anyerror!std.json.Parsed(github.AccessToken)) !Response {
    if (parsed_token_or_error) |parsed_token| {
        defer parsed_token.deinit();
        const token = parsed_token.value;

        const parsed_user = try github.fetchUser(request.arena, token.access_token);
        defer parsed_user.deinit();

        const external_user_id = try std.fmt.allocPrint(request.arena, "{d}", .{parsed_user.value.id});
        defer request.arena.free(external_user_id);
        const authenticator = model.Authenticator.github;
        try request.app.sqlite.insertOrIgnoreUser(request.arena, external_user_id, parsed_user.value.login, authenticator);
        const user = try request.app.sqlite.selectUserByExternalId(request.arena, external_user_id, authenticator);
        defer user.deinit();
        try request.app.token_cache.put(token.access_token, token.expires_in, user.id.?);

        const body = try std.json.stringifyAlloc(request.arena, token, .{});
        errdefer request.arena.free(body);

        return Response{
            .body = .{ .alloc = body },
            .content_type = http.Mime.application_json,
        };
    } else |err| {
        const err_body = Body{ .comp = "{\"error\":\"Failed to fetch token.\"}" };
        const content_type = http.Mime.application_json;
        switch (err) {
            github.FetchTokenError.Unauthorized => return Response{
                .body = err_body,
                .content_type = content_type,
                .status = .unauthorized,
            },
            github.FetchTokenError.Forbidden => return Response{
                .body = err_body,
                .content_type = content_type,
                .status = .forbidden,
            },
            github.FetchTokenError.NotFound => return Response{
                .body = err_body,
                .content_type = content_type,
                .status = .not_found,
            },
            else => return err,
        }
    }
}

fn respondGithubAccessToken(request: *Request) !Response {
    var query = try request.getQuery();
    defer query.deinit();

    const code = query.get("code") orelse {
        return Response{
            .body = Body{ .comp = "Missing expected query param `code`" },
            .content_type = http.Mime.text_plain,
            .status = .bad_request,
        };
    };

    const state = query.get("state") orelse {
        return Response{
            .body = Body{ .comp = "Missing expected query param `state`" },
            .content_type = http.Mime.text_plain,
            .status = .bad_request,
        };
    };

    const state_valid = request.app.nonce_map.remove(state);
    if (!state_valid) {
        return Response{
            .body = Body{ .comp = "Invalid state query param" },
            .content_type = http.Mime.text_plain,
            .status = .forbidden,
        };
    }

    const payload: github.FetchTokenPayload = .{ .authorization_code = .{ .code = code } };

    return handleFetchedToken(request, github.fetchToken(request.arena, request.app.github_creds, payload));
}

fn respondGithubRefreshToken(request: *Request) !Response {
    var query = try request.getQuery();
    defer query.deinit();

    const refresh_token = query.get("refresh_token") orelse {
        return Response{
            .body = .{ .comp = "Missing expected query param `refresh_token`." },
            .content_type = http.Mime.text_plain,
            .status = .bad_request,
        };
    };

    const payload: github.FetchTokenPayload = .{ .refresh_token = .{
        .refresh_token = refresh_token,
    } };

    return handleFetchedToken(request, github.fetchToken(request.arena, request.app.github_creds, payload));
}

const ContactView = struct {
    id: i64,
    full_name: []const u8,
    frequency_days: u16,
    due_at: u32,

    pub fn fromContact(contact: model.Contact) ContactView {
        return ContactView{
            .id = contact.id.?,
            .full_name = contact.full_name,
            .frequency_days = contact.frequency_days,
            .due_at = contact.due_at,
        };
    }
};

test "ContactView.fromContact" {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;

    var contact = model.Contact.init(alloc);
    defer contact.deinit();
    contact.id = 1;
    var full_name = std.ArrayList(u8).init(alloc);
    try full_name.appendSlice("john doe");
    contact.full_name = try full_name.toOwnedSlice();
    contact.frequency_days = 30;
    contact.due_at = 1737400035;

    const contact_view = ContactView.fromContact(contact);
    try expectEqual(1, contact_view.id);
    try expectEqual(30, contact_view.frequency_days);
    try std.testing.expectEqualStrings("john doe", contact_view.full_name);
    try expectEqual(1737400035, contact_view.due_at);
}

const ContactViewList = struct {
    alloc: std.mem.Allocator,
    contacts: []ContactView,

    pub fn fromContactList(alloc: std.mem.Allocator, contact_list: model.ContactList) !ContactViewList {
        const tr = tracy.trace(@src());
        defer tr.end();

        var contact_view_list = std.ArrayList(ContactView).init(alloc);
        var entry_iter = contact_list.map.iterator();
        while (entry_iter.next()) |entry| {
            const contact_view = ContactView.fromContact(entry.value_ptr.*);
            try contact_view_list.append(contact_view);
        }

        return ContactViewList{
            .alloc = alloc,
            .contacts = try contact_view_list.toOwnedSlice(),
        };
    }

    pub fn deinit(self: *const ContactViewList) void {
        self.alloc.free(self.contacts);
    }

    pub fn jsonStringify(self: *const ContactViewList, jw: anytype) !void {
        try jw.beginArray();
        for (self.contacts) |contact| {
            try jw.write(contact);
        }
        try jw.endArray();
    }
};

// test "ContactViewList.fromContactList" {
//     const alloc = std.testing.allocator;
//     const expectEqual = std.testing.expectEqual;
//
//     var contact_list = try model.ContactList.fromCsvFile(alloc, "test_db", true);
//     defer contact_list.deinit();
//
//     const contact_view_list = try ContactViewList.fromContactList(alloc, contact_list);
//     defer contact_view_list.deinit();
//     // contact_list uses a hash map internally. The order of the contact view list is
//     // not guaranteed. Below is a hacky way to find the contact view to test...
//     const first_contact_view = contact_view_list.contacts[0];
//     const second_contact_view = contact_view_list.contacts[1];
//
//     try expectEqual(14, contact_view.frequency_days);
//     try std.testing.expectEqualStrings("jane doe", contact_view.full_name);
//     try expectEqual(1737400036, contact_view.due_at);
// }

fn respondApiV0UserContacts(request: *Request) !Response {
    const tr = tracy.trace(@src());
    defer tr.end();

    const user_id = request.authenticateViaToken() catch |err| switch (err) {
        error.UnauthenticatedRequest => {
            return try respondUnauthorized(request);
        },
    };

    var contact_list = try request.app.sqlite.selectContactsByUser(request.arena, user_id);
    defer contact_list.deinit();

    const contact_view_list = try ContactViewList.fromContactList(request.arena, contact_list);
    defer contact_view_list.deinit();

    const body = try std.json.stringifyAlloc(
        request.arena,
        contact_view_list,
        .{},
    );
    errdefer request.arena.free(body);

    return Response{
        .body = Body{ .alloc = body },
        .content_type = http.Mime.text_plain,
    };
}

fn respondApiV0UserContactsPost(request: *Request) !Response {
    const ContactRequest = struct {
        full_name: []u8,
        frequency_days: u16,
    };

    const user_id = request.authenticateViaToken() catch |err| switch (err) {
        error.UnauthenticatedRequest => {
            return try respondUnauthorized(request);
        },
    };

    const parsed_contact = std.json.parseFromSlice(ContactRequest, request.arena, request.body, .{}) catch |err| switch (err) {
        error.UnknownField => return respondBadRequest(request),
        else => return err,
    };
    defer parsed_contact.deinit();
    const parsed_contact_value = parsed_contact.value;

    var contact = model.Contact.init(request.arena);
    defer contact.deinit();
    contact.user_id = user_id;
    contact.full_name = parsed_contact_value.full_name;
    contact.frequency_days = parsed_contact_value.frequency_days;
    contact.setDueAt(null);

    request.app.sqlite.insertContact(request.arena, contact) catch |err| {
        logger.warn("Failed to create contact: {!}", .{err});
        return respondBadRequest(request);
    };

    return Response{
        .body = Body{ .comp = "" },
        .content_type = http.Mime.text_plain,
        .status = .created,
    };
}

fn respondApiV0UserContactsPatch(request: *Request, path_variables: [][]const u8) !Response {
    assert(1 == path_variables.len);

    const contact_id_str = path_variables[0];
    const contact_id = try std.fmt.parseInt(i64, contact_id_str, 10);

    const user_id = request.authenticateViaToken() catch |err| switch (err) {
        error.UnauthenticatedRequest => {
            return try respondUnauthorized(request);
        },
    };

    var contact_list = try request.app.sqlite.selectContactsByUser(request.arena, user_id);
    defer contact_list.deinit();

    return if (contact_list.getContactPtr(contact_id)) |contact_ptr| blk: {
        contact_ptr.setDueAt(null);
        try request.app.sqlite.updateContact(request.arena, contact_ptr.*);

        const contact_view = ContactView.fromContact(contact_ptr.*);
        const body = try std.json.stringifyAlloc(request.arena, contact_view, .{});
        errdefer request.arena.free(body);

        break :blk Response{
            .body = Body{ .alloc = body },
            .content_type = http.Mime.text_plain,
        };
    } else respondNotFound(request);
}

fn readPublicFile(path: []const u8) ![]u8 {
    var public_dir = try std.fs.cwd().openDir(PUBLIC_PATH, .{});
    defer public_dir.close();
    const file_path = if (std.mem.indexOf(u8, path, "/")) |index| blk: {
        break :blk if (index == 0) path[1..] else path;
    } else blk: {
        break :blk path;
    };
    var file = try public_dir.openFile(file_path, .{});
    defer file.close();
    // TODO: Probably should stream that...
    var buffer: [32768]u8 = undefined;
    const count_read = try file.readAll(&buffer);

    return buffer[0..count_read];
}

test "readPublicFile when file exists" {
    const test_public_file_content = try readPublicFile("./test.txt");
    const expected = "test\n";

    try std.testing.expect(std.mem.eql(u8, expected, test_public_file_content));
}

test "readPublicFile when file does not exist" {
    _ = readPublicFile("./does_not_exist.bob") catch |err| {
        try std.testing.expect(std.mem.eql(u8, "FileNotFound", @errorName(err)));
    };
}

fn respondServeFile(request: *Request) !Response {
    const path = request.getPath();
    const body: []const u8 = readPublicFile(path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                logger.warn("Static file not found: {!}", .{err});
                return respondNotFound(request);
            },
            else => return err,
        }
    };

    return Response{
        .body = Body{ .comp = body },
        .content_type = http.Mime.fromString(path) catch http.Mime.text_plain,
    };
}

fn respondIndex(_: *Request) !Response {
    const path = "/index.html";
    const body: []const u8 = try readPublicFile(path);

    return Response{
        .body = Body{ .comp = body },
        .content_type = http.Mime.fromString(path) catch http.Mime.text_plain,
    };
}

fn respondTestingError(_: *Request) !Response {
    return error.TestErrorTriggered;
}

// fn respondStopServer(_: *Request) !Response {
//     return Response{
//         .body = Body{ .comp = "Stop server" },
//         .content_type = Mime.text_plain,
//     };
// }

test respondTestingError {
    try testResponse("GET", "/testing/error", "500 WHOOPSIE", http.Mime.text_plain, .internal_server_error);
}

fn respondUnauthorized(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "{\"error\":\"Unauthorized\"}" },
        .content_type = http.Mime.application_json,
        .status = .unauthorized,
    };
}

fn respondOk(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "200 OK" },
        .content_type = http.Mime.text_plain,
    };
}

fn respondNotFound(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "404 NOT FOUND" },
        .content_type = http.Mime.text_plain,
        .status = .not_found,
    };
}

fn respondInternalServerError(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "500 WHOOPSIE" },
        .content_type = http.Mime.text_plain,
        .status = .internal_server_error,
    };
}

fn respondBadRequest(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "400 Bad request... maybe..." },
        .content_type = http.Mime.text_plain,
        .status = .bad_request,
    };
}

fn testResponse(comptime method: []const u8, comptime path: []const u8, expected_body: []const u8, expected_mime: http.Mime, expected_status: std.http.Status) !void {
    const allocator = std.testing.allocator;

    try model.Sqlite.setupTest();

    var app = try App.init(.{
        .alloc = allocator,
        .env = App.Env.testing,
        .github_creds = github.ApiCredentials.testing(),
    });
    defer app.deinit();

    const ip = "127.0.0.1";
    const port = 3010;

    const server_thread = try std.Thread.spawn(.{}, (struct {
        fn apply(app_ptr: *App, e_body: []const u8, e_mime: http.Mime, e_status: std.http.Status) !void {
            const address = try std.net.Address.resolveIp(ip, port);
            var net_server = try address.listen(.{ .reuse_address = true });
            defer net_server.deinit();

            const connection = try net_server.accept();
            defer connection.stream.close();

            var server_buffer: [2048]u8 = undefined;
            var server = std.http.Server.init(connection, &server_buffer);
            var http_request = try server.receiveHead();
            var request = try Request.init(allocator, app_ptr, &http_request);
            defer request.deinit();

            const response = try request.respond();

            try std.testing.expectEqualStrings(e_body, response.body.bodyStr());
            try std.testing.expectEqual(e_mime, response.content_type);
            try std.testing.expectEqual(e_status, response.status);
        }
    }).apply, .{ &app, expected_body, expected_mime, expected_status });

    const request_bytes =
        method ++ " " ++ path ++ " HTTP/1.1\r\n" ++
        "Accept: */*\r\n" ++
        "\r\n";

    // Pause for 0.01s otherwise connection is refused in github actions...
    std.posix.nanosleep(0, 10_000_000);

    const stream = try std.net.tcpConnectToHost(allocator, ip, port);
    defer stream.close();
    _ = try stream.writeAll(request_bytes[0..]);

    server_thread.join();
}

test respondHealth {
    try testResponse("GET", "/health", "Hello!", http.Mime.text_plain, .ok);
}

test respondServeFile {
    try testResponse("GET", "/test.txt", "test\n", http.Mime.text_plain, .ok);
}

test respondNotFound {
    try testResponse("GET", "/not_existing_path", "404 NOT FOUND", http.Mime.text_plain, .not_found);
}

const endpointNotFound = EndpointWithoutPathVariables{
    // Path and method don't matter in this case.
    .path = "/404",
    .method = std.http.Method.GET,
    .respond = &respondNotFound,
};

const endpointInternalServerError = EndpointWithoutPathVariables{
    // Path and method don't matter in this case.
    .path = "/500",
    .method = std.http.Method.GET,
    .respond = &respondInternalServerError,
};

const endpoints = [_]Endpoint{
    // Endpoint{ .path = "/stop_server", .method = std.http.Method.GET, .respond = &respondStopServer },
    // Test routes
    .{ .endpoint_without_path_variables = .{ .path = "/testing/error", .method = std.http.Method.GET, .respond = &respondTestingError } },
    .{ .endpoint_without_path_variables = .{ .path = "/health", .method = std.http.Method.GET, .respond = &respondHealth } },
    // Web routes
    .{ .endpoint_without_path_variables = .{ .path = "/", .method = std.http.Method.GET, .respond = &respondIndex } },
    .{ .endpoint_without_path_variables = .{ .path = "/user/contacts", .method = std.http.Method.GET, .respond = &respondIndex } },
    .{ .endpoint_without_path_variables = .{ .path = "/auth/github/login_params", .method = std.http.Method.GET, .respond = &respondGithubLoginParams } },
    .{ .endpoint_without_path_variables = .{ .path = "/auth/github/callback", .method = std.http.Method.GET, .respond = &respondGithubCallback } },
    .{ .endpoint_without_path_variables = .{ .path = "/auth/github/access_token", .method = std.http.Method.GET, .respond = &respondGithubAccessToken } },
    .{ .endpoint_without_path_variables = .{ .path = "/auth/github/refresh_token", .method = std.http.Method.GET, .respond = &respondGithubRefreshToken } },
    // API routes
    .{ .endpoint_without_path_variables = .{ .path = "/api/v0/user/contacts", .method = std.http.Method.GET, .respond = &respondApiV0UserContacts } },
    .{ .endpoint_without_path_variables = .{ .path = "/api/v0/user/contacts", .method = std.http.Method.POST, .respond = &respondApiV0UserContactsPost } },
    .{ .endpoint_with_path_variables = .{ .path = "/api/v0/user/contacts/{s}", .method = std.http.Method.PATCH, .respond = &respondApiV0UserContactsPatch } },
};

fn getStaticEndpoints(allocator: std.mem.Allocator) ![]const EndpointPublicResource {
    var endpoints_list = std.ArrayList(EndpointPublicResource).init(allocator);
    defer endpoints_list.deinit();

    var public_dir = try std.fs.cwd().openDir(PUBLIC_PATH, .{ .iterate = true });
    defer public_dir.close();
    var walker = try public_dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != std.fs.File.Kind.file) {
            continue;
        }
        if (std.mem.indexOf(u8, entry.path, ".DS_Store")) |_| {
            continue;
        }

        const path = try allocator.alloc(u8, entry.path.len + 1);
        errdefer allocator.free(path);
        path[0] = '/';
        @memcpy(path[1..], entry.path);
        const endpoint = EndpointPublicResource{ .path = path };
        try endpoints_list.append(endpoint);
    }

    return try endpoints_list.toOwnedSlice();
}

test getStaticEndpoints {
    const allocator = std.testing.allocator;

    const static_endpoints = try getStaticEndpoints(allocator);
    defer {
        for (static_endpoints) |endpoint| {
            endpoint.free(allocator);
        }
        allocator.free(static_endpoints);
    }

    var contains_test_text = false;
    for (static_endpoints) |endpoint| {
        if (std.mem.eql(u8, "/test.txt", endpoint.path)) {
            contains_test_text = true;
        }
    }
    try std.testing.expect(contains_test_text);
}

pub const Request = struct {
    arena: std.mem.Allocator,
    app: *App,
    inner: *std.http.Server.Request,
    url: []const u8,
    uri: std.Uri,
    body: []const u8,
    // body_params: []BodyParam = undefined,

    // pub const BodyParam = struct {
    //     key: []const u8 = undefined,
    //     value: []const u8 = undefined,
    // };

    pub fn init(arena: std.mem.Allocator, app: *App, request: *std.http.Server.Request) !Request {
        // TODO: figure out how to get the full URL. Or does it actually matter?
        const url = try std.fmt.allocPrint(
            arena,
            "http://localhost{s}",
            .{request.head.target},
        );
        errdefer arena.free(url);
        const uri = try std.Uri.parse(url);

        const reader = try request.reader();

        return .{
            .arena = arena,
            .app = app,
            .inner = request,
            .url = url,
            .uri = uri,
            .body = try reader.readAllAlloc(arena, 8192),
        };
    }

    // No need to deinit, self should have been initiated with an arena.
    pub fn deinit(self: *Request) void {
        self.arena.free(self.url);
        self.arena.free(self.body);
        // self.arena.free(self.body_params);
    }

    fn getMethod(self: *Request) std.http.Method {
        return self.inner.head.method;
    }

    fn getMethodString(self: *Request) []const u8 {
        const Method = std.http.Method;

        return switch (self.inner.head.method) {
            Method.GET => "GET",
            Method.HEAD => "HEAD",
            Method.POST => "POST",
            Method.PUT => "PUT",
            Method.DELETE => "DELETE",
            Method.CONNECT => "CONNECT",
            Method.OPTIONS => "OPTIONS",
            Method.TRACE => "TRACE",
            Method.PATCH => "PATCH",
            else => "?",
        };
    }

    fn getPath(self: *Request) []const u8 {
        return self.uri.path.percent_encoded;
    }

    fn getQuery(self: *Request) !Query {
        const tr = tracy.trace(@src());
        defer tr.end();

        const query_str = if (self.uri.query) |query| query.percent_encoded else "";

        return Query.init(self.arena, query_str);
    }

    fn log(self: *Request) !void {
        logger.info("{s}: {s}\n  Path:   {s}\n  Query: {s}", .{
            self.getMethodString(),
            self.url,
            try self.uri.path.toRawMaybeAlloc(self.arena),
            if (self.uri.query) |query| try query.toRawMaybeAlloc(self.arena) else "",
        });
    }

    fn handleRespondError(request: *Request, err: anyerror) Response {
        logErr("Error while generating response: {!}", .{err});
        const internal_server_error_response = respondInternalServerError(request) catch unreachable;
        return internal_server_error_response;
    }

    // pub fn formUrlEncoded(self: *Request, comptime max_size: usize) ![]BodyParam {
    //     // TODO: Set an upper bound for `max_size` the whole web "app"?
    //
    //     const reader = try self.inner.reader();
    //
    //     return parseFormUrlEncoded(self.arena, reader, max_size);
    // }

    pub fn respond(self: *Request) !Response {
        const tr = tracy.trace(@src());
        defer tr.end();

        try self.log();

        var router = Router.init(self.arena);
        const dispatch_result = router.dispatch(self.getMethod(), self.getPath()) catch |err| blk: {
            logErr("Error while routing: {!}", .{err});
            break :blk DispatchResult{ .endpoint = .{ .endpoint_without_path_variables = endpointInternalServerError }, .path_variables = &.{} };
        };
        defer dispatch_result.free(self.arena);
        const response = switch (dispatch_result.endpoint) {
            .endpoint_without_path_variables => |e| e.respond(self) catch |err| handleRespondError(self, err),
            .endpoint_with_path_variables => |e| e.respond(self, dispatch_result.path_variables) catch |err| handleRespondError(self, err),
            .endpoint_public_resource => |_| respondServeFile(self) catch |err| handleRespondError(self, err),
        };
        defer response.body.free(self.arena);

        // TODO: Look into respondStreaming if need for manipulating the response arises. And transfer-encoding `chunked`?

        response.log();

        const content_type = std.http.Header{ .name = "Content-Type", .value = response.content_type.toString() };

        try self.inner.respond(response.body.bodyStr(), .{
            .status = response.status,
            .extra_headers = &.{
                content_type,
                .{ .name = "Connection", .value = "Close" },
            },
        });

        // TODO: Returning Response for now is to make testing of responses easier. It's a hack.
        return response;
    }

    // Currently only uses the token cache which is in-memory only. So tokens are "invalidated" if the server restarts.
    pub fn authenticateViaToken(self: *Request) !i64 {
        const tr = tracy.trace(@src());
        defer tr.end();

        var header_iter = self.inner.iterateHeaders();
        var auth_header_value: []const u8 = undefined;
        while (header_iter.next()) |header| {
            if (std.mem.eql(u8, "authorization", header.name) or (std.mem.eql(u8, "Authorization", header.name))) {
                auth_header_value = header.value;
                break;
            }
        } else {
            return error.UnauthenticatedRequest;
        }

        const bearer_prefix = "Bearer ".len;
        const access_token = auth_header_value[bearer_prefix..];

        if (self.app.token_cache.get(access_token)) |cached_token| {
            if (cached_token.expired()) {
                _ = self.app.token_cache.remove(cached_token.token);
                return error.UnauthenticatedRequest;
            } else {
                return cached_token.user_id;
            }
        } else {
            return error.UnauthenticatedRequest;
        }
    }
};

const NonceMap = struct {
    alloc: std.mem.Allocator,
    // This should be a secure pseudo-random number generator.
    rand: std.Random,
    // Nonce list. Used for instance for respondGithubLoginParams.
    // The int represents the created_at of the nonce in seconds.
    map: std.StringHashMap(u32),

    pub fn init(alloc: std.mem.Allocator) NonceMap {
        var map = std.StringHashMap(u32).init(alloc);
        _ = &map;

        return .{
            .alloc = alloc,
            .rand = std.crypto.random,
            .map = map,
        };
    }

    pub fn deinit(self: *NonceMap) void {
        var entry_iter = self.map.iterator();
        while (entry_iter.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
        }
        self.map.deinit();
    }

    pub fn new(self: *NonceMap) ![]const u8 {
        const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        const nonce_len = 32;
        var buf: [nonce_len]u8 = undefined;
        for (0..nonce_len) |i| {
            const random_int = self.rand.uintLessThan(u8, chars.len);
            buf[i] = chars[random_int];
        }
        const nonce = try self.alloc.alloc(u8, buf.len);
        errdefer self.alloc.free(nonce);
        @memcpy(nonce, &buf);

        const now_seconds = std.time.timestamp();
        assert(now_seconds > 0);
        try self.map.put(nonce, @intCast(now_seconds));

        return nonce;
    }

    pub fn remove(self: *NonceMap, nonce: []const u8) bool {
        return if (self.map.getKey(nonce)) |key| blk: {
            const deleted = self.map.remove(key);
            self.alloc.free(key);
            break :blk deleted;
        } else false;
    }

    pub fn removeExpired(self: *NonceMap) u16 {
        const now_seconds = std.time.timestamp();
        var removed_count: u16 = 0;

        var entry_iter = self.map.iterator();
        while (entry_iter.next()) |entry| {
            const nonce_duration = now_seconds - entry.value_ptr.*;
            if (nonce_duration > 2 * std.time.s_per_min) {
                removed_count += 1;
                _ = self.remove(entry.key_ptr.*);
            }
        }

        return removed_count;
    }
};

test NonceMap {
    const alloc = std.testing.allocator;

    var nonce_map = NonceMap.init(alloc);
    defer nonce_map.deinit();

    const nonce = try nonce_map.new();
    // nonce is freed as part of remove.
    try std.testing.expectEqual(32, nonce.len);

    const nonce_deleted = nonce_map.remove(nonce);
    try std.testing.expectEqual(true, nonce_deleted);
}

// In-memory Access token cache. Validating 3rd party tokens by the third party
// requires an external http request which can be slow.
const TokenCache = struct {
    alloc: std.mem.Allocator,
    map: std.StringHashMap(AccessToken),

    const AccessToken = struct {
        token: []const u8,
        user_id: i64,
        issued_at: u32,
        expires_in: u32,

        pub fn expired(self: *const AccessToken) bool {
            const now = std.time.timestamp();
            const expires_at = self.issued_at + self.expires_in;

            return expires_at < now;
        }
    };

    pub fn init(alloc: std.mem.Allocator) TokenCache {
        var map = std.StringHashMap(AccessToken).init(alloc);
        _ = &map;

        return .{
            .alloc = alloc,
            .map = map,
        };
    }

    pub fn put(self: *TokenCache, access_token: []const u8, expires_in: u32, user_id: i64) !void {
        const now_seconds = std.time.timestamp();
        assert(now_seconds > 0);
        const issued_at: u32 = @intCast(now_seconds);
        const token_str = try self.alloc.alloc(u8, access_token.len);
        errdefer self.alloc.free(token_str);
        @memcpy(token_str, access_token);

        const token: AccessToken = .{
            .token = token_str,
            .user_id = user_id,
            .issued_at = issued_at,
            .expires_in = expires_in,
        };

        try self.map.put(token_str, token);
    }

    pub fn remove(self: *TokenCache, access_token: []const u8) bool {
        if (self.map.get(access_token)) |cached_token| {
            self.alloc.free(cached_token.token);

            return self.map.remove(access_token);
        } else {
            return false;
        }
    }

    pub fn removeExpired(self: *TokenCache) u16 {
        var removed_count: u16 = 0;

        var entry_iter = self.map.iterator();
        while (entry_iter.next()) |entry| {
            if (entry.value_ptr.*.expired()) {
                removed_count += 1;
                _ = self.remove(entry.key_ptr.*);
            }
        }

        return removed_count;
    }

    pub fn get(self: *TokenCache, access_token: []const u8) ?AccessToken {
        return self.map.get(access_token);
    }

    pub fn deinit(self: *TokenCache) void {
        var entry_iter = self.map.iterator();
        while (entry_iter.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
        }
        self.map.deinit();
    }
};

test TokenCache {
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;

    var token_cache = TokenCache.init(std.testing.allocator);
    defer token_cache.deinit();

    try token_cache.put("abcdef", 3600, 1);
    try expectEqualStrings("abcdef", token_cache.map.get("abcdef").?.token);
    try expectEqual(1, token_cache.map.get("abcdef").?.user_id);
}

const App = struct {
    alloc: std.mem.Allocator,
    sqlite: model.Sqlite,
    nonce_map: NonceMap,
    token_cache: TokenCache,
    github_creds: github.ApiCredentials,

    pub const Env = enum {
        prod,
        testing,
    };

    pub const Options = struct {
        alloc: std.mem.Allocator,
        env: Env,
        github_creds: github.ApiCredentials,
    };

    pub fn init(opts: Options) !App {
        const db_env = switch (opts.env) {
            .prod => model.Sqlite.Env.prod,
            .testing => model.Sqlite.Env.testing,
        };

        const alloc = opts.alloc;

        return .{
            .alloc = alloc,
            .sqlite = try model.Sqlite.open(db_env),
            .nonce_map = NonceMap.init(alloc),
            .token_cache = TokenCache.init(alloc),
            .github_creds = opts.github_creds,
        };
    }

    pub fn deinit(self: *App) void {
        self.sqlite.deinit();
        self.nonce_map.deinit();
        self.token_cache.deinit();
    }
};

fn validateEnvVar(env_map: std.process.EnvMap, var_name: []const u8, missing_error: anyerror, empty_error: anyerror) ![]const u8 {
    if (env_map.get(var_name)) |var_value| {
        return if (std.mem.eql(u8, "", var_value)) empty_error else var_value;
    } else {
        return missing_error;
    }
}

pub fn scheduledJobs(app: *App, alloc: std.mem.Allocator) !void {
    var tidied_at = std.time.timestamp();
    var notified_at = std.time.timestamp();

    while (true) {
        const now = std.time.timestamp();

        const seconds_since_previous_tidy = now - tidied_at;
        if (seconds_since_previous_tidy > TIDY_PERIOD) {
            logger.info("Tidying server...", .{});
            const removed_token_count = app.token_cache.removeExpired();
            logger.info("  Removed {d} expired tokens from cache.", .{removed_token_count});
            const removed_nonce_count = app.nonce_map.removeExpired();
            logger.info("  Removed {d} expired nonces.", .{removed_nonce_count});

            tidied_at = now;
        }

        const seconds_since_previous_notified = now - notified_at;
        if (seconds_since_previous_notified > NOTIFY_PERIOD) {
            logger.info("Checking for notifications...", .{});

            const users = try app.sqlite.selectUsers(alloc);
            defer {
                for (users) |user| {
                    user.deinit();
                }
                alloc.free(users);
            }
            const tomorrow = now + std.time.s_per_day;
            for (users) |user| {
                // Check if user can receive notifications or else skip.
                const webhook = try app.sqlite.selectWebhook(alloc, user.id.?, model.HookFor.slack_notification) orelse continue;

                var contact_list = try app.sqlite.selectContactsByUser(alloc, user.id.?);
                defer contact_list.deinit();
                var contact_iter = contact_list.iterator();
                var due_message = std.ArrayList(u8).init(alloc);
                defer due_message.deinit();
                var writer = due_message.writer();
                while (contact_iter.next()) |entry| {
                    if (entry.value_ptr.isDueBy(tomorrow)) {
                        if (0 == due_message.items.len) {
                            try writer.print("Contacts due:", .{});
                        }
                        try writer.print("\n  {s}", .{entry.value_ptr.full_name});
                    }
                }
                logger.info("Posting message {s} to webhook {s}", .{due_message.items, webhook.url});
                try slack.sendMessage(alloc, webhook.url, due_message.items);
            }

            notified_at = now;
        }
        std.posix.nanosleep(60, 0);
    }
}

pub fn runServer() !void {
    var general_purpose_allocator = std.heap.DebugAllocator(.{}).init;
    // const allocator = std.heap.page_allocator
    const allocator = general_purpose_allocator.allocator();

    // Ensure Github API credentials are present in env variables.
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const github_client_id = try validateEnvVar(env_map, "GITHUB_CLIENT_ID", error.GithubClientIdMissing, error.GithubClientIdEmpty);
    const github_secret = try validateEnvVar(env_map, "GITHUB_SECRET", error.GithubSecretMissing, error.GithubSecretEmpty);
    const github_creds = github.ApiCredentials{
        .client_id = github_client_id,
        .secret = github_secret,
    };

    // TODO: This should be part of sqlite, there should be only 1 method "setup" that depending on the Sqlite.Env sets up the appropriate DB.
    try model.setupSqlite();

    var app = try App.init(.{
        .alloc = allocator,
        .env = App.Env.prod,
        .github_creds = github_creds,
    });
    defer app.deinit();

    const address = try std.net.Address.resolveIp(DEFAULT_HOST, DEFAULT_PORT);
    var net_server = try address.listen(.{ .reuse_address = true });
    defer net_server.deinit();

    const scheduled_jobs_thread = try std.Thread.spawn(.{}, scheduledJobs, .{&app, allocator});

    var server_buffer: [DEFAULT_URL_LENGTH]u8 = undefined;
    while (true) {
        const connection = try net_server.accept();
        defer connection.stream.close();

        var server = std.http.Server.init(connection, &server_buffer);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var http_request = try server.receiveHead();
        var request = try Request.init(arena.allocator(), &app, &http_request);

        _ = try request.respond();
        // const response = try request.respond();
        // if (std.mem.eql(u8, "Stop server", response.body.bodyStr())) break;
    }

    scheduled_jobs_thread.join();
}
