const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Runs the test suite.");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });

    const args_dep = b.dependency("args", .{});
    const ptk_dep = b.dependency("ptk", .{});

    const args_mod = args_dep.module("args");
    const ptk_mod = ptk_dep.module("parser-toolkit");

    const abi_parser_mod = b.addModule("abi-parser", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/abi-parser.zig"),
        .imports = &.{
            .{ .name = "args", .module = args_mod },
            .{ .name = "ptk", .module = ptk_mod },
        },
    });

    const abi_parser_exe = b.addExecutable(.{
        .name = "abi-parser",
        .root_module = abi_parser_mod,
    });

    b.installArtifact(abi_parser_exe);

    const convert_test_file = b.addRunArtifact(abi_parser_exe);
    convert_test_file.addFileArg(b.path("tests/coverage.abi"));
    const output_file = convert_test_file.addPrefixedOutputFileArg("--output=", "coverage.json");

    test_step.dependOn(&b.addInstallFile(output_file, "test/coverage.json").step);
}

pub const Converter = struct {
    b: *std.Build,
    executable: *std.Build.Step.Compile,

    pub fn get_json_dump(cc: Converter, id_database: std.Build.LazyPath, input: std.Build.LazyPath) std.Build.LazyPath {
        const generate_json = cc.b.addRunArtifact(cc.executable);
        // TODO: generate_json.addPrefixedFileArg("--id-db=", id_database);
        _ = id_database;
        const abi_json = generate_json.addPrefixedOutputFileArg("--output=", "abi.json");
        generate_json.addFileArg(input);
        return abi_json;
    }
};

fn add_run_script(b: *std.Build, script: std.Build.LazyPath) *std.Build.Step.Run {
    const run = std.Build.Step.Run.create(b, "custom script");
    run.addFileArg(script);
    return run;
}

fn fail(comptime msg: []const u8, args: anytype) noreturn {
    std.debug.print("build configuration failed:\n" ++ msg ++ "\n", args);
    std.process.exit(1);
}
