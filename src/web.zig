const std = @import("std");
const builtin = @import("builtin");
const model = @import("model.zig");
const github = @import("github.zig");
const tracy = @import("tracy.zig");
const assert = std.debug.assert;

const PUBLIC_PATH = "public/";
const DEFAULT_URL_LENGTH = 2048;
const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 3000;
const TIDY_PERIOD = 1 * std.time.s_per_hour;
// const TIDY_PERIOD = 1 * std.time.s_per_min;

const logger = std.log.scoped(.web);

fn logErr(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        logger.err(fmt, args);
    } else {
        logger.info(fmt, args);
    }
}

pub fn runScratch(_: std.mem.Allocator) !void {}

const Query = struct {
    allocator: std.mem.Allocator,
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
                @memcpy(key, item_key.?);
                const value = try allocator.alloc(u8, item_value.?.len);
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
    content_type: Mime,
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
    path_handles: std.ArrayList(u32),

    pub fn init(alloc: std.mem.Allocator) Router {
        var path_handles = std.ArrayList(u32).init(alloc);
        _ = &path_handles;

        return .{
            .alloc = alloc,
            .path_handles = path_handles,
        };
    }

    // The complexity of this parsing is not necessary for now.
    // Just splitting path end self.path by '/' and compare the parts would have been simpler.
    // TODO: compare performance of both.
    // This method both checks the path of the endpoint AND populates self.path_handles.
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
                try self.path_handles.append(path_var_start_index);
                try self.path_handles.append(i);
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
                    try self.path_handles.append(path_var_start_index);
                    try self.path_handles.append(i);
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
                            .path_handles = try self.path_handles.toOwnedSlice(),
                        };
                    }
                },
                .endpoint_with_path_variables => |e| {
                    if (e.method == method and try self.pathMatches(path, e.path)) {
                        return DispatchResult{
                            .endpoint = endpoint,
                            .path_handles = try self.path_handles.toOwnedSlice(),
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
                        .path_handles = try self.path_handles.toOwnedSlice(),
                    };
                }
            }
        }

        return DispatchResult{
            .endpoint = .{ .endpoint_without_path_variables = endpointNotFound },
            .path_handles = try self.path_handles.toOwnedSlice(),
        };
    }
};

test Router {
    const alloc = std.testing.allocator;
    const expectEqualStrings = std.testing.expectEqualStrings;
    const expectEqualSlices = std.testing.expectEqualSlices;

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
        try expectEqualSlices(u32, &.{ 22, 37 }, dispatch_result.path_handles);
    }
}

const DispatchResult = struct {
    endpoint: Endpoint,
    // Path handles is an owned slice returned by Router.dispatch.
    path_handles: []u32,

    pub fn free(self: *const DispatchResult, alloc: std.mem.Allocator) void {
        alloc.free(self.path_handles);
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
    respond: *const fn (*Request, []u32) anyerror!Response,
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
        .content_type = Mime.text_plain,
    };
}

fn respondGithubLoginParams(request: *Request) !Response {
    const state = try request.app.nonce_map.new();
    const body = try std.fmt.allocPrint(
        request.arena,
        "{{\"github_client_id\":\"" ++ github.GITHUB_CLIENT_ID ++ "\",\"state\":\"{s}\"}}",
        .{state},
    );

    return Response{
        .body = Body{ .alloc = body },
        .content_type = Mime.application_json,
    };
}

test respondGithubLoginParams {
    const allocator = std.testing.allocator;

    var app = App.init(allocator);
    defer app.deinit();

    const ip = "127.0.0.1";
    const port = 3011;

    const server_thread = try std.Thread.spawn(.{}, (struct {
        fn apply(app_ptr: *App) !void {
            const address = try std.net.Address.resolveIp(ip, port);
            var net_server = try address.listen(.{ .reuse_address = true });
            defer net_server.deinit();

            const connection = try net_server.accept();
            defer connection.stream.close();

            var server_buffer: [2048]u8 = undefined;
            var server = std.http.Server.init(connection, &server_buffer);
            var request = try Request.init(allocator, app_ptr, try server.receiveHead());
            defer request.deinit();

            const response = try request.respond();

            const body_str = response.body.bodyStr();
            try std.testing.expectEqual(87, body_str.len);
            try std.testing.expectEqual(Mime.application_json, response.content_type);
            try std.testing.expectEqual(.ok, response.status);
        }
    }).apply, .{&app});

    const request_bytes =
        "GET /auth/github/login_params HTTP/1.1\r\n" ++
        "Accept: */*\r\n" ++
        "\r\n";

    // Pause for 0.001s otherwise connection is refused in github actions...
    std.posix.nanosleep(0, 1_000_000);

    const stream = try std.net.tcpConnectToHost(allocator, ip, port);
    defer stream.close();
    _ = try stream.writeAll(request_bytes[0..]);

    server_thread.join();
}

