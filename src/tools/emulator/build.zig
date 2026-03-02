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

    // -----------------------------------------------------------------------
    // Zig-native unit tests (testsuite.zig with pre-assembled .bin files)
    // -----------------------------------------------------------------------
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

    // -----------------------------------------------------------------------
    // Assembly-based integration tests: assemble .s → .elf → .bin at build
    // time, then run each through the test-runner with its JSON description.
    // Only enabled when a RISC-V cross-compiler is found on PATH.
    // -----------------------------------------------------------------------
    const gcc = b.findProgram(
        &.{ "riscv64-unknown-elf-gcc", "riscv32-unknown-elf-gcc", "riscv64-linux-gnu-gcc" },
        &.{},
    ) catch null;
    const objcopy = b.findProgram(
        &.{ "riscv64-unknown-elf-objcopy", "riscv32-unknown-elf-objcopy", "riscv64-linux-gnu-objcopy" },
        &.{},
    ) catch null;

    if (gcc != null and objcopy != null) {
        const runner_exe = b.addExecutable(.{
            .name = "test-runner",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/test-runner.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "emulator", .module = emu_mod },
                },
            }),
        });

        for (asm_tests) |t| {
            const asm_step = addAsmTestSteps(b, t, gcc.?, objcopy.?, runner_exe);
            test_step.dependOn(asm_step);
        }
    } else {
        // Emit a message during graph creation so the user knows why the
        // assembly tests are skipped.
        const note = b.addSystemCommand(&.{
            "echo",
            "NOTE: RISC-V cross-compiler not found; skipping assembly integration tests.",
        });
        test_step.dependOn(&note.step);
    }
}

// ===========================================================================
// Assembly test table
// ===========================================================================

const AsmTest = struct {
    /// Base name without extension (e.g. "test_addi")
    name: []const u8,
    /// -march flag for gcc (e.g. "rv32imc", "rv32im", "rv32i")
    march: []const u8,
};

const asm_tests = [_]AsmTest{
    .{ .name = "test_addi", .march = "rv32imc" },
    .{ .name = "test_alu", .march = "rv32imc" },
    .{ .name = "test_lui_auipc", .march = "rv32imc" },
    .{ .name = "test_branch", .march = "rv32imc" },
    .{ .name = "test_bltu", .march = "rv32i" },
    .{ .name = "test_jal", .march = "rv32imc" },
    .{ .name = "test_shifts", .march = "rv32imc" },
    .{ .name = "test_slti", .march = "rv32i" },
    .{ .name = "test_mem", .march = "rv32imc" },
    .{ .name = "test_halfword", .march = "rv32i" },
    .{ .name = "test_mul", .march = "rv32imc" },
    .{ .name = "test_div_edge", .march = "rv32im" },
    .{ .name = "test_mulh", .march = "rv32im" },
    .{ .name = "test_compressed", .march = "rv32imc" },
    .{ .name = "test_debug", .march = "rv32imc" },
};

/// Wire up the assemble → objcopy → run pipeline for a single test.
/// Returns a pointer to the final step so the caller can add it as a
/// dependency of the top-level test step.
fn addAsmTestSteps(
    b: *std.Build,
    t: AsmTest,
    gcc: []const u8,
    objcopy: []const u8,
    runner_exe: *std.Build.Step.Compile,
) *std.Build.Step {
    const s_file = b.path(b.fmt("tests/{s}.s", .{t.name}));
    const json_file = b.path(b.fmt("tests/{s}.json", .{t.name}));

    // Step 1: assemble .s → .elf
    const asm_cmd = b.addSystemCommand(&.{
        gcc,
        "-nostdlib",
        "-Ttext=0x0",
        b.fmt("-march={s}", .{t.march}),
        "-mabi=ilp32",
        "-o",
    });
    const elf_file = asm_cmd.addOutputFileArg(b.fmt("{s}.elf", .{t.name}));
    asm_cmd.addFileArg(s_file);

    // Step 2: objcopy .elf → .bin
    const objcopy_cmd = b.addSystemCommand(&.{
        objcopy,
        "-O",
        "binary",
    });
    objcopy_cmd.addFileArg(elf_file);
    const bin_file = objcopy_cmd.addOutputFileArg(b.fmt("{s}.bin", .{t.name}));

    // Step 3: run test-runner <rom.bin> <test.json>
    const run_cmd = b.addRunArtifact(runner_exe);
    run_cmd.addFileArg(bin_file);
    run_cmd.addFileArg(json_file);

    return &run_cmd.step;
}
