const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ashet_fb);
const machine = ashet.machine.peripherals;

const Ashet_Framebuffer = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

pub const width = 640;
pub const height = 400;

driver: Driver = .{
    .name = "Ashet Framebuffer",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .begin_write_pixels_fn = begin_write_pixels,
        },
    },
},

framebuffer: *align(ashet.memory.page_size) volatile [256_000]u8,
control: *volatile machine.VideoControl,

pub fn init(
    control: *volatile machine.VideoControl,
    framebuffer: *align(ashet.memory.page_size) volatile [256_000]u8,
) Ashet_Framebuffer {
    framebuffer.* = @splat(ashet.video.defaults.border_color.to_u8());
    ashet.video.load_splash_screen(.{
        .base = @ptrCast(@volatileCast(framebuffer)),
        .width = 640,
        .height = 400,
        .stride = 640,
    });

    control.flush = 1;

    return .{
        .control = control,
        .framebuffer = framebuffer,
    };
}

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    const vd = driver.resolve(Ashet_Framebuffer, "driver");
    return .{
        .video_memory = @ptrCast(@volatileCast(vd.framebuffer)),
        .video_memory_mapping = .buffered,
        .stride = width,
        .resolution = .{
            .width = width,
            .height = height,
        },
    };
}

fn begin_write_pixels(
    driver: *Driver,
    call: *ashet.overlapped.AsyncCall,
    rectangle: ashet.abi.Rectangle,
    pixels: []const Color,
    stride: usize,
    mode: ashet.abi.video.PresentMode,
) void {
    const vd = driver.resolve(Ashet_Framebuffer, "driver");

    ashet.video.utils.copy_pixels(
        Color,
        .{
            .dst_buffer = .{
                .data = vd.framebuffer,
                .width = width,
                .height = height,
                .stride = width,
            },
            .dst_pos = .{
                .x = @intCast(rectangle.x),
                .y = @intCast(rectangle.y),
            },
            .src_buffer = .{
                .data = pixels.ptr,
                .width = rectangle.width,
                .height = rectangle.height,
                .stride = stride,
            },
        },
        null,
    );

    _ = mode;

    return call.finalize(ashet.abi.video.WritePixels, .{});
}
