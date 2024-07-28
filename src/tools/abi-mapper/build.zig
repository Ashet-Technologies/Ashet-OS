const std = @import("std");
const builtin = @import("builtin");

const requirements = [_][]const u8{
    "case-converter>=1.1.0",
    "lark>=1.1",
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

    const cc = Converter{
        .b = b,
        .py3 = pyenv_python3,
        .install_packages = &pyenv_install_packages.step,
        .script = b.path("abi-mapper.py"),
    };

    const abi_v2_def = b.path("../../abi/abi-v2.zig");

    {
        const abi_zig = cc.convert_abi_file(abi_v2_def, .definition);
        b.getInstallStep().dependOn(&b.addInstallHeaderFile(abi_zig, "abi.zig").step);
    }

    {
        const abi_zig = cc.convert_abi_file(abi_v2_def, .kernel);
        b.getInstallStep().dependOn(&b.addInstallHeaderFile(abi_zig, "kernel-impl.zig").step);
    }

    {
        const abi_zig = cc.convert_abi_file(abi_v2_def, .userland);
        b.getInstallStep().dependOn(&b.addInstallHeaderFile(abi_zig, "userland-impl.zig").step);
    }

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
    py3: std.Build.LazyPath,
    script: std.Build.LazyPath,
    install_packages: *std.Build.Step,

    pub fn convert_abi_file(cc: Converter, input: std.Build.LazyPath, mode: enum { userland, kernel, definition }) std.Build.LazyPath {
        const generate_core_abi = add_run_script(cc.b, cc.py3);
        generate_core_abi.addFileArg(cc.script);
        generate_core_abi.addPrefixedFileArg("--zig-exe=", .{ .cwd_relative = cc.b.graph.zig_exe });
        generate_core_abi.addArg(cc.b.fmt("--mode={s}", .{@tagName(mode)}));
        const abi_zig = generate_core_abi.addPrefixedOutputFileArg("--output=", "impl.zig");
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
