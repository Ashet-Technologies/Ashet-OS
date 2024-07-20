const std = @import("std");
const builtin = @import("builtin");

const requirements = [_][]const u8{
    "case-converter>=1.1.0",
    "lark>=1.1",
};

pub fn build(b: *std.Build) void {
    const create_venv_step = b.step("venv", "Creates the python venv");

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

    const pyenv_pip = if (builtin.os.tag == .windows)
        pyenv.path(b, "Scripts/pip.exe")
    else
        pyenv.path(b, "bin/pip");

    const pyenv_install_packages = addRunScript(b, pyenv_pip);

    pyenv_install_packages.addFileArg(pyenv_pip);
    pyenv_install_packages.addArg("install");
    pyenv_install_packages.addArgs(&requirements);

    const venv_info_printer = b.addSystemCommand(&.{"echo"});
    venv_info_printer.step.dependOn(&pyenv_install_packages.step);

    venv_info_printer.addArg("python3=");
    venv_info_printer.addFileArg(pyenv_python3);

    venv_info_printer.addArg("pip=");
    venv_info_printer.addFileArg(pyenv_pip);

    create_venv_step.dependOn(&venv_info_printer.step);

    const abi_mapper_script = b.path("abi-mapper.py");
    const abi_v2_def = b.path("../../abi/abi-v2.zig");

    {
        const generate_core_abi = addRunScript(b, pyenv_python3);
        generate_core_abi.addFileArg(abi_mapper_script);
        generate_core_abi.addArg("--mode=definition");
        const abi_zig = generate_core_abi.addPrefixedOutputFileArg("--output=", "abi.zig");
        generate_core_abi.addFileArg(abi_v2_def);

        b.getInstallStep().dependOn(&b.addInstallHeaderFile(abi_zig, "abi.zig").step);
    }

    {
        const generate_core_abi = addRunScript(b, pyenv_python3);
        generate_core_abi.addFileArg(abi_mapper_script);
        generate_core_abi.addArg("--mode=kernel");
        const abi_zig = generate_core_abi.addPrefixedOutputFileArg("--output=", "kernel-impl.zig");
        generate_core_abi.addFileArg(abi_v2_def);

        b.getInstallStep().dependOn(&b.addInstallHeaderFile(abi_zig, "kernel-impl.zig").step);
    }

    {
        const generate_core_abi = addRunScript(b, pyenv_python3);
        generate_core_abi.addFileArg(abi_mapper_script);
        generate_core_abi.addArg("--mode=userland");
        const abi_zig = generate_core_abi.addPrefixedOutputFileArg("--output=", "userland-impl.zig");
        generate_core_abi.addFileArg(abi_v2_def);

        b.getInstallStep().dependOn(&b.addInstallHeaderFile(abi_zig, "userland-impl.zig").step);
    }
}

fn addRunScript(b: *std.Build, script: std.Build.LazyPath) *std.Build.Step.Run {
    const run = std.Build.Step.Run.create(b, "custom script");
    run.addFileArg(script);
    return run;
}

fn fail(comptime msg: []const u8, args: anytype) noreturn {
    std.debug.print("build configuration failed:\n" ++ msg ++ "\n", args);
    std.process.exit(1);
}
