const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"virtio-gpu");
const virtio = @import("virtio");

const Virtio_GPU_Device = @This();
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;
const Driver = ashet.drivers.Driver;

const max_width = 800;
const max_height = 600;

backing_buffer: [max_width * max_height]Color align(ashet.memory.page_size) = undefined,

gpu: GPU,

graphics_resized: bool = true,
graphics_width: u16 = 256,
graphics_height: u16 = 128,

driver: Driver = .{
    .name = "Virtio GPU Device",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .flush_fn = flush,
        },
    },
},

pub fn init(allocator: std.mem.Allocator, index: usize, regs: *volatile virtio.ControlRegs) !*Virtio_GPU_Device {
    _ = index;
    const vd = try allocator.create(Virtio_GPU_Device);
    errdefer allocator.destroy(vd);

    vd.* = Virtio_GPU_Device{
        .gpu = undefined,
    };

    try vd.gpu.initialize(allocator, regs);

    vd.graphics_width = @intCast(@min(std.math.maxInt(u16), vd.gpu.fb_width));
    vd.graphics_height = @intCast(@min(std.math.maxInt(u16), vd.gpu.fb_height));

    @memset(&vd.backing_buffer, ashet.video.defaults.border_color);

    ashet.video.load_splash_screen(.{
        .base = &vd.backing_buffer,
        .width = vd.graphics_width,
        .height = vd.graphics_height,
        .stride = vd.graphics_width,
    });

    vd.driver.class.video.flush();

    return vd;
}

inline fn pal(vd: *Virtio_GPU_Device, color: Color) u32 {
    _ = vd;
    @setRuntimeSafety(false);
    return color.to_rgb32();
}

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    const vd: *Virtio_GPU_Device = @alignCast(@fieldParentPtr("driver", driver));
    return .{
        .resolution = .{
            .width = vd.graphics_width,
            .height = vd.graphics_height,
        },
        .stride = vd.graphics_width,
        .video_memory = &vd.backing_buffer,
        .video_memory_mapping = .buffered,
    };
}

// var flush_limit: u64 = 0;
// var flush_count: u64 = 0;

/// baseline,Debug:  debug(platform-virt): frame flush time: 132914953 cycles, avg 158259348 cycles
/// inline,Debug:    debug(platform-virt): frame flush time: 119970714 cycles, avg 102176562 cycles
/// noclear,Debug:   debug(platform-virt): frame flush time:  50613156 cycles, avg  56891973 cycles
/// opticlear,Debug: debug(platform-virt): frame flush time:  48036765 cycles, avg  53044756 cycles
/// correct,Debug:   debug(platform-virt): frame flush time:  50813279 cycles, avg  51812661 cycles
/// no_mul,Debug:    debug(platform-virt): frame flush time:  38071785 cycles, avg  41297847 cycles
/// no_runsaf,Debug: debug(platform-virt): frame flush time:  36532901 cycles, avg  41069180 cycles
/// no safety,Debug: debug(platform-virt): frame flush time:  35441413 cycles, avg  35434932 cycles
fn flush(driver: *Driver) void {
    const vd: *Virtio_GPU_Device = @alignCast(@fieldParentPtr("driver", driver));

    @setRuntimeSafety(false);
    // const flush_time_start = readHwCounter();

    const dx = (vd.gpu.fb_width - vd.graphics_width) / 2;
    const dy = (vd.gpu.fb_height - vd.graphics_height) / 2;

    if (vd.graphics_resized) {
        vd.graphics_resized = false;

        const border_value = vd.pal(ashet.video.defaults.border_color);

        const limit = vd.gpu.fb_width * vd.gpu.fb_height;

        var row_addr = vd.gpu.fb_mem.ptr;

        @memset(row_addr[0 .. vd.gpu.fb_width * dy], border_value);
        @memset(row_addr[vd.gpu.fb_width * (dy + vd.graphics_height) .. limit], border_value);

        var y: usize = 0;
        row_addr += vd.gpu.fb_width * dy;
        while (y < vd.graphics_height) : (y += 1) {
            @memset(row_addr[0..dx], border_value);
            @memset(row_addr[dx + vd.graphics_width .. vd.gpu.fb_width], border_value);
            row_addr += vd.gpu.fb_width;
        }
    }

    const pixel_count = @as(usize, vd.graphics_width) * @as(usize, vd.graphics_height);

    {
        var row = vd.gpu.fb_mem.ptr + vd.gpu.fb_width * dy + dx;
        var ind: usize = 0;

        var x: usize = 0;
        var y: usize = 0;

        for (vd.backing_buffer[0..pixel_count]) |color| {
            row[ind] = vd.pal(color);
            ind += 1;

            x += 1;
            if (x == vd.graphics_width) {
                x = 0;
                ind = 0;
                row += vd.gpu.fb_width;
                y += 1;
            }
        }
    }

    vd.gpu.flushFramebuffer(0, 0, 0, 0);

    // const flush_time_end = readHwCounter();
    // const flush_time = flush_time_end -| flush_time_start;

    // flush_limit += flush_time;
    // flush_count += 1;

    // logger.debug("frame flush time: {} cycles, avg {} cycles", .{ flush_time, flush_limit / flush_count });
}

