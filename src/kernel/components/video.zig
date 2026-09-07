const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.video);

pub const Color = ashet.abi.Color;
pub const OutputID = ashet.abi.video.VideoOutputID;
pub const Resolution = ashet.abi.Size;
pub const VideoMemory = ashet.abi.video.VideoMemory;

const Rectangle = ashet.abi.Rectangle;
const PresentMode = ashet.abi.video.PresentMode;

pub const Buffering = enum {
    buffered,
    unbuffered,
};

pub const DeviceProperties = struct {
    resolution: Resolution,
    stride: usize,

    video_memory_mapping: Buffering,
    video_memory: []align(ashet.memory.page_size) Color,
};

pub const VideoDevice = struct {
    flush_fn: *const fn (*ashet.drivers.Driver) void,
    get_properties_fn: *const fn (*ashet.drivers.Driver) DeviceProperties,
    get_one_vblank_event_fn: ?*const fn (*ashet.drivers.Driver) bool = null, // TODO: Go through all drivers and see which actually support this

    begin_write_pixels_fn: ?*const fn (
        driver: *ashet.drivers.Driver,
        call: *ashet.overlapped.AsyncCall,
        rectangle: Rectangle,
        pixels: []const Color,
        mode: PresentMode,
    ) void,

    pub fn flush(vd: *VideoDevice) void {
        vd.flush_fn(ashet.drivers.resolveDriver(.video, vd));
    }

    pub fn get_properties(vd: *VideoDevice) DeviceProperties {
        return vd.get_properties_fn(ashet.drivers.resolveDriver(.video, vd));
    }

    pub fn supports_vblank_event(vd: *VideoDevice) bool {
        return vd.get_one_vblank_event_fn != null;
    }

    pub fn get_one_vblank_event(vd: *VideoDevice) bool {
        if (vd.get_one_vblank_event_fn) |get_one_vblank_event_fn| {
            return get_one_vblank_event_fn(ashet.drivers.resolveDriver(.video, vd));
        } else {
            @panic("invalid API use");
        }
    }

    pub fn begin_write_pixels(
        vd: *VideoDevice,
        call: *ashet.overlapped.AsyncCall,
        rectangle: Rectangle,
        pixels: []const Color,
        mode: PresentMode,
    ) void {
        vd.begin_write_pixels_fn(
            ashet.drivers.resolveDriver(.video, vd),
            call,
            rectangle,
            pixels,
            mode,
        );
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

    /// Requests that the driver shall flip front- and back buffers in the next
    /// frame.
    ///
    /// NOTE: This is only a request, and might be called more often than necessary,
    ///       without impacting performance.
    pub fn flush(output: *Output) void {
        output.flush_required = true;
    }

    /// Potentially synchronizes the video storage with the screen.
    /// Without calling this, the screen might not be refreshed at all.
    ///
    /// NOTE: This function will forcefully flip the buffers and might cost
    ///       a good amount of time.
    pub fn force_flush(output: *Output) void {
        output.video_driver.flush();
        output.flush_required = false;
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
    pub fn get_video_memory(mapping: *const BufferMapping) VideoMemory {
        const props = mapping.output.video_driver.get_properties();

        std.debug.assert(props.video_memory.len >= (props.stride * @as(usize, props.resolution.height)));

        return .{
            .base = props.video_memory.ptr,
            .stride = props.stride,
            .width = props.resolution.width,
            .height = props.resolution.height,
        };
    }
};

const frame_rate = 1000 / 30; // 30 Hz

var video_outputs: []Output = &.{};
var video_flush_deadline = ashet.time.Deadline.init_abs(.system_start);

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
    video_flush_deadline = ashet.time.Deadline.init_rel(frame_rate);
}

fn flush_all() void {
    // Go through all video outputs that no support vertical blanking
    // notifications with a periodic interval and manually flush them:
    for (video_outputs) |*video_output| {
        if (video_output.video_driver.supports_vblank_event())
            continue;
        if (video_output.auto_flush or video_output.flush_required) {
            video_output.force_flush();
        }
        video_output.notify_vblank_awaiters();
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
            video_output.force_flush();
            video_output.notify_vblank_awaiters();
        }
    }

    if (video_flush_deadline.is_reached()) {
        video_flush_deadline.move_forward(frame_rate);
        flush_all();

        var drop_count: usize = 0;
        while (video_flush_deadline.is_reached()) {
            drop_count += 1;
            video_flush_deadline.move_forward(frame_rate);
        }
        if (drop_count > 0) {
            logger.warn("dropping {} video frames!", .{drop_count});
        }
    }
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

pub fn load_splash_screen(vmem: VideoMemory) void {
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
    pub const splash_screen: VideoMemory = .{
        .width = 256,
        .height = 128,
        .stride = 256,
        .base = @ptrCast(@alignCast(@constCast(@embedFile("splashscreen-256x128.raw")))),
    };

    /// The default border color if the screen is downscaled
    pub const border_color = splash_screen.base[0]; // just use the top-left pixel of the splash screen.
};
