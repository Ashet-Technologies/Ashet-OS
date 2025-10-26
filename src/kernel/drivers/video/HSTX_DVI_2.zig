//!
//! HDMI/DVI Bitbang Driver based on the RP2350 HSTX
//!
const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.hstx_dvi);
const Driver = ashet.drivers.Driver;
const rp2350 = @import("rp2350-hal");

const hw_alloc = ashet.machine.hw_alloc;

const SpScQueue = @import("../../utils/spsc_queue.zig").SpScQueue;

const cvt = @import("cvt");

const chip = @import("rp2350").peripherals;

const HSTX_DVI = @This();

const Color = ashet.video.Color;

const hstx_ctrl_hw = chip.HSTX_CTRL;

const framebuffer_size: ashet.video.Resolution = .{
    .width = 640,
    .height = 400,
};

const framebuffer_item_cnt = @as(u32, framebuffer_size.width) * framebuffer_size.height;

fn cast_to_fb(src: *const [framebuffer_item_cnt]u8) [framebuffer_item_cnt]Color {
    return @bitCast(src.*);
}

pub var framebuffer: [framebuffer_item_cnt]Color align(4096) linksection(img_framebuf_section) = blk: {
    var fb: [framebuffer_item_cnt]Color align(4) = @splat(ashet.video.defaults.border_color);
    ashet.video.load_splash_screen(.{
        .base = &fb,
        .width = framebuffer_size.width,
        .height = framebuffer_size.height,
        .stride = framebuffer_size.width,
    });
    break :blk fb;
};

const PaletteColor = RGB555;
// const PaletteColor = RGB888x;

const letterbox_color = [1]PaletteColor{.from_hex(0x7E2553)} ** @divExact(@sizeOf(u32), @sizeOf(PaletteColor));

var backend_ready = false;

driver: Driver,

pub fn init(comptime clock_config: rp2350.clocks.config.Global) !HSTX_DVI {
    _ = clock_config;

    // if (!backend_ready)
    //     @panic("HSTX_DVI requires the backend to be started before initializing the driver!");

    logger.info("Video Timings:", .{});
    logger.info(" Horizontal: {} {} {} {}", .{
        timings.horizontal.front_porch,
        timings.horizontal.sync_width,
        timings.horizontal.back_porch,
        timings.horizontal.active_items,
    });
    logger.info(" Vertical:   {} {} {} {}", .{
        timings.vertical.front_porch,
        timings.vertical.sync_width,
        timings.vertical.back_porch,
        timings.vertical.active_items,
    });

    // logger.info(" Timing:     {d:.2} Hz, {d:.2} kHz, {d:.2} MHz, ", .{
    //     video_timings.vrefresh_hz,
    //     video_timings.hsync_khz,
    //     @as(f32, @floatFromInt(video_timings.dot_clock_khz)) / 1000.0,
    // });

    // const pixel_clock = 1000 * video_timings.dot_clock_khz;
    // const hstx_src_clock = clock_config.hstx.?.frequency();
    // const hstx_bit_clock = 2 * hstx_src_clock;
    // const dvi_bit_clock = 10 * pixel_clock;

    // logger.info("Pixel Clock     = {}", .{ashet.utils.fmt.freq(pixel_clock)});
    // logger.info("DVI Bit Clock   = {}", .{ashet.utils.fmt.freq(dvi_bit_clock)});
    // logger.info("HSTX Peri Clock = {}", .{ashet.utils.fmt.freq(hstx_src_clock)});
    // logger.info("HSTX Bit Clock  = {}", .{ashet.utils.fmt.freq(hstx_bit_clock)});
    // logger.info("Clock Precision = {d:.2} %", .{
    //     100 * @as(f64, @floatFromInt(hstx_bit_clock)) / @as(f64, @floatFromInt(dvi_bit_clock)),
    // });

    // var rng = std.Random.Xoroshiro128.init(10);
    // rng.random().bytes(std.mem.sliceAsBytes(&framebuffer));

    const vd: HSTX_DVI = .{
        .driver = .{
            .name = "HSTX DVI",
            .class = .{
                .video = .{
                    .get_properties_fn = get_properties,
                    .flush_fn = flush,
                },
            },
        },
    };

    return vd;
}

fn instance(dri: *Driver) *HSTX_DVI {
    return @fieldParentPtr("driver", dri);
}

fn get_properties(dri: *Driver) ashet.video.DeviceProperties {
    const vd = instance(dri);
    _ = vd;
    return .{
        .video_memory = &framebuffer,
        .video_memory_mapping = .unbuffered,
        .resolution = framebuffer_size,
        .stride = framebuffer_size.width,
    };
}

