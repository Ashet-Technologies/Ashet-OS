const std = @import("std");
const cpu = @import("cpu.zig");
const registers = cpu.registers;

const cache_line_size = 32;

pub fn init() void {
    if (!instructionCacheEnabled()) {
        enableInstructionCache();
    }

    if (!dataCacheEnabled()) {
        enableDataCache();
    }

    if (!level2CacheEnabled()) {
        initializeLevel2Cache();
        enableLevel2Cache();
    }
}

pub fn instructionCacheFlashInvalidate() void {
    registers.HID0.modify(.{
        .icfi = true,
    });
    cpu.isync();
}

pub inline fn instructionCacheEnabled() bool {
    return registers.HID0.read().ice;
}

pub fn enableInstructionCache() void {
    registers.HID0.modify(.{
        .ice = true,
    });
    cpu.isync();
}

pub fn disableInstructionCache() void {
    registers.HID0.modify(.{
        .ice = false,
    });
    cpu.isync();
}

pub fn invalidateInstructionCacheRange(memory: []align(cache_line_size) volatile u8) void {
    const cache_lines = std.math.divCeil(usize, memory.len, cache_line_size) catch unreachable;
    for (0..cache_lines) |i| {
        asm volatile (
            \\icbi %[offset], %[address]
            :
            : [address] "r" (memory.ptr),
              [offset] "r" (i * cache_line_size),
        );
    }

    cpu.sync();
    cpu.isync();
}

pub inline fn dataCacheEnabled() bool {
    return registers.HID0.read().dce;
}

pub fn enableDataCache() void {
    registers.HID0.modify(.{
        .dce = true,
    });
    cpu.isync();
}

pub fn disableDataCache() void {
    registers.HID0.modify(.{
        .dce = false,
    });
    cpu.isync();
}

pub noinline fn flushDataCacheRange(memory: []align(cache_line_size) const volatile u8) void {
    flushDataCacheRangeNoSync(memory);
    cpu.systemCall();
}

pub noinline fn flushDataCacheRangeNoSync(memory: []align(cache_line_size) const volatile u8) void {
    const cache_lines = std.math.divCeil(usize, memory.len, cache_line_size) catch unreachable;
    for (0..cache_lines) |i| {
        asm volatile (
            \\dcbf %[offset], %[address]
            :
            : [address] "r" (memory.ptr),
              [offset] "r" (i * cache_line_size),
        );
    }
}

pub noinline fn invalidateDataCacheRange(memory: []align(cache_line_size) volatile u8) void {
    const cache_lines = std.math.divCeil(usize, memory.len, cache_line_size) catch unreachable;
    for (0..cache_lines) |i| {
        asm volatile (
            \\dcbi %[offset], %[address]
            :
            : [address] "r" (memory.ptr),
              [offset] "r" (i * cache_line_size),
        );
    }
}

pub inline fn level2CacheEnabled() bool {
    return registers.L2CR.read().l2e;
}

pub fn initializeLevel2Cache() void {
    const msr = registers.MSR.read();
    cpu.sync();

    // Enable Instruction and Data Address Translation
    // TODO Isn't this enabled already?
    // TODO This disables everything else, feels wrong
    registers.MSR.write(.{
        .instructionAddressTranslation = true,
        .dataAddressTranslation = true,
    });
    cpu.sync();

    invalidateLevel2Cache();

    // Return to old MSR
    registers.MSR.write(msr);
}

pub fn enableLevel2Cache() void {
    cpu.sync();

    registers.L2CR.modify(.{
        .l2e = true,
        .l2do = false,
        .l2i = false,
    });
    cpu.sync();
}

pub fn disableLevel2Cache() void {
    cpu.sync();

    // Clear L2E bit
    registers.L2CR.modify(.{
        .l2e = false,
    });

    cpu.sync();
}

pub fn invalidateLevel2Cache() void {
    disableLevel2Cache();

    // Set L2I bit (global invalidate)
    registers.L2CR.modify(.{
        .l2i = true,
    });

    // Wait for L2IP bit to be 0 (invalidate progress)
    while (registers.L2CR.read().l2ip) {}

    // Clear L2DO and L2I bits
    registers.L2CR.modify(.{
        .l2do = false,
        .l2i = false,
    });

    // Wait for L2IP bit to be 0 (invalidate progress)
    while (registers.L2CR.read().l2ip) {}
}
