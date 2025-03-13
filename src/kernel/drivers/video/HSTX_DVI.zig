//!
//! HDMI/DVI Bitbang Driver based on the RP2350 HSTX
//!
const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.hstx_dvi);
const Driver = ashet.drivers.Driver;
const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");

const cvt = @import("cvt");

const regz = rp2350.devices.RP2350.peripherals;

const HSTX_DVI = @This();

const Color = ashet.video.Color;
const ColorIndex = ashet.video.ColorIndex;
const Resolution = ashet.video.Resolution;

const hstx_ctrl = regz.HSTX_CTRL;
const hstx_fifo = regz.HSTX_FIFO;

const video_resolution = Resolution.new(640, 480);

const video_timings = cvt.compute(.{
    .width = video_resolution.width,
    .height = video_resolution.height,
    .refresh_rate = 75.0,
});

const MODE_H_SYNC_POLARITY = @intFromBool(video_timings.hsync == .positive);
const MODE_H_FRONT_PORCH = video_timings.hfrontporch();
const MODE_H_SYNC_WIDTH = video_timings.hsyncwidth();
const MODE_H_BACK_PORCH = video_timings.hbackporch();
const MODE_H_ACTIVE_PIXELS = video_timings.hdisplay;

const MODE_V_SYNC_POLARITY = @intFromBool(video_timings.vsync == .positive);
const MODE_V_FRONT_PORCH = video_timings.vfrontporch();
const MODE_V_SYNC_WIDTH = video_timings.vsyncwidth();
const MODE_V_BACK_PORCH = video_timings.vbackporch();
const MODE_V_ACTIVE_LINES = video_timings.vdisplay;
const MODE_V_TOTAL_LINES = video_timings.vtotal;

var framebuffer: [@as(usize, video_resolution.width) * video_resolution.height]ColorIndex align(4096) = undefined;
var palette: [256]Color = undefined;

const led_pin = hal.gpio.num(3);

driver: Driver,

var backend_ready = false;

pub fn init(comptime clock_config: hal.clocks.config.Global) !HSTX_DVI {
    if (!backend_ready)
        @panic("HSTX_DVI requires the backend to be started before initializing the driver!");

    logger.info("Video Timings:", .{});
    logger.info(" Horizontal: {} {} {} {}", .{
        video_timings.hdisplay,
        video_timings.hsync_start,
        video_timings.hsync_end,
        video_timings.htotal,
    });
    logger.info(" Vertical:   {} {} {} {}", .{
        video_timings.vdisplay,
        video_timings.vsync_start,
        video_timings.vsync_end,
        video_timings.vtotal,
    });

    logger.info(" Timing:     {d:.2} Hz, {d:.2} kHz, {d:.2} MHz, ", .{
        video_timings.vrefresh_hz,
        video_timings.hsync_khz,
        @as(f32, @floatFromInt(video_timings.dot_clock_khz)) / 1000.0,
    });

    const pixel_clock = 1000 * video_timings.dot_clock_khz;
    const hstx_src_clock = clock_config.hstx.?.frequency();
    const hstx_bit_clock = 2 * hstx_src_clock;
    const dvi_bit_clock = 10 * pixel_clock;

    logger.info("Pixel Clock     = {}", .{ashet.utils.fmt.freq(pixel_clock)});
    logger.info("DVI Bit Clock   = {}", .{ashet.utils.fmt.freq(dvi_bit_clock)});
    logger.info("HSTX Peri Clock = {}", .{ashet.utils.fmt.freq(hstx_src_clock)});
    logger.info("HSTX Bit Clock  = {}", .{ashet.utils.fmt.freq(hstx_bit_clock)});
    logger.info("Clock Precision = {d:.2} %", .{
        100 * @as(f64, @floatFromInt(hstx_bit_clock)) / @as(f64, @floatFromInt(dvi_bit_clock)),
    });

    var rng = std.Random.Xoroshiro128.init(10);
    rng.random().bytes(std.mem.sliceAsBytes(&framebuffer));

    const vd: HSTX_DVI = .{
        .driver = .{
            .name = "HSTX DVI",
            .class = .{
                .video = .{
                    .getVideoMemoryFn = get_video_memory,
                    .getPaletteMemoryFn = get_palette_memory,
                    .setBorderFn = set_border,
                    .flushFn = flush,
                    .getResolutionFn = get_resolution,
                    .getMaxResolutionFn = get_max_resolution,
                    .getBorderFn = get_border,
                    .setResolutionFn = set_resolution,
                },
            },
        },
    };

    return vd;
}