fn respondGithubCallback(request: *Request) !Response {
    var query = try request.getQuery();
    defer query.deinit();

    _ = query.get("code") orelse {
        return Response{
            .body = Body{ .comp = "Missing expected query param `code`" },
            .content_type = Mime.text_plain,
            .status = .bad_request,
        };
    };

    return respondIndex(request);
}

pub const GrantType = enum {
    AuthorizationCode,
    RefreshToken,
};

fn handleFetchedToken(request: *Request, parsed_token_or_error: anyerror!std.json.Parsed(github.AccessToken)) !Response {
    if (parsed_token_or_error) |parsed_token| {
        defer parsed_token.deinit();
        const token = parsed_token.value;

        const parsed_user = try github.fetch_user(request.arena, token.access_token);
        defer parsed_user.deinit();

        try request.app.token_cache.put(token.access_token, token.expires_in, parsed_user.value.login);

        const body = try std.json.stringifyAlloc(request.arena, token, .{});

        return Response{
            .body = .{ .alloc = body },
            .content_type = Mime.application_json,
        };
    } else |err| {
        const err_body = Body{ .comp = "{\"error\":\"Failed to fetch token.\"}" };
        const content_type = Mime.application_json;
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
            .content_type = Mime.text_plain,
            .status = .bad_request,
        };
    };

    const state = query.get("state") orelse {
        return Response{
            .body = Body{ .comp = "Missing expected query param `state`" },
            .content_type = Mime.text_plain,
            .status = .bad_request,
        };
    };

    const state_valid = request.app.nonce_map.remove(state);
    if (!state_valid) {
        return Response{
            .body = Body{ .comp = "Invalid state query param" },
            .content_type = Mime.text_plain,
            .status = .forbidden,
        };
    }

    return handleFetchedToken(request, github.fetch_token(request.arena, .AuthorizationCode, code));
}

fn respondGithubRefreshToken(request: *Request) !Response {
    var query = try request.getQuery();
    defer query.deinit();

    const refresh_token = query.get("refresh_token") orelse {
        return Response{
            .body = .{ .comp = "Missing expected query param `refresh_token`." },
            .content_type = Mime.text_plain,
            .status = .bad_request,
        };
    };

    return handleFetchedToken(request, github.fetch_token(request.arena, .RefreshToken, refresh_token));
}

