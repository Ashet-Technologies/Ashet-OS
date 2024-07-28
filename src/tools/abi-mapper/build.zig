const std = @import("std");
const builtin = @import("builtin");

const requirements_spec =
    \\case-converter>=1.1.0
    \\lark>=1.1
    \\pyinstaller>=6.9.0
;

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

    const requirements_file = b.addWriteFile("requirements.txt", requirements_spec);

    const pyenv_install_packages = add_run_script(b, pyenv_python3);

    pyenv_install_packages.addArg("-m");
    pyenv_install_packages.addArg("pip");
    pyenv_install_packages.addArg("install");
    pyenv_install_packages.addArg("-r");
    pyenv_install_packages.addFileArg(requirements_file.files.items[0].getPath()); // we need to use a
    pyenv_install_packages.addArg("--log");
    const install_log = pyenv_install_packages.addOutputFileArg("pip.log");

    const venv_info_printer = b.addSystemCommand(&.{"echo"});
    install_log.addStepDependencies(&venv_info_printer.step);

    venv_info_printer.addArg("python3=");
    venv_info_printer.addFileArg(pyenv_python3);

    create_venv_step.dependOn(&venv_info_printer.step);

    const python_wrapper_options = b.addOptions();
    python_wrapper_options.addOptionPath("interpreter", pyenv_python3);
    python_wrapper_options.addOptionPath("script", b.path("src/abi-mapper.py"));
    python_wrapper_options.step.dependOn(&pyenv_install_packages.step);

    const python_wrapper = b.addExecutable(.{
        .name = "abi-mapper",
        .optimize = .ReleaseSafe,
        .target = b.host,
        .root_source_file = b.path("src/exe-wrapper.zig"),
    });
    python_wrapper.root_module.addOptions("options", python_wrapper_options);

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
