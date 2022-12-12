const std = @import("std");
const x86 = @import("../x86.zig");

pub const InterruptHandler = *const fn (*CpuState) *CpuState;

var irqHandlers = [_]?InterruptHandler{null} ** 32;

pub fn set_IRQ_Handler(irq: u4, handler: ?InterruptHandler) void {
    irqHandlers[irq] = handler;
}

export fn handle_interrupt(_cpu: *CpuState) *CpuState {
    var cpu = _cpu;
    switch (cpu.interrupt) {
        0x00...0x1F => {
            // Exception
            std.log.err("Unhandled exception: {s}", .{@as([]const u8, switch (cpu.interrupt) {
                0x00 => "Divide By Zero",
                0x01 => "Debug",
                0x02 => "Non Maskable Interrupt",
                0x03 => "Breakpoint",
                0x04 => "Overflow",
                0x05 => "Bound Range",
                0x06 => "Invalid Opcode",
                0x07 => "Device Not Available",
                0x08 => "Double Fault",
                0x09 => "Coprocessor Segment Overrun",
                0x0A => "Invalid TSS",
                0x0B => "Segment not Present",
                0x0C => "Stack Fault",
                0x0D => "General Protection Fault",
                0x0E => "Page Fault",
                0x0F => "Reserved",
                0x10 => "x87 Floating Point",
                0x11 => "Alignment Check",
                0x12 => "Machine Check",
                0x13 => "SIMD Floating Point",
                0x14...0x1D => "Reserved",
                0x1E => "Security-sensitive event in Host",
                0x1F => "Reserved",
                else => "Unknown",
            })});
            std.log.err("{}", .{cpu});

            if (cpu.interrupt == 0x0E) {
                const cr2 = asm volatile ("mov %%cr2, %[cr]"
                    : [cr] "=r" (-> usize),
                );
                const cr3 = asm volatile ("mov %%cr3, %[cr]"
                    : [cr] "=r" (-> usize),
                );
                _ = cr3;
                std.log.err("Page Fault when {1s} address 0x{0X} from {3s}: {2s}", .{
                    cr2,
                    if ((cpu.errorcode & 2) != 0) @as([]const u8, "writing") else @as([]const u8, "reading"),
                    if ((cpu.errorcode & 1) != 0) @as([]const u8, "access denied") else @as([]const u8, "page unmapped"),
                    if ((cpu.errorcode & 4) != 0) @as([]const u8, "userspace") else @as([]const u8, "kernelspace"),
                });
            }

            while (true) {
                asm volatile (
                    \\ cli
                    \\ hlt
                );
            }
        },
        0x20...0x2F => {
            // IRQ
            if (irqHandlers[cpu.interrupt - 0x20]) |handler| {
                cpu = handler(cpu);
            } else {
                std.log.warn("Unhandled IRQ{}: {}", .{ cpu.interrupt - 0x20, cpu });
            }

            if (cpu.interrupt >= 0x28) {
                x86.out(u8, 0xA0, 0x20); // ACK secondary PIC
            }
            x86.out(u8, 0x20, 0x20); // ACK primary PIC
        },
        else => {
            std.log.err("Unhandled interrupt: {}", .{cpu});
            while (true) {
                asm volatile (
                    \\ cli
                    \\ hlt
                );
            }
        },
    }

    return cpu;
}

export var idt: [256]Descriptor align(16) = undefined;

pub fn init() void {
    comptime var i: usize = 0;
    inline while (i < idt.len) : (i += 1) {
        idt[i] = Descriptor.init(getInterruptStub(i), 0x08, .interruptGate, .bits32, 0, true);
    }

    asm volatile ("lidt idtp");

    // Initialize primary PIC
    x86.out(u8, 0x20, 0x11); // Initialization command
    x86.out(u8, 0x21, 0x20); // First interrupt of the primary PIC, so: IRQ0
    x86.out(u8, 0x21, 0x04); // Secondary pic is chained via IRQ2
    x86.out(u8, 0x21, 0x01); // ICW 4

    // Initialize secondary PIC
    x86.out(u8, 0xa0, 0x11); // Initialization command
    x86.out(u8, 0xa1, 0x28); // First interrupt of the secondary PIC, so: IRQ8
    x86.out(u8, 0xa1, 0x02); // Secondary pic is chained via IRQ2
    x86.out(u8, 0xa1, 0x01); // ICW 4

    disableAllIRQs();
}

pub fn fireInterrupt(comptime intr: u32) void {
    asm volatile ("int %[i]"
        :
        : [i] "n" (intr),
    );
}

pub fn enableIRQ(irqNum: u4) void {
    switch (irqNum) {
        0...7 => {
            x86.out(u8, 0x21, x86.in(u8, 0x21) & ~(@as(u8, 1) << @intCast(u3, irqNum)));
        },
        8...15 => {
            x86.out(u8, 0x21, x86.in(u8, 0x21) & ~(@as(u8, 1) << @intCast(u3, irqNum - 8)));
        },
    }
}

pub fn disableIRQ(irqNum: u4) void {
    switch (irqNum) {
        0...7 => {
            x86.out(u8, 0x21, x86.in(u8, 0x21) | (@as(u8, 1) << @intCast(u3, irqNum)));
        },
        8...15 => {
            x86.out(u8, 0x21, x86.in(u8, 0x21) | (@as(u8, 1) << @intCast(u3, irqNum - 8)));
        },
    }
}

pub fn enableAllIRQs() void {
    // Alle IRQs aktivieren (demaskieren)
    x86.out(u8, 0x21, 0x0);
    x86.out(u8, 0xa1, 0x0);
}

