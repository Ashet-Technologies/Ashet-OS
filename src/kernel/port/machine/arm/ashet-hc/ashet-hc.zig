const std = @import("std");
const logger = std.log.scoped(.ashet_hc);
const ashet = @import("../../../../main.zig");
const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");
const rp2350_regs = rp2350.devices.RP2350.peripherals;

const psram = @import("psram.zig");

const disk_image_start = 0x10800000;
const disk_image_end = 0x11000000;

pub const clock_config = hal.clocks.config.preset.default();

pub const debug_uart = hal.uart.instance.UART0;

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = null,
    .early_initialize = early_initialize,
    .get_tick_count_ms = get_tick_count_ms,
    .initialize = initialize,
    .debug_write = debug_write,
    .get_linear_memory_region = get_linear_memory_region,
};

const pinout = struct {
    const debug_tx = hal.gpio.num(0);
    const debug_rx = hal.gpio.num(1);
    const xip_cs1 = hal.gpio.num(8);

    // // bitbang interface:
    // const dbg_sel = hal.gpio.num(9);
    // const dbg_sck = hal.gpio.num(10);
    // const dbg_sda = hal.gpio.num(11);
};

const hw = struct {
    //! list of fixed hardware components

    var rtc: ashet.drivers.rtc.Dummy_RTC = undefined;

    var uart0: ashet.drivers.serial.RP2xxx = undefined;
    var uart1: ashet.drivers.serial.RP2xxx = undefined;

    // var fb_video: ashet.drivers.video.Virtual_Video_Output = undefined;
    var hstx_video: ashet.drivers.video.HSTX_DVI = undefined;

    var xip_flash: ashet.drivers.block.Memory_Mapped_Flash = undefined;
};

fn get_tick_count_ms() u64 {
    var cs = ashet.CriticalSection.enter();
    defer cs.leave();

    return systick.total_count_ms;
}

var interrupt_table: ashet.platform.profile.start.InterruptTable align(128) = ashet.platform.profile.start.initial_vector_table.*;

fn early_initialize() void {
    // Disable watch dog, reset all peripherials, and set the clocks and PLLs:
    hal.init_sequence(clock_config);

    pinout.xip_cs1.set_function(.gpck_xip_cs_coresight_trace);
    pinout.debug_tx.set_function(.uart_first);
    pinout.debug_rx.set_function(.uart_first);
    // pinout.dbg_sel.set_function(.sio);
    // pinout.dbg_sck.set_function(.sio);
    // pinout.dbg_sda.set_function(.sio);

    // pinout.dbg_sel.set_direction(.out);
    // pinout.dbg_sck.set_direction(.out);
    // pinout.dbg_sda.set_direction(.out);
    // pinout.dbg_sel.put(0);
    // pinout.dbg_sck.put(0);
    // pinout.dbg_sda.put(0);

    debug_uart.apply(.{
        .baud_rate = 115_200,
        .clock_config = clock_config,
    });

    logger.info("Debug output ready.", .{});

    // bitbang_write("Debug ready.\r\n");

    psram.init() catch @panic("failed to initialize psram!");

    logger.info("Machine early initialize done.", .{});
}

fn initialize() !void {
    logger.info("cpuid: {s}", .{
        ashet.platform.profile.registers.system_control_block.cpuid.read(),
    });

    // Remap interrupt table:
    ashet.platform.profile.registers.system_control_block.vtor.write(.{
        .table_offset = @truncate(@intFromPtr(&interrupt_table) >> 7),
    });

    logger.info("initialize SysTick...", .{});
    systick.init();

    // Initialize devices and drivers:
    {
        hw.rtc = ashet.drivers.rtc.Dummy_RTC.init(1739025296 * std.time.ns_per_s);

        hw.uart0 = try ashet.drivers.serial.RP2xxx.init(clock_config, hal.uart.instance.UART0);
        hw.uart1 = try ashet.drivers.serial.RP2xxx.init(clock_config, hal.uart.instance.UART1);

        // hw.fb_video = ashet.drivers.video.Virtual_Video_Output.init();

        hw.hstx_video = try ashet.drivers.video.HSTX_DVI.init(clock_config);

        hw.xip_flash = ashet.drivers.block.Memory_Mapped_Flash.init(
            disk_image_start,
            disk_image_end - disk_image_start,
        );
    }

    ashet.drivers.install(&hw.rtc.driver);
    ashet.drivers.install(&hw.uart0.driver);
    ashet.drivers.install(&hw.uart1.driver);
    ashet.drivers.install(&hw.hstx_video.driver);
    ashet.drivers.install(&hw.xip_flash.driver);
}

fn debug_write(msg: []const u8) void {
    debug_uart.write_blocking(msg, null) catch {};
}

extern const __machine_linmem_start: u8 align(4);
extern const __machine_linmem_end: u8 align(4);

fn get_linear_memory_region() ashet.memory.Range {
    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = @intFromPtr(&__machine_linmem_end);
    return .{ .base = linmem_start, .length = linmem_end - linmem_start };
}

const systick = struct {
    const regs = ashet.platform.profile.registers.sys_tick;

    var total_count_ms: u64 = 0;

    fn init() void {
        const calib = regs.calib.read();

        if (calib.ten_ms == 0) {
            @panic("Virtual SysTick requires known 10ms calibration, but none present!");
        }
        if (calib.skew != .exact) {
            logger.warn("SysTick has time skew!", .{});
        }

        regs.rvr.write(.{ .reload = @max(1, calib.ten_ms / 10) });

        interrupt_table.systick = increment_clock_irq;

        regs.csr.modify(.{
            .enabled = true,
            .interrupt = .enabled,
            .clock_source = .external_clock,
        });
    }

    fn increment_clock_irq() callconv(.C) void {
        total_count_ms +%= 1;
    }
};

export const image_def align(64) linksection(".text.image_def") = [_]u32{
    // For explanation, see RP2350 Datasheet, Chapter "5.9.5. Minimum Viable Image Metadata":
    PICOBIN_BLOCK_MARKER_START,
    0x10210142, // IMAGE_TYPE = EXE + Secure Arm + RP2350
    0x000001ff, // End Marker Item, Total Size 1
    0x00000000, // Pointer to the next block (self loop)
    PICOBIN_BLOCK_MARKER_END,
};

const PICOBIN_BLOCK_MARKER_START = 0xffffded3;
const PICOBIN_BLOCK_MARKER_END = 0xab123579;

// pub fn bitbang_write(data: []const u8) linksection(".ramcode") void {
//     @setRuntimeSafety(false);

//     const sck_mask = comptime pinout.dbg_sck.mask();
//     const sda_mask = comptime pinout.dbg_sda.mask();
//     const sel_mask = comptime pinout.dbg_sel.mask();

//     for (data) |byte| {
//         rp2350_regs.SIO.GPIO_OUT_SET.write_raw(sel_mask); // SEL=H
//         defer rp2350_regs.SIO.GPIO_OUT_CLR.write_raw(sel_mask); // SEL=L

//         var shift = byte;
//         for (0..8) |_| {
//             if ((shift & 0x80) != 0) {
//                 rp2350_regs.SIO.GPIO_OUT_SET.write_raw(sda_mask);
//             } else {
//                 rp2350_regs.SIO.GPIO_OUT_CLR.write_raw(sda_mask);
//             }

//             rp2350_regs.SIO.GPIO_OUT_SET.write_raw(sck_mask);

//             asm volatile ("nop");
//             asm volatile ("nop");
//             rp2350_regs.SIO.GPIO_OUT_CLR.write_raw(sck_mask);

//             shift <<= 1;
//         }
//     }
// }
