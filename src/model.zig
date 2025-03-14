const std = @import("std");
const tracy = @import("tracy.zig");
const assert = std.debug.assert;

const DB_DIR = "resource/db";
const READ_FLAGS = std.fs.File.OpenFlags{ .mode = std.fs.File.OpenMode.read_only };
const WRITE_FLAGS = std.fs.File.OpenFlags{ .mode = std.fs.File.OpenMode.write_only };

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

pub const Contact = struct {
    alloc: std.mem.Allocator,
    created_at: u32,
    full_name: []u8,
    frequency_days: u16,
    due_at: u32,

    pub const header_line = "created_at,full_name,frequency_days,due_at";

    pub fn init(alloc: std.mem.Allocator) Contact {
        return .{
            .alloc = alloc,
            .created_at = undefined,
            .full_name = undefined,
            .frequency_days = undefined,
            .due_at = undefined,
        };
    }

    pub fn setDueAt(self: *Contact, maybe_contacted_at_seconds: ?u32) void {
        const contacted_at_seconds = if (maybe_contacted_at_seconds) |x| x else blk: {
            const now_seconds = std.time.timestamp();
            assert(now_seconds > 0);
            const contacted_at: u32 = @intCast(now_seconds);
            break :blk contacted_at;
        };

        const due_at: u32 = contacted_at_seconds + @as(u32, self.frequency_days) * std.time.s_per_day;
        self.due_at = due_at;
    }

    pub fn fromCsvLine(alloc: std.mem.Allocator, reader: anytype) !Contact {
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

        var contact = Contact.init(alloc);

        contact.created_at = created_at;

        const full_name_value = parsedValue(reader.readUntilDelimiterOrEof(&buf, ','));
        const full_name = try alloc.alloc(u8, full_name_value.len);
        errdefer alloc.free(full_name);
        @memcpy(full_name, full_name_value);
        contact.full_name = full_name;

        const frequency_days = parsedValue(reader.readUntilDelimiterOrEof(&buf, ','));
        contact.frequency_days = try std.fmt.parseInt(u16, frequency_days, 10);

        const due_at = parsedValue(reader.readUntilDelimiterOrEof(&buf, '\n'));
        contact.due_at = try std.fmt.parseInt(u32, due_at, 10);

        return contact;
    }

    pub fn deinit(self: *Contact) void {
        self.alloc.free(self.full_name);
    }

    pub fn format(
        self: Contact,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;

        if (std.mem.eql(u8, "csv", fmt)) {
            try writer.print("{d},{s},{d},{d}\n", .{
                self.created_at,
                self.full_name,
                self.frequency_days,
                self.due_at,
            });
        } else {
            try writer.print(
                \\Contact(
                \\  created_at: {d},
                \\  full_name: {s},
                \\  frequency_days: {d},
                \\  due_at: {d})
                \\
            , .{
                self.created_at,
                self.full_name,
                self.frequency_days,
                self.due_at,
            });
        }
    }
};

test "Contact.setDueAt" {
    const csv_line = "1737401035,john doe,30,1737400035\n";
    var stream = std.io.fixedBufferStream(csv_line);
    const reader = stream.reader();

    var contact = try Contact.fromCsvLine(std.testing.allocator, reader);
    defer contact.deinit();

    const contacted_at_seconds = 1737400030;
    contact.setDueAt(contacted_at_seconds);

    const expected_due_at = contacted_at_seconds + 30 * std.time.s_per_day;
    try std.testing.expectEqual(expected_due_at, contact.due_at);
}

