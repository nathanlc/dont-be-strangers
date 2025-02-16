const std = @import("std");
const builtin = @import("builtin");
const model = @import("model.zig");
const github = @import("github.zig");

const PUBLIC_PATH = "public/";
const DEFAULT_URL_LENGTH = 2048;
const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 3000;

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
        errdefer {
            var entry_iter = map.iterator();
            while (entry_iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            map.deinit();
        }

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
        var entry_iter = self.map.iterator();
        while (entry_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }
};

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

const Endpoint = struct {
    path: []const u8,
    method: std.http.Method,
    respond: *const fn (*Request) anyerror!Response,

    // When Endpoint is created for static endpoints by getStaticEndpoints, the path
    // has to be allocated.
    // TODO: Should we create an EndpointList or a StaticEndpoint?
    pub fn deinit(self: *const Endpoint, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

fn respondHealth(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "Hello!" },
        .content_type = Mime.text_plain,
    };
}

fn respondGithubLoginParams(_: *Request) !Response {
    // const state = "abc123";
    const body =
        \\{
        \\  "github_client_id": "
    ++ github.GITHUB_CLIENT_ID ++
        \\"
        \\}
    ;

    return Response{
        .body = Body{ .comp = body },
        .content_type = Mime.application_json,
    };
}

test respondGithubLoginParams {
    const expected_body =
        \\{
        \\  "github_client_id": "test_github_client_id"
        \\}
    ;
    try testResponse("GET", "/auth/github/login_params", expected_body, Mime.application_json, .ok);
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

fn respondGithubAccessToken(request: *Request) !Response {
    var query = try request.getQuery();
    defer query.deinit();

    // TODO: Should verify "state" as well.

    const code = query.get("code") orelse {
        return Response{
            .body = Body{ .comp = "Missing expected query param `code`" },
            .content_type = Mime.text_plain,
            .status = .bad_request,
        };
    };

    return try github.fetch_token(request.arena, .AuthorizationCode, code);
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

    return try github.fetch_token(request.arena, .RefreshToken, refresh_token);
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
        var contact_view_list = std.ArrayList(ContactView).init(alloc);
        for (contact_list.contacts) |contact| {
            const contact_view = ContactView.fromContact(contact);
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
    const contact_view = contact_view_list.contacts[1];

    try expectEqual(1737401036, contact_view.created_at);
    try expectEqual(14, contact_view.frequency_days);
    try std.testing.expectEqualStrings("jane doe", contact_view.full_name);
    try expectEqual(1737400036, contact_view.due_at);
}

fn respondUserContacts(request: *Request) !Response {
    var query = try request.getQuery();
    defer query.deinit();

    const parsed_gh_user_info = request.authenticateViaGithub() catch |err| {
        switch (err) {
            error.UnauthenticatedRequest => {
                return try respondUnauthorized(request);
            },
            else => {
                logErr("Unexpected error when authenticating user: {!}", .{err});
                return err;
            },
        }
    };
    defer parsed_gh_user_info.deinit();

    const gh_user_info = parsed_gh_user_info.value;

    var contact_list = model.ContactList.fromCsvFile(request.arena, gh_user_info.login, true) catch |err| {
        return switch (err) {
            error.ContactListNotFound => respondNotFound(request),
            else => err,
        };
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

test respondTestingError {
    try testResponse("GET", "/testing/error", "500 WHOOPSIE", Mime.text_plain, .internal_server_error);
}

fn respondUnauthorized(_: *Request) !Response {
    return Response{
        .body = Body{ .comp = "Unauthorized" },
        .content_type = Mime.text_plain,
        .status = .unauthorized,
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

    const ip = "127.0.0.1";
    const port = 3010;

    const server_thread = try std.Thread.spawn(.{}, (struct {
        fn apply(e_body: []const u8, e_mime: Mime, e_status: std.http.Status) !void {
            const address = try std.net.Address.resolveIp(ip, port);
            var net_server = try address.listen(.{ .reuse_address = true });
            defer net_server.deinit();

            const connection = try net_server.accept();
            defer connection.stream.close();

            var server_buffer: [2048]u8 = undefined;
            var server = std.http.Server.init(connection, &server_buffer);
            var request = try Request.init(try server.receiveHead(), allocator);
            defer request.deinit();

            const response = try request.respond();

            try std.testing.expectEqualStrings(e_body, response.body.bodyStr());
            try std.testing.expectEqual(e_mime, response.content_type);
            try std.testing.expectEqual(e_status, response.status);
        }
    }).apply, .{ expected_body, expected_mime, expected_status });

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

const endpointNotFound = Endpoint{
    // Path and method don't matter in this case.
    .path = "/404",
    .method = std.http.Method.GET,
    .respond = &respondNotFound,
};

const endpointInternalServerError = Endpoint{
    // Path and method don't matter in this case.
    .path = "/500",
    .method = std.http.Method.GET,
    .respond = &respondInternalServerError,
};

const endpoints = [_]Endpoint{
    // Test routes
    Endpoint{ .path = "/testing/error", .method = std.http.Method.GET, .respond = &respondTestingError },
    Endpoint{ .path = "/health", .method = std.http.Method.GET, .respond = &respondHealth },
    // Web routes
    Endpoint{ .path = "/", .method = std.http.Method.GET, .respond = &respondIndex },
    Endpoint{ .path = "/user/contacts", .method = std.http.Method.GET, .respond = &respondIndex },
    Endpoint{ .path = "/auth/github/login_params", .method = std.http.Method.GET, .respond = &respondGithubLoginParams },
    Endpoint{ .path = "/auth/github/callback", .method = std.http.Method.GET, .respond = &respondGithubCallback },
    Endpoint{ .path = "/auth/github/access_token", .method = std.http.Method.GET, .respond = &respondGithubAccessToken },
    Endpoint{ .path = "/auth/github/refresh_token", .method = std.http.Method.GET, .respond = &respondGithubRefreshToken },
    // API routes
    Endpoint{ .path = "/api/v0/user/contacts", .method = std.http.Method.GET, .respond = &respondUserContacts },
};

fn getStaticEndpoints(allocator: std.mem.Allocator) ![]const Endpoint {
    var endpoints_list = std.ArrayList(Endpoint).init(allocator);
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
        const endpoint = Endpoint{
            .path = path,
            .method = std.http.Method.GET,
            .respond = &respondServeFile,
        };
        try endpoints_list.append(endpoint);
    }

    return try endpoints_list.toOwnedSlice();
}

test getStaticEndpoints {
    const allocator = std.testing.allocator;

    const static_endpoints = try getStaticEndpoints(allocator);
    defer {
        for (static_endpoints) |endpoint| {
            endpoint.deinit(allocator);
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

fn route(allocator: std.mem.Allocator, path: []const u8, method: std.http.Method) !Endpoint {
    for (endpoints) |endpoint| {
        if (endpoint.method == method and std.mem.eql(u8, endpoint.path, path)) {
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
        if (endpoint.method == method and std.mem.eql(u8, endpoint.path, path)) {
            return endpoint;
        }
    }

    return endpointNotFound;
}

pub const Request = struct {
    inner: std.http.Server.Request,
    arena: std.mem.Allocator,
    url: []const u8,
    uri: std.Uri,

    pub fn init(request: std.http.Server.Request, arena: std.mem.Allocator) !Request {
        // TODO: figure out how to get the full URL. Or does it actually matter?
        const url = try std.fmt.allocPrint(
            arena,
            "http://localhost{s}",
            .{request.head.target},
        );
        const uri = try std.Uri.parse(url);

        return .{
            .inner = request,
            .arena = arena,
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

    pub fn respond(self: *Request) !Response {
        try self.log();

        const matching_endpoint = route(self.arena, self.uri.path.percent_encoded, self.getMethod()) catch |err| blk: {
            logErr("Error while routing: {!}", .{err});
            break :blk endpointInternalServerError;
        };
        const response = matching_endpoint.respond(self) catch |err| blk: {
            logErr("Error while generating response: {!}", .{err});
            const internal_server_error_response = respondInternalServerError(self) catch unreachable;
            break :blk internal_server_error_response;
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

    pub fn authenticateViaGithub(self: *Request) !std.json.Parsed(github.User) {
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
        const access_token = auth_header_value[bearer_prefix - 1 ..];

        return github.fetch_user(self.arena, access_token);
    }
};

pub fn runServer() !void {
    const address = try std.net.Address.resolveIp(DEFAULT_HOST, DEFAULT_PORT);
    var net_server = try address.listen(.{ .reuse_address = true });
    defer net_server.deinit();

    var server_buffer: [DEFAULT_URL_LENGTH]u8 = undefined;

    while (true) {
        const connection = try net_server.accept();
        defer connection.stream.close();

        var server = std.http.Server.init(connection, &server_buffer);

        var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = general_purpose_allocator.allocator();
        // const allocator = std.heap.page_allocator
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        var request = try Request.init(try server.receiveHead(), arena.allocator());

        _ = try request.respond();
    }
}
