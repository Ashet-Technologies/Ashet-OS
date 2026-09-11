const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.video);

pub const Color = ashet.abi.Color;
pub const OutputID = ashet.abi.video.VideoOutputID;
pub const Resolution = ashet.abi.Size;

const Rectangle = ashet.abi.Rectangle;
const PresentMode = ashet.abi.video.PresentMode;

pub const DeviceProperties = struct {
    /// The video resolution of the device.
    resolution: Resolution,

    /// Determines how buffer mappings work with the device.
    buffer_support: MappableBufferSupport,

    pub const MappableBufferSupport = enum {
        /// The device does not support memory-mappable buffers.
        none,

        /// The device only supports a front buffer, which keeps
        /// its address between swaps.
        front_stable,
    };
};

/// A raw device-backed video memory buffer.
pub const VideoMemory = struct {
    /// A pointer to the first pixel.
    ///
    /// The pixel layout is row-major. This means that we have a
    /// sequence of image lines, each line `width` elements long.
    ///
    /// Lines in the video memory are `stride` elements apart, so
    /// the index of a pixel is `stride * y + x`.
    base: [*]Color,

    /// The distance of two pixel rows in memory.
    /// This unit is provided in "number of `base` indices".
    ///
    /// NOTE: For the 8 bit color format we use, this is also
    ///       a byte offset.
    stride: usize,

    comptime {
        std.debug.assert(@sizeOf(Color) == 1);
    }
};

/// Determines the type of video memory buffer.
pub const BufferKind = enum {
    /// The front buffer is the memory area the
    /// scanout unit reads and displays.
    ///
    /// Changes to this buffer are immediately
    /// reflected
    front,

    ///
    back,
};

pub const VideoDevice = struct {
    get_properties_fn: *const fn (*ashet.drivers.Driver) DeviceProperties,
    get_one_vblank_event_fn: ?*const fn (*ashet.drivers.Driver) bool = null, // TODO(gpu_support): Go through all drivers and see which actually support this

    begin_write_pixels_fn: *const fn (
        driver: *ashet.drivers.Driver,
        call: *ashet.overlapped.AsyncCall,
        rectangle: Rectangle,
        pixels: []const Color,
        stride: usize,
        mode: PresentMode,
    ) void,

    create_mapped_buffer_fn: ?*const fn (
        driver: *ashet.drivers.Driver,
        buffer: BufferKind,
    ) error{ SystemResources, IoError, Unsupported }!void = unsupported_create_mapped_buffer,

    get_mapped_buffer_fn: ?*const fn (
        driver: *ashet.drivers.Driver,
        buffer: BufferKind,
    ) error{IoError}!VideoMemory = unsupported_get_mapped_buffer,

    fn get_properties(vd: *VideoDevice) DeviceProperties { // pub
        return vd.get_properties_fn(ashet.drivers.resolveDriver(.video, vd));
    }

    fn supports_vblank_event(vd: *VideoDevice) bool { // pub
        return vd.get_one_vblank_event_fn != null;
    }

    fn get_one_vblank_event(vd: *VideoDevice) bool { // pub
        if (vd.get_one_vblank_event_fn) |get_one_vblank_event_fn| {
            return get_one_vblank_event_fn(ashet.drivers.resolveDriver(.video, vd));
        } else {
            @panic("invalid API use");
        }
    }

    fn create_mapped_buffer( // pub
        vd: *VideoDevice,
        buffer: BufferKind,
    ) error{ SystemResources, IoError, Unsupported }!void {
        return vd.create_mapped_buffer_fn(ashet.drivers.resolveDriver(.video, vd), buffer);
    }

    fn get_mapped_buffer( // pub
        vd: *VideoDevice,
        buffer: BufferKind,
    ) error{IoError}!VideoMemory {
        return vd.create_mapped_buffer_fn(ashet.drivers.resolveDriver(.video, vd), buffer);
    }

    fn begin_write_pixels( // pub
        vd: *VideoDevice,
        call: *ashet.overlapped.AsyncCall,
        rectangle: Rectangle,
        pixels: []const Color,
        stride: usize,
        mode: PresentMode,
    ) void {
        vd.begin_write_pixels_fn(
            ashet.drivers.resolveDriver(.video, vd),
            call,
            rectangle,
            pixels,
            stride,
            mode,
        );
    }

    pub fn default_create_mapped_buffer_front(
        driver: *ashet.drivers.Driver,
        buffer: BufferKind,
    ) error{ SystemResources, IoError, Unsupported }!void {
        _ = driver;
        switch (buffer) {
            .front => {},
            .back => return error.Unsupported,
        }
    }

    pub fn default_create_mapped_buffer_back(
        driver: *ashet.drivers.Driver,
        buffer: BufferKind,
    ) error{ SystemResources, IoError, Unsupported }!void {
        _ = driver;
        switch (buffer) {
            .front => return error.Unsupported,
            .back => {},
        }
    }

    pub fn default_create_mapped_buffer_both(
        driver: *ashet.drivers.Driver,
        buffer: BufferKind,
    ) error{ SystemResources, IoError, Unsupported }!void {
        _ = driver;
        _ = buffer;
    }

    fn unsupported_create_mapped_buffer(
        driver: *ashet.drivers.Driver,
        buffer: BufferKind,
    ) error{ SystemResources, IoError, Unsupported }!void {
        _ = driver;
        _ = buffer;
        return error.Unsupported;
    }

    fn unsupported_get_mapped_buffer(
        driver: *ashet.drivers.Driver,
        buffer: BufferKind,
    ) error{IoError}!VideoMemory {
        _ = driver;
        _ = buffer;
        @panic("kernel bug: get_mapped_buffer_fn was not correctly set by the ");
    }
};

