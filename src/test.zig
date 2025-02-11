comptime {
    _ = @import("root.zig");
    _ = @import("main.zig");
    _ = @import("cli.zig");
    _ = @import("web.zig");
    _ = @import("github.zig");
    _ = @import("model.zig");
}

pub const Config = struct {
    github_client_id: ?[]const u8 = "test_github_client_id",
    github_client_secret: ?[]const u8 = "test_github_client_secret",
};
