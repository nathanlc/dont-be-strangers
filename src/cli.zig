const std = @import("std");
const builtin = @import("builtin");
const model = @import("model.zig");

const logger = std.log.scoped(.cli);

fn logErr(comptime fmt: []const u8, args: anytype) void {
    if (!builtin.is_test) {
        logger.err(fmt, args);
    } else {
        logger.info(fmt, args);
    }
}

const ActionTag = enum {
    help,
    contacts,
    server,
    // pub fn helpMessage(self: Action) []const u8 {
    //     switch (self) {
    //         .help => return
    //         \\keep-in-touch-backend help...
    //         \\  blablabla
    //         ,
    //         .list => return
    //         \\keep-in-touch-backend list help...
    //         \\  blablabla
    //         ,
    //         .server => return
    //         \\keep-in-touch-backend server help...
    //         \\  blablabla
    //         ,
    //     }
    // }
};

const ContactsOptions = struct {
    id: []const u8,
};

const Action = union(ActionTag) {
    help: void,
    contacts: ContactsOptions,
    server: void,
};

const Error = error{
    InvalidAction,
    MissingAction,
    InvalidOption,
    MissingOption,
};

fn parseContactsArgs(arena_alloc: std.mem.Allocator, arg_iterator_ptr: anytype) !Action {
    const option = if (arg_iterator_ptr.*.next()) |arg| arg else {
        return error.MissingOption;
    };
    if (std.mem.eql(u8, "", option)) {
        return error.MissingOption;
    }

    if (!std.mem.startsWith(u8, option, "--")) {
        logErr("Invalid option {s}, expected to start with `--`", .{option});
        return error.InvalidOption;
    }

    if (std.mem.indexOf(u8, option, "=")) |index| {
        const option_key = option[2..index];
        const option_value = option[index + 1 ..];

        if (!std.mem.eql(u8, "id", option_key)) {
            logErr("Invalid option {s}, expected `--id`", .{option});
            return error.InvalidOption;
        }

        // const key = try arena_alloc.alloc(u8, option_key.len);
        // errdefer arena_alloc.free(key);
        // @memcpy(key, option_key);
        const value = try arena_alloc.alloc(u8, option_value.len);
        errdefer arena_alloc.free(value);
        @memcpy(value, option_value);

        return Action{ .contacts = ContactsOptions{ .id = value } };
    } else {
        logErr("Invalid option {s}, expected: --key=value", .{option});
        return error.InvalidOption;
    }
}

// Using anytype instead of std.process.ArgIterator to be able to test with ArgIteratorGeneral.
// alloc is expected to be an arena allocator for the memory to be freed.
pub fn parseArgs(arena_alloc: std.mem.Allocator, arg_iterator: anytype) !Action {
    if (arg_iterator.next() == null) {
        return error.MissingAction;
    }

    const action_arg = if (arg_iterator.next()) |arg| arg else {
        return error.MissingAction;
    };
    const action_tag = if (std.meta.stringToEnum(ActionTag, action_arg)) |tag| tag else {
        return error.InvalidAction;
    };

    return switch (action_tag) {
        .help => ActionTag.help,
        .server => ActionTag.server,
        .contacts => try parseContactsArgs(arena_alloc, &arg_iterator),
    };
}

pub fn runHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("keep-in-touch-backend help blablabla\n", .{});
}

pub fn runContactsList(allocator: std.mem.Allocator, id: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    var contact_list = model.ContactList.fromCsvFile(allocator, id, true) catch |err| {
        switch (err) {
            error.ContactListNotFound => {
                try stdout.print("No contact list found for ID: {s}\n", .{id});
                std.process.exit(1);
                return err;
            },
            else => return err,
        }
    };
    defer contact_list.deinit();

    try stdout.print("ID: {s}\n\n", .{id});
    try contact_list.format("{s}", .{}, stdout);
    try stdout.print("\n", .{});
}

test "parseArgs with contacts action" {
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts --id=abc123",
    );
    defer arg_iterator.deinit();

    try std.testing.expect(try parseArgs(allocator, &arg_iterator) == Action.contacts);
}

test "parseArgs with contacts missing option" {
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.MissingOption, parseArgs(allocator, &arg_iterator));
}

test "parseArgs with contacts incorrect option format" {
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts -i abc123",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.InvalidOption, parseArgs(allocator, &arg_iterator));
}

test "parseArgs with contacts invalid option" {
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts --bob=abc123",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.InvalidOption, parseArgs(allocator, &arg_iterator));
}

test "parseArgs with missing action" {
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable",
    );
    defer arg_iterator.deinit();

    try std.testing.expect(parseArgs(allocator, &arg_iterator) == error.MissingAction);
}

test "parseArgs with invalid action" {
    const testing_allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(testing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable invalid_action",
    );
    defer arg_iterator.deinit();

    try std.testing.expect(parseArgs(allocator, &arg_iterator) == error.InvalidAction);
}
