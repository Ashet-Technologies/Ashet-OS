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

pub fn build(b: *std.Build) void {
    // Steps:

    const machine_steps = blk: {
        var steps = std.EnumArray(Machine, *std.Build.Step).initUndefined();
        for (std.enums.values(Machine)) |machine| {
            const step = b.step(
                @tagName(machine),
                b.fmt("Compiles the OS for {s}", .{@tagName(machine)}),
            );
            if (default_machines.contains(machine)) {
                b.getInstallStep().dependOn(step);
            }
            steps.set(machine, step);
        }
        break :blk steps;
    };

    // Options:
    const maybe_run_machine = b.option(Machine, "machine", "Selects which machine to run with the 'run' step");
    const no_gui = b.option(bool, "no-gui", "Disables GUI for runners") orelse false;

    // Dependencies:

    const debugfilter_dep = b.dependency("debugfilter", .{});

    // Build:

    const debugfilter = debugfilter_dep.artifact("debug-filter");

    for (std.enums.values(Machine)) |machine| {
        const step = machine_steps.get(machine);

        const machine_os_dep = b.dependency("os", .{
            .machine = machine,
        });

        const install_step = b.addInstallDirectory(.{
            .source_dir = .{ .cwd_relative = machine_os_dep.builder.install_prefix },
            .install_dir = .prefix,
            .install_subdir = @tagName(machine),
        });
        install_step.step.dependOn(machine_os_dep.builder.getInstallStep());
        step.dependOn(&install_step.step);
    }

    // Run:

    if (maybe_run_machine) |run_machine| {
        const run_step = b.step("run", b.fmt("Runs the OS machine {s}", .{@tagName(run_machine)}));

        const platform_info = platform_info_map.get(run_machine.get_platform());
        const machine_info = machine_info_map.get(run_machine);

        const disk_img: std.Build.LazyPath = if (true) @panic("oh no") else false;
        const kernel_bin: std.Build.LazyPath = if (true) @panic("oh no") else false;
        const kernel_elf: std.Build.LazyPath = if (true) @panic("oh no") else false;

        const AppDef = struct {
            name: []const u8,
            exe: std.Build.LazyPath,
        };

        const apps: []const AppDef = &.{};

        const Variables = struct {
            @"${DISK}": std.Build.LazyPath,
            @"${BOOTROM}": std.Build.LazyPath,
            @"${KERNEL}": std.Build.LazyPath,
        };

        const variables = Variables{
            .@"${DISK}" = disk_img,
            .@"${BOOTROM}" = kernel_bin,
            .@"${KERNEL}" = kernel_elf,
        };

        // Run qemu with the debug-filter wrapped around so we can translate addresses
        // to file:line,function info
        const vm_runner = b.addRunArtifact(debugfilter);

        // Add debug elf contexts:
        vm_runner.addArg("--elf");
        vm_runner.addPrefixedFileArg("kernel=", kernel_elf);

        for (apps) |app| {
            var app_name_buf: [128]u8 = undefined;

            const app_name = try std.fmt.bufPrint(&app_name_buf, "{s}=", .{app.name});

            vm_runner.addArg("--elf");
            vm_runner.addPrefixedFileArg(app_name, app.exe);
        }

        // from now on regular QEMU flags:
        vm_runner.addArg(platform_info.qemu_exe);
        vm_runner.addArgs(&generic_qemu_flags);

        if (no_gui) {
            vm_runner.addArgs(&console_qemu_flags);
        } else {
            vm_runner.addArgs(&display_qemu_flags);
        }

        arg_loop: for (machine_info.qemu_cli) |arg| {
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

const PlatformStartupConfig = struct {
    qemu_exe: []const u8,
};

const MachineStartupConfig = struct {
    /// Instantiation:
    /// Uses place holders:
    /// - "${BOOTROM}"
    /// - "${DISK}"
    qemu_cli: []const []const u8,
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
            "-hda",     "${DISK}",
            "-vga",     "std",
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
        .qemu_cli = &.{},
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