fn flush(dri: *Driver) void {
    const vd = instance(dri);
    _ = vd;
}

const dma_data0_section = ".sram.bank2";
const dma_data1_section = ".sram.bank3";
const dma_datax_section = ".sram.bank1";
const dma_code_section = ".sram.bank0";

const img_framebuf_section = ".sram.bank1.noinit";
const img_palette_section = ".sram.bank1";

// CVT 800x480: Pixel Clock = 29.5 MHz
// https://tomverbeure.github.io/video_timings_calculator
const timings: VideoTiming = .{
    .horizontal = .{
        .front_porch = 24,
        .sync_width = 72,
        .back_porch = 96,
        .active_items = 800,
    },

    .vertical = .{
        .front_porch = 3,
        .sync_width = 7,
        .back_porch = 10,
        .active_items = 480,
    },
};

/// Starts the backin
pub fn init_backend(comptime clock_config: rp2350.clocks.config.Global) void {
    if (comptime clock_config.get_frequency(.clk_sys).? != 150_000_000) {
        @compileError("System must run at 150 MHz to create the correct video timings!");
    }

    // Configure HSTX's TMDS encoder for the used RGB color type:
    hstx_ctrl_hw.EXPAND_TMDS.write(.{
        .L2_NBITS = compute_tmds_nbits(.r),
        .L2_ROT = compute_tmds_rot(.r),
        .L1_NBITS = compute_tmds_nbits(.g),
        .L1_ROT = compute_tmds_rot(.g),
        .L0_NBITS = compute_tmds_nbits(.b),
        .L0_ROT = compute_tmds_rot(.b),
        .padding = 0,
    });

    // Pixels (TMDS) come in 4 8-bit chunks. Control symbols (RAW) are an
    // entire 32-bit word.
    hstx_ctrl_hw.EXPAND_SHIFT.write(.{
        .ENC_N_SHIFTS = @divExact(32, @bitSizeOf(PaletteColor)),
        .ENC_SHIFT = @bitSizeOf(PaletteColor) % 32,
        .RAW_N_SHIFTS = 1,
        .RAW_SHIFT = 0,
        .padding = 0,
        .reserved8 = 0,
        .reserved16 = 0,
        .reserved24 = 0,
    });

    // Serial output config: clock period of 5 cycles, pop from command
    // expander every 5 cycles, shift the output shiftreg by 2 every cycle.
    hstx_ctrl_hw.CSR.write_raw(0);
    hstx_ctrl_hw.CSR.write(.{
        .EXPAND_EN = 1,
        .CLKDIV = 5,
        .N_SHIFTS = 5,
        .SHIFT = 2,
        .EN = 1,

        .COUPLED_MODE = 0,
        .COUPLED_SEL = 0,
        .CLKPHASE = 0,

        .reserved4 = 0,
        .reserved8 = 0,
        .reserved16 = 0,
        .reserved24 = 0,
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
    const HstxBit = @TypeOf(hstx_ctrl_hw.BIT0);
    const hstx_ctrl_bits: *volatile [8]HstxBit = @ptrCast(&hstx_ctrl_hw.BIT0);

    hstx_ctrl_bits[0].write(.{ .CLK = 1, .INV = 1, .SEL_P = 0, .SEL_N = 0 });
    hstx_ctrl_bits[1].write(.{ .CLK = 1, .INV = 0, .SEL_P = 0, .SEL_N = 0 });
    inline for (0..3) |lane| {
        // For each TMDS lane, assign it to the correct GPIO pair based on the
        // desired pinout:
        const lane_to_output_bit: [3]usize = .{ 2, 4, 6 };
        const bit = lane_to_output_bit[lane];
        // Output even bits during first half of each HSTX cycle, and odd bits
        // during second half. The shifter advances by two bits each cycle.

        // The two halves of each pair get identical data, but one pin is inverted.
        hstx_ctrl_bits[bit + 0].write(comptime .{
            .SEL_P = @intCast(10 * lane),
            .SEL_N = @intCast(10 * lane + 1),
            .INV = 1,
            .CLK = 0,
        });
        hstx_ctrl_bits[bit + 1].write(comptime .{
            .SEL_P = @intCast(10 * lane),
            .SEL_N = @intCast(10 * lane + 1),
            .INV = 0,
            .CLK = 0,
        });
    }

    // Both channels are set up identically, to transfer a whole scanline and
    // then chain to the opposite channel. Each time a channel finishes, we
    // reconfigure the one that just finished, meanwhile the opposite channel
    // is already making progress.

    hw_alloc.dma.hdmi_ping.setup_transfer_raw(
        @intFromPtr(&chip.HSTX_FIFO.FIFO),
        @intFromPtr(&fifo_chunks.non_image_data),
        fifo_chunks.non_image_data.len,
        .{
            .trigger = false,
            .data_size = .size_32,
            .enable = true,
            .read_increment = true,
            .write_increment = false,
            .dreq = .hstx,
            .chain_to = hw_alloc.dma.hdmi_pong,
            .high_priority = true,
        },
    );
    hw_alloc.dma.hdmi_pong.setup_transfer_raw(
        @intFromPtr(&chip.HSTX_FIFO.FIFO),
        @intFromPtr(&fifo_chunks.non_image_data),
        fifo_chunks.non_image_data.len,
        .{
            .trigger = false,
            .data_size = .size_32,
            .enable = true,
            .read_increment = true,
            .write_increment = false,
            .dreq = .hstx,
            .chain_to = hw_alloc.dma.hdmi_ping,
            .high_priority = true,
        },
    );

    // Clear potentially pending interrupt bits:
    hw_alloc.dma.hdmi_ping.acknowledge_irq1();
    hw_alloc.dma.hdmi_pong.acknowledge_irq1();

    hw_alloc.dma.hdmi_ping.set_irq1_enabled(true);
    hw_alloc.dma.hdmi_pong.set_irq1_enabled(true);

    const irq = hw_alloc.irq.video_dma;
    irq.set_handler(handle_hstx_dma_irq);
    irq.set_priority(.highest);
    irq.enable();

    hw_alloc.pins.hdmi_d0_p.set_function(.hstx);
    hw_alloc.pins.hdmi_d0_n.set_function(.hstx);
    hw_alloc.pins.hdmi_clk_p.set_function(.hstx);
    hw_alloc.pins.hdmi_clk_n.set_function(.hstx);
    hw_alloc.pins.hdmi_d1_p.set_function(.hstx);
    hw_alloc.pins.hdmi_d1_n.set_function(.hstx);
    hw_alloc.pins.hdmi_d2_p.set_function(.hstx);
    hw_alloc.pins.hdmi_d2_n.set_function(.hstx);
}

pub fn start_backend() linksection(".sram.bank0") void {
    ashet.platform.enableInterrupts();

    rp2350.dma.multi_channel_trigger(&.{hw_alloc.dma.hdmi_ping});

    backend_ready = true;
}

const Scanline: type = [framebuffer_size.width]PaletteColor;

var v_scanline: u32 = 0;

var use_pong = false;

var current_scanline_src: [*]align(4) Color = &framebuffer;

inline fn set_dma_channel(regs: *volatile rp2350.dma.Channel.Regs, comptime T: type, slice: []const T) void {
    regs.read_addr = @intFromPtr(slice.ptr);
    switch (@bitSizeOf(T)) {
        8 => regs.trans_count = @divExact(slice.len, 4),
        16 => regs.trans_count = @divExact(slice.len, 2),
        32 => regs.trans_count = slice.len,

        else => @compileError("Invalid bit size! Transfers must be 32 bits!"),
    }
}

fn handle_hstx_dma_irq() linksection(dma_code_section) callconv(.c) void {
    @setRuntimeSafety(false);
    // @optimizeFor(.ReleaseFast);

    if (builtin.mode == .Debug) {
        @panic("The HSTX/HDMI driver has to be compiled with a release mode, otherwise it will be too slow.");
    }

    // if (chip.HSTX_FIFO.STAT.read().EMPTY == 1) {
    //     logger.err("FIFO UNDERFLOW at {}  {}", .{ v_scanline, vactive_cmdlist_state });
    //     ashet.halt();
    // }

    const chan: rp2350.dma.Channel = if (use_pong)
        hw_alloc.dma.hdmi_pong
    else
        hw_alloc.dma.hdmi_ping;
    use_pong = !use_pong;

    chan.acknowledge_irq1();

    const ch = chan.get_regs();

    if (v_scanline >= framebuffer_size.height) {
        // we've sent the full image so we now transfer the whole letterbox + vblank section:
        set_dma_channel(ch, HstxFifoItem, fifo_chunks.even_image_line.as_hstx_slice());
        v_scanline = 0;
    } else {
        comptime std.debug.assert(@mod(framebuffer_size.height, 2) == 0);
        const buf_id = v_scanline & 1;

        const current_buffer: *align(16) fifo_chunks.ImageLine, const next_buffer: *align(16) fifo_chunks.ImageLine = if (buf_id != 0)
            .{ &fifo_chunks.odd_image_line, &fifo_chunks.even_image_line }
        else
            .{ &fifo_chunks.even_image_line, &fifo_chunks.odd_image_line };

        set_dma_channel(
            ch,
            HstxFifoItem,
            current_buffer.as_hstx_slice(),
        );

        v_scanline += 1;
        if (v_scanline == framebuffer_size.height) {
            current_scanline_src = &framebuffer;
            set_dma_channel(
                ch,
                HstxFifoItem,
                &fifo_chunks.non_image_data,
            );
        }

        // Expand the next scanline into memory:
        // convert_scanline_basic(current_scanline_src, &next_buffer.data);
        convert_scanline_minisimd(current_scanline_src, &next_buffer.data);

        current_scanline_src += framebuffer_size.width;
    }
}

inline fn convert_scanline_basic(
    src: [*]Color,
    dst: *Scanline,
) void {

    // this loop takes 2772 which is roughly 4.3 instructions per pixel.
    // the theoretical optimum are 3 instructions per pixel (load, load, store) without any increment,
    // so we're pretty good here.
    for (dst, src) |*d, s| {
        d.* = palette[@as(u8, @bitCast(s))];
    }
}

/// This is a memory-access optimized version for scanline conversion,
/// which reads 4 pixels at once, and writes them back in two writes.
///
/// This should reduce memory pressure on the system quite a lot.
///
/// It doesn't execute much faster than the 1 pixel variant (rougly 300 cycles less),
/// but it decreases the chance of memory contestion.
inline fn convert_scanline_minisimd(
    raw_src: [*]align(4) Color,
    raw_dst: *align(8) Scanline,
) void {
    comptime std.debug.assert((framebuffer_size.width % 4) == 0);

    const Src = packed struct(u32) {
        c0: u8,
        c1: u8,
        c2: u8,
        c3: u8,
    };
    const Dst = packed struct(u64) {
        c0: PaletteColor,
        c1: PaletteColor,
        c2: PaletteColor,
        c3: PaletteColor,
    };

    const src: [*]Src = @ptrCast(raw_src);
    const dst: *[framebuffer_size.width / 4]Dst = @ptrCast(raw_dst);

    for (dst, src) |*d, s| {
        d.* = Dst{
            .c0 = palette[s.c0],
            .c1 = palette[s.c1],
            .c2 = palette[s.c2],
            .c3 = palette[s.c3],
        };
    }
}

/// LORE: This is a **pointer** to the actual color palette.
///       A bug in Zig 0.14.1 creates an implicit array copy when indexing an array like `array[i]` directly.
///       By using an indirection through a pointer, we're still getting the correct optimized behaviour,
///       but the implicit copy is prevented.
///       The problem with the implicit copy is that it's stored in `.rodata`, and thus the external XIP0 flash
///       memory, which has too much latencies to be accessed in the HSTX interrupt handler.
const palette: *const [256]PaletteColor = &palette_storage;

const palette_storage: [256]PaletteColor align(256) linksection(img_palette_section) = blk: {
    @setEvalBranchQuota(10_000);

    // Compute the initial palette from the actual color definition by converting the palette index
    // into the 8 bit color value, then expanding it to the "true color rgb",
    // and store it into the palette backing.
    var pal: [256]PaletteColor = undefined;
    for (&pal, 0..) |*true_color, index| {
        const index8: u8 = @intCast(index);
        const color: Color = @bitCast(index8);
        const rgb = color.to_rgb888();
        true_color.* = .from_rgb(rgb.r, rgb.g, rgb.b);
    }
    break :blk pal;
};

const RGB555 = packed struct(u16) {
    r: u5,
    g: u5,
    b: u5,
    _padding: u1 = 0,

    pub fn from_hex(val: u24) RGB555 {
        const Hex = packed struct(u24) {
            b: u8,
            g: u8,
            r: u8,
        };
        const hex: Hex = @bitCast(val);
        return from_rgb(hex.r, hex.g, hex.b);
    }

    pub fn from_rgb(r: u8, g: u8, b: u8) RGB555 {
        return .{
            .r = @intCast(r >> 3),
            .g = @intCast(g >> 3),
            .b = @intCast(b >> 3),
        };
    }
};

const RGB888x = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    _padding: u8 = 0,

    pub fn from_hex(val: u24) RGB888x {
        const Hex = packed struct(u24) {
            r: u8,
            g: u8,
            b: u8,
        };
        const hex: Hex = @bitCast(val);
        return .{
            .r = hex.r,
            .g = hex.g,
            .b = hex.b,
        };
    }
    pub fn from_rgb(r: u8, g: u8, b: u8) RGB555 {
        return .{ .r = r, .g = g, .b = b };
    }
};

const AxisTiming = struct {
    front_porch: u32,
    sync_width: u32,
    back_porch: u32,
    active_items: u32,

    pub inline fn total(timing: AxisTiming) u32 {
        return timing.front_porch + timing.sync_width + timing.back_porch + timing.active_items;
    }
};

const VideoTiming = struct {
    vertical: AxisTiming,
    horizontal: AxisTiming,
};

const SyncCmd = packed struct(u32) {
    cmd0: u10,
    cmd1: u10,
    cmd2: u10,
    _padding: u2 = 0,
};

const HstxCmdId = enum(u4) {
    raw = 0x0,
    raw_repeat = 0x1,
    tmds = 0x2,
    tmds_repeat = 0x3,
    nop = 0xf,
};

const HstxCmd = packed struct(u16) {
    length: u12, // 0 = infinite
    cmd: HstxCmdId,
};

const TMDS_CTRL_00: u10 = 0x354;
const TMDS_CTRL_01: u10 = 0x0ab;
const TMDS_CTRL_10: u10 = 0x154;
const TMDS_CTRL_11: u10 = 0x2ab;

const SYNC_V0_H0: SyncCmd = .{
    .cmd0 = TMDS_CTRL_00,
    .cmd1 = TMDS_CTRL_00,
    .cmd2 = TMDS_CTRL_00,
};

const SYNC_V0_H1: SyncCmd = .{
    .cmd0 = TMDS_CTRL_01,
    .cmd1 = TMDS_CTRL_00,
    .cmd2 = TMDS_CTRL_00,
};

const SYNC_V1_H0: SyncCmd = .{
    .cmd0 = TMDS_CTRL_10,
    .cmd1 = TMDS_CTRL_00,
    .cmd2 = TMDS_CTRL_00,
};

const SYNC_V1_H1: SyncCmd = .{
    .cmd0 = TMDS_CTRL_11,
    .cmd1 = TMDS_CTRL_00,
    .cmd2 = TMDS_CTRL_00,
};

const letterbox_margin: ashet.video.Resolution = .{
    .width = @divExact(timings.horizontal.active_items - framebuffer_size.width, 2),
    .height = @divExact(timings.vertical.active_items - framebuffer_size.height, 2),
};

// ----------------------------------------------------------------------------
// HSTX command lists

// Lists are padded with NOPs to be >= HSTX FIFO size, to avoid DMA rapidly
// pingponging and tripping up the IRQs.

const HstxFifoItem = packed struct(u32) {
    raw: u32,

    pub fn cmd(id: HstxCmdId, len: u12) HstxFifoItem {
        return .{
            .raw = @as(u16, @bitCast(HstxCmd{ .cmd = id, .length = len })),
        };
    }

    pub fn value(val: u32) HstxFifoItem {
        return .{ .raw = val };
    }

    pub fn sync(val: SyncCmd) HstxFifoItem {
        return .{ .raw = @bitCast(val) };
    }
};

comptime {
    std.debug.assert(@bitSizeOf(HstxFifoItem) == 32);
}

const fifo_chunks = struct {
    const ImageLine = extern struct {
        comptime {
            // This code assumes that the emitted palette color is perfectly reinterpretable as an array of u32
            std.debug.assert(@mod(@sizeOf(Scanline), 4) == 0);

            std.debug.assert(@offsetOf(@This(), "prefix") == 0);
            std.debug.assert(std.mem.isAligned(@offsetOf(@This(), "data"), 8));
            std.debug.assert(std.mem.isAligned(@offsetOf(@This(), "suffix"), 4));
            std.debug.assert(@sizeOf(@This()) == @offsetOf(@This(), "suffix") + 8);
        }

        pub fn as_hstx_slice(line: *const ImageLine) *const [@divExact(@sizeOf(@This()), 4)]HstxFifoItem {
            return @ptrCast(line);
        }

        prefix: [10]HstxFifoItem = .{
            .cmd(.raw_repeat, timings.horizontal.front_porch),
            .sync(SYNC_V1_H1),
            .cmd(.raw_repeat, timings.horizontal.sync_width),
            .sync(SYNC_V1_H0),
            .cmd(.raw_repeat, timings.horizontal.back_porch),
            .sync(SYNC_V1_H1),
            .cmd(.nop, 0),
            .cmd(.tmds_repeat, letterbox_margin.width),
            .value(@bitCast(letterbox_color)),
            .cmd(.tmds, framebuffer_size.width),
        },
        data: Scanline = undefined,
        suffix: [2]HstxFifoItem = .{
            .cmd(.tmds_repeat, letterbox_margin.width),
            .value(@bitCast(letterbox_color)),
        },
    };

    const non_image_data linksection(dma_datax_section) = ([0]HstxFifoItem{} ++
        snippets.letterbox_line ** letterbox_margin.height ++
        snippets.vsync_off ** timings.vertical.front_porch ++
        snippets.vsync_on ** timings.vertical.sync_width ++
        snippets.vsync_off ** timings.vertical.back_porch ++
        snippets.letterbox_line ** letterbox_margin.height ++
        [0]HstxFifoItem{});

    var even_image_line: ImageLine align(16) linksection(dma_data1_section) = .{};

    var odd_image_line: ImageLine align(16) linksection(dma_data0_section) = .{};

    const snippets = struct {
        // A full horizontal line, with vsync off (front or back porch)
        const vsync_off linksection(".discard") = [_]HstxFifoItem{
            .cmd(.raw_repeat, timings.horizontal.front_porch),
            .sync(SYNC_V1_H1),
            .cmd(.raw_repeat, timings.horizontal.sync_width),
            .sync(SYNC_V1_H0),
            .cmd(.raw_repeat, timings.horizontal.back_porch + timings.horizontal.active_items),
            .sync(SYNC_V1_H1),
        };

        // A full horizontal line, with vsync on (sync pulse)
        const vsync_on linksection(".discard") = [_]HstxFifoItem{
            .cmd(.raw_repeat, timings.horizontal.front_porch),
            .sync(SYNC_V0_H1),
            .cmd(.raw_repeat, timings.horizontal.sync_width),
            .sync(SYNC_V0_H0),
            .cmd(.raw_repeat, timings.horizontal.back_porch + timings.horizontal.active_items),
            .sync(SYNC_V0_H1),
        };

        // a full horizontal line in the image, showing only the letterbox color
        const letterbox_line linksection(".discard") = [_]HstxFifoItem{
            .cmd(.raw_repeat, timings.horizontal.front_porch),
            .sync(SYNC_V1_H1),
            .cmd(.raw_repeat, timings.horizontal.sync_width),
            .sync(SYNC_V1_H0),
            .cmd(.raw_repeat, timings.horizontal.back_porch),
            .sync(SYNC_V1_H1),
            .cmd(.tmds_repeat, timings.horizontal.active_items),
            .value(@bitCast(letterbox_color)),
        };
    };
};

/// Computes the number of bits we have to right-rotate our field value
/// so we align our field MSB with the 7th bit of a 32 bit word.
///
/// Bits:   31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
/// RGB555:                                                     B  B  B  B  B  G  G  G  G  G  R  R  R  R  R
/// RGB888:                          B  B  B  B  B  B  B  B  G  G  G  G  G  G  G  G  R  R  R  R  R  R  R  R
/// Output:                                                                          x  x  x  x  x  -  -  -
///
/// This is really unintuitive and hard to grasp, so here's the math.
inline fn compute_tmds_rot(comptime fld: std.meta.FieldEnum(PaletteColor)) u5 {
    const FType = @FieldType(PaletteColor, @tagName(fld));
    const offset = @bitOffsetOf(PaletteColor, @tagName(fld));
    const bsize = @bitSizeOf(FType);

    // the bit position of our MSB
    const hbitpos = offset + bsize - 1;

    // the target bit position
    const tbitpos = 7;

    // compute the delta between our MSB and the target
    // in a way that it reflects the number of right shifts:
    const shift = hbitpos - tbitpos;

    // as we can only shift 0..31 bits, we're using @mod to compute
    // the number of shifts, as a -3 corresponds to a 29, and @mod will
    // take care of that:
    const encshift = @mod(shift, 32);

    // @compileLog(fld, hbitpos, tbitpos, shift, encshift);

    return encshift;
}

inline fn compute_tmds_nbits(comptime fld: std.meta.FieldEnum(PaletteColor)) u3 {
    return @bitSizeOf(@FieldType(PaletteColor, @tagName(fld))) - 1;
}
