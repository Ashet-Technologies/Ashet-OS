const std = @import("std");
const kernel_package = @import("kernel");
const abi_package = @import("ashet-abi");

const Machine = kernel_package.Machine;
const Platform = abi_package.Platform;

const excluded_machines: []const Machine = &.{
    // Options here are excluded:
};

const default_machines = std.EnumSet(Machine).initMany(excluded_machines).complement();

const qemu_debug_options_default = "cpu_reset,guest_errors,unimp";

const QemuDisplayMode = enum {
    headless,
    sdl,
    gtk,
    cocoa,
};

const ToolDep = struct {
    dependency: []const u8,
    artifacts: []const []const u8,
};

const installed_tools: []const ToolDep = &.{
    .{
        .dependency = "debugfilter",
        .artifacts = &.{"debug-filter"},
    },
    .{
        .dependency = "mkicon",
        .artifacts = &.{"mkicon"},
    },
    .{
        .dependency = "mkfont",
        .artifacts = &.{"mkfont"},
    },
};

pub fn build(b: *std.Build) void {
    // Options:
    const optimize_kernel = b.option(bool, "optimize-kernel", "Should the kernel be optimized?") orelse false;
    const optimize_apps = b.option(std.builtin.OptimizeMode, "optimize-apps", "Optimization mode for the applications") orelse .Debug;

    const install_rootfs = b.option(bool, "rootfs", "Installs the rootfs contents as well for hosted targets (default: off)") orelse false;

    const maybe_run_machine = b.option(Machine, "machine", "Selects which machine to run with the 'run' step");
    const qemu_gui = b.option(QemuDisplayMode, "gui", "Selects GUI mode for QEMU (headless, sdl, gtk)") orelse if (b.graph.host.result.os.tag.isDarwin())
        QemuDisplayMode.cocoa
    else
        QemuDisplayMode.gtk;
    const qemu_debug_options = b.option(
        []const u8,
        "qemu-debug",
        b.fmt("Sets the QEMU debug options (default: '{s}')", .{qemu_debug_options_default}),
    ) orelse
        qemu_debug_options_default;
    const list_apps = b.option(bool, "list-apps", "Prints a list of all files published by the OS dependency") orelse false;

    // Steps:
    const test_step = b.step("test", "Runs the test suite");

    const machine_steps = blk: {
        var steps = std.EnumArray(Machine, *std.Build.Step).initUndefined();
        for (std.enums.values(Machine)) |machine| {
            const step = b.step(
                @tagName(machine),
                b.fmt("Compiles the OS for {s}", .{@tagName(machine)}),
            );
            if (maybe_run_machine == null or maybe_run_machine == machine) {
                if (default_machines.contains(machine)) {
                    b.getInstallStep().dependOn(step);
                }
            }
            steps.set(machine, step);
        }
        break :blk steps;
    };

    // Tools
    for (installed_tools) |tool_dep| {
        const dep = b.dependency(tool_dep.dependency, .{});
        for (tool_dep.artifacts) |art_name| {
            const art = dep.artifact(art_name);
            b.installArtifact(art);
        }
    }

    // Dependencies:

    const debugfilter_dep = b.dependency("debugfilter", .{});

    // Build:

    const debugfilter = debugfilter_dep.artifact("debug-filter");

    // Install the debug-filter executable so we can utilize it for debugging
    b.installArtifact(debugfilter);

    var os_deps: std.EnumArray(Machine, *std.Build.Dependency) = .initUndefined();
    var os_rootfs: std.EnumArray(Machine, ?std.Build.LazyPath) = .initFill(null);
    for (std.enums.values(Machine)) |machine| {
        const step = machine_steps.get(machine);

        const machine_os_dep = b.dependency("os", .{
            .machine = machine,
            .@"optimize-kernel" = optimize_kernel,
            .@"optimize-apps" = optimize_apps,
        });
        os_deps.set(machine, machine_os_dep);

        const os_files = machine_os_dep.namedWriteFiles("ashet-os");
        const rootfs_files = machine_os_dep.namedWriteFiles("rootfs");

        const install_elves = b.addInstallDirectory(.{
            .source_dir = os_files.getDirectory(),
            .install_dir = .{ .custom = @tagName(machine) },
            .install_subdir = "",
        });
        step.dependOn(&install_elves.step);

        if (install_rootfs and machine.is_hosted()) {
            const install_rootfs_dir = b.addInstallDirectory(.{
                .source_dir = rootfs_files.getDirectory(),
                .install_dir = .{ .custom = @tagName(machine) },
                .install_subdir = "rootfs",
            });
            step.dependOn(&install_rootfs_dir.step);

            // `b.getInstallPath` is copied from the InstallStep itself to figure out the final output directory:
            const install_path = b.getInstallPath(install_rootfs_dir.options.install_dir, install_rootfs_dir.options.install_subdir);
            std.debug.assert(std.fs.path.isAbsolute(install_path));
            os_rootfs.set(machine, .{ .cwd_relative = install_path });
        }

        if (list_apps) {
            std.debug.print("available files for '{s}':\n", .{
                @tagName(machine),
            });
            for (os_files.files.items) |file| {
                std.debug.print("- {s}\n", .{file.sub_path});
            }
        }
    }

    // Kernel Unit Tests
    // {
    //     const abi_dep = b.dependency("ashet-abi", .{});
    //     const abi_mod = abi_dep.module("ashet-abi");

    //     const machine_info = b.addWriteFile("machine_info.zig",
    //         \\pub const platform_id = .x86;
    //         \\pub const machine_id = .@"pc-bios";
    //     ).files.items[0].getPath();

    //     const machine_info_mod = b.createModule(.{
    //         .root_source_file = machine_info,
    //     });

    //     const kernel_tests = b.addTest(.{
    //         .root_source_file = b.path("src/kernel/main.zig"),
    //         .target = b.resolveTargetQuery(.{ .cpu_arch = .x86 }),
    //         .optimize = .Debug,
    //     });
    //     kernel_tests.root_module.addImport("machine-info", machine_info_mod);
    //     kernel_tests.root_module.addImport("args", machine_info_mod);
    //     kernel_tests.root_module.addImport("ashet-abi", abi_mod);
    //     test_step.dependOn(&b.addRunArtifact(kernel_tests).step);
    // }

    {
        const astd_mod = b.dependency("ashet-std", .{});

        const astd_tests = astd_mod.artifact("ashet-std-tests");

        test_step.dependOn(&b.addRunArtifact(astd_tests).step);
    }

    // Run:

    if (maybe_run_machine) |run_machine| {
        const run_step = b.step("run", b.fmt("Runs the OS machine {s}", .{@tagName(run_machine)}));

        run_step.dependOn(machine_steps.get(run_machine));

        const platform_info = platform_info_map.get(run_machine.get_platform());
        const machine_info = machine_info_map.get(run_machine);

        const machine_os_dep = os_deps.get(run_machine);

        const os_files = machine_os_dep.namedWriteFiles("ashet-os");

        const kernel_elf = get_named_file(os_files, "kernel.elf");
        const disk_img = get_named_file(os_files, "disk.img");
        const kernel_bin = get_optional_named_file(os_files, "kernel.bin");

        const AppDef = struct {
            name: []const u8,
            exe: std.Build.LazyPath,
        };

        const apps: []const AppDef = &.{
            .{ .name = "init", .exe = get_named_file(os_files, "apps/init.elf") },
            .{ .name = "hello-world", .exe = get_named_file(os_files, "apps/hello-world.elf") },
            .{ .name = "hello-gui", .exe = get_named_file(os_files, "apps/hello-gui.elf") },
            .{ .name = "classic", .exe = get_named_file(os_files, "apps/desktop/classic.elf") },
            .{ .name = "dungeon.ashex", .exe = get_named_file(os_files, "apps/dungeon.elf") },
        };

        const variables = Variables{
            .@"${DISK}" = disk_img,
            .@"${KERNEL}" = kernel_elf,
            .@"${BOOTROM}" = kernel_bin orelse b.path("<no bootrom>"),
            .@"${ROOTFS}" = os_rootfs.get(run_machine) orelse b.path("<no rootfs>"),
        };

        // Run qemu with the debug-filter wrapped around so we can translate addresses
        // to file:line,function info
        const vm_runner = b.addRunArtifact(debugfilter);

        // Add debug elf contexts:
        vm_runner.addArg("--elf");
        vm_runner.addPrefixedFileArg("kernel=", kernel_elf);

        for (apps) |app| {
            var app_name_buf: [128]u8 = undefined;

            const app_name = std.fmt.bufPrint(&app_name_buf, "{s}=", .{app.name}) catch @panic("out of memory");

            vm_runner.addArg("--elf");
            vm_runner.addPrefixedFileArg(app_name, app.exe);
        }

        if (!run_machine.is_hosted()) {

            // from now on regular QEMU flags:
            vm_runner.addArg(platform_info.qemu_exe);
            vm_runner.addArgs(&generic_qemu_flags);

            if (qemu_debug_options.len > 0) {
                vm_runner.addArgs(&.{ "-d", qemu_debug_options });
            }

            vm_runner.addArgs(qemu_display_flags.get(qemu_gui));

            for (machine_info.qemu_cli) |arg| {
                variables.addArg(vm_runner, arg);
            }
        } else {
            vm_runner.addFileArg(kernel_elf);
            for (machine_info.hosted_cli) |arg| {
                variables.addArg(vm_runner, arg);
            }
            if (machine_info.hosted_video_setup.get(qemu_gui)) |gui_args| {
                for (gui_args) |arg| {
                    variables.addArg(vm_runner, arg);
                }
            }
        }

        if (b.args) |args| {
            vm_runner.addArgs(args);
        }

        vm_runner.stdio = .inherit;
        vm_runner.has_side_effects = true;
        vm_runner.disable_zig_progress = true;

        run_step.dependOn(&vm_runner.step);
    }

    {
        const depz_step = b.step("depz", "Run depz build runner to get dependency graph.dot");
        const run_depz = @import("depz").runDepz(b);
        depz_step.dependOn(&run_depz.step);
    }
}

