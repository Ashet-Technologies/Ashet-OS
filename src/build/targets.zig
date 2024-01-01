const std = @import("std");

const kernel_targets = @import("../kernel/port/targets.zig");

pub const Platform = kernel_targets.Platform;
pub const Machine = kernel_targets.Machine;

pub const PlatformSpec = struct {
    name: []const u8,
    platform_id: []const u8,
    source_file: []const u8,
    target: std.zig.CrossTarget,

    qemu_exe: []const u8,
};

pub const MachineSpec = struct {
    name: []const u8,
    machine_id: []const u8,
    platform: Platform,
    source_file: []const u8,
    linker_script: []const u8,
    disk_formatter: []const u8, // defined in build.zig

    /// Instantiation:
    /// Uses place holders:
    /// - "${BOOTROM}"
    /// - "${DISK}"
    qemu_cli: []const []const u8,
};

pub fn getPlatformSpec(platform: Platform) *const PlatformSpec {
    return switch (platform) {
        .riscv => comptime &PlatformSpec{
            .name = "RISC-V",
            .platform_id = "riscv",
            .source_file = "src/kernel/port/platform/riscv.zig",
            .target = std.zig.CrossTarget{
                .cpu_arch = .riscv32,
                .os_tag = .freestanding,
                .abi = .eabi,
                .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
                .cpu_features_add = std.Target.riscv.featureSet(&[_]std.Target.riscv.Feature{
                    .c,
                    .m,
                    .reserve_x4, // Don't allow LLVM to use the "tp" register. We want that for our own purposes
                }),
            },
            .qemu_exe = "qemu-system-riscv32",
        },

        .arm => comptime &PlatformSpec{
            .name = "Arm",
            .platform_id = "arm",
            .source_file = "src/kernel/port/platform/arm.zig",
            .target = std.zig.CrossTarget{
                .cpu_arch = .arm,
                .os_tag = .freestanding,
                .abi = .eabi,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.generic },
            },
            .qemu_exe = "qemu-system-arm",
        },

        .x86 => comptime &PlatformSpec{
            .name = "x86",
            .platform_id = "x86",
            .source_file = "src/kernel/port/platform/x86.zig",
            .target = std.zig.CrossTarget{
                .cpu_arch = .x86,
                .os_tag = .freestanding,
                .abi = .musleabi,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.i486 },
                .cpu_features_add = std.Target.x86.featureSet(&.{
                    .soft_float,
                }),
                .cpu_features_sub = std.Target.x86.featureSet(&.{
                    .x87,
                }),
            },
            .qemu_exe = "qemu-system-i386",
        },
    };
}

pub fn getMachineSpec(machine: Machine) *const MachineSpec {
    return switch (machine) {
        // RISC-V machines:
        // pub const ashet_home_computer = MachineSpec{
        //     .name = "Ashet Home Computer",
        //     .machine_id = "ashet_home_computer",
        //     .platform = platforms.specs.riscv,
        //     .source_file = "src/kernel/port/machine/ashet_home_computer/machine.zig",
        //     .linker_script = "src/kernel/port/machine/ashet_home_computer/linker.ld",

        //     .disk_formatter = "ahc",
        // };

        .rv32_virt => comptime &MachineSpec{
            .name = "RISC-V virt",
            .machine_id = "rv32_virt",
            .platform = .riscv,
            .source_file = "src/kernel/port/machine/rv32_virt/rv32_virt.zig",
            .linker_script = "src/kernel/port/machine/rv32_virt/linker.ld",

            .disk_formatter = "rv32_virt",

            .qemu_cli = &.{
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

        // x86 machines:
        .bios_pc => &MachineSpec{
            .name = "Generic PC (BIOS)",
            .machine_id = "bios_pc",
            .platform = .x86,
            .source_file = "src/kernel/port/machine/bios_pc/bios_pc.zig",
            .linker_script = "src/kernel/port/machine/bios_pc/linker.ld",

            .disk_formatter = "bios_pc",

            .qemu_cli = &.{
                "-machine", "pc",
                "-cpu",     "pentium2",
                "-hda",     "${DISK}",
                "-vga",     "std",
            },
        },

        // pub const efi_pc = MachineSpec{
        //     .name = "Generic PC (EFI)",
        //     .machine_id = "efi_pc",
        //     .platform = platforms.specs.x86,
        //     .source_file = "src/kernel/port/machine/efi_pc/machine.zig",
        //     .linker_script = "src/kernel/port/machine/efi_pc/linker.ld",

        //     .disk_formatter = "efi_pc",
        // };

        // pub const microvm = MachineSpec{
        //     .name = "MicroVM",
        //     .machine_id = "microvm",
        //     .platform = platforms.specs.x86,
        //     .source_file = "src/kernel/port/machine/microvm/machine.zig",
        //     .linker_script = "src/kernel/port/machine/microvm/linker.ld",

        //     .disk_formatter = "microvm",
        // };

        // Arm machines:
        // pub const arm_virt = MachineSpec{
        //     .name = "Arm virt",
        //     .machine_id = "arm_virt",
        //     .platform = platforms.specs.arm,
        //     .source_file = "src/kernel/port/machine/arm_virt/machine.zig",
        //     .linker_script = "src/kernel/port/machine/arm_virt/linker.ld",

        //     .disk_formatter = "arm virt",
        // };
    };
}
