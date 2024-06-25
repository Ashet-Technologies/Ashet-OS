const std = @import("std");

const disk_image_step = @import("disk-image-step");

const ashet_com = @import("src/build/os-common.zig");
const ashet_apps = @import("src/build/apps.zig");
const ashet_kernel = @import("src/build/kernel.zig");
const AssetBundleStep = @import("src/build/AssetBundleStep.zig");
const BitmapConverter = @import("src/build/BitmapConverter.zig");

const kernel_targets = @import("src/kernel/port/targets.zig");
const build_targets = @import("src/build/targets.zig");
const platforms_build = @import("src/build/platform.zig");

pub fn build(b: *std.Build) !void {
    // const hosted_target = b.standardTargetOptions(.{});
    const kernel_step = b.step("kernel", "Only builds the OS kernel");
    const validate_step = b.step("validate", "Validates files in the rootfs");
    const run_step = b.step("run", "Executes the selected kernel with qemu. Use -Dmachine to run only one");
    const tools_step = b.step("tools", "Builds the build and debug tools");
    const abi_step = b.step("abi", "Only compile and update the ABI stuff");

    // subgroups:

    b.getInstallStep().dependOn(abi_step);
    b.getInstallStep().dependOn(tools_step);

    // options:

    const no_gui = b.option(bool, "no-gui", "Disables GUI for runners") orelse false;

    const optimize_kernel = b.option(
        bool,
        "optimize",
        "Optimize the kernel and applications.",
    ) orelse false;

    const optimize_kernel_mode: std.builtin.OptimizeMode = if (optimize_kernel)
        .ReleaseSafe
    else
        .Debug;

    const optimize_apps_mode: std.builtin.OptimizeMode = b.option(
        std.builtin.OptimizeMode,
        "optimize-apps",
        "Optimize apps differently from the kernel.",
    ) orelse if (optimize_kernel)
        .ReleaseSafe
    else
        .Debug;

    const build_native_apps = b.option(bool, "apps", "Builds the native apps (default: on)") orelse true;
    // const build_hosted_apps = b.option(bool, "hosted", "Builds the hosted apps (default: on)") orelse true;

    b.getInstallStep().dependOn(validate_step); // "install" also validates the rootfs.

    /////////////////////////////////////////////////////////////////////////////
    // tools and deps ↓

    const lua_dep = b.dependency("lua", .{
        .interpreter = true,
        .compiler = false,
        .@"shared-lib" = false,
        .@"static-lib" = false,
        .headers = false,
        .target = std.Target.Query{
            .abi = .musl,
        },
    });

    const lua_exe = lua_dep.artifact("lua");

    const turtlefont_dep = b.dependency("turtlefont", .{});

    const network_dep = b.dependency("network", .{});
    const vnc_dep = b.dependency("vnc", .{});

    const mod_network = network_dep.module("network");

    const mod_vnc = vnc_dep.module("vnc");

    const text_editor_module = b.dependency("text-editor", .{}).module("text-editor");
    const mod_hyperdoc = b.dependency("hyperdoc", .{}).module("hyperdoc");

    const mod_args = b.dependency("args", .{}).module("args");
    const mod_zigimg = b.dependency("zigimg", .{}).module("zigimg");
    const mod_fraxinus = b.dependency("fraxinus", .{}).module("fraxinus");

    const mod_ashet_std = b.addModule("ashet-std", .{
        .root_source_file = b.path("src/std/std.zig"),
    });

    const mod_virtio = b.addModule("virtio", .{
        .root_source_file = b.path("vendor/libvirtio/src/virtio.zig"),
    });

    const abi_src = blk: {
        const compile_abi = b.addSystemCommand(&.{
            "python3.11",
            b.pathFromRoot("./tools/abi-mapper.py"),
        });

        const unformatted = compile_abi.captureStdOut();
        compile_abi.captured_stdout.?.basename = "abi-unformatted.zig";

        const fmt = b.addSystemCommand(&.{
            b.graph.zig_exe, "fmt", "--stdin",
        });

        fmt.setStdIn(.{ .lazy_path = unformatted });
        const formatted = fmt.captureStdOut();
        fmt.captured_stdout.?.basename = "abi.zig";

        const wf = b.addWriteFiles();
        const abi_src = wf.addCopyFile(formatted, "AshetOS.zig");
        _ = wf.addCopyFile(b.path("src/abi/error_set.zig"), "error_set.zig");
        _ = wf.addCopyFile(b.path("src/abi/iops.zig"), "iops.zig");

        const install_mod_step = b.addInstallDirectory(.{
            .source_dir = wf.getDirectory(),
            .install_dir = .lib,
            .install_subdir = "zig",
        });
        abi_step.dependOn(&install_mod_step.step);

        const docgen = b.addTest(.{
            .root_source_file = abi_src,
        });

        const install_docs = b.addInstallDirectory(.{
            .source_dir = docgen.getEmittedDocs(),
            .install_dir = .lib,
            .install_subdir = "docs",
        });
        abi_step.dependOn(&install_docs.step);

        break :blk abi_src;
    };

    _ = abi_src;

    const mod_ashet_abi = b.addModule("ashet-abi", .{
        .root_source_file = b.path("src/abi/abi.zig"),
    });

    const mod_libashet = b.addModule("ashet", .{
        .root_source_file = b.path("src/libashet/main.zig"),
        .imports = &.{
            .{ .name = "ashet-abi", .module = mod_ashet_abi },
            .{ .name = "ashet-std", .module = mod_ashet_std },
            // .{ .name = "text-editor", .module = text_editor_module },
        },
    });

    const mod_ashet_gui = b.addModule("ashet-gui", .{
        .root_source_file = b.path("src/libgui/gui.zig"),
        .imports = &.{
            .{ .name = "ashet", .module = mod_libashet },
            .{ .name = "ashet-std", .module = mod_ashet_std },
            .{ .name = "text-editor", .module = text_editor_module },
            .{ .name = "turtlefont", .module = turtlefont_dep.module("turtlefont") },
        },
    });

    const mod_libhypertext = b.addModule("hypertext", .{
        .root_source_file = b.path("src/libhypertext/hypertext.zig"),
        .imports = &.{
            .{ .name = "ashet", .module = mod_libashet },
            .{ .name = "ashet-gui", .module = mod_ashet_gui },
            .{ .name = "hyperdoc", .module = mod_hyperdoc },
        },
    });

    const mod_libashetfs = b.addModule("ashet-fs", .{
        .root_source_file = b.path("src/libafs/afs.zig"),
    });

    const modules: ashet_com.Modules = .{
        .hyperdoc = mod_hyperdoc,
        .args = mod_args,
        .zigimg = mod_zigimg,
        .fraxinus = mod_fraxinus,
        .ashet_std = mod_ashet_std,
        .virtio = mod_virtio,
        .ashet_abi = mod_ashet_abi,
        .libashet = mod_libashet,
        .ashet_gui = mod_ashet_gui,
        .libhypertext = mod_libhypertext,
        .libashetfs = mod_libashetfs,
        // .fatfs = fatfs_module,
        .network = mod_network,
        .vnc = mod_vnc,
    };

    const debug_filter = blk: {
        const debug_filter = b.addExecutable(.{
            .name = "debug-filter",
            .root_source_file = b.path("tools/debug-filter.zig"),
            .target = b.graph.host,
        });
        debug_filter.root_module.addImport("args", mod_args);
        debug_filter.linkLibC();

        const install_step = b.addInstallArtifact(debug_filter, .{});
        tools_step.dependOn(&install_step.step);

        break :blk debug_filter;
    };

    const bmpconv = BitmapConverter.init(b);
    b.installArtifact(bmpconv.converter);
    {
        const tool_extract_icon = b.addExecutable(.{
            .name = "tool_extract_icon",
            .root_source_file = b.path("tools/extract-icon.zig"),
            .target = b.graph.host,
        });
        tool_extract_icon.root_module.addImport("zigimg", mod_zigimg);
        tool_extract_icon.root_module.addImport("ashet-abi", mod_ashet_abi);
        tool_extract_icon.root_module.addImport("args", mod_args);
        b.installArtifact(tool_extract_icon);
    }

    {
        const wikitool = b.addExecutable(.{
            .name = "wikitool",
            .root_source_file = b.path("tools/wikitool.zig"),
            .target = b.graph.host,
        });

        wikitool.root_module.addImport("hypertext", mod_libhypertext);
        wikitool.root_module.addImport("hyperdoc", mod_hyperdoc);
        wikitool.root_module.addImport("args", mod_args);
        wikitool.root_module.addImport("zigimg", mod_zigimg);
        wikitool.root_module.addImport("ashet", mod_libashet);
        wikitool.root_module.addImport("ashet-gui", mod_ashet_gui);

        b.installArtifact(wikitool);
    }

    // tools and deps ↑
    /////////////////////////////////////////////////////////////////////////////
    // ashet os ↓

    const platforms = platforms_build.init(b, modules);

    const MachineSet = std.enums.EnumSet(Machine);

    const machines = if (b.option([]const u8, "machine", "Defines the machine Ashet OS should be built for.")) |machine_list_str| set: {
        var set = MachineSet.initEmpty();

        var tokenizer = std.mem.tokenizeScalar(u8, machine_list_str, ',');

        while (tokenizer.next()) |machine_str| {
            const machine = std.meta.stringToEnum(Machine, machine_str) orelse {
                try writeAllMachineInfo();
                return error.BadMachine;
            };
            set.insert(machine);
        }

        if (set.count() == 0) {
            try writeAllMachineInfo();
            return error.BadMachine;
        }

        break :set set;
    } else MachineSet.initFull(); // by default, build for all machines

    {
        var iter = machines.iterator();
        while (iter.next()) |machine| {
            const machine_spec = build_targets.getMachineSpec(machine);
            const platform_spec = build_targets.getPlatformSpec(machine_spec.platform);

            const os = buildOs(
                b,
                optimize_kernel_mode,
                optimize_apps_mode,
                bmpconv,
                modules,
                lua_exe,
                kernel_step,
                machine,
                build_native_apps,
                platforms,
            );

            const Variables = struct {
                @"${DISK}": std.Build.LazyPath,
                @"${BOOTROM}": std.Build.LazyPath,
                @"${KERNEL}": std.Build.LazyPath,
            };

            const variables = Variables{
                .@"${DISK}" = os.disk_img,
                .@"${BOOTROM}" = os.kernel_bin,
                .@"${KERNEL}" = os.kernel_elf,
            };

            // Run qemu with the debug-filter wrapped around so we can translate addresses
            // to file:line,function info
            const vm_runner = b.addRunArtifact(debug_filter);

            // Add debug elf contexts:
            vm_runner.addArg("--elf");
            vm_runner.addPrefixedFileArg("kernel=", os.kernel_elf);

            for (os.apps) |app| {
                var app_name_buf: [128]u8 = undefined;

                const app_name = try std.fmt.bufPrint(&app_name_buf, "{s}=", .{app.name});

                vm_runner.addArg("--elf");
                vm_runner.addPrefixedFileArg(app_name, app.exe);
            }

            // from now on regular QEMU flags:
            vm_runner.addArg(platform_spec.qemu_exe);
            vm_runner.addArgs(&generic_qemu_flags);

            if (no_gui) {
                vm_runner.addArgs(&console_qemu_flags);
            } else {
                vm_runner.addArgs(&display_qemu_flags);
            }

            arg_loop: for (machine_spec.qemu_cli) |arg| {
                inline for (@typeInfo(Variables).Struct.fields) |fld| {
                    const path = @field(variables, fld.name);

                    if (std.mem.eql(u8, arg, fld.name)) {
                        vm_runner.addFileArg(path);
                        continue :arg_loop;
                    } else if (std.mem.endsWith(u8, arg, fld.name)) {
                        vm_runner.addPrefixedFileArg(arg[0 .. arg.len - fld.name.len], path);
                        continue :arg_loop;
                    }
                }
                vm_runner.addArg(arg);
            }

            if (b.args) |args| {
                vm_runner.addArgs(args);
            }

            vm_runner.stdio = .inherit;

            run_step.dependOn(&vm_runner.step);
        }
    }

    // ashet os ↑
    /////////////////////////////////////////////////////////////////////////////
    // tests ↓

    // if (b.option([]const u8, "test-ui", "If set to a file, will compile the ui-layout-tester tool based on the file passed")) |file_name| {
    //     const ui_tester = b.addExecutable(.{
    //         .name = "ui-layout-tester",
    //         .root_source_file = b.path("tools/ui-layout-tester.zig"),
    //     });

    //     ui_tester.addModule("ashet", mod_libashet);
    //     ui_tester.addModule("ashet-gui", mod_ashet_gui);
    //     ui_tester.addModule("ui-layout", ui_gen.render(.{ .path = b.pathFromRoot(file_name) }));

    //     ui_tester.linkSystemLibrary("sdl2");
    //     b.installArtifact(ui_tester);
    //     ui_tester.linkLibC();
    // }

    const std_tests = b.addTest(.{
        .root_source_file = b.path("src/std/std.zig"),
        .target = b.graph.host,
        .optimize = optimize_kernel_mode,
    });

    const fs_tests = b.addTest(.{
        .root_source_file = b.path("src/libafs/testsuite.zig"),
        .target = b.graph.host,
        .optimize = optimize_kernel_mode,
    });

    const gui_tests = b.addTest(.{
        .root_source_file = b.path("src/libgui/gui.zig"),
        .target = b.graph.host,
        .optimize = optimize_kernel_mode,
    });
    {
        var iter = b.modules.get("ashet-gui").?.import_table.iterator();
        while (iter.next()) |kv| {
            gui_tests.root_module.addImport(kv.key_ptr.*, kv.value_ptr.*);
        }
    }

    const test_step = b.step("test", "Run unit tests on the standard library");
    test_step.dependOn(&b.addRunArtifact(std_tests).step);
    test_step.dependOn(&b.addRunArtifact(gui_tests).step);
    test_step.dependOn(&b.addRunArtifact(fs_tests).step);

    // tests ↑
    /////////////////////////////////////////////////////////////////////////////
    // validation ↓
    {
        const validate_wiki = b.addSystemCommand(&.{b.pathFromRoot("./tools/validate-wiki.sh")});

        validate_step.dependOn(&validate_wiki.step);
    }
    // validation ↑
    /////////////////////////////////////////////////////////////////////////////

}

