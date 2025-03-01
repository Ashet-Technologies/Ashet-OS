const std = @import("std");
const cr = @import("registers.zig");
const x86 = @import("../x86.zig");
const logger = std.log.scoped(.idt);
const PIC = @import("PIC.zig");

const stack_alignment = 16;

pub const InterruptHandler = *const fn (*CpuState) void;

var irqHandlers = [_]?InterruptHandler{null} ** 32;

pub fn set_IRQ_Handler(irq: u4, handler: ?InterruptHandler) void {
    irqHandlers[irq] = handler;
}

export fn handle_interrupt(cpu: *CpuState) *CpuState {

    // This assertion must hold, as otherwise, our code walks weird paths:
    std.debug.assert(_x86_interrupt_nesting > 0);

    // var cpu = _cpu;
    // logger.debug("int[0x{X:0>2}]", .{cpu.interrupt});
    switch (cpu.interrupt) {
        0x00...0x1F => {
            // Exception
            logger.err("Unhandled exception: {s}", .{@as([]const u8, switch (cpu.interrupt) {
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
            logger.err("{}", .{cpu});

            if (cpu.interrupt == 0x0D) {
                // GPF
                logger.err("Offending address: kernel:0x{X:0>8}", .{cpu.eip});
                logger.err("Error code:        kernel:0x{X:0>8}", .{cpu.errorcode});
            }

            if (cpu.interrupt == 0x0E) {
                // PF
                const cr2 = cr.CR2.read();
                const cr3 = cr.CR3.read();

                _ = cr3;
                logger.err("Page Fault when {s} address kernel:0x{X:0>8} from {s}: {s}", .{
                    if ((cpu.errorcode & 2) != 0) @as([]const u8, "writing") else @as([]const u8, "reading"),
                    cr2.page_fault_address,
                    if ((cpu.errorcode & 4) != 0) @as([]const u8, "userspace") else @as([]const u8, "kernelspace"),
                    if ((cpu.errorcode & 1) != 0) @as([]const u8, "access denied") else @as([]const u8, "page unmapped"),
                });
                logger.err("Offending address: kernel:0x{X:0>8}", .{cpu.eip});
            }

            @panic("Unhandled exception!");

            // while (true) {
            //     asm volatile (
            //         \\ cli
            //         \\ hlt
            //     );
            // }
        },
        0x20...0x2F => {
            // IRQ
            if (irqHandlers[cpu.interrupt - 0x20]) |handler| {
                handler(cpu);
            } else {
                logger.warn("Unhandled IRQ{}:\n{}", .{ cpu.interrupt - 0x20, cpu });
            }

            if (cpu.interrupt >= 0x28) {
                PIC.secondary.notifyEndOfInterrupt();
            }
            PIC.primary.notifyEndOfInterrupt();
        },
        else => {
            logger.err("Unhandled interrupt:\n{}", .{cpu});

            @panic("Unhandled exception!");
            // while (true) {
            //     asm volatile (
            //         \\ cli
            //         \\ hlt
            //     );
            // }
        },
    }

    return cpu;
}

export var idt: [256]Descriptor align(16) linksection(".rodata.irq") = .{@as(Descriptor, @bitCast(@as(u64, 0)))} ** 256;

const InterruptTable = extern struct {
    limit: u16,
    table: [*]Descriptor align(2),
};

export const idtp linksection(".rodata.irq") = InterruptTable{
    .limit = @sizeOf(@TypeOf(idt)) - 1,
    .table = &idt,
};

/// We're running interrupts on a dedicated stack which is not
/// the same as the stack of the thread we're running on.
///
/// This variable is a global that stores that stack pointer.
export var _x86_interrupt_stack_end: [*]align(stack_alignment) u8 = undefined;

export var _x86_interrupt_nesting: u32 = 0;

pub fn init(interrupt_stack: []align(stack_alignment) u8) void {
    std.debug.assert(std.mem.isAligned(interrupt_stack.len, stack_alignment));

    _x86_interrupt_stack_end = @alignCast(interrupt_stack.ptr + interrupt_stack.len);

    inline for (&idt, 0..) |*entry, i| {
        const desc = Descriptor.init(getInterruptStub(i), 0x08, .interruptGate, .bits32, 0, true);
        entry.* = desc;
    }
    asm volatile ("lidt idtp");

    PIC.primary.initialize(0x20);
    PIC.secondary.initialize(0x28);

    disableAllIRQs();
}

pub fn isInInterruptContext() bool {
    return (_x86_interrupt_nesting > 0);
}

pub fn fireInterrupt(comptime intr: u32) void {
    asm volatile ("int %[i]"
        :
        : [i] "n" (intr),
    );
}

pub fn enableIRQ(index: u4) void {
    logger.debug("enable irq {}", .{index});
    switch (index) {
        0...7 => PIC.primary.enable(@as(u3, @truncate(index))),
        8...15 => PIC.secondary.enable(@as(u3, @truncate(index))),
    }
}

pub fn disableIRQ(index: u4) void {
    logger.debug("disable irq {}", .{index});
    switch (index) {
        0...7 => PIC.primary.disable(@as(u3, @truncate(index))),
        8...15 => PIC.secondary.disable(@as(u3, @truncate(index))),
    }
}

pub fn enableAllIRQs() void {
    logger.debug("enable all irqs", .{});

    PIC.primary.enableAll();
    PIC.secondary.enableAll();
}

pub fn disableAllIRQs() void {
    logger.debug("disable all irqs", .{});

    PIC.primary.disableAll();
    PIC.secondary.disableAll();
    PIC.primary.enable(PIC.cascade_irq); // keep the cascade alive, otherwise it will make our head ache
}

pub fn enableExternalInterrupts() void {
    // logger.debug("interrupts are now enabled", .{});
    asm volatile ("sti");
}

pub fn disableExternalInterrupts() void {
    // logger.debug("interrupts are now disabled", .{});
    asm volatile ("cli");
}

pub const CpuState = packed struct {
    // manually saved inside scheduler:
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,

    interrupt: u32,
    errorcode: u32,

    // saved by the cpu interrupt mechanism:
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
        const offset_val = @intFromPtr(offset);
        return Descriptor{
            .offset0 = @as(u16, @truncate(offset_val & 0xFFFF)),
            .offset1 = @as(u16, @truncate((offset_val >> 16) & 0xFFFF)),
            .selector = selector,
            .type = _type,
            .bits = bits,
            .privilege = privilege,
            .enabled = enabled,
        };
    }
};

export fn common_isr_handler() callconv(.Naked) void {
    asm volatile (
        \\
        // Increment interrupt nesting counter so we can detect that we're in
        // an interrupt handler routine:
        \\ addl $1, _x86_interrupt_nesting
        \\
        // save cpu state
        \\ push %%ebp
        \\ push %%edi
        \\ push %%esi
        \\ push %%edx
        \\ push %%ecx
        \\ push %%ebx
        \\ push %%eax
        \\ 
        // back up the actual "pointer to stack" into eax
        \\ mov %%esp, %%eax
        // stack here is in a desolate state of "whatever happened to me, oh god"
        // let's align it for SysV abi conformance:
        \\ and $0xfffffff0, %esp
        \\ sub $0x0C, %esp
        // Set the stack pointer to the interrupt area
        // if we're the first interrupt (which means we have no nesting):
        // \\ cmpl $1, _x86_interrupt_nesting
        // \\ jne .nested_interrupt
        // \\ movl _x86_interrupt_stack_end, %esp
        // \\.nested_interrupt:
        // invoke the handler with the previous stack pointer as paramter, and return value
        \\ push %%eax
        \\ call handle_interrupt
        // Restore the stack to whatever we were before the interrupt:
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
        // Decrement interrupt nesting counter:
        \\ subl $1, _x86_interrupt_nesting
        // back to the code and restore CPU state
        \\ iret
    );
}

fn getInterruptStub(comptime i: u32) *const fn () callconv(.Naked) void {
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
        8, 10...14, 17 => &Wrapper.stub_with_errorcode,
        else => &Wrapper.stub_with_zero,
    };
}
