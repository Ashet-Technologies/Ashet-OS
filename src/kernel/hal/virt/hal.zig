const std = @import("std");
const ashet = @import("root");
const logger = std.log.scoped(.@"platform-virt");

const virtio = @import("virtio/virtio.zig");

pub const serial = @import("serial.zig");

pub fn initialize() void {

    // Initialize all virtio devices:
    {
        const virtio_base = @intToPtr([*]align(4096) volatile virtio.ControlRegs, @import("regs.zig").VPBA_VIRTIO_BASE);

        if (virtio_base[0].magic != virtio.ControlRegs.magic) {
            @panic("not virt platform!");
        }

        var i: usize = 0;

        while (i < 8 and virtio_base[i].magic == virtio.ControlRegs.magic) : (i += 1) {
            const regs = &virtio_base[i];

            if (regs.version != 1 and regs.version != 2) {
                continue;
            }

            switch (regs.device_id) {
                .reserved => continue,
                .gpu => gpu.initialize(regs) catch |err| @panic(@errorName(err)),
                else => logger.info("Found unsupported virtio device: {s}", .{@tagName(regs.device_id)}),
            }
        }
    }

    video.present(); // force the gpu to show the splash screen

    // initialize block devices here:

    storage.initialize();
}

pub const storage = struct {
    const BlockDevice = ashet.storage.BlockDevice;

    var pflash1: ashet.drivers.block_device.CFI = undefined;

    var devices_backing = std.BoundedArray(ashet.storage.BlockDevice, 8){};
    pub var devices: []ashet.storage.BlockDevice = undefined;

    pub fn initialize() void {
        pflash1 = ashet.drivers.block_device.CFI.init(0x2200_0000, 0x0200_0000) catch @panic("pflash1 not present!");

        devices_backing.append(.{
            .name = "PF0",
            .interface = pflash1.interface(),
        }) catch unreachable;
        devices = devices_backing.slice();
    }
};

pub const memory = struct {
    pub const flash = ashet.memory.Section{ .offset = 0x2000_000, .length = 0x200_0000 };
    pub const ram = ashet.memory.Section{ .offset = 0x8000_0000, .length = 0x100_0000 };
};

pub const video = struct {
    var backing_buffer: [32768]u8 align(ashet.memory.page_size) = ashet.video.defaults.splash_screen;
    var backing_palette: [256]u16 = ashet.video.defaults.palette;

    pub const memory: []align(ashet.memory.page_size) u8 = &backing_buffer;
    pub const palette: *[256]u16 = &backing_palette;

    var video_mode: ashet.video.Mode = .graphics;
    var border_color: u8 = ashet.video.defaults.border;

    pub fn setMode(m: ashet.video.Mode) void {
        video_mode = m;
    }

    pub fn setBorder(b: u8) void {
        border_color = b;
    }

    fn pal(index: u8) u32 {
        return ashet.video.Color.fromU16(backing_palette[index]).toRgb32();
    }

    pub fn present() void {
        std.mem.set(u32, gpu.fb_mem, pal(border_color));

        switch (video_mode) {
            .text => {
                const font = ashet.video.defaults.font;

                const w = 64;
                const h = 32;

                const gw = 6;
                const gh = 8;

                const dx = (gpu.fb_width - gw * w) / 2;
                const dy = (gpu.fb_height - gh * h) / 2;

                var i: usize = 0;
                while (i < w * h) : (i += 1) {
                    const cx = i % w;
                    const cy = i / w;

                    const char = video.memory[2 * i + 0];
                    const attr = ashet.video.CharAttributes.fromByte(video.memory[2 * i + 1]);

                    const glyph = font[char];

                    var x: usize = 0;
                    while (x < gw) : (x += 1) {
                        var bits = glyph[x];

                        comptime var y: usize = 0;
                        inline while (y < gh) : (y += 1) {
                            const index = if ((bits & (1 << y)) != 0)
                                attr.fg
                            else
                                attr.bg;
                            gpu.fb_mem[gpu.fb_width * (dy + gh * cy + y) + (dx + gw * cx + x)] = pal(index);
                        }
                    }
                }
            },

            .graphics => {
                const dx = (gpu.fb_width - 256) / 2;
                const dy = (gpu.fb_height - 128) / 2;

                for (video.memory[0..32768]) |index, i| {
                    const x = dx + i % 256;
                    const y = dy + i / 256;

                    gpu.fb_mem[gpu.fb_width * y + x] = pal(index);
                }
            },
        }

        gpu.flushFramebuffer(0, 0, 0, 0);
    }
};

