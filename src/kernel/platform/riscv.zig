const std = @import("std");
const ashet = @import("../main.zig");

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = struct {
    export fn handleTrap() align(4) callconv(.C) noreturn {
        @panic("unhandled trap");
    }

    comptime {
        asm (
            \\.section .text._start
            \\.global _start
            \\_start:
            \\  la   sp, kernel_stack // defined in linker script 
            \\
            \\  la     t0, handleTrap
            \\  csrw   mtvec, t0
            \\
            \\  call ashet_kernelMain
            \\
            \\  li      t0, 0x38
            \\  csrc    mstatus, t0
            \\
            \\hang:
            \\  wfi
            \\  j hang
            \\
        );
    }
};

pub inline fn getStackPointer() usize {
    return asm (""
        : [sp] "={sp}" (-> usize),
    );
}

noinline fn readHwCounter() u64 {
    var res: u64 = undefined;
    asm volatile (
        \\read_hwcnt_loop:
        \\  rdcycleh t0 // hi
        \\  rdcycle  t1 // lo
        \\  rdcycleh t2 // check
        \\  bne t0, t2, read_hwcnt_loop
        \\  sw t0, 4(%[ptr])
        \\  sw t1, 0(%[ptr])
        :
        : [ptr] "r" (&res),
        : "{t0}", "{t1}", "{t2}"
    );
    return res;
}

pub fn areInterruptsEnabled() bool {
    return false;
}
pub fn disableInterrupts() void {}
pub fn enableInterrupts() void {}