/// Starts the backin
pub fn start_backend(comptime clock_config: hal.clocks.config.Global) void {
    _ = clock_config;

    // Claim the two channels
    DMACH_PING.claim();
    DMACH_PONG.claim();

    led_pin.set_function(.sio);
    led_pin.set_direction(.out);

    // Configure HSTX's TMDS encoder for RGB332

    hstx_ctrl.EXPAND_TMDS.write_default(.{
        .L2_NBITS = 2,
        .L2_ROT = 0,
        .L1_NBITS = 2,
        .L1_ROT = 29,
        .L0_NBITS = 1,
        .L0_ROT = 26,
    });

    // Pixels (TMDS) come in 4 8-bit chunks. Control symbols (RAW) are an
    // entire 32-bit word.
    hstx_ctrl.EXPAND_SHIFT.write_default(.{
        .ENC_N_SHIFTS = 4,
        .ENC_SHIFT = 8,
        .RAW_N_SHIFTS = 1,
        .RAW_SHIFT = 0,
    });

    // Serial output config: clock period of 5 cycles, pop from command
    // expander every 5 cycles, shift the output shiftreg by 2 every cycle.
    hstx_ctrl.CSR.write_raw(0);

    hstx_ctrl.CSR.write_default(.{
        .EXPAND_EN = 1,
        .CLKDIV = 5,
        .N_SHIFTS = 5,
        .SHIFT = 2,
        .EN = 1,
    });

    // Note we are leaving the HSTX clock at the SDK default of 125 MHz; since
    // we shift out two bits per HSTX clock cycle, this gives us an output of
    // 250 Mbps, which is very close to the bit clock for 480p 60Hz (252 MHz).
    // If we want the exact rate then we'll have to reconfigure PLLs.

    // HSTX outputs 0 through 7 appear on GPIO 12 through 19.
    // Pinout on Pico DVI sock:
    //
    //   GP12 D0+  GP13 D0-
    //   GP14 CK+  GP15 CK-
    //   GP16 D2+  GP17 D2-
    //   GP18 D1+  GP19 D1-

    // Assign clock pair to two neighbouring pins:
    hstx_ctrl.BIT2.write_default(.{ .CLK = 1 });
    hstx_ctrl.BIT3.write_default(.{ .CLK = 1, .INV = 1 });

    // For each TMDS lane, assign it to the correct GPIO pair based on the
    // desired pinout:

    hstx_ctrl.BIT0.write_default(.{ .SEL_P = 0, .SEL_N = 1, .INV = 0 });
    hstx_ctrl.BIT1.write_default(.{ .SEL_P = 0, .SEL_N = 1, .INV = 1 });
    hstx_ctrl.BIT6.write_default(.{ .SEL_P = 10, .SEL_N = 11, .INV = 0 });
    hstx_ctrl.BIT7.write_default(.{ .SEL_P = 10, .SEL_N = 11, .INV = 1 });
    hstx_ctrl.BIT4.write_default(.{ .SEL_P = 20, .SEL_N = 21, .INV = 0 });
    hstx_ctrl.BIT5.write_default(.{ .SEL_P = 20, .SEL_N = 21, .INV = 1 });

    for (12..20) |gpio| { // 12...19 (inc)
        hal.gpio.num(@truncate(gpio)).set_function(.hstx);
    }

    // Both channels are set up identically, to transfer a whole scanline and
    // then chain to the opposite channel. Each time a channel finishes, we
    // reconfigure the one that just finished, meanwhile the opposite channel
    // is already making progress.

    // Configure PING channel:
    const ping_ch = DMACH_PING.get_regs();
    ping_ch.al1_ctrl.write(.{
        .EN = 1,
        .HIGH_PRIORITY = 0,
        .DATA_SIZE = .SIZE_WORD,

        .INCR_READ = 1,
        .INCR_READ_REV = 0,

        .INCR_WRITE = 0,
        .INCR_WRITE_REV = 0,

        .RING_SIZE = .RING_NONE,
        .RING_SEL = 0,

        .CHAIN_TO = @intFromEnum(DMACH_PONG),
        .TREQ_SEL = .HSTX,

        .IRQ_QUIET = 0,
        .BSWAP = 0,
        .SNIFF_EN = 0,
        .BUSY = 0,
        .reserved29 = 0,
        .WRITE_ERROR = 0,
        .READ_ERROR = 0,
        .AHB_ERROR = 0,
    });

    const pong_ch = DMACH_PONG.get_regs();
    pong_ch.al1_ctrl.write(.{
        .EN = 1,
        .HIGH_PRIORITY = 0,
        .DATA_SIZE = .SIZE_WORD,

        .INCR_READ = 1,
        .INCR_READ_REV = 0,

        .INCR_WRITE = 0,
        .INCR_WRITE_REV = 0,

        .RING_SIZE = .RING_NONE,
        .RING_SEL = 0,

        .CHAIN_TO = @intFromEnum(DMACH_PING),
        .TREQ_SEL = .HSTX,

        .IRQ_QUIET = 0,
        .BSWAP = 0,
        .SNIFF_EN = 0,
        .BUSY = 0,
        .reserved29 = 0,
        .WRITE_ERROR = 0,
        .READ_ERROR = 0,
        .AHB_ERROR = 0,
    });

    set_read_transfer(ping_ch, &vblank_line_vsync_off);
    set_read_transfer(pong_ch, &vblank_line_vsync_off);

    ping_ch.write_addr = @intFromPtr(&hstx_fifo.FIFO);
    pong_ch.write_addr = @intFromPtr(&hstx_fifo.FIFO);

    // Enable both IRQs on IRQ 0
    regz.DMA.INTE0.write_raw(DMACH_PING_MASK | DMACH_PONG_MASK);

    // Acknowledge potential pending IRQs:
    regz.DMA.INTS0.write_raw(DMACH_PING_MASK | DMACH_PONG_MASK);

    logger.info("INTE0: 0x{X:0>4}", .{regz.DMA.INTE0.read().INTE0});
    logger.info("INTS0: 0x{X:0>4}", .{regz.DMA.INTS0.read().INTS0});

    const irq = ashet.machine.IRQ.DMA_IRQ_0;

    irq.set_handler(dma_irq_handler);
    irq.enable();

    // regz.BUSCTRL.BUS_PRIORITY.write_default(.{
    //     // DMA read and write win over CPU:
    //     .DMA_W = 1,
    //     .DMA_R = 1,
    //     .PROC0 = 0,
    //     .PROC1 = 0,
    // });

    ashet.platform.profile.enable_interrupts();

    // Start transferring the PING to kick off the video generation:
    regz.DMA.MULTI_CHAN_TRIGGER.write_raw(DMACH_PING_MASK);

    backend_ready = true;
}

