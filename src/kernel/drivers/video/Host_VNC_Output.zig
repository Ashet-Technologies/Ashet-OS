const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.virtual_screen);

const Host_VNC_Output = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

const VNC_Server = @import("../../port/hosted/VNC_Server.zig");

backbuffer_lock: std.Thread.Mutex = .{},

backbuffer: []Color,
width: u16,
height: u16,

driver: Driver = .{
    .name = "Host VNC Screen",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .begin_write_pixels_fn = begin_write_pixels,
        },
    },
},

pub fn init(
    width: u16,
    height: u16,
) !Host_VNC_Output {
    const fb = try std.heap.page_allocator.alloc(Color, @as(u32, width) * @as(u32, height));
    errdefer std.heap.page_allocator.free(fb);

    return .{
        .width = width,
        .height = height,
        .backbuffer = fb,
    };
}

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);
    return .{
        .resolution = .{
            .width = vd.width,
            .height = vd.height,
        },
    };
}

fn vnc_server(output: *Host_VNC_Output) *VNC_Server {
    return @fieldParentPtr("screen", output);
}

fn begin_write_pixels(
    driver: *Driver,
    call: *ashet.overlapped.AsyncCall,
    rectangle: ashet.abi.Rectangle,
    pixels: []const Color,
    stride: usize,
    mode: ashet.abi.video.PresentMode,
) void {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);

    ashet.video.utils.copy_pixels(
        Color,
        .{
            .dst_buffer = .{
                .data = vd.backbuffer.ptr,
                .width = vd.width,
                .height = vd.height,
                .stride = vd.width,
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

    switch (mode) {
        .dont_care => {},
        .immediate, .vblank => vd.vnc_server().notify_flush(),
    }

    return call.finalize(ashet.abi.video.WritePixels, .{});
}
