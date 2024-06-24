const std = @import("std");
const kernel_package = @import("kernel");

const Machine = kernel_package.Machine;

pub fn build(b: *std.Build) void {
    // Steps:

    const machine_steps = blk: {
        var steps = std.EnumArray(Machine, *std.Build.Step).initUndefined();
        for (std.enums.values(Machine)) |machine| {
            const step = b.step(
                @tagName(machine),
                b.fmt("Compiles the OS for {s}", .{@tagName(machine)}),
            );
            b.getInstallStep().dependOn(step);
            steps.set(machine, step);
        }
        break :blk steps;
    };

    // Options:
    const maybe_run_machine = b.option(Machine, "machine", "Selects which machine to run with the 'run' step");

    // Build:

    _ = machine_steps;

    if (maybe_run_machine) |run_machine| {
        const run_step = b.step("run", b.fmt("Runs the OS machine {s}", .{@tagName(run_machine)}));

        // TODO: Implement run step here!
        _ = run_step;
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

const platform_info_map = std.EnumArray(PlatformStartupConfig, PlatformStartupConfig).init(.{
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
