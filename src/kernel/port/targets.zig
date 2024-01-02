const std = @import("std");
const ashet = @import("../main.zig");

pub const Platform = enum {
    riscv,
    arm,
    x86,
};

pub const Machine = enum {
    rv32_virt,
    arm_virt,
    bios_pc,
};

pub const MachineConfig = struct {
    /// If this is set, the kernel will initialize the `.data` and `.bss` sections.
    load_sections: ashet.memory.MemorySections,
};
