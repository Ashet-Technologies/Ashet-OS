pub const registers = @import("registers.zig");

pub inline fn isync() void {
    asm volatile ("isync");
}

pub inline fn sync() void {
    asm volatile ("sync");
}

pub inline fn returnFromInterrupt() void {
    asm volatile ("rfi");
}

pub inline fn systemCall() void {
    asm volatile ("sc");
}

pub inline fn disableInterrupts() bool {
    var msr = registers.MSR.read();
    const ee = msr.externalInterrupt;
    msr.externalInterrupt = false;
    registers.MSR.write(msr);
    return ee;
}

pub inline fn enableInterrupts(enable: bool) void {
    if (enable) {
        registers.MSR.modify(.{
            .externalInterrupt = true,
        });
    }
}
