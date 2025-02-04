const std = @import("std");
const abi = @import("ashet-abi");

///
/// The MachineID defines the target machine for which the kernel and operating system will be built.
///
/// It follows the schema `platform-vendor-machine` where `vendor` is a context and `machine` is a
/// concrete realization of that context.
///
pub const MachineID = enum {
    @"arm-ashet-hc",
    @"arm-ashet-vhc",
    @"arm-qemu-virt",
    // @"arm-raspberrypi-pi400",

    @"rv32-qemu-virt",
    // @"rv32-ashet-hc",
    // @"rv32-pine64-ox64",

    @"x86-hosted-linux",
    // @"x86-hosted-windows",

    @"x86-pc-bios",
    // @"x86-pc-efi",

    // @"ppc-nintendo-gamecube",

    pub fn is_hosted(target: MachineID) bool {
        return switch (target) {
            .@"arm-ashet-vhc",
            .@"arm-ashet-hc",
            .@"arm-qemu-virt",
            .@"rv32-qemu-virt",
            .@"x86-pc-bios",
            => false,

            .@"x86-hosted-linux",
            => true,
        };
    }

    pub fn get_display_name(target: MachineID) []const u8 {
        return switch (target) {
            .@"arm-ashet-hc" => "Ashet Home Computer",
            .@"arm-ashet-vhc" => "Ashet Virtual Home Computer",
            .@"arm-qemu-virt" => "QEMU virt (Arm)",
            .@"rv32-qemu-virt" => "QEMU virt (RISC-V)",
            .@"x86-hosted-linux" => "OS Hosted (x86, Linux)",
            .@"x86-pc-bios" => "x86 PC (BIOS)",
        };
    }

    pub fn get_platform(target: MachineID) abi.Platform {
        return switch (target) {
            .@"arm-qemu-virt",
            .@"arm-ashet-vhc",
            .@"arm-ashet-hc",
            => .arm,

            .@"rv32-qemu-virt",
            => .rv32,

            .@"x86-hosted-linux",
            .@"x86-pc-bios",
            => .x86,
        };
    }
};
