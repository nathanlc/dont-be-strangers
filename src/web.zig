const std = @import("std");

const PUBLIC_PATH = "public/";

fn httpMethodToString(method: std.http.Method) []const u8 {
    const Method = std.http.Method;

    return switch (method) {
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

const Response = struct {
    body: []const u8,
    content_type: Mime,
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
        .body = "Hello!",
        .content_type = Mime.text_plain,
    };
}

fn respondContacts(_: *Request) !Response {
    return Response{
        .body = "Contact list",
        .content_type = Mime.text_plain,
    };
}

fn eqlU8(str1: []const u8, str2: []const u8) bool {
    return std.mem.eql(u8, str1, str2);
}

const Mime = enum {
    text_html,
    text_javascript,
    text_css,
    text_plain,
    application_json,
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

        std.log.warn("Unexpected extension: {s}\n  for file_name: {s}\nReturning text/plain", .{ extension, file_name });
        return error.MimeNotFound;
    }

    pub fn toString(self: Mime) []const u8 {
        return switch (self) {
            Mime.text_html => "text/html",
            Mime.text_javascript => "text/javascript",
            Mime.text_css => "text/css",
            Mime.text_plain => "text/plain",
            Mime.application_json => "application/json",
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
    // TODO: Probably need to stream that...
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
                std.log.warn("Static file not found: {!}", .{err});
                return respond404(request);
            },
            else => return err,
        }
    };

    return Response{
        .body = body,
        .content_type = Mime.fromString(path) catch Mime.text_plain,
    };
}

fn testResponse(comptime method: []const u8, comptime path: []const u8, expected_body: []const u8, expected_mime: Mime) !void {
    const allocator = std.testing.allocator;

    const ip = "127.0.0.1";
    const port = 3010;

    const server_thread = try std.Thread.spawn(.{}, (struct {
        fn apply(e_body: []const u8, e_mime: Mime) !void {
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

            try std.testing.expectEqualStrings(e_body, response.body);
            try std.testing.expectEqual(e_mime, response.content_type);
        }
    }).apply, .{ expected_body, expected_mime });

    const request_bytes =
        method ++ " " ++ path ++ " HTTP/1.1\r\n" ++
        "Accept: */*\r\n" ++
        "\r\n";

    const stream = try std.net.tcpConnectToHost(allocator, ip, port);
    defer stream.close();
    _ = try stream.writeAll(request_bytes[0..]);

    server_thread.join();
}

test "respondServeFile with request /test.txt" {
    try testResponse("GET", "/test.txt", "test\n", Mime.text_plain);
}

test respondHealth {
    try testResponse("GET", "/health", "Hello!", Mime.text_plain);
}

fn respond404(_: *Request) !Response {
    return Response{
        .body = "404 NOT FOUND",
        .content_type = Mime.text_plain,
    };
}

fn respond500(_: *Request) !Response {
    return Response{
        .body = "500 WHOOPSIE",
        .content_type = Mime.text_plain,
    };
}

const endpoint404 = Endpoint{
    // Path and method don't matter in this case.
    .path = "/404",
    .method = std.http.Method.GET,
    .respond = &respond404,
};

const endpoint500 = Endpoint{
    // Path and method don't matter in this case.
    .path = "/500",
    .method = std.http.Method.GET,
    .respond = &respond500,
};

const endpoints = [_]Endpoint{
    Endpoint{ .path = "/health", .method = std.http.Method.GET, .respond = &respondHealth },
    Endpoint{ .path = "/contacts", .method = std.http.Method.GET, .respond = &respondContacts },
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

    return endpoint404;
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

    fn getPath(self: *Request) []const u8 {
        return self.uri.path.percent_encoded;
    }

    fn getMethod(self: *Request) std.http.Method {
        return self.inner.head.method;
    }

    fn getMethodString(self: *Request) []const u8 {
        return httpMethodToString(self.getMethod());
    }

    fn logRequest(self: *Request) !void {
        std.log.info("{s}: {s}\n  Path:   {s}\n  Query: {s}\n", .{
            self.getMethodString(),
            self.url,
            try self.uri.path.toRawMaybeAlloc(self.arena),
            if (self.uri.query) |query| try query.toRawMaybeAlloc(self.arena) else "",
        });
    }

    // TODO: Returning Response for now is to make testing of responses easier. It's a hack.
    pub fn respond(self: *Request) !Response {
        // TODO: errdefer respond with a 500 or something.
        try self.logRequest();
        const matching_endpoint = route(self.arena, self.uri.path.percent_encoded, self.getMethod()) catch |err| blk: {
            std.log.err("Error while routing: {!}\n", .{err});
            break :blk endpoint500;
        };
        const response = try matching_endpoint.respond(self);
        // TODO: Look into respondStreaming if need for manipulating the response arises.

        const content_type = std.http.Header{ .name = "Content-Type", .value = response.content_type.toString() };
        try self.inner.respond(response.body, .{
            .extra_headers = &.{
                content_type,
                .{ .name = "Connection", .value = "Close" },
            },
        });

        return response;
    }
};
