const std = @import("std");
const zon: Zon = @import("build.zig.zon");

const Zon = struct {
    name: @TypeOf(.enum_literal),
    fingerprint: u64,
    version: []const u8,
    minimum_zig_version: []const u8,
    dependencies: struct {},
    paths: []const []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_name = @tagName(zon.name);

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const wf = b.addWriteFiles();
    const exe_path = b.fmt("{s}/{s}", .{ exe_name, exe.out_filename });
    const exe_dir = b.fmt("{s}/", .{exe_name});
    const resource_dir = b.fmt("{s}/resource", .{exe_name});
    _ = wf.addCopyFile(exe.getEmittedBin(), exe_path);
    _ = wf.addCopyDirectory(.{ .cwd_relative = "resource" }, resource_dir, .{});

    const tar = b.addSystemCommand(&.{ "tar", "czf" });
    tar.setCwd(wf.getDirectory());
    const tar_out_name = b.fmt("{s}.tar.gz", .{exe_name});
    const out_file = tar.addOutputFileArg(tar_out_name);
    tar.addArgs(&.{exe_dir});

    const install_tar = b.addInstallFileWithDir(out_file, .prefix, tar_out_name);
    b.getInstallStep().dependOn(&install_tar.step);

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

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        b.installArtifact(exe);
    }

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // TEST
    {
        const test_step = b.step("test", "Run unit tests");

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
