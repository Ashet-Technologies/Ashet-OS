const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.virtual_screen);

const Host_VNC_Output = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

backbuffer_lock: std.Thread.Mutex = .{},

backbuffer: []ColorIndex,
frontbuffer: []align(ashet.memory.page_size) ColorIndex,
width: u16,
height: u16,

palette: [256]Color = ashet.video.defaults.palette,

driver: Driver = .{
    .name = "Host VNC Screen",
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
) !Host_VNC_Output {
    const fb = try std.heap.page_allocator.alignedAlloc(
        ColorIndex,
        ashet.memory.page_size,
        2 * @as(u32, width) * @as(u32, height),
    );
    errdefer std.heap.page_allocator.free(fb);

    return .{
        .width = width,
        .height = height,
        .frontbuffer = fb[0 .. fb.len / 2],
        .backbuffer = fb[fb.len / 2 .. fb.len],
    };
}

fn getVideoMemory(driver: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    return vd.frontbuffer;
}

fn getPaletteMemory(driver: *Driver) *[256]Color {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    return &vd.palette;
}

fn getResolution(driver: *Driver) Resolution {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    return Resolution{
        .width = vd.width,
        .height = vd.height,
    };
}

fn getMaxResolution(driver: *Driver) Resolution {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    return Resolution{
        .width = vd.width,
        .height = vd.height,
    };
}

fn setResolution(driver: *Driver, width: u15, height: u15) void {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    _ = vd;
    _ = width;
    _ = height;
    logger.warn("resize not supported of vnc screen!", .{});
}

fn setBorder(driver: *Driver, color: ColorIndex) void {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    _ = vd;
    _ = color;
}

fn getBorder(driver: *Driver) ColorIndex {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    _ = vd;
    return ColorIndex.get(0);
}

fn flush(driver: *Driver) void {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);

    // vd.backbuffer_lock.lock();
    // defer vd.backbuffer_lock.unlock();

    @memcpy(vd.backbuffer, vd.frontbuffer);
}
