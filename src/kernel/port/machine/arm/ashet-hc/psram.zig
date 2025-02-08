const std = @import("std");
const logger = std.log.scoped(.ashet_hc_psram);
const ashet = @import("../../../../main.zig");
const machine = @import("ashet-hc.zig");

const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");

const qmi_hw = rp2350.devices.RP2350.peripherals.QMI;
const xip_ctrl_hw = rp2350.devices.RP2350.peripherals.XIP_CTRL;

const RP2350_PSRAM_ID: u8 = 0x5D;

const SFE_SEC_TO_FS = 1_000_000_000_000_000;

// max select pulse width = 8us => 8e6 ns => 8000 ns => 8000 * 1e6 fs => 8000e6 fs
// Additionally, the MAX select is in units of 64 clock cycles - will use a constant that
// takes this into account - so 8000e6 fs / 64 = 125e6 fs

const SFE_PSRAM_MAX_SELECT_FS64 = 125000000;

// min deselect pulse width = 50ns => 50 * 1e6 fs => 50e7 fs
const SFE_PSRAM_MIN_DESELECT_FS = 50000000;

// from psram datasheet - max Freq with VDDat 3.3v - SparkFun RP2350 boards run at 3.3v.
// If VDD = 3.0 Max Freq is 133 Mhz
const SFE_PSRAM_MAX_SCK_HZ = 109000000;

// PSRAM SPI command codes
const PSRAM_CMD_QUAD_END: u8 = 0xF5;
const PSRAM_CMD_QUAD_ENABLE: u8 = 0x35;
const PSRAM_CMD_READ_ID: u8 = 0x9F;
const PSRAM_CMD_RSTEN: u8 = 0x66;
const PSRAM_CMD_RST: u8 = 0x99;
const PSRAM_CMD_QUAD_READ: u8 = 0xEB;
const PSRAM_CMD_QUAD_WRITE: u8 = 0x38;
const PSRAM_CMD_NOOP: u8 = 0xFF;

pub fn init() !void {

    // start with zero size
    const psram_size = get_psram_size();

    logger.info("detected external PSRAM size: {}", .{psram_size});

    // No PSRAM - no dice
    if (psram_size == 0) {
        return error.FailedToDetectRAM;
    }

    _ = try init_xip1(psram_size);

    logger.info("external PSRAM ready.", .{});
}

