//!
//! HDMI/DVI Bitbang Driver based on the RP2350 HSTX
//!
const std = @import("std");
const ashet = @import("../../main.zig");
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
    .refresh_rate = 60.0,
});

const MODE_H_SYNC_POLARITY = @intFromBool(video_timings.hsync == .positive);
const MODE_H_FRONT_PORCH = video_timings.hfrontporch();
const MODE_H_SYNC_WIDTH = video_timings.hsyncwidth();
const MODE_H_BACK_PORCH = video_timings.hbackporch();
const MODE_H_ACTIVE_PIXELS = video_timings.hdisplay;
const MODE_H_TOTAL_PIXELS = video_timings.htotal;

const MODE_V_SYNC_POLARITY = @intFromBool(video_timings.vsync == .positive);
const MODE_V_FRONT_PORCH = video_timings.vfrontporch();
const MODE_V_SYNC_WIDTH = video_timings.vsyncwidth();
const MODE_V_BACK_PORCH = video_timings.vbackporch();
const MODE_V_ACTIVE_LINES = video_timings.vdisplay;
const MODE_V_TOTAL_LINES = video_timings.vtotal;

var framebuffer: [@as(usize, video_resolution.width) * video_resolution.height]ColorIndex align(4096) = undefined;
var palette: [256]Color = undefined;

driver: Driver,

