const std = @import("std");
const ashet = @import("../../main.zig");
const sdl = @import("../../port/machine/linux_pc/SDL2.zig");
const logger = std.log.scoped(.host_sdl_output);

const Host_SDL_Output = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

renderer: *sdl.SDL_Renderer,
texture: *sdl.SDL_Texture,

backbuffer: []align(ashet.memory.page_size) ColorIndex,
width: u16,
height: u16,

palette: [256]Color = ashet.video.defaults.palette,

driver: Driver = .{
    .name = "Host SDL Screen",
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

pub fn init(renderer: *sdl.SDL_Renderer, texture: *sdl.SDL_Texture) !Host_SDL_Output {
    var c_width: c_int = 0;
    var c_height: c_int = 0;

    sdl.assert(sdl.SDL_QueryTexture(
        texture,
        null,
        null,
        &c_width,
        &c_height,
    ));
    const width: u16 = @intCast(c_width);
    const height: u16 = @intCast(c_height);

    const backbuffer = try std.heap.page_allocator.alignedAlloc(
        ColorIndex,
        ashet.memory.page_size,
        @as(u32, width) * @as(u32, height),
    );
    errdefer std.heap.page_allocator.free(backbuffer);

    return .{
        .width = width,
        .height = height,

        .renderer = renderer,
        .texture = texture,

        .backbuffer = backbuffer,
    };
}

fn getVideoMemory(driver: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);
    return vd.backbuffer;
}

fn getPaletteMemory(driver: *Driver) *[256]Color {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);
    return &vd.palette;
}

fn getResolution(driver: *Driver) Resolution {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);
    return Resolution{
        .width = vd.width,
        .height = vd.height,
    };
}

fn getMaxResolution(driver: *Driver) Resolution {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);
    return Resolution{
        .width = vd.width,
        .height = vd.height,
    };
}

fn setResolution(driver: *Driver, width: u15, height: u15) void {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);
    _ = vd;
    _ = width;
    _ = height;
    logger.warn("resize not supported of vnc screen!", .{});
}

fn setBorder(driver: *Driver, color: ColorIndex) void {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);
    _ = vd;
    _ = color;
}

fn getBorder(driver: *Driver) ColorIndex {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);
    _ = vd;
    return ColorIndex.get(0);
}

fn flush(driver: *Driver) void {
    const vd = @fieldParentPtr(Host_SDL_Output, "driver", driver);

    // Stream texture data:
    // logger.debug("stream data begin", .{});
    {
        var raw_pixel_ptr: ?*anyopaque = undefined;
        var raw_pixel_pitch: c_int = 0;
        sdl.assert(sdl.SDL_LockTexture(
            vd.texture,
            null,
            &raw_pixel_ptr,
            &raw_pixel_pitch,
        ));
        defer sdl.SDL_UnlockTexture(vd.texture);

        var src_pixel_ptr: [*]const ColorIndex = vd.backbuffer.ptr;
        const src_pixel_pitch: usize = vd.width;

        var dst_pixel_ptr: [*]u8 = @ptrCast(raw_pixel_ptr.?);
        const dst_pixel_pitch: usize = @intCast(raw_pixel_pitch);

        for (0..vd.height) |_| {
            const src_scanline: [*]const ColorIndex = src_pixel_ptr;
            const dst_scanline: [*]Color = @ptrCast(@alignCast(dst_pixel_ptr));

            for (src_scanline[0..vd.width], dst_scanline[0..vd.width]) |index, *color| {
                color.* = vd.palette[@intFromEnum(index)];
            }

            src_pixel_ptr += src_pixel_pitch;
            dst_pixel_ptr += dst_pixel_pitch;
        }
    }
    // logger.debug("stream data end", .{});

    sdl.assert(sdl.SDL_RenderCopy(
        vd.renderer,
        vd.texture,
        null,
        null,
    ));

    // logger.debug("present", .{});
    sdl.SDL_RenderPresent(vd.renderer);
    // logger.debug("render end", .{});
}
