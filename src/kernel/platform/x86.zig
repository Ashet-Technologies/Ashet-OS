const std = @import("std");
const ashet = @import("../main.zig");

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = struct {
    comptime {
        asm (
            \\.section .text._start
            \\.global _start
            \\_start:
            \\  mov kernel_stack, %esp // defined in linker script 
            \\
            \\  call ashet_kernelMain
            \\
            \\hang:
            \\  cli
            \\  jmp hang
            \\
        );
    }
};

pub inline fn getStackPointer() usize {
    return asm (""
        : [sp] "={esp}" (-> usize),
    );
}