pub fn init(comptime clock_config: hal.clocks.config.Global) !HSTX_DVI {
    _ = clock_config;

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
    const lane_to_output_bit = .{
        .{ &hstx_ctrl.BIT0, &hstx_ctrl.BIT1 },
        .{ &hstx_ctrl.BIT6, &hstx_ctrl.BIT7 },
        .{ &hstx_ctrl.BIT4, &hstx_ctrl.BIT5 },
    };

    inline for (lane_to_output_bit, 0..) |bitlane, lane| {
        const pos, const neg = bitlane;

        // Output even bits during first half of each HSTX cycle, and odd bits
        // during second half. The shifter advances by two bits each cycle.
        const p = lane * 10;
        const n = lane * 10 + 1;

        // The two halves of each pair get identical data, but one pin is inverted.
        pos.write_default(.{ .SEL_P = p, .SEL_N = n });
        neg.write_default(.{ .SEL_P = p, .SEL_N = n, .INV = 1 });
    }

    for (12..20) |gpio| { // 12...19 (inc)
        hal.gpio.num(@truncate(gpio)).set_function(.hstx);
    }

    // Both channels are set up identically, to transfer a whole scanline and
    // then chain to the opposite channel. Each time a channel finishes, we
    // reconfigure the one that just finished, meanwhile the opposite channel
    // is already making progress.
    // dma_channel_config c;
    // c = dma_channel_get_default_config(DMACH_PING);
    // channel_config_set_chain_to(&c, DMACH_PONG);
    // channel_config_set_dreq(&c, DREQ_HSTX);
    // dma_channel_configure(
    //     DMACH_PING,
    //     &c,
    //     &hstx_fifo_hw->fifo,
    //     vblank_line_vsync_off,
    //     count_of(vblank_line_vsync_off),
    //     false
    // );
    // c = dma_channel_get_default_config(DMACH_PONG);
    // channel_config_set_chain_to(&c, DMACH_PING);
    // channel_config_set_dreq(&c, DREQ_HSTX);
    // dma_channel_configure(
    //     DMACH_PONG,
    //     &c,
    //     &hstx_fifo_hw->fifo,
    //     vblank_line_vsync_off,
    //     count_of(vblank_line_vsync_off),
    //     false
    // );

    // dma_hw->ints0 = (1u << DMACH_PING) | (1u << DMACH_PONG);
    // dma_hw->inte0 = (1u << DMACH_PING) | (1u << DMACH_PONG);
    // irq_set_exclusive_handler(DMA_IRQ_0, dma_irq_handler);
    // irq_set_enabled(DMA_IRQ_0, true);

    // bus_ctrl_hw->priority = BUSCTRL_BUS_PRIORITY_DMA_W_BITS | BUSCTRL_BUS_PRIORITY_DMA_R_BITS;

    // dma_channel_start(DMACH_PING);

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

const vblank_line_vsync_off = [_]u32{
    HSTX_CMD_RAW_REPEAT | MODE_H_FRONT_PORCH,
    SYNC_V1_H1,
    HSTX_CMD_RAW_REPEAT | MODE_H_SYNC_WIDTH,
    SYNC_V1_H0,
    HSTX_CMD_RAW_REPEAT | (MODE_H_BACK_PORCH + MODE_H_ACTIVE_PIXELS),
    SYNC_V1_H1,
    HSTX_CMD_NOP,
};

const vblank_line_vsync_on = [_]u32{
    HSTX_CMD_RAW_REPEAT | MODE_H_FRONT_PORCH,
    SYNC_V0_H1,
    HSTX_CMD_RAW_REPEAT | MODE_H_SYNC_WIDTH,
    SYNC_V0_H0,
    HSTX_CMD_RAW_REPEAT | (MODE_H_BACK_PORCH + MODE_H_ACTIVE_PIXELS),
    SYNC_V0_H1,
    HSTX_CMD_NOP,
};

const vactive_line = [_]u32{
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

const DMACH_PING: u4 = 0;
const DMACH_PONG: u4 = 1;

// First we ping. Then we pong. Then... we ping again.
var dma_pong = false;

// A ping and a pong are cued up initially, so the first time we enter this
// handler it is to cue up the second ping after the first ping has completed.
// This is the third scanline overall (-> =2 because zero-based).
var v_scanline: u32 = 2;

// During the vertical active period, we take two IRQs per scanline: one to
// post the command list, and another to post the pixels.
var vactive_cmdlist_posted = false;

fn dma_irq_handler() linksection(".ramtext.bank4") callconv(.C) void {
    // dma_pong indicates the channel that just finished, which is the one
    // we're about to reload.
    const ch_num = if (dma_pong) DMACH_PONG else DMACH_PING;

    const ch = hal.dma.channel(ch_num);

    regz.DMA.INTR.write_raw(@as(u32, 1) << ch_num);

    dma_pong = !dma_pong;

    if (v_scanline >= MODE_V_FRONT_PORCH and v_scanline < (MODE_V_FRONT_PORCH + MODE_V_SYNC_WIDTH)) {
        ch.read_addr = vblank_line_vsync_on;
        ch.transfer_count = vblank_line_vsync_on.len;
    } else if (v_scanline < MODE_V_FRONT_PORCH + MODE_V_SYNC_WIDTH + MODE_V_BACK_PORCH) {
        ch.read_addr = vblank_line_vsync_off;
        ch.transfer_count = vblank_line_vsync_off.len;
    } else if (!vactive_cmdlist_posted) {
        ch.read_addr = vactive_line;
        ch.transfer_count = vactive_line.len;
        vactive_cmdlist_posted = true;
    } else {
        ch.read_addr = &framebuffer[(v_scanline - (MODE_V_TOTAL_LINES - MODE_V_ACTIVE_LINES)) * MODE_H_ACTIVE_PIXELS];
        ch.transfer_count = MODE_H_ACTIVE_PIXELS / @sizeOf(u32);
        vactive_cmdlist_posted = false;
    }

    if (!vactive_cmdlist_posted) {
        v_scanline = (v_scanline + 1) % MODE_V_TOTAL_LINES;
    }
}

// ----------------------------------------------------------------------------
// Main program

// inline fn   colour_rgb565(r: u8 ,  g: u8,  b: u8) u16 {
//     return ((uint16_t)r & 0xf8) >> 3 | ((uint16_t)g & 0xfc) << 3 | ((uint16_t)b & 0xf8) << 8;
// }

// inline fn   colour_rgb332(r: u8 ,  g: u8,  b: u8) u8 {
//     return (r & 0xc0) >> 6 | (g & 0xe0) >> 3 | (b & 0xe0) >> 0;
// }
