const std = @import("std");
const ashet = @import("kernel");

pub const page_size = std.mem.page_size;

pub const scheduler = struct {
    //
};

pub const start = struct {
    // pub export var multiboot_info: ?*multiboot.Info = null;

    // comptime {
    //     @export(multiboot_info, .{
    //         .name = "ashet_x86_kernel_multiboot_info",
    //     });

    //     // the startup routine must be written in assembler to
    //     // guarantee that no stack and register is touched is used until
    //     // we saved
    //     asm (
    //         \\.section .text
    //         \\.global _start
    //         \\_start:
    //         \\  mov $kernel_stack, %esp
    //         \\  cmpl $0x2BADB002, %eax
    //         \\  jne .no_multiboot
    //         \\
    //         \\.has_multiboot:
    //         \\  movl %ebx, ashet_x86_kernel_multiboot_info
    //         \\  call ashet_kernelMain
    //         \\  jmp hang
    //         \\
    //         \\.no_multiboot:
    //         \\  movl $0, ashet_x86_kernel_multiboot_info
    //         \\  call ashet_kernelMain
    //         \\
    //         \\hang:
    //         \\  cli
    //         \\  hlt
    //         \\  jmp hang
    //         \\
    //     );
    // }
};

pub inline fn getStackPointer() usize {
    return asm (""
        : [sp] "={esp}" (-> usize),
    );
}

pub fn areInterruptsEnabled() bool {
    return false;
}

pub fn disableInterrupts() void {
    //
}
pub fn enableInterrupts() void {
    //
}