const PlatformStartupConfig = struct {
    qemu_exe: []const u8,
};

const Variables = struct {
    @"${DISK}": std.Build.LazyPath,
    @"${BOOTROM}": std.Build.LazyPath,
    @"${KERNEL}": std.Build.LazyPath,
    @"${ROOTFS}": std.Build.LazyPath,

    pub fn addArg(variables: Variables, runner: *std.Build.Step.Run, arg: []const u8) void {
        inline for (@typeInfo(Variables).@"struct".fields) |fld| {
            const path = @field(variables, fld.name);

            if (std.mem.eql(u8, arg, fld.name)) {
                runner.addFileArg(path);
                return;
            }

            if (std.mem.endsWith(u8, arg, fld.name)) {
                runner.addPrefixedFileArg(arg[0 .. arg.len - fld.name.len], path);
                return;
            }
        }
        runner.addArg(arg);
    }
};

const MachineStartupConfig = struct {
    /// Instantiation:
    /// Uses place holders:
    /// - "${BOOTROM}" is the boot rom which contains the os kernel
    /// - "${KERNEL}"  is the path to the ELF file of the kernel
    /// - "${DISK}"    is the the file system disk image
    /// - "${ROOTFS}"  is the path to a host directory in the prefix which contains a rootfs. Only available on hosted machines
    qemu_cli: []const []const u8 = &.{},

    hosted_cli: []const []const u8 = &.{},

    hosted_video_setup: std.EnumArray(QemuDisplayMode, ?[]const []const u8) = .initFill(null),
};

