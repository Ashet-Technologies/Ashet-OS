const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.vga);

const x86 = ashet.ports.platforms.x86;
const VGA = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

const modes = @import("x86/vga-mode-presets.zig");

backbuffer: [320 * 240]ColorIndex align(ashet.memory.page_size) = undefined,
palette: [256]Color = ashet.video.defaults.palette,

driver: Driver = .{
    .name = "VGA",
    .class = .{
        .video = .{
            .getVideoMemoryFn = getVideoMemory,
            .getPaletteMemoryFn = getPaletteMemory,
            .setBorderFn = setBorder,
            .flushFn = flush,
            .getResolutionFn = getResolution,
            .getMaxResolutionFn = getMaxResolution,
            .getBorderFn = getBorder,
            .setResolutionFn = setResolution,
        },
    },
},

const memory_ranges = [_]x86.vmm.Range{
    .{ .base = 0xA0000, .length = 0x20000 },
    // these are included in the range above:
    // .{.base = 0xA0000, .length = 0x10000 },
    // .{.base = 0xB0000, .length = 0x08000 },
    // .{.base = 0xB8000, .length = 0x08000 },
};

pub fn init(vga: *VGA) !void {
    for (memory_ranges) |range| {
        x86.vmm.update(range, .read_write);
    }

    vga.* = VGA{};

    writeVgaRegisters(modes.g_320x200x256);

    vga.loadPalette(vga.palette);
    @memset(@as([*]align(ashet.memory.page_size) ColorIndex, @ptrFromInt(0xA0000))[0 .. 320 * 240], ColorIndex.get(0));
}

fn getVideoMemory(driver: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    return &vd.backbuffer;
}
fn getPaletteMemory(driver: *Driver) *[256]Color {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    return &vd.palette;
}

fn getResolution(driver: *Driver) Resolution {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    _ = vd;

    return Resolution{
        .width = 320,
        .height = 240,
    };
}

fn getMaxResolution(driver: *Driver) Resolution {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    _ = vd;
    return Resolution{
        .width = 320,
        .height = 240,
    };
}

fn setResolution(driver: *Driver, width: u15, height: u15) void {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    _ = vd;
    _ = width;
    _ = height;
    logger.warn("resize not supported on plain VGA!", .{});
}

fn setBorder(driver: *Driver, color: ColorIndex) void {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    _ = vd;
    _ = color;
}

fn getBorder(driver: *Driver) ColorIndex {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    _ = vd;
    return ColorIndex.get(0);
}

fn flush(driver: *Driver) void {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));

    vd.loadPalette(vd.palette);

    const target = @as([*]align(ashet.memory.page_size) ColorIndex, @ptrFromInt(0xA0000))[0 .. 320 * 240];
    std.mem.copyForwards(ColorIndex, target, &vd.backbuffer);
}

fn writeVgaRegisters(regs: [61]u8) void {
    var index: usize = 0;
    var i: u8 = 0;

    // write MISCELLANEOUS reg
    x86.out(u8, VGA_MISC_WRITE, regs[index]);
    index += 1;

    // write SEQUENCER regs
    i = 0;
    while (i < VGA_NUM_SEQ_REGS) : (i += 1) {
        x86.out(u8, VGA_SEQ_INDEX, i);
        x86.out(u8, VGA_SEQ_DATA, regs[index]);
        index += 1;
    }

    // unlock CRTC registers
    x86.out(u8, VGA_CRTC_INDEX, 0x03);
    x86.out(u8, VGA_CRTC_DATA, x86.in(u8, VGA_CRTC_DATA) | 0x80);
    x86.out(u8, VGA_CRTC_INDEX, 0x11);
    x86.out(u8, VGA_CRTC_DATA, x86.in(u8, VGA_CRTC_DATA) & ~@as(u8, 0x80));

    // make sure they remain unlocked
    // TODO: Reinsert again
    // regs[0x03] |= 0x80;
    // regs[0x11] &= ~0x80;

    // write CRTC regs

    i = 0;
    while (i < VGA_NUM_CRTC_REGS) : (i += 1) {
        x86.out(u8, VGA_CRTC_INDEX, i);
        x86.out(u8, VGA_CRTC_DATA, regs[index]);
        index += 1;
    }
    // write GRAPHICS CONTROLLER regs
    i = 0;
    while (i < VGA_NUM_GC_REGS) : (i += 1) {
        x86.out(u8, VGA_GC_INDEX, i);
        x86.out(u8, VGA_GC_DATA, regs[index]);
        index += 1;
    }
    // write ATTRIBUTE CONTROLLER regs
    i = 0;
    while (i < VGA_NUM_AC_REGS) : (i += 1) {
        _ = x86.in(u8, VGA_INSTAT_READ);
        x86.out(u8, VGA_AC_INDEX, i);
        x86.out(u8, VGA_AC_WRITE, regs[index]);
        index += 1;
    }
    // lock 16-color palette and unblank display
    _ = x86.in(u8, VGA_INSTAT_READ);
    x86.out(u8, VGA_AC_INDEX, 0x20);
}

pub fn setPlane(plane: u2) void {
    const pmask: u8 = u8(1) << plane;

    // set read plane
    x86.out(u8, VGA_GC_INDEX, 4);
    x86.out(u8, VGA_GC_DATA, plane);
    // set write plane
    x86.out(u8, VGA_SEQ_INDEX, 2);
    x86.out(u8, VGA_SEQ_DATA, pmask);
}

