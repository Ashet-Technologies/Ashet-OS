const std = @import("std");
const ashet = @import("kernel");
const builtin = @import("builtin");

comptime {
    if (builtin.single_threaded) {
        @compileError("hosted builds must be compiled as multi-threaded!");
    }
}

pub const page_size = std.mem.page_size;

pub const scheduler = struct {
    //
};

pub const start = struct {};

pub inline fn getStackPointer() usize {
    return asm (""
        : [sp] "={esp}" (-> usize),
    );
}

var global_lock: std.Thread.Mutex = .{};
var interrupt_flag: bool = true;

pub fn areInterruptsEnabled() bool {
    return @atomicLoad(bool, &interrupt_flag, .seq_cst);
}

pub inline fn isInInterruptContext() bool {
    return false; // Hosted systems don't know interrupts.
}

pub fn disableInterrupts() void {
    global_lock.lock();
    std.debug.assert(areInterruptsEnabled());
    @atomicStore(bool, &interrupt_flag, false, .seq_cst);
}

pub fn enableInterrupts() void {
    std.debug.assert(!areInterruptsEnabled());
    @atomicStore(bool, &interrupt_flag, true, .seq_cst);
    global_lock.unlock();
}

pub fn get_cpu_cycle_counter() u64 {
    // return @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())));

    var buf: [8]u8 = undefined;
    // almost everything should support this
    std.posix.getrandom(&buf) catch @panic("unsupported call");
    return @bitCast(buf);
}

pub fn get_cpu_random_seed() ?u64 {
    var seed: u64 = 0;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch @panic("getrandom failed");
    return seed;
}
