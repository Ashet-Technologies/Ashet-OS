const std = @import("std");
const builtin = @import("builtin");

const requirements = [_][]const u8{
    "case-converter>=1.1.0",
    "lark>=1.1",
    "pyinstaller>=6.9.0",
};

pub fn build(b: *std.Build) void {
    const create_venv_step = b.step("venv", "Creates the python venv");
    const test_step = b.step("test", "Runs the test suite");

    const global_python3 = b.findProgram(&.{
        "python3.11",
        "python3",
        "python",
    }, &.{}) catch |err| fail("python3 not found: {s}", .{@errorName(err)});

    const pyversion = b.run(&.{ global_python3, "--version" });

    if (!std.ascii.lessThanIgnoreCase("Python 3.11", pyversion))
        fail("Python version must be at least 3.11, but found {s}", .{pyversion});

    const create_pyenv = b.addSystemCommand(&.{
        global_python3,
        "-m",
        "venv",
    });
    const pyenv = create_pyenv.addOutputDirectoryArg("venv");

    const pyenv_python3 = if (builtin.os.tag == .windows)
        pyenv.path(b, "Scripts/python.exe")
    else
        pyenv.path(b, "bin/python");

    const pyenv_install_packages = add_run_script(b, pyenv_python3);

    pyenv_install_packages.addArg("-m");
    pyenv_install_packages.addArg("pip");
    pyenv_install_packages.addArg("install");
    pyenv_install_packages.addArgs(&requirements);

    const venv_info_printer = b.addSystemCommand(&.{"echo"});
    venv_info_printer.step.dependOn(&pyenv_install_packages.step);

    venv_info_printer.addArg("python3=");
    venv_info_printer.addFileArg(pyenv_python3);

    create_venv_step.dependOn(&venv_info_printer.step);

    const compile_abi_mapper = add_run_script(b, pyenv_python3);
    compile_abi_mapper.addFileArg(b.path("create-wrapper.py"));
    compile_abi_mapper.addPrefixedFileArg("--interpreter=", pyenv_python3);
    compile_abi_mapper.addPrefixedFileArg("--script=", b.path("abi-mapper.py"));
    compile_abi_mapper.addArg(b.fmt("--host={s}", .{@tagName(b.host.result.os.tag)}));

    const script_name = if (b.host.result.os.tag == .windows)
        "abi-mapper.bat"
    else
        "abi-mapper.sh";

    const wrapper_script = compile_abi_mapper.addPrefixedOutputFileArg("--output=", script_name);

    // for debugging:
    venv_info_printer.addArg("abi-mapper=");
    venv_info_printer.addDirectoryArg(wrapper_script);

    const named_scripts = b.addNamedWriteFiles("scripts");

    _ = named_scripts.addCopyFile(wrapper_script, script_name);

    const install_script_step = b.addInstallFileWithDir(wrapper_script, .bin, script_name);
    b.getInstallStep().dependOn(&install_script_step.step);

    const cc = Converter{
        .b = b,
        .install_packages = &pyenv_install_packages.step,
        .script = wrapper_script,
    };

    test_step.dependOn(add_behaviour_test(
        cc,
        b.path("tests/coverage.zabi"),
        b.path("tests/coverage.zig"),
    ));
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

    const test_runner = cc.b.addTest(.{
        .root_source_file = evaluator,
    });

    test_runner.root_module.addImport("abi", abi_mod);
    test_runner.root_module.addImport("provider", provider_mod);
    test_runner.root_module.addImport("consumer", consumer_mod);

    const test_exec = cc.b.addRunArtifact(test_runner);

    return &test_exec.step;
}

const Converter = struct {
    b: *std.Build,
    script: std.Build.LazyPath,
    install_packages: *std.Build.Step,

    pub fn convert_abi_file(cc: Converter, input: std.Build.LazyPath, mode: enum { userland, kernel, definition }) std.Build.LazyPath {
        const generate_core_abi = add_run_script(cc.b, cc.script);
        generate_core_abi.addPrefixedFileArg("--zig-exe=", .{ .cwd_relative = cc.b.graph.zig_exe });
        generate_core_abi.addArg(cc.b.fmt("--mode={s}", .{@tagName(mode)}));
        const abi_zig = generate_core_abi.addPrefixedOutputFileArg("--output=", cc.b.fmt("{s}.zig", .{@tagName(mode)}));
        generate_core_abi.addFileArg(input);
        generate_core_abi.step.dependOn(cc.install_packages);
        return abi_zig;
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