fn kill_dma() void {
    regz.DMA.INTE0.write_raw(0);
    regz.DMA.INTS0.write_raw(DMACH_PING_MASK | DMACH_PONG_MASK);
}

noinline fn dma_error(ch0: anytype, ch1: anytype) void {
    kill_dma();
    logger.err("DMA CLICKS: {}", .{dma_clicks});
    logger.err("DMA ERROR: ch0: {}", .{ch0});
    logger.err("DMA ERROR: ch1: {}", .{ch1});
}

noinline fn dma_timeout(mask: u16) void {
    kill_dma();
    logger.err("DMA CLICKS: {}", .{dma_clicks});
    logger.err("DMA TIMING: 0x{X:0>4}", .{mask});
}
var dma_clicks: u32 = 0;

noinline fn dma_irq_handler() linksection(".ramtext.bank4") callconv(.C) void {
    @setRuntimeSafety(false);

    dma_clicks += 1;

    const ch0_stat = regz.DMA.CH0_CTRL_TRIG.read();
    const ch1_stat = regz.DMA.CH1_CTRL_TRIG.read();

    if (ch0_stat.AHB_ERROR != 0 or ch1_stat.AHB_ERROR != 0) {
        return dma_error(ch0_stat, ch1_stat);
    }

    const status = regz.DMA.INTS0.read();
    if (status.INTS0 != 1 and status.INTS0 != 2) {
        return dma_timeout(status.INTS0);
    }

    // dma_pong indicates the channel that just finished, which is the one
    // we're about to reload.
    const mask = if (dma_pong) DMACH_PONG_MASK else DMACH_PING_MASK;

    const ch = if (dma_pong) comptime DMACH_PONG.get_regs() else comptime DMACH_PING.get_regs();

    regz.DMA.INTR.write_raw(mask);

    dma_pong = !dma_pong;

    if (v_scanline >= MODE_V_FRONT_PORCH and v_scanline < (MODE_V_FRONT_PORCH + MODE_V_SYNC_WIDTH)) {
        set_read_transfer(ch, &vblank_line_vsync_on);
    } else if (v_scanline < MODE_V_FRONT_PORCH + MODE_V_SYNC_WIDTH + MODE_V_BACK_PORCH) {
        set_read_transfer(ch, &vblank_line_vsync_off);
    } else if (!vactive_cmdlist_posted) {
        set_read_transfer(ch, &vactive_line);
        vactive_cmdlist_posted = true;
        return; // don't increment the scanline!
    } else {
        set_read_transfer_raw(
            ch,
            &framebuffer[(v_scanline - (MODE_V_TOTAL_LINES - MODE_V_ACTIVE_LINES)) * MODE_H_ACTIVE_PIXELS],
            @divExact(MODE_H_ACTIVE_PIXELS, 4),
        );
        vactive_cmdlist_posted = false;
    }

    v_scanline = (v_scanline + 1) % MODE_V_TOTAL_LINES;

    if (v_scanline == 0) {
        led_pin.put(0);
    }
    if (v_scanline == MODE_V_TOTAL_LINES / 2) {
        led_pin.put(1);
    }
}

