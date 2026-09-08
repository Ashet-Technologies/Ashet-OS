//!
//! This video driver is a thin layer inserted between another subsystem
//! and the kernel.
//!
//! Primarily intended for the "hosted" targets, this video output basically
//! converts a video output instance into a callback + parameter, allowing
//! generic use and embedding in other components.
//!
//! This driver implements an optional retaining native-color format framebuffer
//! which allows fullscreen conversion.
//!

const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.virtual_screen);

const Host_VNC_Output = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

pub const WritePixelsSyncFn = fn (
    context: ?*anyopaque,
    rectangle: ashet.abi.Rectangle,
    pixels: []const Color,
    stride: usize,
    mode: ashet.abi.video.PresentMode,
) void;

pub const BackingStorage = enum { allocate, virtual };

backbuffer_lock: std.Thread.Mutex = .{},

backbuffer: ?[]Color,
width: u16,
height: u16,

driver: Driver,

write_pixels_fn: *const WritePixelsSyncFn,
write_pixels_arg: ?*anyopaque,

pub fn init(
    comptime name: []const u8,
    width: u16,
    height: u16,
    comptime write_pixels_fn: WritePixelsSyncFn,
    write_pixels_arg: ?*anyopaque,
    comptime backing: BackingStorage,
) !Host_VNC_Output {
    const fb: ?[]Color = switch (backing) {
        .allocate => try std.heap.page_allocator.alloc(Color, @as(u32, width) * @as(u32, height)),
        .virtual => null,
    };
    errdefer @compileError("No errors beyond this point.");

    return .{
        .driver = comptime .{
            .name = name,
            .class = .{
                .video = .{
                    .get_properties_fn = get_properties,
                    .begin_write_pixels_fn = begin_write_pixels,
                },
            },
        },

        .width = width,
        .height = height,
        .backbuffer = fb,

        .write_pixels_fn = &write_pixels_fn,
        .write_pixels_arg = write_pixels_arg,
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

fn begin_write_pixels(
    driver: *Driver,
    call: *ashet.overlapped.AsyncCall,
    rectangle: ashet.abi.Rectangle,
    pixels: []const Color,
    stride: usize,
    mode: ashet.abi.video.PresentMode,
) void {
    const vd: *Host_VNC_Output = @fieldParentPtr("driver", driver);

    if (vd.backbuffer) |backbuffer| {
        ashet.video.utils.copy_pixels(
            Color,
            .{
                .dst_buffer = .{
                    .data = backbuffer.ptr,
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
    }

    vd.write_pixels_fn(
        vd.write_pixels_ctx,
        rectangle,
        pixels,
        stride,
        mode,
    );

    return call.finalize(ashet.abi.video.WritePixels, .{});
}
