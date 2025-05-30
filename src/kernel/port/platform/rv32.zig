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

pub const csr = @import("rv32/csr.zig");

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = struct {
    export fn handleTrap() align(4) callconv(.C) noreturn {
        const trap_reason = csr.ControlStatusRegister.read(.mcause);
        const trap_location = csr.ControlStatusRegister.read(.mepc);
        const trap_status = csr.ControlStatusRegister.read(.mstatus);

        logger.err("trap happened. trap code:    0x{X:0>8}", .{trap_reason});
        logger.err("               trap address: 0x{X:0>8}", .{trap_location});
        logger.err("                             {}", .{ashet.fmtCodeLocation(trap_location)});
        logger.err("               trap status:  0x{X:0>8}", .{trap_status});

        const mstatus: csr.MStatus = @bitCast(trap_status);
        logger.err("                             {}", .{ashet.utils.fmt.@"struct"(mstatus)});

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

        // TODO(fqu): Reimplement this
        // if (ashet.scheduler.Thread.current()) |thread| {
        //     if (thread.process_link) |link| {
        //         _ = link;

        //         ashet.scheduler.exit(1);
        //     }
        // }

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
    return false; // TODO: Implement interrupts on RISC-V!
}

pub inline fn isInInterruptContext() bool {
    return false; // TODO: Implement interrupts on RISC-V!
}

pub fn disableInterrupts() void {
    // TODO: Implement interrupts on RISC-V!
}
pub fn enableInterrupts() void {
    // TODO: Implement interrupts on RISC-V!
}

pub fn get_cpu_cycle_counter() u64 {
    return csr.ControlStatusRegister.read(.cycle);
}

pub fn get_cpu_random_seed() ?u64 {
    return csr.ControlStatusRegister.read(.time);
}