fn getFramebufferSegment() [*]volatile u8 {
    x86.out(u8, VGA_GC_INDEX, 6);
    const seg = (x86.in(u8, VGA_GC_DATA) >> 2) & 3;
    return @as([*]volatile u8, @ptrFromInt(switch (@as(u2, @truncate(seg))) {
        0, 1 => @as(u32, 0xA0000),
        2 => @as(u32, 0xB0000),
        3 => @as(u32, 0xB8000),
    }));
}

const PALETTE_INDEX = 0x03c8;
const PALETTE_DATA = 0x03c9;

const RGB = packed struct {
    b: u8,
    g: u8,
    r: u8,
    x: u8,
};

// see: http://www.brackeen.com/vga/source/bc31/palette.c.html
fn loadPalette(vga: VGA, palette: [256]Color) void {
    _ = vga;

    x86.out(u8, PALETTE_INDEX, 0); // tell the VGA that palette data is coming.
    for (palette) |rgb| {

        // enhance RGB565 to RGB666
        x86.out(u8, PALETTE_DATA, (@as(u6, rgb.r) << 1) | (rgb.r >> 4));
        x86.out(u8, PALETTE_DATA, (@as(u6, rgb.g) << 0));
        x86.out(u8, PALETTE_DATA, (@as(u6, rgb.b) << 1) | (rgb.b >> 4));
    }
}

// pub fn setPaletteEntry(entry: u8, color: RGB) void {
//     io.out(u8, PALETTE_INDEX, entry); // tell the VGA that palette data is coming.
//     io.out(u8, PALETTE_DATA, color.r >> 2); // write the data
//     io.out(u8, PALETTE_DATA, color.g >> 2);
//     io.out(u8, PALETTE_DATA, color.b >> 2);
// }

// see: http://www.brackeen.com/vga/source/bc31/palette.c.html
pub fn waitForVSync() void {
    const INPUT_STATUS = 0x03da;
    const VRETRACE = 0x08;

    // wait until done with vertical retrace
    while ((x86.in(u8, INPUT_STATUS) & VRETRACE) != 0) {}
    // wait until done refreshing
    while ((x86.in(u8, INPUT_STATUS) & VRETRACE) == 0) {}
}

const VGA_AC_INDEX = 0x3C0;
const VGA_AC_WRITE = 0x3C0;
const VGA_AC_READ = 0x3C1;
const VGA_MISC_WRITE = 0x3C2;
const VGA_SEQ_INDEX = 0x3C4;
const VGA_SEQ_DATA = 0x3C5;
const VGA_DAC_READ_INDEX = 0x3C7;
const VGA_DAC_WRITE_INDEX = 0x3C8;
const VGA_DAC_DATA = 0x3C9;
const VGA_MISC_READ = 0x3CC;
const VGA_GC_INDEX = 0x3CE;
const VGA_GC_DATA = 0x3CF;
//            COLOR emulation        MONO emulation
const VGA_CRTC_INDEX = 0x3D4; // 0x3B4
const VGA_CRTC_DATA = 0x3D5; // 0x3B5
const VGA_INSTAT_READ = 0x3DA;

const VGA_NUM_SEQ_REGS = 5;
const VGA_NUM_CRTC_REGS = 25;
const VGA_NUM_GC_REGS = 9;
const VGA_NUM_AC_REGS = 21;
const VGA_NUM_REGS = (1 + VGA_NUM_SEQ_REGS + VGA_NUM_CRTC_REGS + VGA_NUM_GC_REGS + VGA_NUM_AC_REGS);

// pub fn setPixelDirect(x: usize, y: usize, c: Color) void {
//     switch (mode) {
//         .mode320x200 => {
//             // setPlane(@truncate(u2, 0));
//             var segment = getFramebufferSegment();
//             segment[320 * y + x] = c;
//         },

//         .mode640x480 => {
//             const wd_in_bytes = 640 / 8;
//             const off = wd_in_bytes * y + x / 8;
//             const px = @truncate(u3, x & 7);
//             var mask: u8 = u8(0x80) >> px;
//             var pmask: u8 = 1;

//             comptime var p: usize = 0;
//             inline while (p < 4) : (p += 1) {
//                 setPlane(@truncate(u2, p));
//                 var segment = getFramebufferSegment();
//                 const src = segment[off];
//                 segment[off] = if ((pmask & c) != 0) src | mask else src & ~mask;
//                 pmask <<= 1;
//             }
//         },
//     }
// }

// pub fn swapBuffers() void {
//     @setRuntimeSafety(false);
//     @setCold(false);

//     switch (mode) {
//         .mode320x200 => {
//             @intToPtr(*[height][width]Color, 0xA0000).* = backbuffer;
//         },
//         .mode640x480 => {

//             // const bytes_per_line = 640 / 8;
//             var plane: usize = 0;
//             while (plane < 4) : (plane += 1) {
//                 const plane_mask: u8 = u8(1) << @truncate(u3, plane);
//                 setPlane(@truncate(u2, plane));

//                 var segment = get_fb_seg();

//                 var offset: usize = 0;

//                 var y: usize = 0;
//                 while (y < 480) : (y += 1) {
//                     var x: usize = 0;
//                     while (x < 640) : (x += 8) {
//                         // const offset = bytes_per_line * y + (x / 8);
//                         var bits: u8 = 0;

//                         // unroll for maximum fastness
//                         comptime var px: usize = 0;
//                         inline while (px < 8) : (px += 1) {
//                             const mask = u8(0x80) >> px;
//                             const index = backbuffer[y][x + px];
//                             if ((index & plane_mask) != 0) {
//                                 bits |= mask;
//                             }
//                         }

//                         segment[offset] = bits;
//                         offset += 1;
//                     }
//                 }
//             }
//         },
//     }
// }