///
/// WARNING: `noinline` and `linksection(".ramtext")` are necessary!
///          This function must fully execute from RAM and is not allowed to
///          access any flash-mapped content!
///
noinline fn init_xip1(psram_size: usize) linksection(".ramtext") !u32 {
    {
        const intr_stash = save_and_disable_interrupts();
        defer restore_interrupts(intr_stash);

        // Enable quad mode.
        qmi_hw.DIRECT_CSR.write_default(.{
            .EN = 1,
            .CLKDIV = 30,
        });

        // Need to poll for the cooldown on the last XIP transfer to expire
        // (via direct-mode BUSY flag) before it is safe to perform the first
        // direct-mode operation
        while (qmi_hw.DIRECT_CSR.read().BUSY != 0) {}

        // RESETEN, RESET and quad enable
        for (0..3) |i| {
            qmi_hw.DIRECT_CSR.modify(.{ .ASSERT_CS1N = 1 });
            switch (i) {
                0 => qmi_hw.DIRECT_TX.write_default(.{ .DATA = PSRAM_CMD_RSTEN }),
                1 => qmi_hw.DIRECT_TX.write_default(.{ .DATA = PSRAM_CMD_RST }),
                else => qmi_hw.DIRECT_TX.write_default(.{ .DATA = PSRAM_CMD_QUAD_ENABLE }),
            }

            while (qmi_hw.DIRECT_CSR.read().BUSY != 0) {}
            qmi_hw.DIRECT_CSR.modify(.{ .ASSERT_CS1N = 0 });

            for (0..20) |_| {
                asm volatile ("nop");
            }

            _ = qmi_hw.DIRECT_RX.read();
        }

        // Disable direct csr.
        qmi_hw.DIRECT_CSR.modify(.{
            .ASSERT_CS1N = 0,
            .EN = 0,
        });
    }

    try set_psram_timing();

    {
        const intr_stash = save_and_disable_interrupts();
        defer restore_interrupts(intr_stash);

        qmi_hw.M1_RFMT.write_default(.{
            .PREFIX_WIDTH = .Q,
            .ADDR_WIDTH = .Q,
            .SUFFIX_WIDTH = .Q,
            .DUMMY_WIDTH = .Q,
            .DUMMY_LEN = .@"24",
            .DATA_WIDTH = .Q,
            .PREFIX_LEN = .@"8",
            .SUFFIX_LEN = .NONE,
        });

        qmi_hw.M1_RCMD.write_default(.{
            .PREFIX = PSRAM_CMD_QUAD_READ,
            .SUFFIX = 0,
        });

        qmi_hw.M1_WFMT.write_default(.{
            .PREFIX_WIDTH = .Q,
            .ADDR_WIDTH = .Q,
            .SUFFIX_WIDTH = .Q,
            .DUMMY_WIDTH = .Q,
            .DUMMY_LEN = .NONE,
            .DATA_WIDTH = .Q,
            .PREFIX_LEN = .@"8",
            .SUFFIX_LEN = .NONE,
        });

        qmi_hw.M1_WCMD.write_default(.{
            .PREFIX = PSRAM_CMD_QUAD_WRITE,
            .SUFFIX = 0,
        });

        // Mark that we can write to PSRAM.
        xip_ctrl_hw.CTRL.modify(.{
            .WRITABLE_M1 = 1,
        });
    }

    return psram_size;
}

///
/// WARNING: `noinline` and `linksection(".ramtext")` are necessary!
///          This function must fully execute from RAM and is not allowed to
///          access any flash-mapped content!
///
noinline fn get_psram_size() linksection(".ramtext") u32 {
    var psram_size: usize = 0;

    const intr_stash = save_and_disable_interrupts();
    defer restore_interrupts(intr_stash);

    // Try and read the PSRAM ID via direct_csr.
    qmi_hw.DIRECT_CSR.write_default(.{
        .CLKDIV = 30,
        .EN = 1,
    });

    // Need to poll for the cooldown on the last XIP transfer to expire
    // (via direct-mode BUSY flag) before it is safe to perform the first
    // direct-mode operation
    while (qmi_hw.DIRECT_CSR.read().BUSY != 0) {}

    // Exit out of QMI in case we've inited already
    qmi_hw.DIRECT_CSR.modify(.{ .ASSERT_CS1N = 1 });

    // Transmit the command to exit QPI quad mode - read ID as standard SPI
    qmi_hw.DIRECT_TX.write_default(.{
        .IWIDTH = .Q,
        .OE = 1,
        .DATA = PSRAM_CMD_QUAD_END,
    });

    while (qmi_hw.DIRECT_CSR.read().BUSY != 0) {}

    _ = qmi_hw.DIRECT_RX.read();

    qmi_hw.DIRECT_CSR.modify(.{ .ASSERT_CS1N = 0 });

    // Read the id
    qmi_hw.DIRECT_CSR.modify(.{ .ASSERT_CS1N = 1 });

    var kgd: u8 = 0;
    var eid: u8 = 0;
    for (0..8) |i| {
        qmi_hw.DIRECT_TX.write_default(.{
            .DATA = if (i == 0)
                PSRAM_CMD_READ_ID
            else
                PSRAM_CMD_NOOP,
        });

        while (qmi_hw.DIRECT_CSR.read().TXEMPTY == 0) {}
        while (qmi_hw.DIRECT_CSR.read().BUSY != 0) {}

        if (i == 5) {
            kgd = @truncate(qmi_hw.DIRECT_RX.read().DIRECT_RX);
        } else if (i == 6) {
            eid = @truncate(qmi_hw.DIRECT_RX.read().DIRECT_RX);
        } else {
            _ = qmi_hw.DIRECT_RX.read(); // just read and discard
        }
    }

    // Disable direct csr.
    qmi_hw.DIRECT_CSR.write_default(.{ .EN = 0 });

    // is this the PSRAM we're looking for obi-wan?
    if (kgd == RP2350_PSRAM_ID) {
        // PSRAM size
        psram_size = 1024 * 1024; // 1 MiB
        const size_id: u8 = @intCast(eid >> 5);
        if (eid == 0x26 or size_id == 2) {
            psram_size *= 8;
        } else if (size_id == 0) {
            psram_size *= 2;
        } else if (size_id == 1) {
            psram_size *= 4;
        }
    }

    return psram_size;
}

