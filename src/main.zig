const std = @import("std");
const cli = @import("cli.zig");
const web = @import("web.zig");

const DB_PATH = "resources/db.csv";
const READ_FLAGS = std.fs.File.OpenFlags{ .mode = std.fs.File.OpenMode.read_only };
const DEFAULT_URL_LENGTH = 2048;
const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 3000;

fn parsedOptionalValue(parsed_result: anyerror!?[]u8) ?[]u8 {
    if (parsed_result) |maybe_value| {
        return maybe_value;
    } else |err| {
        std.debug.panic("parsed_result was an error {!}\n", .{err});
    }
}

fn parsedValue(parsed_result: anyerror!?[]u8) []u8 {
    if (parsedOptionalValue(parsed_result)) |value| {
        return value;
    } else {
        std.debug.panic("parsed value was null\n", .{});
    }
}

const Contact = struct {
    allocator: std.mem.Allocator,
    created_at: u32,
    full_name: []u8,
    frequency_days: u16,
    contacted_at: ?u32,

    pub fn init(allocator: std.mem.Allocator) Contact {
        return .{
            .allocator = allocator,
            .created_at = undefined,
            .full_name = undefined,
            .frequency_days = undefined,
            .contacted_at = null,
        };
    }

    pub fn fromCsvLine(allocator: std.mem.Allocator, reader: anytype) !Contact {
        var buf: [1024]u8 = undefined;
        // If parsing created_at fails or is null, there is no contact to create.
        // E.g. end of file was reached or the line was incorrectly formatted.
        const maybe_created_at = reader.readUntilDelimiterOrEof(&buf, ',') catch |err| {
            return err;
        };
        if (maybe_created_at == null) {
            return error.CreatedAtNull;
        }
        const created_at = try std.fmt.parseInt(u32, maybe_created_at.?, 10);

        var contact = Contact.init(allocator);

        contact.created_at = created_at;

        const full_name_value = parsedValue(reader.readUntilDelimiterOrEof(&buf, ','));
        const full_name = try allocator.alloc(u8, full_name_value.len);
        errdefer allocator.free(full_name);
        @memcpy(full_name, full_name_value);
        contact.full_name = full_name;

        const frequency_days = parsedValue(reader.readUntilDelimiterOrEof(&buf, ','));
        contact.frequency_days = try std.fmt.parseInt(u16, frequency_days, 10);

        const maybe_contacted_at = try reader.readUntilDelimiterOrEof(&buf, '\n');
        if (maybe_contacted_at) |contacted_at| {
            contact.contacted_at = std.fmt.parseInt(u32, contacted_at, 10) catch |err| blk: {
                break :blk switch (err) {
                    error.InvalidCharacter => null,
                    else => unreachable,
                };
            };
        }

        return contact;
    }

    pub fn deinit(self: Contact) void {
        self.allocator.free(self.full_name);
    }

    pub fn format(
        self: Contact,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print(
            \\Contact(
            \\  created_at: {d},
            \\  full_name: {s},
            \\  frequency_days: {d},
            \\  contacted_at: {?})
        , .{
            self.created_at,
            self.full_name,
            self.frequency_days,
            self.contacted_at,
        });
    }
};

const ContactList = struct {
    contacts: std.ArrayList(Contact),

    pub fn init(allocator: std.mem.Allocator) ContactList {
        return .{
            .contacts = std.ArrayList(Contact).init(allocator),
        };
    }

    pub fn fromCsvFile(allocator: std.mem.Allocator, reader: anytype, has_headers: bool) !ContactList {
        var contact_list = ContactList.init(allocator);
        errdefer contact_list.deinit();

        // Skip headers
        if (has_headers) {
            try reader.skipUntilDelimiterOrEof('\n');
        }
        while (true) {
            var contact = Contact.fromCsvLine(allocator, reader) catch {
                break;
            };
            errdefer contact.deinit();
            try contact_list.contacts.append(contact);
        }

        return contact_list;
    }

    pub fn deinit(self: ContactList) void {
        for (self.contacts.items) |contact| {
            contact.deinit();
        }
        self.contacts.deinit();
    }

    pub fn format(
        self: ContactList,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        for (self.contacts.items, 0..) |contact, i| {
            try writer.print("{s}", .{contact});
            if (i < (self.contacts.items.len - 1)) {
                try writer.print("\n\n", .{});
            }
        }
    }
};

pub fn runHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("keep-in-touch-backend help blablabla\n", .{});
}

