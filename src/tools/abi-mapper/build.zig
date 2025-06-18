const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
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

    // const test_step = b.step("test", "Runs the test suite");

    // const cc = Converter{
    //     .b = b,
    //     .executable = python_wrapper,
    // };

    // const json = cc.get_json_dump(
    //     b.path("tests/coverage-ids.json"),
    //     b.path("tests/coverage.zabi"),
    // );

    // const test_exe = b.addTest(.{
    //     .root_source_file = abi_schema_mod.root_source_file.?,
    //     .target = b.graph.host,
    //     .optimize = .Debug,
    // });

    // test_exe.root_module.addAnonymousImport("coverage.json", .{
    //     .root_source_file = json,
    // });

    // const run_test = b.addRunArtifact(test_exe);

    // test_step.dependOn(&run_test.step);

    // const json_step = b.step("json", "Emit the JSON dump of test abi");

    // json_step.dependOn(&b.addInstallFile(json, "abi-test.json").step);
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
