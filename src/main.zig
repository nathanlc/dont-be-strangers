const std = @import("std");
const cli = @import("cli.zig");
const web = @import("web.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.DebugAllocator(.{}).init;
    var arena = std.heap.ArenaAllocator.init(general_purpose_allocator.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var arg_iterator = try std.process.argsWithAllocator(allocator);
    defer arg_iterator.deinit();

    const action = cli.Action.fromArgs(&arg_iterator) catch |err| {
        std.log.err("Error while parsing args: {!}", .{err});
        try cli.runHelp();
        std.process.exit(1);
    };

    switch (action) {
        .help => try cli.runHelp(),
        .scratch => try web.runScratch(allocator),
        .contacts => |options| try cli.runContactsList(allocator, options.id),
        .server => try web.runServer(),
    }
}