pub fn runListContacts(allocator: std.mem.Allocator) !void {
    const db_file = try std.fs.cwd().openFile(DB_PATH, READ_FLAGS);
    defer db_file.close();

    var contact_list = try ContactList.fromCsvFile(allocator, db_file.reader(), true);
    defer contact_list.deinit();

    const stdout = std.io.getStdOut().writer();
    try contact_list.format("{s}", .{}, stdout);
    try stdout.print("\n", .{});
}

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
        var request = try web.Request.init(try server.receiveHead(), arena.allocator());

        _ = try request.respond();
    }
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();

    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    const action = cli.parseArgs(&arg_iterator) catch {
        try runHelp();
        std.process.exit(1);
    };

    switch (action) {
        .help => try runHelp(),
        .list => try runListContacts(allocator),
        .server => try runServer(),
    }
}

test "Contact.fromCsvLine with some contacted_at" {
    const expect = std.testing.expect;

    const csv_line = "1737401035,john doe,30,1737400035\n";
    var stream = std.io.fixedBufferStream(csv_line);
    const reader = stream.reader();
    const contact = try Contact.fromCsvLine(std.testing.allocator, reader);
    defer contact.deinit();

    try expect(contact.created_at == 1737401035);
    try expect(std.mem.eql(u8, contact.full_name, "john doe"));
    try expect(contact.frequency_days == 30);
    try expect(contact.contacted_at.? == 1737400035);
}

test "Contact.fromCsvLine with contacted_at null" {
    const expect = std.testing.expect;

    const csv_line = "1737401035,john doe,30,\n";
    var stream = std.io.fixedBufferStream(csv_line);
    const reader = stream.reader();
    const contact = try Contact.fromCsvLine(std.testing.allocator, reader);
    defer contact.deinit();

    try expect(contact.created_at == 1737401035);
    try expect(std.mem.eql(u8, contact.full_name, "john doe"));
    try expect(contact.frequency_days == 30);
    try expect(contact.contacted_at == null);
}

test "ContactList.fromCsvFile" {
    const expect = std.testing.expect;
    const allocator = std.testing.allocator;

    const test_db = try std.fs.cwd().openFile("resources/test_db.csv", READ_FLAGS);
    defer test_db.close();

    var contact_list = try ContactList.fromCsvFile(allocator, test_db.reader(), true);
    defer contact_list.deinit();

    const first_contact = contact_list.contacts.items[0];
    const second_contact = contact_list.contacts.items[1];

    try expect(first_contact.created_at == 1737401035);
    try expect(std.mem.eql(u8, first_contact.full_name, "john doe"));
    try expect(first_contact.frequency_days == 30);
    try expect(first_contact.contacted_at.? == 1737400035);

    try expect(second_contact.created_at == 1737401036);
    try expect(std.mem.eql(u8, second_contact.full_name, "jane doe"));
    try expect(second_contact.frequency_days == 14);
    try expect(second_contact.contacted_at == null);
}

test "ContactList.format" {
    const alloc = std.testing.allocator;

    var contact = Contact.init(alloc);
    contact.created_at = 1737401035;
    var full_name = std.ArrayList(u8).init(alloc);
    try full_name.appendSlice("john doe");
    contact.full_name = full_name.items;
    contact.frequency_days = 30;
    contact.contacted_at = 1737400035;

    var other_contact = Contact.init(alloc);
    other_contact.created_at = 1737401036;
    var other_full_name = std.ArrayList(u8).init(alloc);
    try other_full_name.appendSlice("jane doe");
    other_contact.full_name = other_full_name.items;
    other_contact.frequency_days = 14;
    other_contact.contacted_at = null;

    var contact_list = ContactList.init(alloc);
    defer contact_list.deinit();
    try contact_list.contacts.append(contact);
    try contact_list.contacts.append(other_contact);

    const contact_list_fmt_str = try std.fmt.allocPrint(alloc, "{s}", .{contact_list});
    defer alloc.free(contact_list_fmt_str);

    try std.testing.expect(std.mem.eql(u8, contact_list_fmt_str,
        \\Contact(
        \\  created_at: 1737401035,
        \\  full_name: john doe,
        \\  frequency_days: 30,
        \\  contacted_at: 1737400035)
        \\
        \\Contact(
        \\  created_at: 1737401036,
        \\  full_name: jane doe,
        \\  frequency_days: 14,
        \\  contacted_at: null)
    ));
}
