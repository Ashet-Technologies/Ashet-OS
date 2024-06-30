const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.virtual_screen);

const Virtual_Video_Output = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

backbuffer: [320 * 240]ColorIndex align(ashet.memory.page_size) = undefined,
palette: [256]Color = ashet.video.defaults.palette,

driver: Driver = .{
    .name = "Virtual Screen",
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

pub fn init() Virtual_Video_Output {
    return .{};
}

fn getVideoMemory(driver: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    return &vd.backbuffer;
}
fn getPaletteMemory(driver: *Driver) *[256]Color {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    return &vd.palette;
}

fn getResolution(driver: *Driver) Resolution {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = vd;

    return Resolution{
        .width = 320,
        .height = 240,
    };
}

fn getMaxResolution(driver: *Driver) Resolution {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = vd;
    return Resolution{
        .width = 320,
        .height = 240,
    };
}

fn setResolution(driver: *Driver, width: u15, height: u15) void {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = vd;
    _ = width;
    _ = height;
    logger.warn("resize not supported of virtual screen!", .{});
}

fn setBorder(driver: *Driver, color: ColorIndex) void {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = vd;
    _ = color;
}

fn getBorder(driver: *Driver) ColorIndex {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = vd;
    return ColorIndex.get(0);
}

fn flush(driver: *Driver) void {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = vd;
}
