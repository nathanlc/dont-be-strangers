const std = @import("std");

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