fn addBitmap(target: *std.build.LibExeObjStep, bmpconv: BitmapConverter, src: []const u8, dst: []const u8, size: [2]u32) void {
    const file = bmpconv.convert(.{ .path = src }, std.fs.path.basename(dst), .{ .geometry = size });

    file.addStepDependencies(&target.step);
}

const Platform = kernel_targets.Platform;
const Machine = kernel_targets.Machine;
const MachineSpec = kernel_targets.MachineSpec;

const generic_qemu_flags = [_][]const u8{
    "-d",         "guest_errors,unimp",
    "-serial",    "stdio",
    "-no-reboot", "-no-shutdown",
    "-s",
};

const display_qemu_flags = [_][]const u8{
    "-display", "gtk,show-tabs=on",
};

const console_qemu_flags = [_][]const u8{
    "-display", "none",
};

const OS = struct {
    kernel_elf: std.Build.LazyPath,
    kernel_bin: std.Build.LazyPath,
    disk_img: std.Build.LazyPath,

    apps: []const ashet_apps.App,
};

fn buildOs(
    b: *std.Build,
    optimize_kernel: std.builtin.OptimizeMode,
    optimize_apps: std.builtin.OptimizeMode,
    bmpconv: BitmapConverter,
    modules: ashet_com.Modules,
    lua_exe: *std.Build.Step.Compile,
    kernel_step: *std.Build.Step,
    machine: Machine,
    build_apps: bool,
    platforms: platforms_build.PlatformData,
) OS {
    var ui_gen = ashet_com.UiGenerator{
        .builder = b,
        .lua = lua_exe,
        .mod_ashet = modules.libashet,
        .mod_ashet_gui = modules.ashet_gui,
        .mod_system_assets = system_assets,
    };

    const kernel_file = kernel_exe.getEmittedBin();

    {
        const install_kernel = b.addInstallFileWithDir(
            kernel_file,
            .{ .custom = "kernel" },
            b.fmt("{s}.elf", .{machine_spec.machine_id}),
        );

        kernel_step.dependOn(&install_kernel.step);
        b.getInstallStep().dependOn(&install_kernel.step);
    }

    const raw_step = b.addObjCopy(kernel_file, .{
        .basename = b.fmt("{s}.bin", .{machine_spec.machine_id}),
        .format = .bin,
        // .only_section
        .pad_to = machine_spec.rom_size,
    });
    raw_step.step.dependOn(&kernel_exe.step);

    const install_raw_step = b.addInstallFileWithDir(
        raw_step.getOutputSource(),
        .{ .custom = "rom" },
        raw_step.basename,
    );
    b.getInstallStep().dependOn(&install_raw_step.step);

    var ctx = ashet_apps.AshetContext.init(
        b,
        bmpconv,
        .{
            .native = .{
                .platforms = platforms,
                .platform = machine_spec.platform,
                .rootfs = &rootfs,
            },
        },
    );

    if (build_apps) {
        ashet_apps.compileApps(
            &ctx,
            optimize_apps,
            modules,
            &ui_gen,
        );
    }

    return OS{
        .disk_img = disk_image,
        .kernel_bin = raw_step.getOutputSource(),
        .kernel_elf = kernel_file,
        .apps = ctx.app_list.items,
    };
}

fn writeAllMachineInfo() !void {
    var stderr = std.io.getStdErr();

    var writer = stderr.writer();
    try writer.writeAll("Bad or emptymachine selection. All available machines are:\n");

    for (comptime std.enums.values(Machine)) |decl| {
        try writer.print("- {s}\n", .{@tagName(decl)});
    }

    try writer.writeAll("Please fix your command line!\n");
}