pub const Output = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _noop);

    system_resource: ashet.resources.SystemResource = .{ .type = .video_video_output },

    buffer_mappings: std.EnumArray(ashet.abi.video.BufferKind, ?*BufferMapping) = .initFill(null),

    supports_partial_update: bool = true, // TODO(gpu_support): Query this from the driver

    /// If true, the kernel will automatically flush the screen in a background process.
    auto_flush: bool = true, // TODO: Fix this
    flush_required: bool = false,
    video_driver: *ashet.drivers.VideoDevice,

    vsync_awaiters: ashet.overlapped.WorkQueue = .{
        .wakeup_thread = null,
    },

    fn _noop(_: *Output) void {}

    pub fn get_resolution(output: *const Output) Resolution {
        return output.video_driver.get_properties().resolution;
    }

    pub fn begin_write_pixels(output: *const Output, call: *ashet.overlapped.AsyncCall, destination: Rectangle, pixels: []const Color, stride: usize, mode: PresentMode) error{
        BufferSize,
        InvalidStride,
        InvalidRegion,
        InvalidOperation,
    }!void {
        const resolution = output.get_resolution();

        const screen_rect: Rectangle = .new(.zero, resolution);

        if (!screen_rect.containsRectangle(destination)) {
            // No updates allowed outside the screen boundaries
            return error.InvalidRegion;
        }

        if (!output.supports_partial_update and !destination.eql(screen_rect)) {
            // No partial updates allowed
            return error.InvalidOperation;
        }

        if (stride < destination.width) {
            // Check if each row contains at least the actual row length of pixels.
            return error.InvalidStride;
        }

        const expected_pixel_count = stride * @max(0, destination.height -| 1) + destination.width;
        if (pixels.len < expected_pixel_count) {
            // Check if the buffer is big enough to be written
            return error.BufferSize;
        }

        if (destination.width == 0 or destination.height == 0) {
            // Trivial case: Immediate completion when empty target.
            return call.finalize(ashet.abi.video.WritePixels, .{});
        }

        return output.video_driver.begin_write_pixels(
            call,
            destination,
            pixels,
            stride,
            mode,
        );
    }

    /// Notifies all overlapped events that wait for V-Blank on this output.
    pub fn notify_vblank_awaiters(output: *Output) void {
        while (output.vsync_awaiters.dequeue()) |tup| {
            const call, _ = tup;
            call.finalize(ashet.abi.video.WaitForVBlank, .{});
        }
    }
};

pub const BufferMapping = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _noop);

    system_resource: ashet.resources.SystemResource = .{ .type = .video_video_output },

    output: *Output,

    fn _noop(_: *BufferMapping) void {}

    /// The raw exposed video memory. Writing to this will change the content
    /// on the screen.
    /// Memory is interpreted with the current video mode to produce an image.
    pub fn get_video_memory(mapping: *const BufferMapping) ashet.abi.video.VideoMemory {
        _ = mapping;
        @panic("TODO: Implement get_video_memory"); // TODO(gpu_support): Implement get_video_memory
        // const props = mapping.output.video_driver.get_properties();

        // std.debug.assert(props.video_memory.len >= (props.stride * @as(usize, props.resolution.height)));

        // return .{
        //     .base = props.video_memory.ptr,
        //     .stride = props.stride,
        //     .width = props.resolution.width,
        //     .height = props.resolution.height,
        // };
    }
};

var video_outputs: []Output = &.{};

pub fn initialize() !void {
    const count: usize = blk: {
        var drivers = ashet.drivers.enumerate(.video);
        var count: usize = 0;
        while (drivers.next() != null) {
            count += 1;
        }
        break :blk count;
    };

    video_outputs = try ashet.memory.allocator.alloc(Output, count);
    {
        var drivers = ashet.drivers.enumerate(.video);
        var index: usize = 0;
        while (drivers.next()) |driver| : (index += 1) {
            video_outputs[index] = Output{
                .video_driver = driver,
            };

            const output = &video_outputs[index];

            logger.info("found video output {}: {f}", .{
                index,
                output.get_resolution(),
            });
        }
    }
}

///Ticks the video subsystem
pub fn tick() void {
    for (video_outputs) |*video_output| {
        // Go through all video outputs that support vertical blanking
        // notifications and complete the awaiters:
        if (!video_output.video_driver.supports_vblank_event())
            continue;

        if (video_output.video_driver.get_one_vblank_event()) {
            // video_output.force_flush();
            video_output.notify_vblank_awaiters();
        }
    }

    // TODO(gpu_support): How to implement non-vblanking video outputs with WaitForVSync?
}

