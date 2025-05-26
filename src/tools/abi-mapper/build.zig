const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Runs the test suite");

    const abi_schema_mod = b.addModule("abi-schema", .{
        .root_source_file = b.path("src/json-schema.zig"),
    });

    const python3_dep = b.dependency("cpython", .{ .optimize = .ReleaseFast });
    const lark_dep = b.dependency("lark", .{});
    const caseconverter_dep = b.dependency("caseconverter", .{});

    const pydeps_folder = b.addWriteFiles();

    _ = pydeps_folder.addCopyDirectory(python3_dep.path("Lib"), ".", .{});
    _ = pydeps_folder.addCopyDirectory(lark_dep.path("lark"), "lark", .{});
    _ = pydeps_folder.addCopyDirectory(caseconverter_dep.path("caseconverter"), "caseconverter", .{});

    const python3_exe = python3_dep.artifact("cpython");

    const abi_mapper_py = b.path("src/abi-mapper.py");
    const grammar_file = b.path("src/minizig.lark");

    const python_wrapper_options = b.addOptions();
    python_wrapper_options.addOptionPath("interpreter", python3_exe.getEmittedBin());
    python_wrapper_options.addOptionPath("script", abi_mapper_py);
    python_wrapper_options.addOptionPath("python_prefix", pydeps_folder.getDirectory());

    const python_wrapper = b.addExecutable(.{
        .name = "abi-mapper",
        .optimize = .ReleaseSafe,
        .target = b.graph.host,
        .root_source_file = b.path("src/exe-wrapper.zig"),
    });
    python_wrapper.root_module.addOptions("options", python_wrapper_options);
    python_wrapper.root_module.addAnonymousImport("abi-mapper.py", .{
        // Hack to make abi-mapper propagate changes on the python script:
        .root_source_file = abi_mapper_py,
    });
    python_wrapper.root_module.addAnonymousImport("minizig.lark", .{
        // Hack to make abi-mapper propagate changes on the python script:
        .root_source_file = grammar_file,
    });

    b.installArtifact(python_wrapper);

    const cc = Converter{
        .b = b,
        .executable = python_wrapper,
    };

    test_step.dependOn(add_behaviour_test(
        cc,
        b.path("tests/coverage.zabi"),
        b.path("tests/coverage.zig"),
    ));

    const json = cc.get_json_dump(b.path("tests/coverage.zabi"));

    const test_exe = b.addTest(.{
        .root_source_file = abi_schema_mod.root_source_file.?,
        .target = b.graph.host,
        .optimize = .Debug,
    });

    test_exe.root_module.addAnonymousImport("coverage.json", .{
        .root_source_file = json,
    });

    const run_test = b.addRunArtifact(test_exe);

    test_step.dependOn(&run_test.step);

    const json_step = b.step("json", "Emit the JSON dump of test abi");

    json_step.dependOn(&b.addInstallFile(json, "abi-test.json").step);
}

fn add_behaviour_test(cc: Converter, input: std.Build.LazyPath, evaluator: std.Build.LazyPath) *std.Build.Step {
    const abi_code = cc.convert_abi_file(input, .definition);
    const provider_code = cc.convert_abi_file(input, .kernel);
    const consumer_code = cc.convert_abi_file(input, .userland);

    const abi_mod = cc.b.createModule(.{ .root_source_file = abi_code });
    const provider_mod = cc.b.createModule(.{
        .root_source_file = provider_code,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });
    const consumer_mod = cc.b.createModule(.{
        .root_source_file = consumer_code,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });

    const out_dir: std.Build.InstallDir = .{ .custom = "coverage" };

    const install_abi_code = cc.b.addInstallFileWithDir(abi_code, out_dir, "abi.zig");
    const install_provider_code = cc.b.addInstallFileWithDir(provider_code, out_dir, "provider.zig");
    const install_consumer_code = cc.b.addInstallFileWithDir(consumer_code, out_dir, "consumer.zig");

    const test_runner = cc.b.addTest(.{
        .root_source_file = evaluator,
    });

    test_runner.root_module.addImport("abi", abi_mod);
    test_runner.root_module.addImport("provider", provider_mod);
    test_runner.root_module.addImport("consumer", consumer_mod);

    test_runner.step.dependOn(&install_abi_code.step);
    test_runner.step.dependOn(&install_provider_code.step);
    test_runner.step.dependOn(&install_consumer_code.step);

    const test_exec = cc.b.addRunArtifact(test_runner);

    return &test_exec.step;
}

pub const Converter = struct {
    b: *std.Build,
    executable: *std.Build.Step.Compile,

    pub fn convert_abi_file(cc: Converter, input: std.Build.LazyPath, mode: enum { userland, kernel, definition, stubs }) std.Build.LazyPath {
        const generate_core_abi = cc.b.addRunArtifact(cc.executable);
        generate_core_abi.addPrefixedFileArg("--zig-exe=", .{ .cwd_relative = cc.b.graph.zig_exe });
        generate_core_abi.addArg(cc.b.fmt("--mode={s}", .{@tagName(mode)}));
        const abi_zig = generate_core_abi.addPrefixedOutputFileArg("--output=", cc.b.fmt("{s}.zig", .{@tagName(mode)}));
        generate_core_abi.addFileArg(input);
        return abi_zig;
    }

    pub fn get_json_dump(cc: Converter, input: std.Build.LazyPath) std.Build.LazyPath {
        const generate_json = cc.b.addRunArtifact(cc.executable);
        const abi_json = generate_json.addPrefixedOutputFileArg("--emit-json=", "abi.json");
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
