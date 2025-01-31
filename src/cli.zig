const std = @import("std");
const model = @import("model.zig");

const READ_FLAGS = std.fs.File.OpenFlags{ .mode = std.fs.File.OpenMode.read_only };
const DB_PATH = "resources/db.csv";

const Action = enum {
    help,
    list,
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
};

const Error = error{
    InvalidAction,
    MissingAction,
};

// Using anytype instead of std.process.ArgIterator to be able to test with ArgIteratorGeneral.
pub fn parseArgs(arg_iterator: anytype) Error!Action {
    var i: usize = 0;
    while (arg_iterator.next()) |arg| : (i += 1) {
        if (i == 1) {
            if (std.meta.stringToEnum(Action, arg)) |action| {
                return action;
            } else {
                return error.InvalidAction;
            }
        }
    }

    return error.MissingAction;
}

pub fn runHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("keep-in-touch-backend help blablabla\n", .{});
}

pub fn runListContacts(allocator: std.mem.Allocator) !void {
    const db_file = try std.fs.cwd().openFile(DB_PATH, READ_FLAGS);
    defer db_file.close();

    var contact_list = try model.ContactList.fromCsvFile(allocator, db_file.reader(), true);
    defer contact_list.deinit();

    const stdout = std.io.getStdOut().writer();
    try contact_list.format("{s}", .{}, stdout);
    try stdout.print("\n", .{});
}

test "parseArgs with correct action" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable list",
    );
    defer arg_iterator.deinit();

    try std.testing.expect(try parseArgs(&arg_iterator) == Action.list);
}

test "parseArgs with missing action" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable",
    );
    defer arg_iterator.deinit();

    try std.testing.expect(parseArgs(&arg_iterator) == error.MissingAction);
}

test "parseArgs with invalid action" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable invalid_action",
    );
    defer arg_iterator.deinit();

    try std.testing.expect(parseArgs(&arg_iterator) == error.InvalidAction);
}
