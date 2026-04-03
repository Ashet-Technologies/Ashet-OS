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
            .flush_fn = flush,
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

fn flush(driver: *Driver) void {
    const vd = driver.resolve(Ashet_Framebuffer, "driver");

    vd.control.flush = 1;

    // TODO: wait for vblank?
}
