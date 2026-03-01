const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Runs the test suite");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const emu_mod = b.addModule("emulator", .{
        .root_source_file = b.path("src/emulator.zig"),
        .optimize = optimize,
    });

    const host_exe = b.addExecutable(.{
        .name = "emulator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main-desktop.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "emulator", .module = emu_mod },
            },
        }),
    });
    b.installArtifact(host_exe);

    const wasm_exe = b.addExecutable(.{
        .name = "emulator-web",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main-web.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = optimize,
            .imports = &.{
                .{ .name = "emulator", .module = emu_mod },
            },
        }),
    });
    wasm_exe.entry = .disabled;
    b.installArtifact(wasm_exe);

    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/testsuite.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "emulator", .module = emu_mod },
            },
        }),
    });

    const test_run = b.addRunArtifact(test_exe);

    test_step.dependOn(&test_run.step);
}
