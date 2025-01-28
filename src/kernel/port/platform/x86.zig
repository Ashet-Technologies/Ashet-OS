const std = @import("std");

pub const multiboot = @import("x86/multiboot.zig");
pub const gdt = @import("x86/gdt.zig");
pub const idt = @import("x86/idt.zig");
pub const vmm = @import("x86/vmm.zig");
pub const cmos = @import("x86/cmos.zig");
pub const registers = @import("x86/registers.zig");

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = struct {
    pub export var multiboot_info: ?*multiboot.Info = null;

    comptime {
        @export(multiboot_info, .{
            .name = "ashet_x86_kernel_multiboot_info",
        });

        // the startup routine must be written in assembler to
        // guarantee that no stack and register is touched is used until
        // we saved
        asm (
            \\.section .text
            \\.global _start
            \\_start:
            \\  mov $__kernel_stack_end, %esp
            \\  cmpl $0x2BADB002, %eax
            \\  jne .no_multiboot
            \\
            \\.has_multiboot:
            \\  movl %ebx, ashet_x86_kernel_multiboot_info
            \\  call ashet_kernelMain
            \\  jmp hang
            \\
            \\.no_multiboot:
            \\  movl $0, ashet_x86_kernel_multiboot_info
            \\  call ashet_kernelMain
            \\
            \\hang:
            \\  cli
            \\  hlt
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

pub fn areInterruptsEnabled() bool {
    const flags = asm (
        \\pushfd
        \\pop %[res]
        : [res] "=r" (-> registers.EFLAGS),
        :
        : "stack"
    );
    return flags.interrupt_enable; // 9th bit is "interrupts are enabled"
}

pub const isInInterruptContext = idt.isInInterruptContext;
pub const disableInterrupts = idt.disableExternalInterrupts;
pub const enableInterrupts = idt.enableExternalInterrupts;

/// Implements the `out` instruction for an x86 processor.
/// `type` must be one of `u8`, `u16`, `u32`, `port` is the
/// port number and `value` will be sent to that port.
pub inline fn out(comptime T: type, port: u16, value: T) void {
    // if (port != 0x3F8 and port != 0x80) {
    //     logger.debug("out(0x{X:0>4}, {X:0>2})", .{
    //         port, value,
    //     });
    // }
    switch (T) {
        u8 => asm volatile ("outb %[value], %[port]"
            :
            : [port] "{dx}" (port),
              [value] "{al}" (value),
        ),
        u16 => asm volatile ("outw %[value], %[port]"
            :
            : [port] "{dx}" (port),
              [value] "{ax}" (value),
        ),
        u32 => asm volatile ("outl %[value], %[port]"
            :
            : [port] "{dx}" (port),
              [value] "{eax}" (value),
        ),
        else => @compileError("Only u8, u16 or u32 are allowed for port I/O!"),
    }
}

/// Implements the `in` instruction for an x86 processor.
/// `type` must be one of `u8`, `u16`, `u32`, `port` is the
/// port number and the value received from that port will be returned.
pub inline fn in(comptime T: type, port: u16) T {
    return switch (T) {
        u8 => asm volatile ("inb  %[port], %[ret]"
            : [ret] "={al}" (-> u8),
            : [port] "{dx}" (port),
        ),
        u16 => asm volatile ("inw  %[port], %[ret]"
            : [ret] "={ax}" (-> u16),
            : [port] "{dx}" (port),
        ),
        u32 => asm volatile ("inl  %[port], %[ret]"
            : [ret] "={eax}" (-> u32),
            : [port] "{dx}" (port),
        ),
        else => @compileError("Only u8, u16 or u32 are allowed for port I/O!"),
    };
}

/// Perform a short I/O delay.
pub fn waitIO() void {
    // see:
    // https://wiki.osdev.org/Inline_Assembly/Examples#IO_WAIT

    // port 0x80 was wired to a hex display in the past and
    // is now mostly unused. This should be a safe no-op.
    out(u8, 0x80, 0);
}

pub fn get_cpu_cycle_counter() u64 {
    return rdtsc();
}

pub fn get_cpu_random_seed() ?u64 {
    return rdseed();
}

/// Invokes x86 Read Time-Stamp Counter instruction
fn rdtsc() u64 {
    var a: u32 = undefined;
    var b: u32 = undefined;
    asm volatile ("rdtsc"
        : [a] "={edx}" (a),
          [b] "={eax}" (b),
        :
        : "ecx"
    );
    return (@as(u64, a) << 32) | b;
}

/// Invokes x86 Read Random SEED instructions
fn rdseed() ?u64 {
    const features = @import("builtin").target.cpu.features;
    if (!std.Target.x86.featureSetHas(features, .rdseed)) return null;

    var v: u64 = undefined;
    asm volatile ("rdseed %[out]"
        : [out] "=r" (v),
    );
    return v;
}
