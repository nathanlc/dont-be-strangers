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
    scratch,
    contacts,
    server,
    // pub fn helpMessage(self: Action) []const u8 {
    //     switch (self) {
    //         .help => return
    //         \\dont-be-strangers help...
    //         \\  blablabla
    //         ,
    //         .scratch => return
    //         \\dont-be-strangers scratch help...
    //         \\  blablabla
    //         ,
    //         .contacts => return
    //         \\dont-be-strangers contacts help...
    //         \\  blablabla
    //         ,
    //         .server => return
    //         \\dont-be-strangers server help...
    //         \\  blablabla
    //         ,
    //     }
    // }
};

const ContactsOptions = struct {
    id: i64,
};

pub const Action = union(ActionTag) {
    help: void,
    scratch: void,
    contacts: ContactsOptions,
    server: void,

    pub fn fromArgs(arg_iterator: anytype) !Action {
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
            .scratch => ActionTag.scratch,
            .server => ActionTag.server,
            .contacts => try Action.fromContactsArgs(&arg_iterator),
        };
    }

    fn fromContactsArgs(arg_iterator_ptr: anytype) !Action {
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

            const contact_options = ContactsOptions{ .id = try std.fmt.parseInt(i64, option_value, 10) };
            return Action{ .contacts = contact_options };
        } else {
            logErr("Invalid option {s}, expected: --key=value", .{option});
            return error.InvalidOption;
        }
    }
};

const Error = error{
    InvalidAction,
    MissingAction,
    InvalidOption,
    MissingOption,
};

pub fn runHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("dont-be-strangers help blablabla\n", .{});
}

pub fn runContactsList(alloc: std.mem.Allocator, user_id: i64) !void {
    const stdout = std.io.getStdOut().writer();

    const sqlite = try model.Sqlite.open(model.Sqlite.Env.prod);
    defer sqlite.deinit();
    var contact_list = try sqlite.selectContactsByUser(alloc, user_id);
    defer contact_list.deinit();

    try stdout.print("User ID: {d}\n\n", .{user_id});
    try contact_list.format("{s}", .{}, stdout);
    try stdout.print("\n", .{});
}

test "Action.fromArgs with contacts action" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts --id=abc123",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.InvalidCharacter, Action.fromArgs(&arg_iterator));
}

test "Action.fromArgs with contacts missing option" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.MissingOption, Action.fromArgs(&arg_iterator));
}

test "Action.fromArgs with contacts incorrect option format" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts -i abc123",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.InvalidOption, Action.fromArgs(&arg_iterator));
}

test "Action.fromArgs with contacts invalid option" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable contacts --bob=abc123",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.InvalidOption, Action.fromArgs(&arg_iterator));
}

test "Action.fromArgs with missing action" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.MissingAction, Action.fromArgs(&arg_iterator));
}

test "Action.fromArgs with invalid action" {
    const allocator = std.testing.allocator;

    var arg_iterator = try std.process.ArgIteratorGeneral(.{}).init(
        allocator,
        "executable invalid_action",
    );
    defer arg_iterator.deinit();

    try std.testing.expectError(error.InvalidAction, Action.fromArgs(&arg_iterator));
}
