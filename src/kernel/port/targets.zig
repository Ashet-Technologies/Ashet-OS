const std = @import("std");
const ashet = @import("../main.zig");

pub const Platform = enum {
    riscv,
    arm,
    x86,
};

pub const Machine = enum {
    rv32_virt,
    bios_pc,
};

pub const MachineConfig = struct {
    /// If this is set, the kernel will initialize the `.data` and `.bss` sections.
    load_sections: ashet.memory.MemorySections,
};

// pub fn platform_code(comptime platform: Platform) type {
//     return switch (platform) {
//         .riscv => @import("riscv.zig"),
//         .arm => @import("arm.zig"),
//         .x86 => @import("x86.zig"),
//     };
// }

// pub fn machine_code(comptime machine: Machine) type {
//     return switch (machine) {
//         .ashet_home_computer => @import("ashet_home_computer/ashet_home_computer.zig"),
//         .rv32_virt => @import("rv32_virt/rv32_virt.zig"),
//         .bios_pc => @import("bios_pc/bios_pc.zig"),
//         .efi_pc => @import("efi_pc/efi_pc.zig"),
//         .microvm => @import("microvm/microvm.zig"),
//         .arm_virt => @import("arm_virt/arm_virt.zig"),
//     };
// }