const gpu = struct {

    // // Chosen by virtio-gpu
    const CURSOR_W = 64;
    const CURSOR_H = 64;

    var fb_width: u32 = 0;
    var fb_height: u32 = 0;
    var fb_mem: []u32 = undefined;

    var vq: virtio.queue.VirtQ(4) = undefined;
    var cursor_vq: virtio.queue.VirtQ(4) = undefined;

    var gpu_command: virtio.gpu.GPUCommand align(16) = undefined;
    var gpu_command2: virtio.gpu.GPUCommand align(16) = undefined;
    var gpu_response: virtio.gpu.Response align(16) = undefined;

    var cursor_commands: [cursor_vq.size]virtio.gpu.CursorCommand align(16) = undefined;

    const Scanout = enum(u32) { first = 0, _ };
    const ResourceId = enum(u32) { invalid = 0, framebuffer = 1, cursor = 2, _ };

    fn initialize(regs: *volatile virtio.ControlRegs) !void {
        logger.info("initializing gpu {*}", .{regs});

        if (isInitialized()) {
            logger.warn("Multiple GPUs detected. Ignoring every GPU except the first one!", .{});
            return;
        }

        _ = try regs.negotiateFeatures(virtio.FeatureFlags.any_layout | virtio.FeatureFlags.version_1);

        if (regs.device.gpu.num_scanouts < 1) {
            logger.err("gpu does not provide any scanouts!", .{});
            return;
        }

        try vq.init(0, regs);
        // try cursor_vq.init(1, regs);

        regs.status |= virtio.DeviceStatus.driver_ok;

        //     for (int i = 0; i < QUEUE_SIZE; i++) {
        //         vq_push_descriptor(&cursor_vq, &cursor_commands[i],
        //                            sizeof(struct VirtIOGPUCursorCommand),
        //                            false, true, true);
        //     }
        //     // Those descriptors are not full, so reset avail_i
        //     cursor_vq.avail_i = 0;

        const di = (try getDisplayInfo()) orelse {
            logger.err("failed to query gpu display info!", .{});
            return;
        };

        for (di.pmodes[0..regs.device.gpu.num_scanouts]) |mode, i| {
            logger.info("Scanout({}{s}): {}x{}:{}x{}", .{
                i,            "",
                mode.r.x,     mode.r.y,
                mode.r.width, mode.r.height,
            });
        }

        fb_mem = setupFramebuffer(Scanout.first, ResourceId.framebuffer, di.pmodes[0].r.width, di.pmodes[0].r.height) catch |err| {
            logger.err("failed to setup framebuffer: {s}", .{@errorName(err)});
            return;
        };
        fb_width = di.pmodes[0].r.width;
        fb_height = di.pmodes[0].r.height;

        std.log.info("gpu ready with {}x{} @ {*}", .{ fb_width, fb_height, fb_mem });
    }

    fn isInitialized() bool {
        return (fb_width != 0);
    }

    fn showTestPattern() void {
        std.debug.assert(isInitialized());
        for (fb_mem) |*item, i| {
            const x = i % fb_width;
            const y = i / fb_width;

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

    fn execCommand() !void {
        vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu_command, false, true, false);
        vq.pushDescriptor(virtio.gpu.Response, &gpu_response, true, false, true);
        vq.exec();
        _ = vq.waitUsed();

        const ok = gpu_response.hdr.type >= virtio.gpu.resp.ok_nodata and
            gpu_response.hdr.type < virtio.gpu.resp.err_unspec;

        if (!ok) return switch (gpu_response.hdr.type) {
            virtio.gpu.resp.err_unspec => error.Unspecified,
            virtio.gpu.resp.err_out_of_memory => error.OutOfMemory,
            virtio.gpu.resp.err_invalid_scanout_id => error.InvalidScanoutId,
            virtio.gpu.resp.err_invalid_resource_id => error.InvalidResourceId,
            virtio.gpu.resp.err_invalid_context_id => error.InvalidContextId,
            virtio.gpu.resp.err_invalid_parameter => error.InvalidParameter,
            else => return error.Unknown,
        };
    }

    fn getDisplayInfo() !?*virtio.gpu.DisplayInfo {
        vq.waitSettled();
        gpu_command.hdr.type = virtio.gpu.cmd.get_display_info;
        try execCommand();
        if (gpu_response.hdr.type != virtio.gpu.resp.ok_display_info) {
            return null;
        }
        return &gpu_response.display_info;
    }

    fn create2dResource(id: ResourceId, format: virtio.gpu.Format, width: u32, height: u32) !void {
        vq.waitSettled();

        gpu_command.res_create_2d = .{
            .resource_id = @enumToInt(id),
            .format = format,
            .width = width,
            .height = height,
        };

        try execCommand();
    }

    fn resourceAttachBacking(id: ResourceId, address: *anyopaque, length: usize) !void {
        vq.waitSettled();

        gpu_command.res_attach_backing = .{
            .resource_id = @enumToInt(id),
            .nr_entries = 1,
        };

        gpu_command.res_attach_backing.entries()[0] = .{
            .addr = @ptrToInt(address),
            .length = length,
        };

        try execCommand();
    }

    fn setScanout(scanout: Scanout, res_id: ResourceId, width: u32, height: u32) !void {
        vq.waitSettled();
        gpu_command.set_scanout = .{
            .r = .{
                .x = 0,
                .y = 0,
                .width = width,
                .height = height,
            },
            .scanout_id = @enumToInt(scanout),
            .resource_id = @enumToInt(res_id),
        };
        try execCommand();
    }

    fn calcStride(width: u32, bpp: u32) usize {
        return ((width * bpp + 31) / 32) * @sizeOf(u32);
    }

    fn setupFramebuffer(scanout: Scanout, res_id: ResourceId, width: u32, height: u32) ![]u32 {
        try create2dResource(res_id, virtio.gpu.Format.r8g8b8x8_unorm, width, height);

        const stride = calcStride(width, 32);
        const required_pages = ashet.memory.getRequiredPages(height * stride);
        const first_page = try ashet.memory.allocPages(required_pages);
        errdefer ashet.memory.freePages(first_page, required_pages);

        try resourceAttachBacking(res_id, ashet.memory.pageToPtr(first_page) orelse unreachable, height * stride);

        try setScanout(scanout, res_id, width, height);

        return std.mem.bytesAsSlice(u32, @ptrCast([*]align(4096) u8, ashet.memory.pageToPtr(first_page))[0 .. height * stride]);
    }

    fn flushFramebuffer(x: u32, y: u32, req_width: u32, req_height: u32) void {
        const width =
            if (req_width <= 0) fb_width else req_width;

        const height = if (req_height <= 0) fb_height else req_height;

        vq.waitSettled();

        gpu_command.transfer_to_host_2d = .{
            .r = .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            },
            .offset = y * calcStride(fb_width, 32) + x * 4,
            .resource_id = @enumToInt(ResourceId.framebuffer),
        };

        gpu_command2.res_flush = .{
            .r = .{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            },
            .resource_id = @enumToInt(ResourceId.framebuffer),
        };

        vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu_command, false, true, false);
        vq.pushDescriptor(virtio.gpu.Response, &gpu_response, true, false, true);

        vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu_command2, false, true, false);

        // We don't care about the result anyway, might as well just
        // overwrite the previous one
        vq.pushDescriptor(virtio.gpu.Response, &gpu_response, true, false, true);

        vq.exec();
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