test Contact {
    const alloc = std.testing.allocator;
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;

    const csv_line = "1737401035,john doe,30,1737400035\n";
    var stream = std.io.fixedBufferStream(csv_line);
    const reader = stream.reader();

    var contact = try Contact.fromCsvLine(alloc, reader);
    defer contact.deinit();

    {
        try expectEqual(1737401035, contact.created_at);
        try expectEqualStrings("john doe", contact.full_name);
        try expectEqual(30, contact.frequency_days);
        try expectEqual(1737400035, contact.due_at);
    }

    {
        const to_csv_line = try std.fmt.allocPrint(alloc, "{s}", .{contact});
        defer alloc.free(to_csv_line);
        try expectEqualStrings(
            \\Contact(
            \\  created_at: 1737401035,
            \\  full_name: john doe,
            \\  frequency_days: 30,
            \\  due_at: 1737400035)
            \\
        , to_csv_line);
    }

    {
        const to_csv_line = try std.fmt.allocPrint(alloc, "{csv}", .{contact});
        defer alloc.free(to_csv_line);
        try expectEqualStrings("1737401035,john doe,30,1737400035\n", to_csv_line);
    }

    {
        const contacted_at_seconds = 1737400030;
        contact.setDueAt(contacted_at_seconds);
        const expected_due_at = contacted_at_seconds + 30 * std.time.s_per_day;
        try expectEqual(expected_due_at, contact.due_at);

        const to_csv_line = try std.fmt.allocPrint(alloc, "{csv}", .{contact});
        defer alloc.free(to_csv_line);
        try expectEqualStrings("1737401035,john doe,30,1739992030\n", to_csv_line);
    }
}