inline fn set_read_transfer(regs: *volatile hal.dma.Channel.Regs, buffer: []const u32) void {
    regs.read_addr = @intFromPtr(buffer.ptr);
    regs.trans_count.write(.{ .COUNT = @intCast(buffer.len), .MODE = .NORMAL });
}

inline fn set_read_transfer_raw(regs: *volatile hal.dma.Channel.Regs, ptr: *anyopaque, count: u28) void {
    regs.read_addr = @intFromPtr(ptr);
    regs.trans_count.write(.{ .COUNT = count, .MODE = .NORMAL });
}

fn instance(dri: *Driver) *HSTX_DVI {
    return @fieldParentPtr("driver", dri);
}

fn get_video_memory(dri: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd = instance(dri);
    _ = vd;
    return &framebuffer;
}

fn get_palette_memory(dri: *Driver) *[256]Color {
    const vd = instance(dri);
    _ = vd;
    return &palette;
}

fn set_border(dri: *Driver, color: ColorIndex) void {
    const vd = instance(dri);
    _ = vd;
    _ = color;
}

fn flush(dri: *Driver) void {
    const vd = instance(dri);
    _ = vd;
}

fn get_resolution(dri: *Driver) Resolution {
    const vd = instance(dri);
    _ = vd;
    return video_resolution;
}

fn get_max_resolution(dri: *Driver) Resolution {
    const vd = instance(dri);
    _ = vd;
    return video_resolution;
}