///
/// WARNING: `noinline` and `linksection(".ramtext")` are necessary!
///          This function must fully execute from RAM and is not allowed to
///          access any flash-mapped content!
///
noinline fn set_psram_timing() linksection(".ramcode") !void {

    // Get secs / cycle for the system clock - get before disabling interrupts.
    const sys_clk: comptime_int = comptime machine.clock_config.sys.?.frequency();

    // Calculate the clock divider - goal to get clock used for PSRAM <= what
    // the PSRAM IC can handle - which is defined in SFE_PSRAM_MAX_SCK_HZ
    const clockDivider = (sys_clk + SFE_PSRAM_MAX_SCK_HZ - 1) / SFE_PSRAM_MAX_SCK_HZ;

    const intr_stash = save_and_disable_interrupts();
    defer restore_interrupts(intr_stash);

    // Get the clock femto seconds per cycle.

    const fsPerCycle = SFE_SEC_TO_FS / sys_clk;

    // the maxSelect value is defined in units of 64 clock cycles
    // So maxFS / (64 * fsPerCycle) = maxSelect = SFE_PSRAM_MAX_SELECT_FS64/fsPerCycle
    const maxSelect = SFE_PSRAM_MAX_SELECT_FS64 / fsPerCycle;

    //  minDeselect time - in system clock cycle
    // Must be higher than 50ns (min deselect time for PSRAM) so add a fsPerCycle - 1 to round up
    // So minFS/fsPerCycle = minDeselect = SFE_PSRAM_MIN_DESELECT_FS/fsPerCycle

    const minDeselect = (SFE_PSRAM_MIN_DESELECT_FS + fsPerCycle - 1) / fsPerCycle;

    // printf("Max Select: %d, Min Deselect: %d, clock divider: %d\n", maxSelect, minDeselect, clockDivider);

    qmi_hw.M1_TIMING.write_default(.{
        .PAGEBREAK = .@"1024", // Break between pages.
        .SELECT_HOLD = 3, // Delay releasing CS for 3 extra system cycles.
        .COOLDOWN = 1,
        .RXDELAY = 1,
        .MAX_SELECT = maxSelect,
        .MIN_DESELECT = minDeselect,
        .CLKDIV = clockDivider,
    });
}

fn save_and_disable_interrupts() bool {
    //
    return false;
}

fn restore_interrupts(old: bool) void {
    _ = old;
}

// inline fn trace(comptime loc: std.builtin.SourceLocation) void {
//     const T = struct {
//         var msg linksection(".data") = [_]u8{
//             'L',
//             '0' + (loc.line / 100) % 10,
//             '0' + (loc.line / 10) % 10,
//             '0' + (loc.line / 1) % 10,
//             '\r',
//             '\n',
//         };
//     };

//     // const msg = std.fmt.comptimePrint("{s}:{d}: {s}\r\n", .{ loc.file, loc.line, loc.fn_name });

//     machine.bitbang_write(&T.msg);
// }
