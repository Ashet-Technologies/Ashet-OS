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
    //         \\  mov $__kernel_stack_end, %esp
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

var global_lock: std.Thread.Mutex = .{};
var interrupt_flag: bool = true;

pub fn areInterruptsEnabled() bool {
    return interrupt_flag;
}

pub fn disableInterrupts() void {
    global_lock.lock();
    interrupt_flag = false;
}

pub fn enableInterrupts() void {
    interrupt_flag = true;
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
