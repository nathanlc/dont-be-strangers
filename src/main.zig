const std = @import("std");
const cli = @import("cli.zig");
const web = @import("web.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_purpose_allocator.allocator();

    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    const action = cli.parseArgs(&arg_iterator) catch {
        try cli.runHelp();
        std.process.exit(1);
    };

    switch (action) {
        .help => try cli.runHelp(),
        .list => try cli.runListContacts(allocator),
        .server => try web.runServer(),
    }
}
