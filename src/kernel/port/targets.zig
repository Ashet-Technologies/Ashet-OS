const std = @import("std");
const ashet = @import("../main.zig");

pub const Machine = @import("machine_id.zig").MachineID;

pub const Platform = ashet.abi.Platform;

pub const MachineConfig = struct {
    /// If this is set, the kernel will initialize the `.data` and `.bss` sections.
    load_sections: ashet.memory.MemorySections,

    memory_protection: ?MemoryProtectionConfig,
};

pub const MemoryProtectionConfig = struct {
    activate: fn () void,
    initialize: fn () error{OutOfMemory}!void,
    update: fn (ashet.memory_protection.Range, ashet.memory_protection.Protection) void,
};

pub const platforms = struct {
    pub const riscv = @import("platform/rv32.zig");
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