pub fn enumerate(maybe_ids: ?[]OutputID) usize {
    if (maybe_ids) |ids| {
        const count = @min(ids.len, video_outputs.len);
        for (ids, 0..count) |*id, index| {
            id.* = @enumFromInt(@as(u8, @intCast(index)));
        }
    }
    return video_outputs.len;
}

pub fn acquire_output(output_id: OutputID) error{ InvalidId, OutputInUse }!*Output {
    const index = @intFromEnum(output_id);
    if (index >= video_outputs.len)
        return error.InvalidId;
    const output = &video_outputs[index];
    if (output.system_resource.owners.len > 0)
        return error.OutputInUse;
    return output;
}

pub fn wait_for_vblank_async(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.video.WaitForVBlank.Inputs) void {
    const output: *Output = ashet.resources.resolve(Output, call.resource_owner, inputs.output.as_resource()) catch {
        call.finalize(ashet.abi.video.WaitForVBlank, error.InvalidHandle);
        return;
    };
    output.vsync_awaiters.enqueue(call, null);
}

pub fn write_pixels_async(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.video.WritePixels.Inputs) void {
    const output: *Output = ashet.resources.resolve(Output, call.resource_owner, inputs.output.as_resource()) catch {
        return call.finalize(ashet.abi.video.WritePixels, error.InvalidHandle);
    };

    output.begin_write_pixels(
        call,
        inputs.destination,
        inputs.pixels_ptr[0..inputs.pixels_len],
        inputs.stride,
        inputs.mode,
    ) catch |err| {
        return call.finalize(ashet.abi.video.WritePixels, err);
    };
}

pub fn present_async(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.video.Present.Inputs) void {
    _ = call;
    _ = inputs;
    @panic("TODO: present_async!");
}

pub fn load_splash_screen(vmem: ashet.abi.video.VideoMemory) void {
    const splash = defaults.splash_screen;
    const clamp_w = @min(vmem.width, splash.width);
    const clamp_h = @min(vmem.height, splash.height);
    const offset_x = (vmem.width -| splash.width) / 2;
    const offset_y = (vmem.height -| splash.height) / 2;

    var src_row: [*]const Color = splash.base;
    var dst_row: [*]Color = vmem.base + vmem.stride * offset_y + offset_x;

    for (0..clamp_h) |_| {
        @memcpy(dst_row[0..clamp_w], src_row[0..clamp_w]);

        src_row += splash.stride;
        dst_row += vmem.stride;
    }
}

/// Contains initialization defaults for the system
pub const defaults = struct {
    /// The splash screen that should be shown until the operating system
    /// has fully bootet. This has to be displayed in 256x128 8bpp video mode.
    pub const splash_screen: ashet.abi.video.VideoMemory = .{
        .width = 256,
        .height = 128,
        .stride = 256,
        .base = @ptrCast(@alignCast(@constCast(@embedFile("splashscreen-256x128.raw")))),
    };

    /// The default border color if the screen is downscaled
    pub const border_color = splash_screen.base[0]; // just use the top-left pixel of the splash screen.
};

pub const utils = struct {
    pub fn PixelBuffer(comptime Pixel: type, mutability: enum { @"const", mut }) type {
        return struct {
            data: switch (mutability) {
                .@"const" => [*]const Pixel,
                .mut => [*]Pixel,
            },
            width: usize,
            height: usize,
            stride: usize,
        };
    }

    pub fn CopyPixelOptions(comptime DstPixel: type) type {
        return struct {
            dst_buffer: PixelBuffer(DstPixel, .mut),
            dst_pos: struct { x: usize, y: usize },

            src_buffer: PixelBuffer(Color, .@"const"),

            convert_ctx: ?*anyopaque = null,
        };
    }

    /// Copies a rectangular portion from src_buffer to dst_buffer,
    /// potentially converting the color data.
    pub fn copy_pixels(
        comptime DstPixel: type,
        options: CopyPixelOptions(DstPixel),
        comptime convert_fn: ?fn (?*anyopaque, Color) DstPixel,
    ) void {
        if (DstPixel != Color and convert_fn == null)
            @compileError("If copying to a non-native target, you have to provide a convert function");

        // Assert that we fit:
        std.debug.assert(options.dst_pos.x +| options.src_buffer.width <= options.dst_buffer.width);
        std.debug.assert(options.dst_pos.y +| options.src_buffer.height <= options.dst_buffer.height);

        var dst_iter: [*]DstPixel = options.dst_buffer.data + options.dst_pos.y * options.dst_buffer.stride + options.dst_pos.x;
        var src_iter: [*]const Color = options.src_buffer.data;

        for (0..options.src_buffer.height) |_| {
            const dst_row = dst_iter;
            const src_row = src_iter;

            for (0..options.src_buffer.width) |x| {
                const src = src_row[x];
                const dst = if (convert_fn) |convert|
                    convert(options.convert_ctx, src)
                else
                    src;
                dst_row[x] = dst;
            }

            dst_iter += options.dst_buffer.stride;
            src_iter += options.src_buffer.stride;
        }
    }
};
