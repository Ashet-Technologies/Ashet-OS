const std = @import("std");
const ashet = @import("root");
const logger = std.log.scoped(.vbe);

const x86 = ashet.platforms.all.x86;
const VESA_BIOS_Extension = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

const multiboot = x86.multiboot;
const vbe = @import("x86/vbe.zig");

driver: Driver = .{
    .name = "VESA Framebuffer",
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

vbe_control: *vbe.Control,
vbe_mode: *vbe.ModeInfo,

framebuffer: Framebuffer,

backing_buffer: []align(ashet.memory.page_size) ColorIndex,
backing_palette: [256]Color = ashet.video.defaults.palette,
border_color: ColorIndex = ashet.video.defaults.border,

graphics_resized: bool = true,
graphics_width: u16 = 256,
graphics_height: u16 = 128,

pub fn init(allocator: std.mem.Allocator, mbinfo: *multiboot.Info) !VESA_BIOS_Extension {
    if (!mbinfo.flags.vbe)
        return error.VBE_Unsupported;

    const vbe_info = mbinfo.vbe;

    const vbe_control = @intToPtr(*vbe.Control, vbe_info.control_info);

    if (vbe_control.signature != vbe.Control.signature)
        @panic("invalid vbe signature!");

    // std.log.info("vbe_control = {}", .{vbe_control});

    std.log.info("  oemstring = '{s}'", .{std.mem.sliceTo(vbe_control.oemstring.get(), 0)});
    std.log.info("  oem_vendor_name = '{s}'", .{std.mem.sliceTo(vbe_control.oem_vendor_name.get(), 0)});
    std.log.info("  oem_product_name = '{s}'", .{std.mem.sliceTo(vbe_control.oem_product_name.get(), 0)});
    std.log.info("  oem_product_rev = '{s}'", .{std.mem.sliceTo(vbe_control.oem_product_rev.get(), 0)});

    {
        std.log.info("  video modes:", .{});
        var modes = vbe_control.mode_ptr.get();
        while (modes[0] != 0xFFFF) {
            std.log.info("    - {X:0>4}", .{modes[0]});
            modes += 1;
        }
    }

    const vbe_mode = @intToPtr(*vbe.ModeInfo, vbe_info.mode_info);

    if (vbe_mode.memory_model != .direct_color) {
        std.log.err("mode_info = {}", .{vbe_mode});
        @panic("VBE mode wasn't properly initialized: invalid color mode");
    }
    if (vbe_mode.number_of_planes != 1) {
        std.log.err("mode_info = {}", .{vbe_mode});
        @panic("VBE mode wasn't properly initialized: more than 1 plane");
    }
    if (vbe_mode.bits_per_pixel != 32) {
        std.log.err("mode_info = {}", .{vbe_mode});
        @panic("VBE mode wasn't properly initialized: expected 32 bpp");
    }

    std.log.info("video resolution: {}x{}", .{ vbe_mode.x_resolution, vbe_mode.y_resolution });
    std.log.info("video memory:     {}K", .{64 * vbe_control.ram_size});

    const framebuffer_config = FramebufferConfig{
        .scanline0 = vbe_mode.phys_base_ptr,
        .width = vbe_mode.x_resolution,
        .height = vbe_mode.y_resolution,

        .bits_per_pixel = vbe_mode.bits_per_pixel,
        .bytes_per_scan_line = vbe_mode.lin_bytes_per_scan_line,

        .red_mask_size = vbe_mode.lin_red_mask_size,
        .green_mask_size = vbe_mode.lin_green_mask_size,
        .blue_mask_size = vbe_mode.lin_blue_mask_size,

        .red_shift = vbe_mode.lin_red_field_position,
        .green_shift = vbe_mode.lin_green_field_position,
        .blue_shift = vbe_mode.lin_blue_field_position,
    };

    const framebuffer = try framebuffer_config.instantiate();

    const vmem = try allocator.alignedAlloc(ColorIndex, ashet.memory.page_size, std.math.max(ashet.video.defaults.splash_screen.len, framebuffer.stride * framebuffer.height));
    errdefer allocator.free(vmem);

    std.mem.copyForwards(ColorIndex, vmem, &ashet.video.defaults.splash_screen);

    return VESA_BIOS_Extension{
        .framebuffer = framebuffer,
        .vbe_control = vbe_control,
        .vbe_mode = vbe_mode,

        .backing_buffer = vmem,
    };
}

fn getVideoMemory(driver: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);
    return vd.backing_buffer;
}

fn getPaletteMemory(driver: *Driver) *[256]Color {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);
    return &vd.backing_palette;
}

