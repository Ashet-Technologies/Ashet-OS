const std = @import("std");
const ashet = @import("../main.zig");

pub const Platform = enum {
    riscv,
    arm,
    x86,
    hosted,
};

pub const Machine = enum {
    rv32_virt,
    arm_virt,
    bios_pc,
    linux_pc,
};

pub const MachineConfig = struct {
    /// If this is set, the kernel will initialize the `.data` and `.bss` sections.
    load_sections: ashet.memory.MemorySections,
};

pub const platforms = struct {
    pub const riscv = @import("platform/riscv.zig");
    pub const arm = @import("platform/arm.zig");
    pub const x86 = @import("platform/x86.zig");
    pub const hosted = @import("platform/hosted.zig");
};

pub const machines = struct {
    pub const rv32_virt = @import("machine/rv32_virt/rv32_virt.zig");
    pub const arm_virt = @import("machine/arm_virt/arm_virt.zig");
    pub const bios_pc = @import("machine/bios_pc/bios_pc.zig");
    pub const linux_pc = @import("machine/linux_pc/linux_pc.zig");
};
