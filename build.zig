const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // root.zig is not used in our project.
    // const lib = b.addStaticLibrary(.{
    //     .name = "dont-be-strangers",
    //     // In this case the main source file is merely a path, however, in more
    //     // complicated build scripts, this could be a generated file.
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // // This declares intent for the library to be installed into the standard
    // // location when the user invokes the "install" step (the default step when
    // // running `zig build`).
    // b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "dontbestrangers",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // See https://ziglang.org/download/0.14.0/release-notes.html#Build-System
    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;

    const github_client_id = b.option([]const u8, "github-client-id", "Github app registered client ID");
    const github_client_secret = b.option([]const u8, "github-client-secret", "Github app registered client secret");

    // Taken from ziglang/zig std/tracy.zig
    const tracy = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");
    const tracy_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);
    const tracy_allocation = b.option(bool, "tracy-allocation", "Include allocation information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);
    const tracy_callstack_depth: u32 = b.option(u32, "tracy-callstack-depth", "Declare callstack depth for Tracy data. Does nothing if -Dtracy_callstack is not provided") orelse 10;

    const options = b.addOptions();
    options.addOption(?[]const u8, "github_client_id", github_client_id);
    options.addOption(?[]const u8, "github_client_secret", github_client_secret);

    options.addOption(bool, "enable_tracy", tracy != null);
    options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
    options.addOption(bool, "enable_tracy_allocation", tracy_allocation);
    options.addOption(u32, "tracy_callstack_depth", tracy_callstack_depth);
    if (tracy) |tracy_path| {
        const client_cpp = b.pathJoin(
            &[_][]const u8{ tracy_path, "public", "TracyClient.cpp" },
        );

        // On mingw, we need to opt into windows 7+ to get some features required by tracy.
        const tracy_c_flags: []const []const u8 = if (target.result.os.tag == .windows and target.result.abi == .gnu)
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "-D_WIN32_WINNT=0x601" }
        else
            &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.root_module.addIncludePath(.{ .cwd_relative = tracy_path });
        exe.root_module.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });
        // if (!enable_llvm) {
        exe.root_module.linkSystemLibrary("c++", .{ .use_pkg_config = .no });
        // }
        exe.root_module.link_libc = true;

        if (target.result.os.tag == .windows) {
            exe.root_module.linkSystemLibrary("dbghelp", .{});
            exe.root_module.linkSystemLibrary("ws2_32", .{});
        }
    }

    exe.root_module.addOptions("config", options);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);
    }

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // TEST
    {
        // Similar to creating the run step earlier, this exposes a `test` step to
        // the `zig build --help` menu, providing a way for the user to request
        // running the unit tests.
        const test_step = b.step("test", "Run unit tests");
        //
        // root.zig is not used in our project.
        // // Creates a step for unit testing. This only builds the test executable
        // // but does not run it.
        // const lib_unit_tests = b.addTest(.{
        //     .root_source_file = b.path("src/root.zig"),
        //     .target = target,
        //     .optimize = optimize,
        // });
        //
        // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

        const exe_unit_tests = b.addTest(.{
            // .root_source_file = b.path("src/main.zig"),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/test.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

        // root.zig is not used in our project.
        // test_step.dependOn(&run_lib_unit_tests.step);
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}