pub fn disableAllIRQs() void {
    // Alle IRQs aktivieren (demaskieren)
    x86.out(u8, 0x21, 0xFF);
    x86.out(u8, 0xa1, 0xFF);
}

pub fn enableExternalInterrupts() void {
    // std.log.debug("interrupts are now enabled", .{});
    asm volatile ("sti");
}

pub fn disableExternalInterrupts() void {
    // std.log.debug("interrupts are now disabled", .{});
    asm volatile ("cli");
}

pub const CpuState = packed struct {
    // Von Hand gesicherte Register
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,

    interrupt: u32,
    errorcode: u32,

    // Von der CPU gesichert
    eip: u32,
    cs: u32,
    eflags: u32,
    esp: u32,
    ss: u32,

    pub fn format(cpu: CpuState, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("  EAX={X:0>8} EBX={X:0>8} ECX={X:0>8} EDX={X:0>8}\r\n", .{ cpu.eax, cpu.ebx, cpu.ecx, cpu.edx });
        try writer.print("  ESI={X:0>8} EDI={X:0>8} EBP={X:0>8} EIP={X:0>8}\r\n", .{ cpu.esi, cpu.edi, cpu.ebp, cpu.eip });
        try writer.print("  INT={X:0>2}       ERR={X:0>8}  CS={X:0>8} FLG={X:0>8}\r\n", .{ cpu.interrupt, cpu.errorcode, cpu.cs, cpu.eflags });
        try writer.print("  ESP={X:0>8}  SS={X:0>8}\r\n", .{ cpu.esp, cpu.ss });
    }
};

const InterruptType = enum(u3) {
    interruptGate = 0b110,
    trapGate = 0b111,
    taskGate = 0b101,
};

const InterruptBits = enum(u1) {
    bits32 = 1,
    bits16 = 0,
};

const Descriptor = packed struct(u64) {
    offset0: u16, // 0-15 Offset 0-15 Gibt das Offset des ISR innerhalb des Segments an. Wenn der entsprechende Interrupt auftritt, wird eip auf diesen Wert gesetzt.
    selector: u16, // 16-31 Selector Gibt den Selector des Codesegments an, in das beim Auftreten des Interrupts gewechselt werden soll. Im Allgemeinen ist dies das Kernel-Codesegment (Ring 0).
    ist: u3 = 0, // 32-34 000 / IST Gibt im LM den Index in die IST an, ansonsten 0!
    _0: u5 = 0, // 35-39 Reserviert Wird ignoriert
    type: InterruptType, // 40-42 Typ Gibt die Art des Interrupts an
    bits: InterruptBits, // 43 D Gibt an, ob es sich um ein 32bit- (1) oder um ein 16bit-Segment (0) handelt.
    // Im LM: Für 64-Bit LDT 0, ansonsten 1
    _1: u1 = 0, // 44 0
    privilege: u2, // 45-46 DPL Gibt das Descriptor Privilege Level an, das man braucht um diesen Interrupt aufrufen zu dürfen.
    enabled: bool, // 47 P Gibt an, ob dieser Eintrag benutzt wird.
    offset1: u16, // 48-63 Offset 16-31

    pub fn init(offset: ?*const fn () callconv(.Naked) void, selector: u16, _type: InterruptType, bits: InterruptBits, privilege: u2, enabled: bool) Descriptor {
        const offset_val = @ptrToInt(offset);
        return Descriptor{
            .offset0 = @truncate(u16, offset_val & 0xFFFF),
            .offset1 = @truncate(u16, (offset_val >> 16) & 0xFFFF),
            .selector = selector,
            .type = _type,
            .bits = bits,
            .privilege = privilege,
            .enabled = enabled,
        };
    }
};

const InterruptTable = extern struct {
    limit: u16,
    table: [*]Descriptor align(2),
};

export const idtp = InterruptTable{
    .limit = @sizeOf(@TypeOf(idt)) - 1,
    .table = &idt,
};

export fn common_isr_handler() callconv(.Naked) void {
    asm volatile (
    // save cpu state
        \\ push %%ebp
        \\ push %%edi
        \\ push %%esi
        \\ push %%edx
        \\ push %%ecx
        \\ push %%ebx
        \\ push %%eax
        \\ 
        // invoke the handler with stack pointer as paramter, and return value
        \\ push %%esp
        \\ call handle_interrupt
        \\ mov %%eax, %%esp
        \\ 
        // restore CPU state
        \\ pop %%eax
        \\ pop %%ebx
        \\ pop %%ecx
        \\ pop %%edx
        \\ pop %%esi
        \\ pop %%edi
        \\ pop %%ebp
        \\ 
        // remove error code pushed by the interrupt stub
        \\ add $8, %%esp
        \\ 
        // back to the code and restore CPU state
        \\ iret
    );
}

fn getInterruptStub(comptime i: u32) fn () callconv(.Naked) void {
    const Wrapper = struct {
        fn stub_with_zero() callconv(.Naked) void {
            asm volatile (
            // this handler has no error code pushed by the cpu, so we have to
                \\ pushl $0
                \\ pushl %[nr]
                \\ jmp common_isr_handler
                :
                : [nr] "n" (i),
            );
        }
        fn stub_with_errorcode() callconv(.Naked) void {
            asm volatile (
            // error code was already pushed by cpu already
                \\ pushl %[nr]
                \\ jmp common_isr_handler
                :
                : [nr] "n" (i),
            );
        }
    };
    return switch (i) {
        8, 10...14, 17 => Wrapper.stub_with_errorcode,
        else => Wrapper.stub_with_zero,
    };
}