fn get_border(dri: *Driver) ColorIndex {
    const vd = instance(dri);
    _ = vd;
    return ColorIndex.get(0);
}

fn set_resolution(dri: *Driver, width: u15, height: u15) void {
    const vd = instance(dri);
    _ = vd;
    _ = width;
    _ = height;
}

// ----------------------------------------------------------------------------
// DVI constants

const TMDS_CTRL_00 = 0x354;
const TMDS_CTRL_01 = 0x0ab;
const TMDS_CTRL_10 = 0x154;
const TMDS_CTRL_11 = 0x2ab;

const SYNC_V0_H0 = TMDS_CTRL_00 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20);
const SYNC_V0_H1 = TMDS_CTRL_01 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20);
const SYNC_V1_H0 = TMDS_CTRL_10 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20);
const SYNC_V1_H1 = TMDS_CTRL_11 | (TMDS_CTRL_00 << 10) | (TMDS_CTRL_00 << 20);

const HSTX_CMD_RAW = (0x0 << 12);
const HSTX_CMD_RAW_REPEAT = (0x1 << 12);
const HSTX_CMD_TMDS = (0x2 << 12);
const HSTX_CMD_TMDS_REPEAT = (0x3 << 12);
const HSTX_CMD_NOP = (0xf << 12);

// ----------------------------------------------------------------------------
// HSTX command lists

// Lists are padded with NOPs to be >= HSTX FIFO size, to avoid DMA rapidly
// pingponging and tripping up the IRQs.

const vblank_line_vsync_off align(4) linksection(".data") = [_]u32{
    HSTX_CMD_RAW_REPEAT | MODE_H_FRONT_PORCH,
    SYNC_V1_H1,
    HSTX_CMD_RAW_REPEAT | MODE_H_SYNC_WIDTH,
    SYNC_V1_H0,
    HSTX_CMD_RAW_REPEAT | (MODE_H_BACK_PORCH + MODE_H_ACTIVE_PIXELS),
    SYNC_V1_H1,
    HSTX_CMD_NOP,
};

const vblank_line_vsync_on align(4) linksection(".data") = [_]u32{
    HSTX_CMD_RAW_REPEAT | MODE_H_FRONT_PORCH,
    SYNC_V0_H1,
    HSTX_CMD_RAW_REPEAT | MODE_H_SYNC_WIDTH,
    SYNC_V0_H0,
    HSTX_CMD_RAW_REPEAT | (MODE_H_BACK_PORCH + MODE_H_ACTIVE_PIXELS),
    SYNC_V0_H1,
    HSTX_CMD_NOP,
};

const vactive_line align(4) linksection(".data") = [_]u32{
    HSTX_CMD_RAW_REPEAT | MODE_H_FRONT_PORCH,
    SYNC_V1_H1,
    HSTX_CMD_NOP,
    HSTX_CMD_RAW_REPEAT | MODE_H_SYNC_WIDTH,
    SYNC_V1_H0,
    HSTX_CMD_NOP,
    HSTX_CMD_RAW_REPEAT | MODE_H_BACK_PORCH,
    SYNC_V1_H1,
    HSTX_CMD_TMDS | MODE_H_ACTIVE_PIXELS,
};

// ----------------------------------------------------------------------------
// DMA logic

const DMACH_PING = hal.dma.channel(0);
const DMACH_PONG = hal.dma.channel(1);

const DMACH_PING_MASK: u16 = @as(u16, 1) << @intFromEnum(DMACH_PING);
const DMACH_PONG_MASK: u16 = @as(u16, 1) << @intFromEnum(DMACH_PONG);

// First we ping. Then we pong. Then... we ping again.
var dma_pong = false;

// A ping and a pong are cued up initially, so the first time we enter this
// handler it is to cue up the second ping after the first ping has completed.
// This is the third scanline overall (-> =2 because zero-based).
var v_scanline: u32 = 2;

// During the vertical active period, we take two IRQs per scanline: one to
// post the command list, and another to post the pixels.
var vactive_cmdlist_posted = false;
