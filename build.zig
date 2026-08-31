const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    const hako = b.addExecutable(.{
        .name = "hako",
        .root_module = mod,
    });
    b.installArtifact(hako);

    if (optimize == .Debug) {
        const watchfd = b.addExecutable(.{
            .name = "watchfd",
            .root_module = mod,
        });

        const dumpfd = b.addExecutable(.{
            .name = "dumpfd",
            .root_module = mod,
        });
        const listen = b.addExecutable(.{
            .name = "listen",
            .root_module = mod,
        });
        const pwait = b.addExecutable(.{
            .name = "pwait",
            .root_module = mod,
        });
        const when = b.addExecutable(.{
            .name = "when",
            .root_module = mod,
        });
        const ports = b.addExecutable(.{
            .name = "ports",
            .root_module = mod,
        });
        b.installArtifact(watchfd);
        b.installArtifact(dumpfd);
        b.installArtifact(listen);
        b.installArtifact(pwait);
        b.installArtifact(when);
        b.installArtifact(ports);
    }

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(hako);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = hako.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