fn getResolution(driver: *Driver) Resolution {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);
    return Resolution{
        .width = vd.graphics_width,
        .height = vd.graphics_height,
    };
}

fn getMaxResolution(driver: *Driver) Resolution {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);
    return Resolution{
        .width = @intCast(u16, vd.framebuffer.width),
        .height = @intCast(u16, vd.framebuffer.height),
    };
}

fn setResolution(driver: *Driver, width: u15, height: u15) void {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);
    vd.graphics_width = std.math.min(vd.framebuffer.width, width);
    vd.graphics_height = std.math.min(vd.framebuffer.height, height);
    vd.graphics_resized = true;
}

fn setBorder(driver: *Driver, color: ColorIndex) void {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);
    vd.border_color = color;
    vd.graphics_resized = true;
}

fn getBorder(driver: *Driver) ColorIndex {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);
    return vd.border_color;
}

fn flush(driver: *Driver) void {
    const vd = @fieldParentPtr(VESA_BIOS_Extension, "driver", driver);

    @setRuntimeSafety(false);
    // const flush_time_start = readHwCounter();

    const dx = (vd.framebuffer.width - vd.graphics_width) / 2;
    const dy = (vd.framebuffer.height - vd.graphics_height) / 2;

    // TODO: Implement border painting
    // if (vd.graphics_resized) {
    //     vd.graphics_resized = false;

    //     const border_value = vd.pal(vd.border_color);

    //     const limit = vd.framebuffer.stride * vd.framebuffer.height;

    //     var row_addr = @ptrCast([*]u32, @alignCast(@alignOf(u32), vd.framebuffer.base));

    //     @memset( row_addr[0 .. vd.framebuffer.stride * dy], border_value);
    //     @memset( row_addr[vd.framebuffer.stride * (dy + vd.graphics_height) .. limit], border_value);

    //     var y: usize = 0;
    //     row_addr += vd.framebuffer.stride * dy;
    //     while (y < vd.graphics_height) : (y += 1) {
    //         @memset( row_addr[0..dx], border_value);
    //         @memset( row_addr[dx + vd.graphics_width .. vd.framebuffer.width], border_value);
    //         row_addr += vd.framebuffer.stride;
    //     }
    // }

    const pixel_count = @as(usize, vd.graphics_width) * @as(usize, vd.graphics_height);

    {
        var row = vd.framebuffer.base + vd.framebuffer.stride * dy + dx;
        var ind: usize = 0;

        var x: usize = 0;
        for (vd.backing_buffer[0..pixel_count]) |color| {
            vd.framebuffer.writeFn(row + ind, vd.pal(color));

            x += 1;
            ind += vd.framebuffer.byte_per_pixel;

            if (x == vd.graphics_width) {
                x = 0;
                ind = 0;
                row += vd.framebuffer.stride;
            }
        }
    }

    // const flush_time_end = readHwCounter();
    // const flush_time = flush_time_end -| flush_time_start;

    // flush_limit += flush_time;
    // flush_count += 1;

    // logger.debug("frame flush time: {} cycles, avg {} cycles", .{ flush_time, flush_limit / flush_count });
}

inline fn pal(vd: *VESA_BIOS_Extension, color: ColorIndex) RGB {
    @setRuntimeSafety(false);
    return @bitCast(RGB, vd.backing_palette[color.index()].toRgb32());
}

