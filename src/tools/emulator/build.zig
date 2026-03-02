const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Runs the test suite");
    const debug_step = b.step("debug", "Installs all intermediate files of the test suite");

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

    const extract_header_comment_exe = b.addExecutable(.{
        .name = "extract-header-comment",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/extract-json.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });

    for (asm_tests) |t| {
        const asm_step = addAsmTestSteps(b, t, extract_header_comment_exe, runner_exe, debug_step);
        test_step.dependOn(asm_step);
    }
}

// ===========================================================================
// Assembly test table
// ===========================================================================

const rv32imc: std.Target.Query = .{
    .cpu_arch = .riscv32,
    .abi = .ilp32,
    .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
    .cpu_features_add = std.Target.riscv.featureSet(&.{
        .i, .m, .c,
    }),
};

const rv32im: std.Target.Query = .{
    .cpu_arch = .riscv32,
    .abi = .ilp32,
    .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
    .cpu_features_add = std.Target.riscv.featureSet(&.{
        .i, .m,
    }),
};

const rv32i: std.Target.Query = .{
    .cpu_arch = .riscv32,
    .abi = .ilp32,
    .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
    .cpu_features_add = std.Target.riscv.featureSet(&.{
        .i,
    }),
};

const AsmTest = struct {
    path: []const u8,
    target: std.Target.Query,
};

const asm_tests = [_]AsmTest{
    // RV32I core instruction set:
    .{ .path = "tests/behaviour/cpu/rv32i/test_addi.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_alu.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_bltu.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_branch.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_halfword.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_jal.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_lui_auipc.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_mem.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_shifts.s", .target = rv32i },
    .{ .path = "tests/behaviour/cpu/rv32i/test_slti.s", .target = rv32i },

    // M extension:
    .{ .path = "tests/behaviour/cpu/rv32im/test_div_edge.s", .target = rv32im },
    .{ .path = "tests/behaviour/cpu/rv32im/test_mul.s", .target = rv32im },
    .{ .path = "tests/behaviour/cpu/rv32im/test_mulh.s", .target = rv32im },

    // C extension:
    .{ .path = "tests/behaviour/cpu/rv32ic/test_compressed.s", .target = rv32imc },

    // Debug peripheral:
    .{ .path = "tests/behaviour/peripheral/test_debug.s", .target = rv32imc },
};

/// Wire up the assemble → objcopy → run pipeline for a single test.
/// Returns a pointer to the final step so the caller can add it as a
/// dependency of the top-level test step.
fn addAsmTestSteps(
    b: *std.Build,
    testcase: AsmTest,
    extract_header_comment_exe: *std.Build.Step.Compile,
    runner_exe: *std.Build.Step.Compile,
    debug_step: *std.Build.Step,
) *std.Build.Step {
    const name_with_ext = std.fs.path.basename(testcase.path);
    const name = name_with_ext[0 .. name_with_ext.len - std.fs.path.extension(name_with_ext).len];

    const s_file = b.path(testcase.path);

    // Step 1: assemble .s → .elf
    const target = b.resolveTargetQuery(testcase.target);
    const assemble = b.addExecutable(.{
        .name = name,
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = null,
            .target = target,
            .optimize = .ReleaseFast,
            .no_builtin = true,
            .link_libc = false,
            .link_libcpp = false,
            .sanitize_c = .off,
            .sanitize_thread = false,
            .stack_check = false,
            .stack_protector = false,
            .unwind_tables = .none,
            .red_zone = false,
            .single_threaded = true,
            .pic = false,
        }),
    });
    assemble.setLinkerScript(b.path("tests/behaviour/linker.ld"));
    assemble.root_module.addAssemblyFile(s_file);

    const elf_file = assemble.getEmittedBin();

    // Step 2: convert .elf → .bin
    const objcopy_step = b.addObjCopy(
        elf_file,
        .{
            .format = .bin,
        },
    );

    const bin_file = objcopy_step.getOutput();

    // Step 3: Extract header comment so we have the JSON data
    const extract_json_file = b.addRunArtifact(extract_header_comment_exe);
    extract_json_file.setStdIn(.{ .lazy_path = s_file });
    const json_file = extract_json_file.captureStdOut();

    // Step 4: run test-runner <rom.bin> <test.json>
    const run_cmd = b.addRunArtifact(runner_exe);
    run_cmd.addFileArg(bin_file);
    run_cmd.addFileArg(json_file);

    // Optional: Install debug files:
    const dir: std.Build.InstallDir = .{
        .custom = b.fmt("tests/behaviour/{s}", .{name}),
    };

    debug_step.dependOn(&b.addInstallFileWithDir(elf_file, dir, b.fmt("{s}.elf", .{name})).step);
    debug_step.dependOn(&b.addInstallFileWithDir(bin_file, dir, b.fmt("{s}.bin", .{name})).step);
    debug_step.dependOn(&b.addInstallFileWithDir(json_file, dir, b.fmt("{s}.json", .{name})).step);

    return &run_cmd.step;
}
