const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.virtual_screen);

const Virtual_Video_Output = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

pub const width = 640;
pub const height = 400;

driver: Driver = .{
    .name = "Virtual Screen",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .begin_write_pixels_fn = driver_begin_write_pixels,
        },
    },
},
resolution: Resolution,

pub fn init(resolution: Resolution) Virtual_Video_Output {
    std.debug.assert(resolution.width > 0 and resolution.height > 0);
    return .{
        .resolution = resolution,
    };
}

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    // const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = driver;
    return .{
        .resolution = .{
            .width = width,
            .height = height,
        },
    };
}
fn driver_begin_write_pixels(
    driver: *Driver,
    call: *ashet.overlapped.AsyncCall,
    rectangle: ashet.abi.Rectangle,
    pixels: []const Color,
    stride: usize,
    mode: ashet.abi.video.PresentMode,
) void {
    _ = driver;
    _ = rectangle;
    _ = pixels;
    _ = stride;
    _ = mode;
    return call.finalize(ashet.abi.video.WritePixels, .{});
}