const platform_info_map = std.EnumArray(Platform, PlatformStartupConfig).init(.{
    .x86 = .{
        .qemu_exe = "qemu-system-i386",
    },
    .arm = .{
        .qemu_exe = "qemu-system-arm",
    },
    .rv32 = .{
        .qemu_exe = "qemu-system-riscv32",
    },
});

const machine_info_map = std.EnumArray(Machine, MachineStartupConfig).init(.{
    .@"x86-pc-bios" = .{
        .qemu_cli = &.{
            "-machine", "pc",
            "-cpu",     "pentium2",
            "-drive",   "if=ide,index=0,format=raw,file=${DISK}",
            "--device", "isa-debug-exit",
            "-vga", "none", // disable standard VGA
            "--device", "VGA,xres=800,yres=480,xmax=800,ymax=480,edid=true", // replace with customized VGA and limited resolution
        },
    },
    .@"rv32-qemu-virt" = .{
        .qemu_cli = &.{
            "-cpu",    "rv32",
            "-M",      "virt",
            "-m",      "32M",
            "-netdev", "user,id=hostnet",
            "-object", "filter-dump,id=hostnet-dump,netdev=hostnet,file=ashet-os.pcap",
            "-device", "virtio-gpu-device,id=screen,xres=800,yres=480",
            "-device", "virtio-keyboard-device",
            "-device", "virtio-mouse-device",
            "-device", "virtio-net-device,netdev=hostnet,mac=52:54:00:12:34:56",
            "-bios",   "none",
            "-drive",  "if=pflash,index=0,format=raw,file=${BOOTROM}",
            "-drive",  "if=pflash,index=1,format=raw,file=${DISK}",
        },
    },
    .@"arm-qemu-virt" = .{
        .qemu_cli = &.{
            "-cpu",    "cortex-a7",
            "-M",      "virt",
            "-m",      "32M",
            "-netdev", "user,id=hostnet",
            "-object", "filter-dump,id=hostnet-dump,netdev=hostnet,file=ashet-os.pcap",
            "-device", "virtio-gpu-device,xres=800,yres=480",
            "-device", "virtio-keyboard-device",
            "-device", "virtio-mouse-device",
            "-device", "virtio-net-device,netdev=hostnet,mac=52:54:00:12:34:56",
            // "-bios",   "none",
            "-drive",  "if=pflash,index=0,format=raw,file=${BOOTROM}",
            "-drive",  "if=pflash,index=1,format=raw,file=${DISK}",
        },
    },
    .@"arm-ashet-vhc" = .{
        .qemu_cli = &.{
            "-M",        "ashet-vhc",
            "-m",        "8M",
            "-kernel",   "${KERNEL}",
            "-blockdev", "driver=file,node-name=disk_file,filename=${DISK}",
            "-blockdev", "driver=raw,node-name=disk,file=disk_file",
            "-device",   "virtio-gpu-device,xres=800,yres=480",
            "-device",   "virtio-keyboard-device",
            "-device",   "virtio-mouse-device",
            "-device",   "virtio-blk-device,drive=disk",

            // we use the second serial for dumping binary data out of the system /o\
            "-serial",
            "file:zig-out/init-linked.bin",

            // "-serial",   "vc",
        },
    },
    .@"arm-ashet-hc" = .{
        // True Home Computer must be debugged/runned on real hardware!
    },

    .@"x86-hosted-linux" = .{
        .hosted_cli = &.{
            "drive:${DISK}",
            // "fs:${ROOTFS}",
        },

        .hosted_video_setup = .init(.{
            .headless = &.{"video:vnc:800:480:0.0.0.0:5900"},
            .gtk = &.{"video:auto-window:800:480"},
            .sdl = &.{"video:sdl:800:480"},
            .cocoa = &.{},
        }),
    },

    .@"x86-hosted-windows" = .{
        .hosted_cli = &.{
            "drive:${DISK}",
            // "fs:${ROOTFS}",
        },

        .hosted_video_setup = .init(.{
            .headless = &.{"video:vnc:800:480:0.0.0.0:5900"},
            .gtk = &.{"video:win:800:480"},
            .sdl = &.{"video:sdl:800:480"},
            .cocoa = &.{},
        }),
    },

    // .@"pc-efi" = .{
    //     .qemu_cli = &.{
    //         "-cpu",     "qemu64",
    //         "-drive",   "if=pflash,format=raw,unit=0,file=/usr/share/qemu/edk2-x86_64-code.fd,readonly=on",
    //         "-drive",   "if=ide,format=raw,unit=0,file=${DISK}",
    //     },
    // },

    // .@"qemu-microvm" = .{
    //     .qemu_cli = &.{
    //         "-M",      "microvm",
    //         "-m",      "32M",
    //         "-netdev", "user,id=hostnet",
    //         "-object", "filter-dump,id=hostnet-dump,netdev=hostnet,file=ashet-os.pcap",
    //         "-device", "virtio-gpu-device,xres=400,yres=300",
    //         "-device", "virtio-keyboard-device",
    //         "-device", "virtio-mouse-device",
    //         "-device", "virtio-net-device,netdev=hostnet,mac=52:54:00:12:34:56",
    //     },
    // },
});

