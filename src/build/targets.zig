const std = @import("std");

const kernel_targets = @import("../kernel/port/targets.zig");

pub const Platform = kernel_targets.Platform;
pub const Machine = kernel_targets.Machine;

pub const PlatformSpec = struct {
    name: []const u8,
    platform_id: []const u8,
    source_file: []const u8,
    target: std.Target.Query,
    start_file: ?std.Build.LazyPath,

    qemu_exe: []const u8,
};

pub const MachineSpec = struct {
    name: []const u8,
    machine_id: []const u8,
    platform: Platform,
    source_file: []const u8,
    linker_script: []const u8,
    disk_formatter: []const u8, // defined in build.zig
    rom_size: ?usize,

    start_file: ?std.Build.LazyPath,
    alt_target: ?std.zig.CrossTarget,

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
            .start_file = null,
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
            .start_file = null,
            .target = std.zig.CrossTarget{
                .cpu_arch = .thumb,
                .os_tag = .freestanding,
                .abi = .eabi,
                .cpu_model = .{
                    // .explicit = &std.Target.arm.cpu.cortex_a7, // this seems to be a pretty reasonable base line
                    .explicit = &std.Target.arm.cpu.generic,
                },
                .cpu_features_add = std.Target.arm.featureSet(&.{
                    .v7a,
                }),
                .cpu_features_sub = std.Target.arm.featureSet(&.{
                    .v7a, // this is stupid, but it keeps out all the neon stuff we don't wnat

                    // drop everything FPU related:
                    .neon,
                    .neonfp,
                    .neon_fpmovs,
                    .fp64,
                    .fpregs,
                    .fpregs64,
                    .vfp2,
                    .vfp2sp,
                    .vfp3,
                    .vfp3d16,
                    .vfp3d16sp,
                    .vfp3sp,
                }),
            },
            .qemu_exe = "qemu-system-arm",
        },

        .x86 => comptime &PlatformSpec{
            .name = "x86",
            .platform_id = "x86",
            .source_file = "src/kernel/port/platform/x86.zig",
            .start_file = null,
            .target = .{
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

        .hosted => comptime &PlatformSpec{
            .name = "hosted",
            .platform_id = "hosted",
            .source_file = "src/kernel/port/platform/hosted.zig",
            .start_file = .{ .cwd_relative = "src/kernel/port/platform/hosted-startup.zig" },
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .freestanding,
                .abi = .musl,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
            },
            .qemu_exe = "echo",
        },
    };
}

pub fn getMachineSpec(machine: Machine) *const MachineSpec {
    return switch (machine) {
        // RISC-V machines:
        // pub const ashet_home_computer =&comptime  MachineSpec{
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
            .start_file = null,
            .linker_script = "src/kernel/port/machine/rv32_virt/linker.ld",

            .disk_formatter = "rv32_virt",
            .alt_target = null,

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

            .rom_size = 0x0200_0000,
        },

        // x86 machines:
        .bios_pc => comptime &MachineSpec{
            .name = "Generic PC (BIOS)",
            .machine_id = "bios_pc",
            .platform = .x86,
            .source_file = "src/kernel/port/machine/bios_pc/bios_pc.zig",
            .start_file = null,
            .linker_script = "src/kernel/port/machine/bios_pc/linker.ld",

            .disk_formatter = "bios_pc",
            .alt_target = null,

            .qemu_cli = &.{
                "-machine", "pc",
                "-cpu",     "pentium2",
                "-hda",     "${DISK}",
                "-vga",     "std",
            },

            .rom_size = null,
        },

        .linux_pc => comptime &MachineSpec{
            .name = "Hosted (x86 Linux)",
            .machine_id = "linux_pc",
            .platform = .hosted,
            .source_file = "src/kernel/port/machine/linux_pc/linux_pc.zig",
            .start_file = null,
            .linker_script = "src/kernel/port/machine/linux_pc/linker.ld",

            .disk_formatter = "linux_pc",
            .alt_target = std.zig.CrossTarget{
                .cpu_arch = .x86,
                .os_tag = .linux,
                .abi = .gnu,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
                .dynamic_linker = std.Target.DynamicLinker.init("/nix/store/xlyscnvzz5l3pkvf280qp5czg387b98f-glibc-2.38-44/lib/ld-linux.so.2"),
            },

            .qemu_cli = &.{},

            .rom_size = null,
        },

        // pub const efi_pc =&comptime  MachineSpec{ (qemu-system-x86_64)
        //     .name = "Generic PC (EFI)",
        //     .machine_id = "efi_pc",
        //     .platform = platforms.specs.x86,
        //     .source_file = "src/kernel/port/machine/efi_pc/machine.zig",
        //     .linker_script = "src/kernel/port/machine/efi_pc/linker.ld",

        //     .disk_formatter = "efi_pc",
        //     .qemu_cli = &.{
        //         "-cpu", "qemu64",
        //         "-drive", "if=pflash,format=raw,unit=0,file=/usr/share/qemu/edk2-x86_64-code.fd,readonly=on",
        //         "-drive", "if=ide,format=raw,unit=0,file=${DISK}",
        //     }
        // };

        // pub const microvm = &comptime MachineSpec{
        //     .name = "MicroVM",
        //     .machine_id = "microvm",
        //     .platform = platforms.specs.x86,
        //     .source_file = "src/kernel/port/machine/microvm/machine.zig",
        //     .linker_script = "src/kernel/port/machine/microvm/linker.ld",

        //     .disk_formatter = "microvm",

        //     .qemu_cli = &.{
        //         "-M",      "microvm",
        //         "-m",      "32M",
        //         "-netdev", "user,id=hostnet",
        //         "-object", "filter-dump,id=hostnet-dump,netdev=hostnet,file=ashet-os.pcap",
        //         "-device", "virtio-gpu-device,xres=400,yres=300",
        //         "-device", "virtio-keyboard-device",
        //         "-device", "virtio-mouse-device",
        //         "-device", "virtio-net-device,netdev=hostnet,mac=52:54:00:12:34:56",
        //     }
        // };

        // Arm machines:
        .arm_virt => &comptime MachineSpec{
            .name = "Arm virt",
            .machine_id = "arm_virt",
            .platform = .arm,
            .source_file = "src/kernel/port/machine/arm_virt/arm_virt.zig",
            .start_file = null,
            .linker_script = "src/kernel/port/machine/arm_virt/linker.ld",

            .disk_formatter = "arm_virt",
            .alt_target = null,

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

            .rom_size = 0x0400_0000,
        },
    };
}
