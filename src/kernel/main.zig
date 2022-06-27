const std = @import("std");
const hal = @import("hal");

export fn ashet_kernelMain() void {
    hal.initialize();

    hal.serial.write(.COM1, "Hello, World!\r\n");

    while (true) {
        //
    }
}

comptime {
    asm (
        \\.section .text
        \\.global _start
        \\_start:
        \\  la   sp, stack
        \\
        \\  call ashet_kernelMain
        \\
        \\  li      t0, 0x38 
        \\  csrc    mstatus, t0
        \\
        \\hang:
        \\wfi
        \\  j hang
        \\
        \\.section .bss
        \\.zero 4096
        \\stack:
    );
}
