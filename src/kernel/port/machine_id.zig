const std = @import("std");

pub const MachineID = enum {
    // pi400,
    // ox64,
    @"pc-bios",
    // @"pc-efi",
    // gamecube,
    @"qemu-virt-rv32",
    @"qemu-virt-arm",
    @"hosted-x86-linux",
    // @"hosted-x86_64-windows",

    pub fn is_hosted(target: MachineID) bool {
        return std.mem.startsWith(u8, @tagName(target), "hosted-");
    }

    pub fn get_display_name(target: MachineID) []const u8 {
        return switch (target) {
            .@"pc-bios" => "x86 PC (BIOS)",
            .@"qemu-virt-rv32" => "QEMU virt (RISC-V)",
            .@"qemu-virt-arm" => "QEMU virt (Arm)",
            .@"hosted-x86-linux" => "OS Hosted (x86, Linux)",
        };
    }
};