pub const ContactList = struct {
    alloc: std.mem.Allocator,
    map: std.AutoHashMap(u32, Contact),

    fn fromCsvReader(alloc: std.mem.Allocator, reader: anytype, has_headers: bool) !ContactList {
        var map = std.AutoHashMap(u32, Contact).init(alloc);
        errdefer map.deinit();

        // Skip headers
        if (has_headers) {
            try reader.skipUntilDelimiterOrEof('\n');
        }
        while (true) {
            var contact = Contact.fromCsvLine(alloc, reader) catch break;
            errdefer contact.deinit();
            try map.put(contact.created_at, contact);
        }

        return ContactList{
            .alloc = alloc,
            .map = map,
        };
    }

    pub fn fromCsvFile(alloc: std.mem.Allocator, id: []const u8, has_headers: bool) !ContactList {
        const tr = tracy.trace(@src());
        defer tr.end();

        const db_path = try std.fmt.allocPrint(
            alloc,
            "{s}/{s}.csv",
            .{ DB_DIR, id },
        );
        defer alloc.free(db_path);

        const db_file = std.fs.cwd().openFile(db_path, READ_FLAGS) catch |err| return switch (err) {
            error.FileNotFound => error.ContactListNotFound,
            else => err,
        };
        defer db_file.close();

        return try ContactList.fromCsvReader(alloc, db_file.reader(), has_headers);
    }

    pub fn toCsvFile(self: *ContactList, id: []const u8, with_headers: bool) !void {
        const db_path = try std.fmt.allocPrint(
            self.alloc,
            "{s}/{s}.csv",
            .{ DB_DIR, id },
        );
        defer self.alloc.free(db_path);

        const db_file = std.fs.cwd().openFile(db_path, WRITE_FLAGS) catch |err| return switch (err) {
            error.FileNotFound => error.ContactListNotFound,
            else => err,
        };
        defer db_file.close();

        const file_content = try if (with_headers) blk: {
            break :blk std.fmt.allocPrint(self.alloc, Contact.header_line ++ "\n{csv}\n", .{self});
        } else std.fmt.allocPrint(self.alloc, "{csv}\n", .{self});
        defer self.alloc.free(file_content);

        // TODO: Research "best" way to write.
        try db_file.writeAll(file_content);
    }

    pub fn getContact(self: *ContactList, key: u32) ?Contact {
        return self.map.get(key);
    }

    pub fn getContactPtr(self: *ContactList, key: u32) ?*Contact {
        return if (self.map.getEntry(key)) |entry| entry.value_ptr else null;
    }

    pub fn deinit(self: *ContactList) void {
        var entry_iter = self.map.iterator();
        while (entry_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.map.deinit();
    }

    pub fn format(
        self: ContactList,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;

        if (std.mem.eql(u8, "csv", fmt)) {
            var entry_iter = self.map.iterator();
            while (entry_iter.next()) |entry| {
                try writer.print("{csv}", .{entry.value_ptr.*});
            }
        } else {
            var entry_iter = self.map.iterator();
            while (entry_iter.next()) |entry| {
                try writer.print("{s}\n", .{entry.value_ptr.*});
            }
        }
    }
};

test ContactList {
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;
    const alloc = std.testing.allocator;

    const test_db = try std.fs.cwd().openFile("resource/db/test_db.csv", READ_FLAGS);
    defer test_db.close();

    var contact_list = try ContactList.fromCsvReader(alloc, test_db.reader(), true);
    defer contact_list.deinit();

    {
        const first_contact = contact_list.getContact(1737401035).?;
        const second_contact = contact_list.getContact(1737401036).?;

        try expectEqual(1737401035, first_contact.created_at);
        try expectEqualStrings("john doe", first_contact.full_name);
        try expectEqual(30, first_contact.frequency_days);
        try expectEqual(1737400035, first_contact.due_at);

        try expectEqual(1737401036, second_contact.created_at);
        try expectEqualStrings("jane doe", second_contact.full_name);
        try expectEqual(14, second_contact.frequency_days);
        try expectEqual(1737400036, second_contact.due_at);
    }

    // Test format
    {
        const contact_list_fmt_str = try std.fmt.allocPrint(alloc, "{s}", .{contact_list});
        defer alloc.free(contact_list_fmt_str);

        // contact_list uses a hash map internally. The order of the contact list iteration is
        // not guaranteed. Below is a hacky way to check the format.
        const expected_either =
            \\Contact(
            \\  created_at: 1737401035,
            \\  full_name: john doe,
            \\  frequency_days: 30,
            \\  due_at: 1737400035)
            \\
            \\Contact(
            \\  created_at: 1737401036,
            \\  full_name: jane doe,
            \\  frequency_days: 14,
            \\  due_at: 1737400036)
            \\
            \\
        ;
        const expected_or =
            \\Contact(
            \\  created_at: 1737401036,
            \\  full_name: jane doe,
            \\  frequency_days: 14,
            \\  due_at: 1737400036)
            \\
            \\Contact(
            \\  created_at: 1737401035,
            \\  full_name: john doe,
            \\  frequency_days: 30,
            \\  due_at: 1737400035)
            \\
            \\
        ;
        const expected_str = if (std.mem.eql(u8, expected_either, contact_list_fmt_str)) expected_either else expected_or;
        try std.testing.expectEqualStrings(expected_str, contact_list_fmt_str);
    }

    // Test format csv
    {
        const contact_list_fmt_str = try std.fmt.allocPrint(alloc, "{csv}", .{contact_list});
        defer alloc.free(contact_list_fmt_str);

        // contact_list uses a hash map internally. The order of the contact list iteration is
        // not guaranteed. Below is a hacky way to check the format.
        const expected_either =
            \\1737401035,john doe,30,1737400035
            \\1737401036,jane doe,14,1737400036
            \\
        ;
        const expected_or =
            \\1737401036,jane doe,14,1737400036
            \\1737401035,john doe,30,1737400035
            \\
        ;
        const expected_str = if (std.mem.eql(u8, expected_either, contact_list_fmt_str)) expected_either else expected_or;
        try std.testing.expectEqualStrings(expected_str, contact_list_fmt_str);
    }

    // Test updating a contact.
    {
        var first_contact_ptr = contact_list.getContactPtr(1737401035).?;
        try expectEqual(*Contact, @TypeOf(first_contact_ptr));

        const original_due_at = first_contact_ptr.due_at;
        const contacted_at_seconds = 1737400030;
        first_contact_ptr.setDueAt(contacted_at_seconds);
        const expected_due_at = contacted_at_seconds + 30 * std.time.s_per_day;
        try expectEqual(expected_due_at, first_contact_ptr.due_at);
        try expectEqual(first_contact_ptr.*, contact_list.getContact(1737401035).?);

        try contact_list.toCsvFile("test_db", true);

        // Restore contact list.
        first_contact_ptr.due_at = original_due_at; // 1737400035
        try expectEqual(1737400035, first_contact_ptr.due_at);
        try contact_list.toCsvFile("test_db", true);
    }
}
