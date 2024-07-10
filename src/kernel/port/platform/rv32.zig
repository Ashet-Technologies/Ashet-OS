//!
//! RISC-V 32 Bit Implementation
//!
//! Documentation:
//! - Assembly Cheat Sheet: https://www.cl.cam.ac.uk/teaching/1617/ECAD+Arch/files/docs/RISCVGreenCardv8-20151013.pdf
//! - RISC-V Priviledged: https://riscv.org/wp-content/uploads/2017/05/riscv-privileged-v1.10.pdf
//!
//!

const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.riscv);

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = struct {
    export fn handleTrap() align(4) callconv(.C) noreturn {
        const trap_reason: u32 = asm ("csrr %[out], mcause"
            : [out] "=r" (-> u32),
        );

        logger.err("trap happened. trap code: 0x{X:0>8}", .{trap_reason});
        if (trap_reason >= 0x8000_0000) {
            // asynchronous
            logger.err("async trap: {s}", .{switch (trap_reason) {
                // swi:
                0x8000_0000 => "user software interrupt",
                0x8000_0001 => "supervisor software interrupt",
                0x8000_0002 => "reserved for future standard use",
                0x8000_0003 => "machine software interrupt",

                // timer:
                0x8000_0004 => "user timer interrupt",
                0x8000_0005 => "supervisor timer interrupt",
                0x8000_0006 => "reserved for future standard use",
                0x8000_0007 => "machine timer interrupt",

                // external:
                0x8000_0008 => "user external interrupt",
                0x8000_0009 => "supervisor external interrupt",
                0x8000_000A => "reserved for future standard use",
                0x8000_000B => "machine external interrupt",

                // reserved:
                0x8000_000C,
                0x8000_000D,
                0x8000_000E,
                0x8000_000F,
                => "reserved for future standard use",

                else => "reserved for platform use",
            }});
        } else {
            // synchronous
            logger.err("sync trap: {s}", .{switch (trap_reason) {
                // faults:
                0x0000_0000 => "instruction address misaligned",
                0x0000_0001 => "instruction access fault",
                0x0000_0002 => "illegal instruction",
                0x0000_0003 => "breakpoint",
                0x0000_0004 => "load address misaligned",
                0x0000_0005 => "load access fault",
                0x0000_0006 => "store/AMO address misaligned",
                0x0000_0007 => "store/AMI access fault",

                // env call:
                0x0000_0008 => "environment call from U-mode",
                0x0000_0009 => "environment call from S-mode",
                0x0000_000A => "reserved",
                0x0000_000B => "environment call from M-mode",

                // page fault:
                0x0000_000C => "instruction page fault",
                0x0000_000D => "load page fault",
                0x0000_000E => "reserved for future standard use",
                0x0000_000F => "store/AMO page fault",

                0x0000_0010...0x0000_0017 => "reserved for future standard use",
                0x0000_0018...0x0000_001F => "reserved for future custom use",
                0x0000_0020...0x0000_002F => "reserved for future standard use",
                0x0000_0030...0x0000_003F => "reserved for future custom use",
                else => "reserved for future standard use",
            }});
        }

        if (ashet.scheduler.Thread.current()) |thread| {
            if (thread.process_link) |link| {
                _ = link;

                ashet.scheduler.exit(1);
            }
        }

        @panic("unhandled trap");
    }

    comptime {
        asm (
            \\.section .text._start
            \\.global _start
            \\_start:
            \\  la   sp, __kernel_stack_end // defined in linker script 
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
        \\_read_hwcnt_loop:
        \\  rdcycleh t0 // hi
        \\  rdcycle  t1 // lo
        \\  rdcycleh t2 // check
        \\  bne t0, t2, _read_hwcnt_loop
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

pub const ControlStatusRegister = enum(u12) {

    // User Trap Setup
    ustatus = 0x000, //  URW  User status register.
    uie = 0x004, //  URW  User interrupt-enable register.
    utvec = 0x005, //  URW  User trap handler base address.

    // User Trap Handling
    uscratch = 0x040, //  URW  Scratch register for user trap handlers.
    uepc = 0x041, //  URW  User exception program counter.
    ucause = 0x042, //  URW  User trap cause.
    utval = 0x043, //  URW  User bad address or instruction.
    uip = 0x044, //  URW  User interrupt pending.

    // User Floating-Point CSRs
    fflags = 0x001, //  URW  Floating-Point Accrued Exceptions.
    frm = 0x002, //  URW  Floating-Point Dynamic Rounding Mode.
    fcsr = 0x003, //  URW  Floating-Point Control and Status Register (frm + fflags).

    // User Counter/Timers
    cycle = 0xC00, //  URO  Cycle counter for RDCYCLE instruction.
    time = 0xC01, //  URO  Timer for RDTIME instruction.
    instret = 0xC02, //  URO  Instructions-retired counter for RDINSTRET instruction.
    hpmcounter3 = 0xC03, //  URO  Performance-monitoring counter.
    hpmcounter4 = 0xC04, //  URO  Performance-monitoring counter.
    hpmcounter5 = 0xC05, //  URO  Performance-monitoring counter.
    hpmcounter6 = 0xC06, //  URO  Performance-monitoring counter.
    hpmcounter7 = 0xC07, //  URO  Performance-monitoring counter.
    hpmcounter8 = 0xC08, //  URO  Performance-monitoring counter.
    hpmcounter9 = 0xC09, //  URO  Performance-monitoring counter.
    hpmcounter10 = 0xC0A, //  URO  Performance-monitoring counter.
    hpmcounter11 = 0xC0B, //  URO  Performance-monitoring counter.
    hpmcounter12 = 0xC0C, //  URO  Performance-monitoring counter.
    hpmcounter13 = 0xC0D, //  URO  Performance-monitoring counter.
    hpmcounter14 = 0xC0E, //  URO  Performance-monitoring counter.
    hpmcounter15 = 0xC0F, //  URO  Performance-monitoring counter.
    hpmcounter16 = 0xC10, //  URO  Performance-monitoring counter.
    hpmcounter17 = 0xC11, //  URO  Performance-monitoring counter.
    hpmcounter18 = 0xC12, //  URO  Performance-monitoring counter.
    hpmcounter19 = 0xC13, //  URO  Performance-monitoring counter.
    hpmcounter20 = 0xC14, //  URO  Performance-monitoring counter.
    hpmcounter21 = 0xC15, //  URO  Performance-monitoring counter.
    hpmcounter22 = 0xC16, //  URO  Performance-monitoring counter.
    hpmcounter23 = 0xC17, //  URO  Performance-monitoring counter.
    hpmcounter24 = 0xC18, //  URO  Performance-monitoring counter.
    hpmcounter25 = 0xC19, //  URO  Performance-monitoring counter.
    hpmcounter26 = 0xC1A, //  URO  Performance-monitoring counter.
    hpmcounter27 = 0xC1B, //  URO  Performance-monitoring counter.
    hpmcounter28 = 0xC1C, //  URO  Performance-monitoring counter.
    hpmcounter29 = 0xC1D, //  URO  Performance-monitoring counter.
    hpmcounter30 = 0xC1E, //  URO  Performance-monitoring counter.
    hpmcounter31 = 0xC1F, //  URO  Performance-monitoring counter.

    cycleh = 0xC80, //  URO  Upper 32 bits of cycle, RV32I only.
    timeh = 0xC81, //  URO  Upper 32 bits of time, RV32I only.
    instreth = 0xC82, //  URO  Upper 32 bits of instret, RV32I only.
    hpmcounter3h = 0xC83, //  URO  Upper 32 bits of hpmcounter3, RV32I only.
    hpmcounter4h = 0xC84, //  URO  Upper 32 bits of hpmcounter4, RV32I only.
    hpmcounter5h = 0xC85, //  URO  Upper 32 bits of hpmcounter5, RV32I only.
    hpmcounter6h = 0xC86, //  URO  Upper 32 bits of hpmcounter6, RV32I only.
    hpmcounter7h = 0xC87, //  URO  Upper 32 bits of hpmcounter7, RV32I only.
    hpmcounter8h = 0xC88, //  URO  Upper 32 bits of hpmcounter8, RV32I only.
    hpmcounter9h = 0xC89, //  URO  Upper 32 bits of hpmcounter9, RV32I only.
    hpmcounter10h = 0xC8A, //  URO  Upper 32 bits of hpmcounter10, RV32I only.
    hpmcounter11h = 0xC8B, //  URO  Upper 32 bits of hpmcounter11, RV32I only.
    hpmcounter12h = 0xC8C, //  URO  Upper 32 bits of hpmcounter12, RV32I only.
    hpmcounter13h = 0xC8D, //  URO  Upper 32 bits of hpmcounter13, RV32I only.
    hpmcounter14h = 0xC8E, //  URO  Upper 32 bits of hpmcounter14, RV32I only.
    hpmcounter15h = 0xC8F, //  URO  Upper 32 bits of hpmcounter15, RV32I only.
    hpmcounter16h = 0xC90, //  URO  Upper 32 bits of hpmcounter16, RV32I only.
    hpmcounter17h = 0xC91, //  URO  Upper 32 bits of hpmcounter17, RV32I only.
    hpmcounter18h = 0xC92, //  URO  Upper 32 bits of hpmcounter18, RV32I only.
    hpmcounter19h = 0xC93, //  URO  Upper 32 bits of hpmcounter19, RV32I only.
    hpmcounter20h = 0xC94, //  URO  Upper 32 bits of hpmcounter20, RV32I only.
    hpmcounter21h = 0xC95, //  URO  Upper 32 bits of hpmcounter21, RV32I only.
    hpmcounter22h = 0xC96, //  URO  Upper 32 bits of hpmcounter22, RV32I only.
    hpmcounter23h = 0xC97, //  URO  Upper 32 bits of hpmcounter23, RV32I only.
    hpmcounter24h = 0xC98, //  URO  Upper 32 bits of hpmcounter24, RV32I only.
    hpmcounter25h = 0xC99, //  URO  Upper 32 bits of hpmcounter25, RV32I only.
    hpmcounter26h = 0xC9A, //  URO  Upper 32 bits of hpmcounter26, RV32I only.
    hpmcounter27h = 0xC9B, //  URO  Upper 32 bits of hpmcounter27, RV32I only.
    hpmcounter28h = 0xC9C, //  URO  Upper 32 bits of hpmcounter28, RV32I only.
    hpmcounter29h = 0xC9D, //  URO  Upper 32 bits of hpmcounter29, RV32I only.
    hpmcounter30h = 0xC9E, //  URO  Upper 32 bits of hpmcounter30, RV32I only.
    hpmcounter31h = 0xC9F, //  URO  Upper 32 bits of hpmcounter31, RV32I only

    // Supervisor Trap Setup
    sstatus = 0x100, //  SRW  Supervisor status register.
    sedeleg = 0x102, //  SRW sedeleg Supervisor exception delegation register.
    sideleg = 0x103, //  SRW sideleg Supervisor interrupt delegation register.
    sie = 0x104, //  SRW sie Supervisor interrupt-enable register.
    stvec = 0x105, //  SRW stvec Supervisor trap handler base address.
    scounteren = 0x106, //  SRW scounteren Supervisor counter enable.

    // Supervisor Trap Handling
    sscratch = 0x140, //  SRW sscratch Scratch register for supervisor trap handlers.
    sepc = 0x141, //  SRW sepc Supervisor exception program counter.
    scause = 0x142, //  SRW scause Supervisor trap cause.
    stval = 0x143, //  SRW stval Supervisor bad address or instruction.
    sip = 0x144, //  SRW sip Supervisor interrupt pending.

    // Supervisor Protection and Translation
    satp = 0x180, //  SRW satp Supervisor address translation and protection,

    // Machine Information Registers
    mvendorid = 0xF11, //  MRO  Vendor ID.
    marchid = 0xF12, //  MRO  Architecture ID.
    mimpid = 0xF13, //  MRO  Implementation ID.
    mhartid = 0xF14, //  MRO  Hardware thread ID.

    // Machine Trap Setup
    mstatus = 0x300, //  MRW  Machine status register.
    misa = 0x301, //  MRW  ISA and extensions
    medeleg = 0x302, //  MRW  Machine exception delegation register.
    mideleg = 0x303, //  MRW  Machine interrupt delegation register.
    mie = 0x304, //  MRW  Machine interrupt-enable register.
    mtvec = 0x305, //  MRW  Machine trap-handler base address.
    mcounteren = 0x306, //  MRW  Machine counter enable.

    // Machine Trap Handling
    mscratch = 0x340, //  MRW  Scratch register for machine trap handlers.
    mepc = 0x341, //  MRW  Machine exception program counter.
    mcause = 0x342, //  MRW  Machine trap cause.
    mtval = 0x343, //  MRW  Machine bad address or instruction.
    mip = 0x344, //  MRW  Machine interrupt pending.

    // Machine Protection and Translation
    pmpcfg0 = 0x3A0, //  MRW  Physical memory protection configuration.
    pmpcfg1 = 0x3A1, //  MRW  Physical memory protection configuration, RV32 only.
    pmpcfg2 = 0x3A2, //  MRW  Physical memory protection configuration.
    pmpcfg3 = 0x3A3, //  MRW  Physical memory protection configuration, RV32 only.

    pmpaddr0 = 0x3B0, //  MRW  Physical memory protection address register.
    pmpaddr1 = 0x3B1, //  MRW  Physical memory protection address register.
    pmpaddr2 = 0x3B2, //  MRW  Physical memory protection address register.
    pmpaddr3 = 0x3B3, //  MRW  Physical memory protection address register.
    pmpaddr4 = 0x3B4, //  MRW  Physical memory protection address register.
    pmpaddr5 = 0x3B5, //  MRW  Physical memory protection address register.
    pmpaddr6 = 0x3B6, //  MRW  Physical memory protection address register.
    pmpaddr7 = 0x3B7, //  MRW  Physical memory protection address register.
    pmpaddr8 = 0x3B8, //  MRW  Physical memory protection address register.
    pmpaddr9 = 0x3B9, //  MRW  Physical memory protection address register.
    pmpaddr10 = 0x3BA, //  MRW  Physical memory protection address register.
    pmpaddr11 = 0x3BB, //  MRW  Physical memory protection address register.
    pmpaddr12 = 0x3BC, //  MRW  Physical memory protection address register.
    pmpaddr13 = 0x3BD, //  MRW  Physical memory protection address register.
    pmpaddr14 = 0x3BE, //  MRW  Physical memory protection address register.
    pmpaddr15 = 0x3BF, //  MRW  Physical memory protection address register.

    // Machine Counter/Timers
    mcycle = 0xB00, //  MRW  Machine cycle counter.
    minstret = 0xB02, //  MRW  Machine instructions-retired counter.
    mhpmcounter3 = 0xB03, //  MRW  Machine performance-monitoring counter.
    mhpmcounter4 = 0xB04, //  MRW  Machine performance-monitoring counter.
    mhpmcounter5 = 0xB05,
    mhpmcounter6 = 0xB06,
    mhpmcounter7 = 0xB07,
    mhpmcounter8 = 0xB08,
    mhpmcounter9 = 0xB09,
    mhpmcounter10 = 0xB0A,
    mhpmcounter11 = 0xB0B,
    mhpmcounter12 = 0xB0C,
    mhpmcounter13 = 0xB0D,
    mhpmcounter14 = 0xB0E,
    mhpmcounter15 = 0xB0F,
    mhpmcounter16 = 0xB10,
    mhpmcounter17 = 0xB11,
    mhpmcounter18 = 0xB12,
    mhpmcounter19 = 0xB13,
    mhpmcounter20 = 0xB14,
    mhpmcounter21 = 0xB15,
    mhpmcounter22 = 0xB16,
    mhpmcounter23 = 0xB17,
    mhpmcounter24 = 0xB18,
    mhpmcounter25 = 0xB19,
    mhpmcounter26 = 0xB1A,
    mhpmcounter27 = 0xB1B,
    mhpmcounter28 = 0xB1C,
    mhpmcounter29 = 0xB1D,
    mhpmcounter30 = 0xB1E,
    mhpmcounter31 = 0xB1F, //  MRW  Machine performance-monitoring counter.
    mcycleh = 0xB80, //  MRW  Upper 32 bits of mcycle, RV32I only.
    minstreth = 0xB82, //  MRW  Upper 32 bits of minstret, RV32I only.
    mhpmcounter3h = 0xB83, //  MRW  Upper 32 bits of mhpmcounter3, RV32I only.
    mhpmcounter4h = 0xB84, //  MRW  Upper 32 bits of mhpmcounter4, RV32I only.
    mhpmcounter5h = 0xB85,
    mhpmcounter6h = 0xB86,
    mhpmcounter7h = 0xB87,
    mhpmcounter8h = 0xB88,
    mhpmcounter9h = 0xB89,
    mhpmcounter10h = 0xB8A,
    mhpmcounter11h = 0xB8B,
    mhpmcounter12h = 0xB8C,
    mhpmcounter13h = 0xB8D,
    mhpmcounter14h = 0xB8E,
    mhpmcounter15h = 0xB8F,
    mhpmcounter16h = 0xB90,
    mhpmcounter17h = 0xB91,
    mhpmcounter18h = 0xB92,
    mhpmcounter19h = 0xB93,
    mhpmcounter20h = 0xB94,
    mhpmcounter21h = 0xB95,
    mhpmcounter22h = 0xB96,
    mhpmcounter23h = 0xB97,
    mhpmcounter24h = 0xB98,
    mhpmcounter25h = 0xB99,
    mhpmcounter26h = 0xB9A,
    mhpmcounter27h = 0xB9B,
    mhpmcounter28h = 0xB9C,
    mhpmcounter29h = 0xB9D,
    mhpmcounter30h = 0xB9E,
    mhpmcounter31h = 0xB9F, //  MRW  Upper 32 bits of mhpmcounter31, RV32I only.

    // Machine Counter Setup
    mhpmevent3 = 0x323, //  MRW  Machine performance-monitoring event selector.
    mhpmevent4 = 0x324, //  MRW  Machine performance-monitoring event selector.
    mhpmevent5 = 0x325,
    mhpmevent6 = 0x326,
    mhpmevent7 = 0x327,
    mhpmevent8 = 0x328,
    mhpmevent9 = 0x329,
    mhpmevent10 = 0x32A,
    mhpmevent11 = 0x32B,
    mhpmevent12 = 0x32C,
    mhpmevent13 = 0x32D,
    mhpmevent14 = 0x32E,
    mhpmevent15 = 0x32F,
    mhpmevent16 = 0x330,
    mhpmevent17 = 0x331,
    mhpmevent18 = 0x332,
    mhpmevent19 = 0x333,
    mhpmevent20 = 0x334,
    mhpmevent21 = 0x335,
    mhpmevent22 = 0x336,
    mhpmevent23 = 0x337,
    mhpmevent24 = 0x338,
    mhpmevent25 = 0x339,
    mhpmevent26 = 0x33A,
    mhpmevent27 = 0x33B,
    mhpmevent28 = 0x33C,
    mhpmevent29 = 0x33D,
    mhpmevent30 = 0x33E,
    mhpmevent31 = 0x33F, //  MRW  Machine performance-monitoring event selector.

    // Debug/Trace Registers (shared with Debug Mode)
    tselect = 0x7A0, //  MRW  Debug/Trace trigger register select.
    tdata1 = 0x7A1, //  MRW  First Debug/Trace trigger data register.
    tdata2 = 0x7A2, //  MRW  Second Debug/Trace trigger data register.
    tdata3 = 0x7A3, //  MRW  Third Debug/Trace trigger data register.

    // Debug Mode Registers
    dcsr = 0x7B0, //  DRW  Debug control and status register.
    dpc = 0x7B1, //  DRW  Debug PC.
    dscratch = 0x7B2, //  DRW  Debug scratch register.

    _,

    pub fn read(comptime csr: ControlStatusRegister) usize {
        return asm ("csrr %[out], %[csr]"
            : [out] "=r" (-> usize),
            : [csr] "in" (@as(u32, @intFromEnum(csr))),
        );
    }

    pub fn write(comptime csr: ControlStatusRegister, value: usize) void {
        asm volatile ("csrw %[csr], %[value]"
            :
            : [csr] "in" (@as(u32, @intFromEnum(csr))),
              [value] "irn" (value),
        );
    }

    pub fn get_access_level(csr: ControlStatusRegister) AccessLevel {
        const encoded: Encoding = @bitCast(csr);
        return encoded.access_level;
    }

    pub fn is_read_only(csr: ControlStatusRegister) bool {
        const encoded: Encoding = @bitCast(csr);
        return (encoded.ops == .read_only);
    }

    const Encoding = packed struct(u12) {
        index: u8,

        access_level: AccessLevel,

        ops: enum(u2) {
            read_write_0 = 0b00,
            read_write_1 = 0b01,
            read_write_2 = 0b10,
            read_only = 0b11,
        },
    };
};

pub const AccessLevel = enum(u2) {
    user = 0b00,
    supervisor = 0b01,
    reserved = 0b10,
    machine = 0b11,
};