const FramebufferConfig = struct {
    scanline0: [*]u8,
    width: u32,
    height: u32,

    bits_per_pixel: u32,
    bytes_per_scan_line: u32,

    red_mask_size: u32,
    green_mask_size: u32,
    blue_mask_size: u32,

    red_shift: u32,
    green_shift: u32,
    blue_shift: u32,

    pub fn instantiate(cfg: FramebufferConfig) error{Unsupported}!Framebuffer {
        errdefer logger.warn("unsupported framebuffer configuration: {}", .{cfg});

        // special case for
        if (cfg.red_mask_size == 0 and
            cfg.green_mask_size == 0 and
            cfg.blue_mask_size == 0 and
            cfg.red_shift == 0 and
            cfg.green_shift == 0 and
            cfg.blue_shift == 0 and
            cfg.bytes_per_scan_line == 0 and
            cfg.bits_per_pixel == 32)
        {
            // Assume the following device:
            // oemstring = 'S3 Incorporated. Twister BIOS'
            // oem_vendor_name = 'S3 Incorporated.'
            // oem_product_name = 'VBE 2.0'
            // oem_product_rev = 'Rev 1.1'

            return Framebuffer{
                .writeFn = buildSpecializedWriteFunc8(u32, 16, 8, 0), // RGBX32

                .base = cfg.scanline0,

                .stride = 4 * cfg.width,
                .width = cfg.width,
                .height = cfg.height,

                .byte_per_pixel = @divExact(cfg.bits_per_pixel, 8),
            };
        }

        const channel_depth_8bit = (cfg.red_mask_size == 8 and cfg.green_mask_size == 8 and cfg.blue_mask_size == 8);
        if (!channel_depth_8bit)
            return error.Unsupported;

        const write_ptr = switch (cfg.bits_per_pixel) {
            32 => if (cfg.red_shift == 0 and cfg.green_shift == 8 and cfg.blue_shift == 16)
                buildSpecializedWriteFunc8(u32, 0, 8, 16) // XBGR32
            else if (cfg.red_shift == 16 and cfg.green_shift == 8 and cfg.blue_shift == 0)
                buildSpecializedWriteFunc8(u32, 16, 8, 0) // XRGB32
            else if (cfg.red_shift == 8 and cfg.green_shift == 16 and cfg.blue_shift == 24)
                buildSpecializedWriteFunc8(u32, 8, 16, 24) // BGRX32
            else if (cfg.red_shift == 24 and cfg.green_shift == 16 and cfg.blue_shift == 8)
                buildSpecializedWriteFunc8(u32, 24, 16, 8) // RGBX32
            else
                return error.Unsupported,

            24 => if (cfg.red_shift == 0 and cfg.green_shift == 8 and cfg.blue_shift == 16)
                buildSpecializedWriteFunc8(u24, 0, 8, 16) // BGR24
            else if (cfg.red_shift == 16 and cfg.green_shift == 8 and cfg.blue_shift == 0)
                buildSpecializedWriteFunc8(u24, 16, 8, 0) // RGB24
            else
                return error.Unsupported,

            // 16 => if (cfg.red_shift == 0 and cfg.green_shift == 5 and cfg.blue_shift == 11)
            //     buildSpecializedWriteFunc32(u16, 0, 5, 11) // RGB565
            // else if (cfg.red_shift == 11 and cfg.green_shift == 5 and cfg.blue_shift == 0)
            //     buildSpecializedWriteFunc32(u16, 11, 5, 0) // BGR565
            // else
            //     return error.Unsupported,

            else => return error.Unsupported,
        };

        return Framebuffer{
            .writeFn = write_ptr,

            .base = cfg.scanline0,

            .stride = cfg.bytes_per_scan_line,
            .width = cfg.width,
            .height = cfg.height,

            .byte_per_pixel = @divExact(cfg.bits_per_pixel, 8),
        };
    }

    pub fn buildSpecializedWriteFunc8(comptime Pixel: type, comptime rshift: u32, comptime gshift: u32, comptime bshift: u32) *const Framebuffer.WriteFn {
        return struct {
            fn write(ptr: [*]u8, rgb: RGB) void {
                @setRuntimeSafety(false);
                const color: Pixel = (@as(Pixel, rgb.r) << rshift) |
                    (@as(Pixel, rgb.g) << gshift) |
                    (@as(Pixel, rgb.b) << bshift);
                std.mem.writeIntLittle(Pixel, ptr[0 .. (@typeInfo(Pixel).Int.bits + 7) / 8], color);
            }
        }.write;
    }
};

const RGB = packed struct {
    r: u8,
    g: u8,
    b: u8,
    x: u8,
};

const Framebuffer = struct {
    const WriteFn = fn (ptr: [*]u8, color: RGB) void;

    writeFn: *const WriteFn,
    base: [*]u8,
    stride: usize,
    width: u32,
    height: u32,
    byte_per_pixel: u32,
};

// var offset: u8 = 0;
// while (true) {
//     std.log.info("frame: {}", .{offset});

//     {
//         @setRuntimeSafety(false);
//         var y: usize = 0;
//         var row = framebuffer.base;
//         while (y < framebuffer.height) : (y += 1) {
//             var column = row;
//             var x: usize = 0;
//             while (x < framebuffer.width) : (x += 1) {
//                 var r: u8 = @truncate(u8, x);
//                 var g: u8 = @truncate(u8, y);
//                 var b: u8 = r ^ g;

//                 if (r == offset or g == offset) {
//                     r = 0;
//                     g = 255;
//                     b = 0;
//                 }

//                 framebuffer.writeFn(column, r, g, b);

//                 column += framebuffer.byte_per_pixel;
//             }

//             row += framebuffer.stride;
//         }
//     }

//     offset +%= 1;
// }