const ContactView = struct {
    created_at: u32,
    full_name: []const u8,
    frequency_days: u16,
    due_at: u32,

    pub fn fromContact(contact: model.Contact) ContactView {
        return ContactView{
            .created_at = contact.created_at,
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
    contact.created_at = 1737401035;
    var full_name = std.ArrayList(u8).init(alloc);
    try full_name.appendSlice("john doe");
    contact.full_name = full_name.items;
    contact.frequency_days = 30;
    contact.due_at = 1737400035;

    const contact_view = ContactView.fromContact(contact);
    try expectEqual(1737401035, contact_view.created_at);
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

test "ContactViewList.fromContactList" {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;

    var contact_list = try model.ContactList.fromCsvFile(alloc, "test_db", true);
    defer contact_list.deinit();

    const contact_view_list = try ContactViewList.fromContactList(alloc, contact_list);
    defer contact_view_list.deinit();
    // contact_list uses a hash map internally. The order of the contact view list is
    // not guaranteed. Below is a hacky way to find the contact view to test...
    const first_contact_view = contact_view_list.contacts[0];
    const second_contact_view = contact_view_list.contacts[1];
    const contact_view = if (first_contact_view.created_at == 1737401036) first_contact_view else second_contact_view;

    try expectEqual(1737401036, contact_view.created_at);
    try expectEqual(14, contact_view.frequency_days);
    try std.testing.expectEqualStrings("jane doe", contact_view.full_name);
    try expectEqual(1737400036, contact_view.due_at);
}

fn respondApiV0UserContacts(request: *Request) !Response {
    const tr = tracy.trace(@src());
    defer tr.end();

    const user_id = request.authenticateViaToken() catch |err| switch (err) {
        error.UnauthenticatedRequest => {
            return try respondUnauthorized(request);
        },
    };

    var contact_list = model.ContactList.fromCsvFile(request.arena, user_id, true) catch |err| return switch (err) {
        error.ContactListNotFound => respondNotFound(request),
        else => err,
    };
    defer contact_list.deinit();

    const contact_view_list = try ContactViewList.fromContactList(request.arena, contact_list);
    defer contact_view_list.deinit();

    const body = try std.json.stringifyAlloc(
        request.arena,
        contact_view_list,
        .{},
    );

    return Response{
        .body = Body{ .alloc = body },
        .content_type = Mime.text_plain,
    };
}

fn respondApiV0UserContactsPatch(request: *Request, path_handles: []u32) !Response {
    assert(2 == path_handles.len);

    const contact_id_str: []const u8 = request.getPath()[path_handles[0]..path_handles[1]];
    const contact_id = try std.fmt.parseInt(u32, contact_id_str, 10);

    const user_id = request.authenticateViaToken() catch |err| switch (err) {
        error.UnauthenticatedRequest => {
            return try respondUnauthorized(request);
        },
    };

    const use_headers = true;
    var contact_list = try model.ContactList.fromCsvFile(request.arena, user_id, use_headers);
    defer contact_list.deinit();

    std.debug.print("contact_id_str: '{s}', contact_id: '{d}'\n", .{ contact_id_str, contact_id });
    std.debug.print("Contact list:\n{csv}\n", .{contact_list});

    return if (contact_list.getContactPtr(contact_id)) |contact_ptr| blk: {
        contact_ptr.setDueAt(null);
        try contact_list.toCsvFile(user_id, use_headers);
        const contact_view = ContactView.fromContact(contact_ptr.*);
        const body = try std.json.stringifyAlloc(request.arena, contact_view, .{});

        break :blk Response{
            .body = Body{ .alloc = body },
            .content_type = Mime.text_plain,
        };
    } else respondNotFound(request);
}

fn eqlU8(str1: []const u8, str2: []const u8) bool {
    return std.mem.eql(u8, str1, str2);
}

pub const Mime = enum {
    text_html,
    text_javascript,
    text_css,
    text_plain,
    application_json,
    application_x_www_form_url_encoded,
    image_x_icon,
    image_svg,
    image_png,

    pub fn fromString(file_name: []const u8) !Mime {
        var iter = std.mem.splitBackwardsScalar(u8, file_name, '.');
        const extension = iter.first();

        if (eqlU8("html", extension)) {
            return Mime.text_html;
        } else if (eqlU8("js", extension)) {
            return Mime.text_javascript;
        } else if (eqlU8("css", extension)) {
            return Mime.text_css;
        } else if (eqlU8("txt", extension)) {
            return Mime.text_plain;
        } else if (eqlU8("webmanifest", extension) or (eqlU8("json", extension))) {
            return Mime.application_json;
        } else if (eqlU8("ico", extension)) {
            return Mime.image_x_icon;
        } else if (eqlU8("svg", extension)) {
            return Mime.image_svg;
        } else if (eqlU8("png", extension)) {
            return Mime.image_png;
        }

        logger.warn("Unexpected extension: {s}\n  for file_name: {s}\nReturning text/plain", .{ extension, file_name });
        return error.MimeNotFound;
    }

    pub fn toString(self: Mime) []const u8 {
        return switch (self) {
            Mime.text_html => "text/html",
            Mime.text_javascript => "text/javascript",
            Mime.text_css => "text/css",
            Mime.text_plain => "text/plain",
            Mime.application_json => "application/json",
            Mime.application_x_www_form_url_encoded => "application/x-www-form-urlencoded",
            Mime.image_x_icon => "image/x-icon",
            Mime.image_svg => "image/svg",
            Mime.image_png => "image/png",
        };
    }
};

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
        .content_type = Mime.fromString(path) catch Mime.text_plain,
    };
}

fn respondIndex(_: *Request) !Response {
    const path = "/index.html";
    const body: []const u8 = try readPublicFile(path);

    return Response{
        .body = Body{ .comp = body },
        .content_type = Mime.fromString(path) catch Mime.text_plain,
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
    try testResponse("GET", "/testing/error", "500 WHOOPSIE", Mime.text_plain, .internal_server_error);
}

fn respondUnauthorized(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "{\"error\":\"Unauthorized\"}" },
        .content_type = Mime.application_json,
        .status = .unauthorized,
    };
}

