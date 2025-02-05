const std = @import("std");
const ashet = @import("../main.zig");

pub const Machine = @import("machine_id.zig").MachineID;

pub const Platform = ashet.abi.Platform;

pub const MachineConfig = struct {
    /// If this is set, the kernel will initialize the `.data` and `.bss` sections.
    load_sections: ashet.memory.MemorySections,

    /// Provides function implementations for memory protections.
    memory_protection: ?MemoryProtectionConfig,

    /// Performs early machine initialization, directly after the kernel
    /// initialized '.data' and '.bss' sections.
    early_initialize: ?fn () void,

    /// Initializes the machine devices and drivers.
    initialize: fn () anyerror!void,

    /// A function that writes debug output for the machine.
    /// This may be a no-op and discard the data if no debug output is available.
    debug_write: fn ([]const u8) void,

    /// Returns the linear memory region in which the OS can allocate
    /// memory pages.
    get_linear_memory_region: fn () ashet.memory.Range,

    /// Returns the number of ticks in milliseconds since system start.
    get_tick_count_ms: fn () u64,
};

pub const MemoryProtectionConfig = struct {
    activate: fn () void,
    initialize: fn () error{OutOfMemory}!void,
    update: fn (ashet.memory.Range, ashet.memory.protection.Protection) void,
    get_protection: fn (address: usize) ashet.memory.protection.Protection,
    get_info: ?fn (address: usize) ashet.memory.protection.AddressInfo,
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
