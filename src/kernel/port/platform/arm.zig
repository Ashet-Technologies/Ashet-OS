const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("kernel");

const a_profile = @import("arm/a-profile.zig");
const m_profile = @import("arm/m-profile.zig");

const ArmProfile = enum {
    a,
    m,
};

pub const profile_type: ArmProfile = blk: {
    const CpuFeature = std.Target.arm.Feature;

    const supported_m_profiles = [_]CpuFeature{
        .v7m,
        .v8m,
        .v8m_main,
        .v8_1m_main,
    };
    const supported_a_profiles = [_]CpuFeature{
        .v7a,
        .v8a,
    };

    // we only support Thumb CPUs
    std.debug.assert(builtin.cpu.arch.isThumb());

    const is_m_profile = std.Target.arm.featureSetHasAny(builtin.cpu.features, &supported_m_profiles);
    const is_a_profile = std.Target.arm.featureSetHasAny(builtin.cpu.features, &supported_a_profiles);

    if (is_a_profile and is_m_profile) {
        @compileError("Cpu was detected both A and M profile. That should not happen.");
    }

    if (!is_a_profile and !is_m_profile) {
        @compileError("Cpu is not supported by Ashet OS.");
    }

    std.debug.assert(is_a_profile != is_m_profile);

    break :blk if (is_a_profile)
        .a
    else
        .m;
};

pub const profile = switch (profile_type) {
    .a => a_profile,
    .m => m_profile,
};

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = profile.start;

pub inline fn getStackPointer() usize {
    return asm (""
        : [sp] "={sp}" (-> usize),
    );
}

pub inline fn areInterruptsEnabled() bool {
    // Read PRIMASK register. When bit 0 is 0, interrupts are enabled.
    // When bit 0 is 1, interrupts are disabled.
    var primask: u32 = undefined;
    asm volatile ("mrs %[ret], primask"
        : [ret] "=r" (primask),
    );
    return (primask & 1) == 0;
}

pub inline fn isInInterruptContext() bool {
    return profile.executing_isr();
}

pub inline fn disableInterrupts() void {
    profile.disable_interrupts();
}

pub inline fn enableInterrupts() void {
    profile.enable_interrupts();
}

pub fn get_cpu_cycle_counter() u64 {
    return 0;
}

pub fn get_cpu_random_seed() ?u64 {
    return null;
}
