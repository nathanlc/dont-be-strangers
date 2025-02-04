const std = @import("std");
const cli = @import("cli.zig");
const web = @import("web.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(general_purpose_allocator.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    const action = cli.parseArgs(allocator, &arg_iterator) catch |err| {
        std.log.err("Error while parsing args: {!}", .{err});
        try cli.runHelp();
        std.process.exit(1);
    };
    defer action.deinit();

    switch (action) {
        .help => try cli.runHelp(),
        .contacts => |options| try cli.runContactsList(allocator, options.id),
        .server => try web.runServer(),
    }
}
