const std = @import("std");
const ashet = @import("../../main.zig");
const sdl2 = @import("../../port/machine/linux_pc/SDL2.zig");
const logger = std.log.scoped(.host_sdl_output);

const Host_SDL_Output = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

frontbuffer: *sdl2.SDL_Texture,
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

pub fn init(
    width: u16,
    height: u16,
) !Host_SDL_Output {
    const fb = try std.heap.page_allocator.alignedAlloc(
        ColorIndex,
        ashet.memory.page_size,
        @as(u32, width) * @as(u32, height),
    );
    errdefer std.heap.page_allocator.free(fb);

    return .{
        .width = width,
        .height = height,
        .backbuffer = fb[0 .. fb.len / 2],
        .frontbuffer = undefined,
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

    _ = vd;

    // TODO: Update texture from frontbuffer!
}
