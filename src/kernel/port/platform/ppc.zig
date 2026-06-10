const std = @import("std");

const registers = @import("ppc/registers.zig");
pub const cpu = @import("ppc/cpu.zig");
pub const cache = @import("ppc/cache.zig");
pub const memory = @import("ppc/memory.zig");

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = struct {
    comptime {
        // the startup routine must be written in assembler to
        // guarantee that no stack and register is touched is used until
        // we saved
        asm (
            \\hang:
            \\  trap
            \\
        );

        _ = kernel_startup;
        _ = kernel_initBATS;
        _ = kernel_configBATS;
        _ = kernel_initGPRS;
        _ = kernel_initHardware;
        _ = kernel_initPS;
        _ = kernel_initSystem;
    }

    export fn _start() linksection(".zgc_bootstrap") callconv(.naked) noreturn {
        asm volatile ("b kernel_startup");
    }

    export fn kernel_startup() callconv(.naked) noreturn {
        asm volatile (
            \\bl    kernel_initBATS        # Initialize BATs to a clear and known state
            \\bl    kernel_initStack       # Initialize Stack
            \\bl    kernel_initGPRS        # Initialize the General Purpose Registers
            \\bl    kernel_initHardware    # Initialize some aspects of the Hardware
            \\bl    kernel_initSystem      # Initialize more cache aspects, clear a few SPR's, and disable interrupts.
            \\
            \\b     ashet_kernelMain       # Branch to the user code!
        );
    }

    /// Initializes the Block Address Translation subsystem.
    /// This is done by turning BATs off, configuring it, and turning it back on.
    export fn kernel_initBATS() callconv(.naked) noreturn {
        asm volatile (
            \\# Store LR to r31 and add 0x8000000
            \\mflr  %r31
            \\oris  %r31, %r31, 0x8000
            \\// Write the address of configBATS to r3
            \\lis   %r3, kernel_configBATS@h
            \\ori   %r3, %r3, kernel_configBATS@l
            \\// Jump to configBATS in realmode
            \\bl    __realmode
            \\// Restore LR
            \\mtlr  %r31
            \\blr
            \\
            \\__realmode:
            \\clrlwi  %r3, %r3, 2         # Clear the 2 left most bits of r3
            \\mtsrr0  %r3                 # Write r3 to srr0
            \\mfmsr   %r3                 # write MSR (Machine State Register) to r3
            \\rlwinm  %r3, %r3, 0, 28, 25 # Clear bits 26 (instruction address translation) and 27 (data address translation) of the MSR (3)
            \\mtsrr1  %r3                 # Write MSR (r3) to srr1
            \\rfi                         # Return from Interop, which will set LR to the passed method originally in r3, and disable adress translation
        );
    }

    /// Configures the Block Address Translation subsystem.
    export fn kernel_configBATS() callconv(.naked) noreturn {
        //@setOptimizeMode(.ReleaseSmall);
        registers.HID0.write(.{
            .bht = true, //branch history table
            .btic = true, //branch target instruction cache
            .dcfa = true, //data cache flush assist
            .dcfi = true, //date cache flash invalidate
            .icfi = true, //instruction cache flash invalidate
            .nhr = true, //not hard reset
            .dpm = true, //dynamic power management
        });
        cpu.isync();

        // Clear all bits on all BATs
        // This is REQUIRED before setting any values.
        registers.IBAT0U.zero();
        registers.IBAT0L.zero();
        registers.IBAT1U.zero();
        registers.IBAT1L.zero();
        registers.IBAT2U.zero();
        registers.IBAT2L.zero();
        registers.IBAT3U.zero();
        registers.IBAT3L.zero();
        registers.DBAT0U.zero();
        registers.DBAT0L.zero();
        registers.DBAT1U.zero();
        registers.DBAT1L.zero();
        registers.DBAT2U.zero();
        registers.DBAT2L.zero();
        registers.DBAT3U.zero();
        registers.DBAT3L.zero();
        cpu.isync();

        // Clear all Segment Registers
        asm volatile (
            \\mtsr  0, %[v]
            \\mtsr  1, %[v]
            \\mtsr  2, %[v]
            \\mtsr  3, %[v]
            \\mtsr  4, %[v]
            \\mtsr  5, %[v]
            \\mtsr  6, %[v]
            \\mtsr  7, %[v]
            \\mtsr  8, %[v]
            \\mtsr  9, %[v]
            \\mtsr  10, %[v]
            \\mtsr  11, %[v]
            \\mtsr  12, %[v]
            \\mtsr  13, %[v]
            \\mtsr  14, %[v]
            \\mtsr  15, %[v]
            \\isync
            :
            : [v] "r" (0x80000000),
        );

        // set [DI]BAT0 for 256MB@80000000,
        // real 00000000, R/W
        // const bat0Upper = .{
        //     .vp = true,
        //     .vs = true,
        //     .bl = .@"256Mbyte",
        //     .bepi = 0x8000 >> 1,
        // };
        // const bat0Lower = .{
        //     .pp = .readwrite,
        // };

        registers.IBAT0U.write(.{
            .vp = true,
            .vs = true,
            .bl = .@"256Mbyte",
            .bepi = 0x8000 >> 1,
        });
        registers.IBAT0L.write(.{
            .pp = .readwrite,
        });
        registers.DBAT0U.write(.{
            .vp = true,
            .vs = true,
            .bl = .@"256Mbyte",
            .bepi = 0x8000 >> 1,
        });
        registers.DBAT0L.write(.{
            .pp = .readwrite,
        });
        cpu.isync();

        // set DBAT1 for 256MB@c0000000,
        // real 00000000, R/W
        registers.DBAT1U.write(.{
            .vp = true,
            .vs = true,
            .bl = .@"256Mbyte",
            .bepi = 0xc000 >> 1,
        });
        registers.DBAT1L.write(.{
            .brpn = 0x000,
            .pp = .readwrite,
            .wimg = .{
                .guarded = true,
                .caching_inhibited = true,
            },
        });
        cpu.isync();

        // Jump back to the call site of what called into __realmode
        // This is done by re-enabling address translation and setting SSR0 to the old LR, then "return from interrupt"
        // var msr = registers.MSR.read();
        // msr.dataAddressTranslation = true;
        // msr.instructionAddressTranslation = true;
        // registers.SSR1.write(msr);
        _ = asm volatile (
            \\mfmsr     %[r]
            \\ori       %[r], %[r], 0x30
            \\mtsrr1    %[r]
            : [r] "=r" (-> u32),
        );

        // const lr = registers.LR.read();
        // registers.SSR0.write(lr | 0x80000000);
        // cpu.returnFromInterrupt();
        _ = asm volatile (
            \\mflr      %[r]
            \\oris      %[r], %[r], 0x8000
            \\mtsrr0    %[r]
            \\rfi
            : [r] "=r" (-> u32),
        );
    }

    // Zero out all registers
    export fn kernel_initGPRS() callconv(.naked) noreturn {
        // Clear all of the GPR's to 0
        asm volatile (
            \\li    %r0, 0
            \\li    %r3, 0
            \\li    %r4, 0
            \\li    %r5, 0
            \\li    %r6, 0
            \\li    %r7, 0
            \\li    %r8, 0
            \\li    %r9, 0
            \\li    %r10, 0
            \\li    %r11, 0
            \\li    %r12, 0
            \\li    %r14, 0
            \\li    %r15, 0
            \\li    %r16, 0
            \\li    %r17, 0
            \\li    %r18, 0
            \\li    %r19, 0
            \\li    %r20, 0
            \\li    %r21, 0
            \\li    %r22, 0
            \\li    %r23, 0
            \\li    %r24, 0
            \\li    %r25, 0
            \\li    %r26, 0
            \\li    %r27, 0
            \\li    %r28, 0
            \\li    %r29, 0
            \\li    %r30, 0
            \\li    %r31, 0
        );

        asm volatile ("blr");
    }

    export fn kernel_initHardware() void {
        // Enable the Floating Point Registers
        registers.MSR.modify(.{
            .floatingPoint = true,
        });

        kernel_initPS();
        kernel_initFPRS();
        cache.init();
    }

    noinline fn kernel_initPS() void {
        registers.HID2.modify(.{
            .loadstore_quantize_enable = true, // Load/Store quantized enable for non-indexed format instructions
            .paired_single_enable = true, // Paired single enabled
        });
        cpu.isync();

        cache.instructionCacheFlashInvalidate();
        cpu.sync();

        registers.GQR0.write(.{});
        registers.GQR1.write(.{});
        registers.GQR2.write(.{});
        registers.GQR3.write(.{});
        registers.GQR4.write(.{});
        registers.GQR5.write(.{});
        registers.GQR6.write(.{});
        registers.GQR7.write(.{});
        cpu.isync();
    }

    noinline fn kernel_initFPRS() void {
        // Enable Floating Point Registers
        registers.MSR.modify(.{
            .floatingPoint = true,
        });

        // Clear FRP's
        const code = comptime blk: {
            @setEvalBranchQuota(10_000);

            var code: []const u8 = "";
            for (1..32) |i| {
                code = code ++ std.fmt.comptimePrint("\nfmr {}, %f0", .{i});
            }
            code = code ++ "\nmtfsf 255, %f0";
            break :blk code;
        };
        asm volatile (code
            :
            : [in] "{f0}" (0),
        );
    }

    export fn kernel_initSystem() void {
        // Disable interrupts
        registers.MSR.modify(.{
            .externalInterrupt = false,
            .exceptionPrefix = false,
        });

        // Clear Special Registers
        registers.MMCR0.write(.{});
        registers.MMCR1.write(.{});
        registers.PMC1.write(.{});
        registers.PMC2.write(.{});
        registers.PMC3.write(.{});
        registers.PMC4.write(.{});
        cpu.isync();

        // Disable speculative cache accesses to non-guarded space from both D and I caches
        registers.HID0.modify(.{
            .spd = true,
        });

        // Set the Non-IEEE mode in the FPSCR
        asm volatile ("mtfsb1 29");

        // Disable Write Pipe Enabled bit
        registers.HID2.modify(.{
            .write_pipe_enable = false,
        });

        // system.init();
    }

    extern var __kernel_stack_start: anyopaque;
    extern var __kernel_stack_end: anyopaque;
    extern var __sdata_start: anyopaque;
    extern var __sdata2_start: anyopaque;

    pub export fn kernel_initStack() callconv(.naked) noreturn {
        // Setup stack
        asm volatile (
            \\li    %r0, 0
            \\stwu  %r0, -4(%r1)
            \\stwu  %r1,-56(%r1)
            \\blr
            :
            : [stack] "+{r1}" (&__kernel_stack_end),
              [sdata2] "+{r2}" (&__sdata2_start),
              [sdata] "+{r13}" (&__sdata_start),
        );
    }
};

pub inline fn getStackPointer() usize {
    return asm (""
        : [sp] "={r1}" (-> usize),
    );
}

pub fn areInterruptsEnabled() bool {
    return false;
}

pub fn isInInterruptContext() bool {
    return false;
}

pub fn disableInterrupts() void {
    // NAH
}

pub fn enableInterrupts() void {
    // NAH
}

pub fn get_cpu_cycle_counter() u64 {
    return 0;
}

pub fn get_cpu_random_seed() ?u64 {
    return null;
}
