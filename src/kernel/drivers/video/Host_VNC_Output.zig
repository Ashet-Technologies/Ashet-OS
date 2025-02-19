const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.virtual_screen);

const Host_VNC_Output = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

backbuffer_lock: std.Thread.Mutex = .{},

backbuffer: []Color,
frontbuffer: []align(ashet.memory.page_size) Color,
width: u16,
height: u16,

driver: Driver = .{
    .name = "Host VNC Screen",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .flush_fn = flush,
        },
    },
},

pub fn init(
    width: u16,
    height: u16,
) !Host_VNC_Output {
    const fb = try std.heap.page_allocator.alignedAlloc(
        Color,
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

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    return .{
        .stride = vd.width,
        .video_memory = vd.frontbuffer,
        .video_memory_mapping = .buffered,
        .resolution = .{
            .width = vd.width,
            .height = vd.height,
        },
    };
}

fn flush(driver: *Driver) void {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);

    // vd.backbuffer_lock.lock();
    // defer vd.backbuffer_lock.unlock();

    @memcpy(vd.backbuffer, vd.frontbuffer);
}
