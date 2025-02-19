const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.virtual_screen);

const Virtual_Video_Output = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

pub const width = 320;
pub const height = 240;

backbuffer: [width * height]Color align(ashet.memory.page_size) = undefined,

driver: Driver = .{
    .name = "Virtual Screen",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .flush_fn = flush,
        },
    },
},

pub fn init() Virtual_Video_Output {
    return .{};
}

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    return .{
        .video_memory = &vd.backbuffer,
        .video_memory_mapping = .unbuffered,
        .stride = width,
        .resolution = .{
            .width = width,
            .height = height,
        },
    };
}
fn flush(driver: *Driver) void {
    const vd = driver.resolve(Virtual_Video_Output, "driver");
    _ = vd;
}
