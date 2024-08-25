const std = @import("std");
const kernel_package = @import("kernel");
const abi_package = @import("ashet-abi");

const Machine = kernel_package.Machine;
const Platform = abi_package.Platform;

const default_machines = std.EnumSet(Machine).init(.{
    .@"pc-bios" = true,
    .@"qemu-virt-rv32" = true,
    .@"hosted-x86-linux" = true,
});

const qemu_debug_options_default = "cpu_reset,guest_errors,unimp";

pub fn build(b: *std.Build) void {

    // Options:
    const maybe_run_machine = b.option(Machine, "machine", "Selects which machine to run with the 'run' step");
    const no_gui = b.option(bool, "no-gui", "Disables GUI for runners") orelse false;
    const qemu_debug_options = b.option(
        []const u8,
        "qemu-debug",
        b.fmt("Sets the QEMU debug options (default: '{s}')", .{qemu_debug_options_default}),
    ) orelse
        qemu_debug_options_default;

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

    // Dependencies:

    const debugfilter_dep = b.dependency("debugfilter", .{});

    // Build:

    const debugfilter = debugfilter_dep.artifact("debug-filter");

    for (std.enums.values(Machine)) |machine| {
        const step = machine_steps.get(machine);

        const machine_os_dep = b.dependency("os", .{
            .machine = machine,
        });

        const out_dir: std.Build.InstallDir = .{ .custom = @tagName(machine) };
        const os_files = machine_os_dep.namedWriteFiles("ashet-os");

        for (os_files.files.items) |file| {
            const install_elf_step = b.addInstallFileWithDir(file.getPath(), out_dir, file.sub_path);
            step.dependOn(&install_elf_step.step);
        }
    }

    // Kernel Unit Tests
    {
        const abi_dep = b.dependency("ashet-abi", .{});
        const abi_mod = abi_dep.module("ashet-abi");

        const machine_info = b.addWriteFile("machine_info.zig",
            \\pub const platform_id = .x86;
            \\pub const machine_id = .@"pc-bios";
        ).files.items[0].getPath();

        const machine_info_mod = b.createModule(.{
            .root_source_file = machine_info,
        });

        const kernel_tests = b.addTest(.{
            .root_source_file = b.path("src/kernel/main.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .x86 }),
            .optimize = .Debug,
        });
        kernel_tests.root_module.addImport("machine-info", machine_info_mod);
        kernel_tests.root_module.addImport("args", machine_info_mod);
        kernel_tests.root_module.addImport("ashet-abi", abi_mod);
        test_step.dependOn(&b.addRunArtifact(kernel_tests).step);
    }

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

        const machine_os_dep = b.dependency("os", .{
            .machine = run_machine,
        });

        const os_files = machine_os_dep.namedWriteFiles("ashet-os");

        const kernel_elf = get_named_file(os_files, "kernel.elf").?;
        const disk_img = get_named_file(os_files, "disk.img").?;
        const kernel_bin = get_named_file(os_files, "kernel.bin");

        const AppDef = struct {
            name: []const u8,
            exe: std.Build.LazyPath,
        };

        const apps: []const AppDef = &.{
            .{ .name = "init", .exe = get_named_file(os_files, "apps/init.elf").? },
            .{ .name = "hello-world", .exe = get_named_file(os_files, "apps/hello-world.elf").? },
        };

        const variables = Variables{
            .@"${DISK}" = disk_img,
            .@"${KERNEL}" = kernel_elf,
            .@"${BOOTROM}" = kernel_bin orelse b.path("<missing>"),
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

            if (no_gui) {
                vm_runner.addArgs(&console_qemu_flags);
            } else {
                vm_runner.addArgs(&display_qemu_flags);
            }

            for (machine_info.qemu_cli) |arg| {
                variables.addArg(vm_runner, arg);
            }
        } else {
            vm_runner.addFileArg(kernel_elf);
            for (machine_info.hosted_cli) |arg| {
                variables.addArg(vm_runner, arg);
            }
        }

        if (b.args) |args| {
            vm_runner.addArgs(args);
        }

        vm_runner.stdio = .inherit;
        vm_runner.has_side_effects = true;

        run_step.dependOn(&vm_runner.step);
    }
}

const PlatformStartupConfig = struct {
    qemu_exe: []const u8,
};

const Variables = struct {
    @"${DISK}": std.Build.LazyPath,
    @"${BOOTROM}": std.Build.LazyPath,
    @"${KERNEL}": std.Build.LazyPath,

    pub fn addArg(variables: Variables, runner: *std.Build.Step.Run, arg: []const u8) void {
        inline for (@typeInfo(Variables).Struct.fields) |fld| {
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
    /// - "${BOOTROM}"
    /// - "${DISK}"
    qemu_cli: []const []const u8 = &.{},

    hosted_cli: []const []const u8 = &.{},
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
    .@"pc-bios" = .{
        .qemu_cli = &.{
            "-machine", "pc",
            "-cpu",     "pentium2",
            "-drive",   "if=ide,index=0,format=raw,file=${DISK}",
            "-vga",     "std",
            "--device", "isa-debug-exit",
        },
    },
    .@"qemu-virt-rv32" = .{
        .qemu_cli = &.{
            "-cpu",    "rv32",
            "-M",      "virt",
            "-m",      "32M",
            "-netdev", "user,id=hostnet",
            "-object", "filter-dump,id=hostnet-dump,netdev=hostnet,file=ashet-os.pcap",
            "-device", "virtio-gpu-device,xres=800,yres=480",
            "-device", "virtio-keyboard-device",
            "-device", "virtio-mouse-device",
            "-device", "virtio-net-device,netdev=hostnet,mac=52:54:00:12:34:56",
            "-bios",   "none",
            "-drive",  "if=pflash,index=0,format=raw,file=${BOOTROM}",
            "-drive",  "if=pflash,index=1,format=raw,file=${DISK}",
        },
    },
    .@"qemu-virt-arm" = .{
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
    .@"hosted-x86-linux" = .{
        .hosted_cli = &.{
            "drive:${DISK}",
            "video:sdl:800:480",
        },
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

fn get_named_file(write_files: *std.Build.Step.WriteFile, sub_path: []const u8) ?std.Build.LazyPath {
    return for (write_files.files.items) |file| {
        if (std.mem.eql(u8, file.sub_path, sub_path))
            break file.getPath();
    } else null;
}
