const std = @import("std");

const kernel_package = @import("kernel");

const TargetMachine = kernel_package.TargetMachine;

pub fn build(b: *std.Build) void {
    // Options:
    const machine = b.option(TargetMachine, "machine", "What machine should AshetOS be built for?") orelse @panic("no machine defined!");
    const optimize = b.standardOptimizeOption(.{});

    const target = machine.get_target();

    // Build:

    _ = target;
    _ = optimize;

    // TODO: Compile disk image for a single target here
}

const MachineDependentOsConfig = struct {
    //
};

const machine_info_map = std.EnumArray(TargetMachine, MachineDependentOsConfig).init(.{
    .@"pc-bios" = .{
        .disk_formatter = "bios_pc",
        .rom_size = null,
    },
    .@"qemu-virt-rv32" = .{
        .disk_formatter = "rv32_virt",
        .rom_size = 0x0200_0000,
    },
    .@"qemu-virt-arm" = .{
        .disk_formatter = "arm_virt",
        .rom_size = 0x0400_0000,
    },
    .@"hosted-x86-linux" = .{
        .disk_formatter = "linux_pc",
        .rom_size = null,
    },
});