fn respondOk(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "200 OK" },
        .content_type = Mime.text_plain,
    };
}

fn respondNotFound(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "404 NOT FOUND" },
        .content_type = Mime.text_plain,
        .status = .not_found,
    };
}

fn respondInternalServerError(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "500 WHOOPSIE" },
        .content_type = Mime.text_plain,
        .status = .internal_server_error,
    };
}

fn testResponse(comptime method: []const u8, comptime path: []const u8, expected_body: []const u8, expected_mime: Mime, expected_status: std.http.Status) !void {
    const allocator = std.testing.allocator;

    var app = App.init(allocator);
    defer app.deinit();

    const ip = "127.0.0.1";
    const port = 3010;

    const server_thread = try std.Thread.spawn(.{}, (struct {
        fn apply(app_ptr: *App, e_body: []const u8, e_mime: Mime, e_status: std.http.Status) !void {
            const address = try std.net.Address.resolveIp(ip, port);
            var net_server = try address.listen(.{ .reuse_address = true });
            defer net_server.deinit();

            const connection = try net_server.accept();
            defer connection.stream.close();

            var server_buffer: [2048]u8 = undefined;
            var server = std.http.Server.init(connection, &server_buffer);
            var request = try Request.init(allocator, app_ptr, try server.receiveHead());
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

    // Pause for 0.001s otherwise connection is refused in github actions...
    std.posix.nanosleep(0, 1_000_000);

    const stream = try std.net.tcpConnectToHost(allocator, ip, port);
    defer stream.close();
    _ = try stream.writeAll(request_bytes[0..]);

    server_thread.join();
}

test respondHealth {
    try testResponse("GET", "/health", "Hello!", Mime.text_plain, .ok);
}

test respondServeFile {
    try testResponse("GET", "/test.txt", "test\n", Mime.text_plain, .ok);
}

test respondNotFound {
    try testResponse("GET", "/not_existing_path", "404 NOT FOUND", Mime.text_plain, .not_found);
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

fn dispatchRoute(allocator: std.mem.Allocator, path: []const u8, method: std.http.Method) !Endpoint {
    for (endpoints) |endpoint| {
        if (endpoint.matches(method, path)) {
            return endpoint;
        }
    }

    // TODO: For static endpoints, should we put all under 1 dir so we can quickly check if the path starts with said dir.
    const static_endpoints = try getStaticEndpoints(allocator);
    defer {
        for (static_endpoints) |endpoint| {
            endpoint.deinit(allocator);
        }
        allocator.free(static_endpoints);
    }
    for (static_endpoints) |endpoint| {
        if (endpoint.matches(method, path)) {
            return endpoint;
        }
    }

    return endpointNotFound;
}

pub const Request = struct {
    arena: std.mem.Allocator,
    app: *App,
    inner: std.http.Server.Request,
    url: []const u8,
    uri: std.Uri,

    pub fn init(arena: std.mem.Allocator, app: *App, request: std.http.Server.Request) !Request {
        // TODO: figure out how to get the full URL. Or does it actually matter?
        const url = try std.fmt.allocPrint(
            arena,
            "http://localhost{s}",
            .{request.head.target},
        );
        const uri = try std.Uri.parse(url);

        return .{
            .arena = arena,
            .app = app,
            .inner = request,
            .url = url,
            .uri = uri,
        };
    }

    // No need to deinit, self should have been initiated with an arena.
    pub fn deinit(self: *Request) void {
        self.arena.free(self.url);
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

    pub fn respond(self: *Request) !Response {
        const tr = tracy.trace(@src());
        defer tr.end();

        try self.log();

        var router = Router.init(self.arena);
        const dispatch_result = router.dispatch(self.getMethod(), self.getPath()) catch |err| blk: {
            logErr("Error while routing: {!}", .{err});
            break :blk DispatchResult{ .endpoint = .{ .endpoint_without_path_variables = endpointInternalServerError }, .path_handles = &.{} };
        };
        defer dispatch_result.free(self.arena);
        const response = switch (dispatch_result.endpoint) {
            .endpoint_without_path_variables => |e| e.respond(self) catch |err| handleRespondError(self, err),
            .endpoint_with_path_variables => |e| e.respond(self, dispatch_result.path_handles) catch |err| handleRespondError(self, err),
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
    pub fn authenticateViaToken(self: *Request) ![]const u8 {
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
        user_id: []const u8,
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

    pub fn put(self: *TokenCache, access_token: []const u8, expires_in: u32, user_id: []const u8) !void {
        const now_seconds = std.time.timestamp();
        assert(now_seconds > 0);
        const issued_at: u32 = @intCast(now_seconds);
        const token_str = try self.alloc.alloc(u8, access_token.len);
        errdefer self.alloc.free(token_str);
        @memcpy(token_str, access_token);
        const user_id_str = try self.alloc.alloc(u8, user_id.len);
        errdefer self.alloc.free(user_id_str);
        @memcpy(user_id_str, user_id);

        const token = .{
            .token = token_str,
            .user_id = user_id_str,
            .issued_at = issued_at,
            .expires_in = expires_in,
        };

        try self.map.put(token_str, token);
    }

    pub fn remove(self: *TokenCache, access_token: []const u8) bool {
        if (self.map.get(access_token)) |cached_token| {
            self.alloc.free(cached_token.token);
            self.alloc.free(cached_token.user_id);

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
            self.alloc.free(entry.value_ptr.*.user_id);
        }
        self.map.deinit();
    }
};

test TokenCache {
    const expect = std.testing.expect;

    var token_cache = TokenCache.init(std.testing.allocator);
    defer token_cache.deinit();

    try token_cache.put("abcdef", 3600, "bob");
    try expect(std.mem.eql(u8, "abcdef", token_cache.map.get("abcdef").?.token));
    try expect(std.mem.eql(u8, "bob", token_cache.map.get("abcdef").?.user_id));
}

const App = struct {
    alloc: std.mem.Allocator,
    nonce_map: NonceMap,
    token_cache: TokenCache,

    pub fn init(alloc: std.mem.Allocator) App {
        const nonce_map = NonceMap.init(alloc);
        const token_cache = TokenCache.init(alloc);

        return .{
            .alloc = alloc,
            .nonce_map = nonce_map,
            .token_cache = token_cache,
        };
    }

    pub fn deinit(self: *App) void {
        self.nonce_map.deinit();
        self.token_cache.deinit();
    }
};

pub fn tidyServer(app_ptr: *App) !void {
    var tidied_at = std.time.timestamp();

    while (true) {
        const now = std.time.timestamp();
        const seconds_since_previous_tidy = now - tidied_at;
        if (seconds_since_previous_tidy > TIDY_PERIOD) {
            logger.info("Tidying server...", .{});
            const removed_token_count = app_ptr.token_cache.removeExpired();
            logger.info("  Removed {d} expired tokens from cache.", .{removed_token_count});
            const removed_nonce_count = app_ptr.nonce_map.removeExpired();
            logger.info("  Removed {d} expired nonces.", .{removed_nonce_count});

            tidied_at = now;
        }
        std.posix.nanosleep(60, 0);
    }
}

pub fn runServer() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = std.heap.page_allocator
    const allocator = general_purpose_allocator.allocator();

    var app = App.init(allocator);
    defer app.deinit();

    const address = try std.net.Address.resolveIp(DEFAULT_HOST, DEFAULT_PORT);
    var net_server = try address.listen(.{ .reuse_address = true });
    defer net_server.deinit();

    const tidy_thread = try std.Thread.spawn(.{}, tidyServer, .{&app});

    var server_buffer: [DEFAULT_URL_LENGTH]u8 = undefined;
    while (true) {
        const connection = try net_server.accept();
        defer connection.stream.close();

        var server = std.http.Server.init(connection, &server_buffer);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var request = try Request.init(arena.allocator(), &app, try server.receiveHead());

        _ = try request.respond();
        // const response = try request.respond();
        // if (std.mem.eql(u8, "Stop server", response.body.bodyStr())) break;
    }

    tidy_thread.join();
}
