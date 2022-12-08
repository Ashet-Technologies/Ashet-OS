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