const GPU = struct {

    // // Chosen by virtio-gpu
    const CURSOR_W = 64;
    const CURSOR_H = 64;

    fb_width: u32 = 0,
    fb_height: u32 = 0,
    fb_mem: []u32 = undefined,

    vq: virtio.queue.VirtQ(4) = undefined,
    // cursor_vq: virtio.queue.VirtQ(4) = undefined;

    gpu_command: virtio.gpu.GPUCommand align(16) = undefined,
    gpu_command2: virtio.gpu.GPUCommand align(16) = undefined,
    gpu_response: virtio.gpu.Response align(16) = undefined,

    // cursor_commands: [cursor_vq.size]virtio.gpu.CursorCommand align(16) = undefined,

    const Scanout = enum(u32) { first = 0, _ };
    const ResourceId = enum(u32) { invalid = 0, framebuffer = 1, cursor = 2, _ };

    fn initialize(gpu: *GPU, allocator: std.mem.Allocator, regs: *volatile virtio.ControlRegs) !void {
        logger.info("initializing gpu {*}", .{regs});

        _ = try regs.negotiateFeatures(.default);

        const num_scanouts = &regs.device.gpu.num_scanouts;
        if (num_scanouts.* < 1) {
            logger.err("gpu does not provide any scanouts!", .{});
            return;
        }

        try gpu.vq.init(0, regs);
        // try cursor_vq.init(1, regs);

        regs.status |= virtio.DeviceStatus.driver_ok;

        //     for (int i = 0; i < QUEUE_SIZE; i++) {
        //         vq_push_descriptor(&cursor_vq, &cursor_commands[i],
        //                            sizeof(struct VirtIOGPUCursorCommand),
        //                            false, true, true);
        //     }
        //     // Those descriptors are not full, so reset avail_i
        //     cursor_vq.avail_i = 0;

        const di = (try gpu.getDisplayInfo()) orelse {
            logger.err("failed to query gpu display info!", .{});
            return;
        };

        for (di.pmodes[0..num_scanouts.*], 0..) |mode, i| {
            logger.info("Scanout({}{s}): {}x{}:{}x{}", .{
                i,            "",
                mode.r.x,     mode.r.y,
                mode.r.width, mode.r.height,
            });
        }

        const width = di.pmodes[0].r.width;
        const height = di.pmodes[0].r.height;

        logger.info("detected framebuffer size: {}x{}", .{ width, height });

        gpu.fb_mem = gpu.setupFramebuffer(allocator, Scanout.first, ResourceId.framebuffer, width, height) catch |err| {
            logger.err("failed to setup framebuffer: {s}", .{@errorName(err)});
            return;
        };
        errdefer allocator.free(gpu.fb_mem);

        gpu.fb_width = width;
        gpu.fb_height = height;

        logger.info("gpu ready with {}x{} @ {*}", .{ gpu.fb_width, gpu.fb_height, gpu.fb_mem });
    }

    fn showTestPattern(gpu: *GPU) void {
        for (gpu.fb_mem, 0..) |*item, i| {
            const x = i % gpu.fb_width;
            const y = i / gpu.fb_width;

            const color = (x / 32 + y / 32) % 3;

            const lut = [3]u32{
                0x000000FF,
                0x0000FF00,
                0x00FF0000,
            };

            const white = ((x % 32) < 16) != ((y % 32) < 16);

            item.* = if (white) lut[color] else 0x0000_0000;
        }

        try flushFramebuffer(0, 0, 0, 0);
    }

    // static bool need_cursor_updates(void)
    // {
    //     return !platform_funcs.has_absolute_pointing_device ||
    //         !platform_funcs.has_absolute_pointing_device();
    // }

    fn execCommand(gpu: *GPU) !void {
        gpu.vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu.gpu_command, .read, true, false);
        gpu.vq.pushDescriptor(virtio.gpu.Response, &gpu.gpu_response, .write, false, true);
        gpu.vq.exec();
        _ = gpu.vq.waitUsed();

        const ok = gpu.gpu_response.hdr.type >= virtio.gpu.resp.ok_nodata and
            gpu.gpu_response.hdr.type < virtio.gpu.resp.err_unspec;

        if (!ok) return switch (gpu.gpu_response.hdr.type) {
            virtio.gpu.resp.err_unspec => error.Unspecified,
            virtio.gpu.resp.err_out_of_memory => error.OutOfMemory,
            virtio.gpu.resp.err_invalid_scanout_id => error.InvalidScanoutId,
            virtio.gpu.resp.err_invalid_resource_id => error.InvalidResourceId,
            virtio.gpu.resp.err_invalid_context_id => error.InvalidContextId,
            virtio.gpu.resp.err_invalid_parameter => error.InvalidParameter,
            else => return error.Unknown,
        };
    }

    fn getDisplayInfo(gpu: *GPU) !?*virtio.gpu.DisplayInfo {
        gpu.vq.waitSettled();
        gpu.gpu_command.hdr.type = virtio.gpu.cmd.get_display_info;
        try gpu.execCommand();
        if (gpu.gpu_response.hdr.type != virtio.gpu.resp.ok_display_info) {
            return null;
        }
        return &gpu.gpu_response.display_info;
    }

    fn create2dResource(gpu: *GPU, id: ResourceId, format: virtio.gpu.Format, width: u32, height: u32) !void {
        gpu.vq.waitSettled();

        gpu.gpu_command.res_create_2d = .{
            .resource_id = @intFromEnum(id),
            .format = format,
            .width = width,
            .height = height,
        };

        try gpu.execCommand();
    }

    fn resourceAttachBacking(gpu: *GPU, id: ResourceId, memory: []const u8) !void {
        gpu.vq.waitSettled();

        gpu.gpu_command.res_attach_backing = .{
            .resource_id = @intFromEnum(id),
            .nr_entries = 1,
        };

        gpu.gpu_command.res_attach_backing.entries()[0] = .{
            .addr = @intFromPtr(memory.ptr),
            .length = memory.len,
        };

        try gpu.execCommand();
    }

    fn setScanout(gpu: *GPU, scanout: Scanout, res_id: ResourceId, width: u32, height: u32) !void {
        gpu.vq.waitSettled();
        gpu.gpu_command.set_scanout = .{
            .r = .{
                .x = 0,
                .y = 0,
                .width = width,
                .height = height,
            },
            .scanout_id = @intFromEnum(scanout),
            .resource_id = @intFromEnum(res_id),
        };
        try gpu.execCommand();
    }

    fn calcStrideBytes(width: u32, bpp: u32) usize {
        return ((width * bpp + 31) / 32) * @sizeOf(u32);
    }

    fn setupFramebuffer(gpu: *GPU, allocator: std.mem.Allocator, scanout: Scanout, res_id: ResourceId, width: u32, height: u32) ![]u32 {
        try gpu.create2dResource(res_id, virtio.gpu.Format.r8g8b8x8_unorm, width, height);

        const stride = @divExact(calcStrideBytes(width, 32), @sizeOf(u32));

        const frame_backing = try allocator.alignedAlloc(u32, @alignOf(u32), height * stride);
        errdefer allocator.free(frame_backing);

        try gpu.resourceAttachBacking(res_id, std.mem.sliceAsBytes(frame_backing));

        try gpu.setScanout(scanout, res_id, width, height);

        return frame_backing;
    }

    fn flushFramebuffer(gpu: *GPU, x: u32, y: u32, req_width: u32, req_height: u32) void {
        const width = if (req_width <= 0) gpu.fb_width else req_width;
        const height = if (req_height <= 0) gpu.fb_height else req_height;

        gpu.vq.waitSettled();

        gpu.gpu_command.transfer_to_host_2d = .{
            .r = .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            },
            .offset = y * calcStrideBytes(gpu.fb_width, 32) + x * 4,
            .resource_id = @intFromEnum(ResourceId.framebuffer),
        };

        gpu.gpu_command2.res_flush = .{
            .r = .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            },
            .resource_id = @intFromEnum(ResourceId.framebuffer),
        };

        gpu.vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu.gpu_command, .read, true, false);
        gpu.vq.pushDescriptor(virtio.gpu.Response, &gpu.gpu_response, .write, false, true);

        gpu.vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu.gpu_command2, .read, true, false);

        // We don't care about the result anyway, might as well just
        // overwrite the previous one
        gpu.vq.pushDescriptor(virtio.gpu.Response, &gpu.gpu_response, .write, false, true);

        gpu.vq.exec();
    }

    // static bool setup_cursor(uint32_t *data, int width, int height,
    //                          int hot_x, int hot_y)
    // {
    //     static bool already_defined;
    //     if (already_defined) {
    //         return false;
    //     }
    //     already_defined = true;

    //     if (width > CURSOR_W || height > CURSOR_H) {
    //         return false;
    //     }

    //     if (!create_2d_resource(RESOURCE_CURSOR, VIRTIO_GPU_FORMAT_B8G8R8A8_UNORM,
    //                             CURSOR_W, CURSOR_H))
    //     {
    //         return false;
    //     }

    //     size_t stride = CALC_STRIDE(CURSOR_W, 32);
    //     static uint32_t cursor_data[(CALC_STRIDE(CURSOR_W, 32) * CURSOR_H) /
    //                                 sizeof(uint32_t)];
    //     for (int y = 0; y < height; y++) {
    //         memcpy(cursor_data + y * stride / sizeof(uint32_t), data + y * width,
    //                width * sizeof(uint32_t));
    //     }

    //     if (!resource_attach_backing(RESOURCE_CURSOR, (uintptr_t)cursor_data,
    //                                  height * stride))
    //     {
    //         return false;
    //     }

    //     vq_wait_settled(&vq);

    //     gpu_command.transfer_to_host_2d = (struct VirtIOGPUTransferToHost2D){
    //         .hdr = {
    //             .type = VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D,
    //         },
    //         .r = {
    //             .width = CURSOR_W,
    //             .height = CURSOR_H,
    //         },
    //         .resource_id = RESOURCE_CURSOR,
    //     };

    //     if (!exec_command()) {
    //         return false;
    //     }

    //     vq_wait_settled(&cursor_vq);

    //     int desc_i = cursor_vq.avail_i++ % QUEUE_SIZE;
    //     cursor_commands[desc_i] = (struct VirtIOGPUCursorCommand){
    //         .hdr = {
    //             .type = VIRTIO_GPU_CMD_UPDATE_CURSOR,
    //         },
    //         .pos = {
    //             .scanout_id = 0,
    //         },
    //         .resource_id = RESOURCE_CURSOR,
    //         .hot_x = hot_x,
    //         .hot_y = hot_y,
    //     };

    //     vq_exec(&cursor_vq);

    //     return true;
    // }

    // static void move_cursor(int x, int y)
    // {
    //     vq_wait_settled(&cursor_vq);

    //     int desc_i = cursor_vq.avail_i++ % QUEUE_SIZE;
    //     cursor_commands[desc_i] = (struct VirtIOGPUCursorCommand){
    //         .hdr = {
    //             .type = VIRTIO_GPU_CMD_MOVE_CURSOR,
    //         },
    //         .pos = {
    //             .scanout_id = 0,
    //             .x = x,
    //             .y = y,
    //         },
    //         // I leave it up to you whether the "spec" (the documentation
    //         // in the reference header) or qemu's implementation is buggy,
    //         // but the latter definitely requires this ID even when just
    //         // moving the cursor
    //         .resource_id = RESOURCE_CURSOR,
    //     };

    //     vq_exec(&cursor_vq);
    // }

};