const generic_qemu_flags = [_][]const u8{
    "-no-reboot", "-no-shutdown",
    "-chardev",   "stdio,id=os-monitor,logfile=zig-out/serial.log,signal=off",
    "-serial",    "chardev:os-monitor",
    "-s",
};

const qemu_display_flags: std.EnumArray(QemuDisplayMode, []const []const u8) = .init(.{
    .gtk = &[_][]const u8{
        "-display", "gtk,show-tabs=on",
    },

    .cocoa = &[_][]const u8{
        "-display", "cocoa",
    },

    .sdl = &[_][]const u8{
        "-display", "sdl,window-close=on",
    },

    .headless = &[_][]const u8{
        "-display", "vnc=0.0.0.0:0", // Binds to VNC Port 5900
    },
});

fn get_optional_named_file(write_files: *std.Build.Step.WriteFile, sub_path: []const u8) ?std.Build.LazyPath {
    for (write_files.files.items) |file| {
        if (std.mem.eql(u8, file.sub_path, sub_path))
            return .{
                .generated = .{
                    .file = &write_files.generated_directory,
                    .sub_path = file.sub_path,
                },
            };
    }
    return null;
}

fn get_named_file(write_files: *std.Build.Step.WriteFile, sub_path: []const u8) std.Build.LazyPath {
    if (get_optional_named_file(write_files, sub_path)) |path|
        return path;

    std.debug.print("missing file '{s}' in dependency '{s}:{s}'. available files are:\n", .{
        sub_path,
        std.mem.trimRight(u8, write_files.step.owner.dep_prefix, "."),
        write_files.step.name,
    });
    for (write_files.files.items) |file| {
        std.debug.print("- '{s}'\n", .{file.sub_path});
    }
    std.process.exit(1);
}
