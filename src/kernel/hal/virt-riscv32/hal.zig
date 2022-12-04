const std = @import("std");
const ashet = @import("root");
const logger = std.log.scoped(.@"platform-virt");

const virtio = @import("virtio");

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
                .input => input.initialize(regs) catch |err| @panic(@errorName(err)),
                .network => network.initialize(regs) catch |err| @panic(@errorName(err)),
                else => logger.info("Found unsupported virtio device: {s}", .{@tagName(regs.device_id)}),
            }
        }
    }

    video.flush(); // force the gpu to show the splash screen

    storage.initialize();

    time.init();
}

pub const time = struct {
    const goldfish_rtc = @intToPtr(*volatile ashet.drivers.rtc.Goldfish, 0x0101000);

    fn init() void {
        // already happy.
    }

    pub fn nanoTimestamp() i128 {
        return goldfish_rtc.read();
    }
};

pub const storage = struct {
    const BlockDevice = ashet.storage.BlockDevice;

    var pflash1: ashet.drivers.block_device.CFI = undefined;

    var devices_backing = std.BoundedArray(ashet.storage.BlockDevice, 8){};
    pub var devices: []ashet.storage.BlockDevice = undefined;

    pub fn initialize() void {
        pflash1 = ashet.drivers.block_device.CFI.init(0x2200_0000, 0x0200_0000) catch @panic("pflash1 not present!");

        devices_backing.appendAssumeCapacity(.{
            .name = "PF0",
            .interface = pflash1.interface(),
        });
        devices = devices_backing.slice();
    }
};

pub const memory = struct {
    pub const flash = ashet.memory.Section{ .offset = 0x2000_000, .length = 0x200_0000 };
    pub const ram = ashet.memory.Section{ .offset = 0x8000_0000, .length = 0x100_0000 };
};

pub const video = struct {
    const ColorIndex = ashet.abi.ColorIndex;
    const Color = ashet.abi.Color;

    const max_width = 400;
    const max_height = 300;

    var backing_buffer: [max_width * max_height]ColorIndex align(ashet.memory.page_size) = ashet.video.defaults.splash_screen ++ ([1]ColorIndex{ColorIndex.get(0)} ** (max_width * max_height - ashet.video.defaults.splash_screen.len));
    var backing_palette: [256]Color = ashet.video.defaults.palette;

    pub const memory: []align(ashet.memory.page_size) ColorIndex = &backing_buffer;
    pub const palette: *[256]Color = &backing_palette;

    var border_color: ColorIndex = ashet.video.defaults.border;

    var graphics_width: u16 = 256;
    var graphics_height: u16 = 128;

    pub fn getResolution() ashet.video.Resolution {
        return ashet.video.Resolution{
            .width = graphics_width,
            .height = graphics_height,
        };
    }
    pub fn getBorder() ColorIndex {
        return border_color;
    }

    pub fn setBorder(b: ColorIndex) void {
        border_color = b;
    }

    pub fn setResolution(width: u16, height: u16) void {
        graphics_width = width;
        graphics_height = height;
    }

    fn pal(color: ColorIndex) u32 {
        return backing_palette[color.index()].toRgb32();
    }

    pub fn flush() void {
        const dx = (gpu.fb_width - graphics_width) / 2;
        const dy = (gpu.fb_height - graphics_height) / 2;

        {
            var i: usize = 0;
            while (i < gpu.fb_width * gpu.fb_height) : (i += 1) {
                const x = i % gpu.fb_width;
                const y = i / gpu.fb_width;

                if (x < dx or x >= dx + graphics_width or y < dy or y >= dy + graphics_height) {
                    gpu.fb_mem[i] = pal(border_color);
                }
            }
        }

        const pixel_count = @as(usize, graphics_width) * @as(usize, graphics_height);

        for (video.memory[0..pixel_count]) |index, i| {
            const x = dx + i % graphics_width;
            const y = dy + i / graphics_width;

            gpu.fb_mem[gpu.fb_width * y + x] = pal(index);
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

        const num_scanouts = &regs.device.gpu.num_scanouts;
        if (num_scanouts.* < 1) {
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

        for (di.pmodes[0..num_scanouts.*]) |mode, i| {
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
        vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu_command, .read, true, false);
        vq.pushDescriptor(virtio.gpu.Response, &gpu_response, .write, false, true);
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

        vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu_command, .read, true, false);
        vq.pushDescriptor(virtio.gpu.Response, &gpu_response, .write, false, true);

        vq.pushDescriptor(virtio.gpu.GPUCommand, &gpu_command2, .read, true, false);

        // We don't care about the result anyway, might as well just
        // overwrite the previous one
        vq.pushDescriptor(virtio.gpu.Response, &gpu_response, .write, false, true);

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

pub const input = struct {
    const queue_size = 8;

    const eventq = 0;
    const statusq = 1;

    fn selectConfig(regs: *volatile virtio.ControlRegs, select: virtio.input.ConfigSelect, subsel: virtio.input.ConfigEvSubSel) void {
        regs.device.input.select = select;
        regs.device.input.subsel = subsel;
    }

    fn initialize(regs: *volatile virtio.ControlRegs) !void {
        logger.info("initializing input device {*}", .{regs});

        const input_dev = &regs.device.input;

        _ = try regs.negotiateFeatures(virtio.FeatureFlags.any_layout | virtio.FeatureFlags.version_1);

        selectConfig(regs, .id_name, .unset);

        var copy = input_dev.data.string;
        logger.info("input: {s}", .{@as([]const u8, std.mem.sliceTo(&copy, 0))});

        selectConfig(regs, .ev_bits, .cess_key);
        var keys: u32 = 0;

        if (input_dev.select != .unset) {
            var i: u16 = 0;
            while (i < @as(u16, input_dev.size) * 8) : (i += 1) {
                if (input_dev.data.isBitSet(i)) {
                    keys += 1;
                }
            }
            logger.info("keys = {}", .{keys});
        }

        selectConfig(regs, .ev_bits, .cess_rel);
        var axes: c_int = 0;
        var mouse_axes = false;

        if (input_dev.select != .unset) {
            var i: u16 = 0;
            while (i < @as(u16, input_dev.size) * 8) : (i += 1) {
                if (input_dev.data.isBitSet(i)) {
                    axes += 1;
                }
            }
            logger.info("rel axes = {}", .{axes});

            if (axes != 0) {
                mouse_axes = (input_dev.data.bitmap[0] & 3) == 3;
            }
        }

        selectConfig(regs, .ev_bits, .cess_abs);
        var tablet_axes = false;

        if (input_dev.select != .unset) {
            var i: u16 = 0;
            while (i < @as(u16, input_dev.size) * 8) : (i += 1) {
                if (input_dev.data.isBitSet(i)) {
                    axes += 1;
                }
            }
            logger.info("abs axes = {}", .{axes});

            if (axes != 0) {
                tablet_axes = (input_dev.data.bitmap[0] & 3) == 3;
            }
        }

        if (axes == 0 and keys >= 80) {
            try initDevice(regs, .keyboard);
        } else if (mouse_axes) {
            try initDevice(regs, .mouse);
        } else if (tablet_axes) {
            try initDevice(regs, .tablet);
        } else {
            logger.warn("Ignoring this device, it has unknown metrics", .{});
        }
    }

    pub const DeviceType = enum {
        keyboard,
        mouse,
        tablet,
    };

    const Device = struct {
        regs: *volatile virtio.ControlRegs,
        kind: DeviceData,

        events: [queue_size]virtio.input.Event,
        vq: virtio.queue.VirtQ(queue_size),
    };

    const DeviceData = union(DeviceType) {
        keyboard,
        mouse,
        tablet: Tablet,
    };

    const Tablet = struct {
        axis_min: [3]u32,
        axis_max: [3]u32,
    };

    var devices = std.BoundedArray(Device, 8){};

    fn initDevice(regs: *volatile virtio.ControlRegs, device_type: DeviceType) !void {
        logger.info("recognized 0x{X:0>8} as {s}", .{ @ptrToInt(regs), @tagName(device_type) });

        const device = try devices.addOne();
        errdefer _ = devices.pop();

        device.* = Device{
            .regs = regs,
            .kind = undefined,
            .events = std.mem.zeroes([queue_size]virtio.input.Event),
            .vq = undefined,
        };

        try device.vq.init(eventq, regs);

        for (device.events) |*event| {
            device.vq.pushDescriptor(virtio.input.Event, event, .write, true, true);
        }

        switch (device_type) {
            .keyboard => {
                device.kind = DeviceData{ .keyboard = {} };
            },

            .mouse => {
                device.kind = DeviceData{ .mouse = {} };
            },

            .tablet => {
                @panic("tablet not supported yet");
                // device.kind = DeviceData{
                //     .tablet = .{
                //         .axis_min = undefined,
                //         .axis_max = undefined,
                //     },
                // };

                // for ([3]u8{ 0x00, 0x01, 0x02 }) |axis| {
                //     selectConfig(regs, .abs_info, @intToEnum(virtio.input.ConfigEvSubSel, axis));
                //     // if (regs.device.input.select == .unset) {
                //     //     return error.AxisInfoError;
                //     // }

                //     // device.kind.tablet.axis_min[axis] = input_dev.data.abs.min;
                //     // device.kind.tablet.axis_max[axis] = input_dev.data.abs.max;
                // }
            },
        }

        selectConfig(regs, .unset, .unset);

        regs.status |= virtio.DeviceStatus.driver_ok;

        device.vq.exec();
    }

    fn getDeviceEvent(dev: *Device) ?virtio.input.Event {
        const ret = dev.vq.singlePollUsed() orelse return null;

        const evt = dev.events[ret % queue_size];
        dev.vq.avail_i += 1;
        dev.vq.exec();

        return evt;
    }

    fn mapToMouseButton(val: u16) ?ashet.abi.MouseButton {
        return switch (val) {
            272 => .left,
            273 => .right,
            274 => .middle,
            275 => .nav_previous,
            276 => .nav_next,
            337 => .wheel_up,
            336 => .wheel_down,
            else => null,
        };
    }

    pub fn poll() void {
        for (devices.slice()) |*device| {
            device_fetch: while (true) {
                const evt = getDeviceEvent(device) orelse break :device_fetch;
                const event_type = @intToEnum(virtio.input.ConfigEvSubSel, evt.type);

                switch (device.kind) {
                    .keyboard => {
                        switch (event_type) {
                            .unset => {},
                            .cess_key => ashet.input.pushRawEvent(.{ .keyboard = .{
                                .scancode = evt.code,
                                .down = evt.value != 0,
                            } }),
                            else => logger.warn("unhandled keyboard event: {}", .{event_type}),
                        }
                    },
                    .mouse => {
                        switch (event_type) {
                            .unset => {},
                            .cess_key => {
                                ashet.input.pushRawEvent(.{ .mouse_button = .{
                                    .button = mapToMouseButton(evt.code) orelse continue,
                                    .down = (evt.value != 0),
                                } });
                            },
                            .cess_rel => {
                                if (evt.code == 0) {
                                    ashet.input.pushRawEvent(.{ .mouse_motion = .{
                                        .dx = @bitCast(i32, evt.value),
                                        .dy = 0,
                                    } });
                                } else if (evt.code == 1) {
                                    ashet.input.pushRawEvent(.{ .mouse_motion = .{
                                        .dx = 0,
                                        .dy = @bitCast(i32, evt.value),
                                    } });
                                }
                            },
                            else => logger.warn("unhandled mouse event: {}", .{event_type}),
                        }
                    },
                    else => logger.warn("unhandled event for {s} device: {}", .{ @tagName(device.kind), event_type }),
                }
            }
        }
    }
};

pub const network = struct {
    fn FixedPool(comptime T: type, comptime size: usize) type {
        return struct {
            const Self = @This();

            items: [size]T = undefined,
            maps: std.bit_set.StaticBitSet(size) = std.bit_set.StaticBitSet(size).initFull(),

            pub fn alloc(pool: *Self) ?*T {
                const index = pool.maps.findFirstSet() orelse return null;
                pool.maps.unset(index);
                return &pool.items[index];
            }

            pub fn get(pool: *Self, index: usize) *T {
                std.debug.assert(index < size);
                return &pool.items[index];
            }

            pub fn free(pool: *Self, item: *T) void {
                const index = @divExact((@ptrToInt(item) -% @ptrToInt(&pool.items[0])), @sizeOf(T));
                std.debug.assert(index < size);
                pool.maps.set(index);
            }
        };
    }

    const DeviceInfo = struct {
        const queue_size = 8;

        pub const vtable = ashet.network.NIC.VTable{
            .linkIsUp = linkIsUp,
            .allocPacket = allocPacket,
            .send = send,
            .fetch = fetchNic,
        };

        receiveq: virtio.queue.VirtQ(queue_size),
        transmitq: virtio.queue.VirtQ(queue_size),

        receive_buffers: FixedPool(Buffer, queue_size) = .{},
        transmit_buffers: FixedPool(Buffer, queue_size) = .{},

        const Buffer = extern struct {
            const max_mtu = 1514;

            header: virtio.network.NetHeader,
            data: [max_mtu]u8,
            length: usize,
        };

        comptime {
            std.debug.assert(@sizeOf(Buffer) >= 1526);
        }

        fn getDevice(nic: *ashet.network.NIC) *DeviceInfo {
            return @ptrCast(*DeviceInfo, @alignCast(@alignOf(DeviceInfo), nic.implementation));
        }

        fn linkIsUp(nic: *ashet.network.NIC) bool {
            _ = nic;
            return true;
        }

        fn allocPacket(nic: *ashet.network.NIC, size: usize) ?[]u8 {
            if (size > Buffer.max_mtu)
                return null;
            const dev = getDevice(nic);
            const buffer = dev.transmit_buffers.alloc() orelse return null;
            buffer.* = DeviceInfo.Buffer{
                .header = .{
                    .flags = .{ .needs_csum = false, .data_valid = false, .rsc_info = false },
                    .gso_type = .none,
                    .hdr_len = 0,
                    .gso_size = 0,
                    .csum_start = 0,
                    .csum_offset = 0,
                    .num_buffers = 0,
                },
                .data = undefined,
                .length = size,
            };
            return &buffer.data;
        }

        fn send(nic: *ashet.network.NIC, packet: []u8) bool {
            std.debug.assert(packet.len == Buffer.max_mtu);
            const dev = getDevice(nic);
            const buffer = @fieldParentPtr(Buffer, "data", packet.ptr[0..Buffer.max_mtu]);

            logger.info("sending {} bytes...", .{buffer.length});

            dev.transmitq.pushDescriptorRaw(buffer, @sizeOf(virtio.network.NetHeader) + buffer.length, .read, true, true);
            dev.transmitq.exec();

            return true;
        }

        fn fetchNic(nic: *ashet.network.NIC) void {
            const dev = getDevice(nic);

            handleIncomingData(nic, dev) catch |err| {
                logger.err("error while receiving packets from nic {s}: {s}", .{ nic.getName(), @errorName(err) });
            };

            handleOutgoingData(nic, dev) catch |err| {
                logger.err("error while recycling packets from nic {s}: {s}", .{ nic.getName(), @errorName(err) });
            };
        }

        pub fn handleOutgoingData(nic: *ashet.network.NIC, dev: *DeviceInfo) !void {
            _ = nic;

            var count: usize = 0;
            while (dev.transmitq.singlePollUsed()) |ret| {
                const buffer = @intToPtr(*DeviceInfo.Buffer, @truncate(usize, dev.transmitq.descriptors[ret % DeviceInfo.queue_size].addr));
                dev.transmit_buffers.free(buffer);
                count += 1;
            }
            if (count > 0) {
                logger.info("recycled {} packets", .{count});
            }
        }

        pub fn handleIncomingData(nic: *ashet.network.NIC, dev: *DeviceInfo) !void {
            defer dev.receiveq.exec();
            while (dev.receiveq.singlePollUsed()) |ret| {
                const buffer = @intToPtr(*DeviceInfo.Buffer, @truncate(usize, dev.receiveq.descriptors[ret % DeviceInfo.queue_size].addr));

                if (buffer.header.num_buffers != 1) {
                    @panic("large packets with more than one buffer not supported yet!");
                }

                // IMPORTANT:
                // This code must run in ANY CASE!
                // If the buffer isn't requeued, we're losing a receive buffer for this NIC,
                // and if that happens too often, the network reception is killed.
                defer {
                    // round and round we go
                    buffer.* = undefined;
                    dev.receiveq.pushDescriptor(DeviceInfo.Buffer, buffer, .write, true, true);
                }

                const packet = try nic.allocPacket(buffer.data.len);
                errdefer nic.freePacket(packet);

                try packet.append(&buffer.data);

                logger.info("received data on nic {s}", .{nic.getName()});

                nic.receive(packet);
            }
        }
    };

    var nics: std.BoundedArray(ashet.network.NIC, 8) = .{};
    var nic_devs: std.BoundedArray(DeviceInfo, 8) = .{};

    pub fn getNICs() []ashet.network.NIC {
        return nics.slice();
    }

    fn initialize(regs: *volatile virtio.ControlRegs) !void {
        logger.info("initializing network device {*}", .{regs});

        const network_dev = &regs.device.network;

        const negotiated_features = try regs.negotiateFeatures(0 |
            virtio.FeatureFlags.any_layout |
            virtio.FeatureFlags.version_1 | // we want the non-legacy interface
            virtio.network.FeatureFlags.mtu | // we want to know the MTU
            virtio.network.FeatureFlags.mrg_rxbuf | // we can use merged buffers, for legacy interface compat
            // virtio.network.FeatureFlags.mac | // use custom mac
            virtio.network.FeatureFlags.status // we want to know the real up/down status
        );

        const features = while (true) {
            const prev = regs.config_generation;
            const set = network_dev.*;
            const next = regs.config_generation;
            if (prev == next)
                break set;
        };

        logger.info("network device info: mac={X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}, status={}, mtu={}, max queues={}, features:", .{
            features.mac[0],
            features.mac[1],
            features.mac[2],
            features.mac[3],
            features.mac[4],
            features.mac[5],
            features.status,
            features.mtu,
            features.max_virtqueue_pairs,
        });
        inline for (comptime std.meta.declarations(virtio.FeatureFlags)) |decl| {
            const has_feature = ((negotiated_features & @field(virtio.FeatureFlags, decl.name)) != 0);
            if (has_feature) {
                logger.info("- {s}", .{decl.name});
            }
        }
        inline for (comptime std.meta.declarations(virtio.network.FeatureFlags)) |decl| {
            const has_feature = ((negotiated_features & @field(virtio.network.FeatureFlags, decl.name)) != 0);
            if (has_feature) {
                logger.info("- {s}", .{decl.name});
            }
        }
        logger.info("legacy: {}", .{regs.version});

        const legacy = regs.isLegacy();
        if (legacy) {
            logger.info("network device is using legacy interface!", .{});
        }

        const nic = try nics.addOne();
        const dev = nic_devs.addOneAssumeCapacity();
        nic.* = ashet.network.NIC{
            .interface = .ethernet,
            .address = ashet.network.MAC.init(features.mac),
            .mtu = DeviceInfo.Buffer.max_mtu,

            .implementation = dev,
            .vtable = &DeviceInfo.vtable,
        };
        dev.* = DeviceInfo{
            .receiveq = undefined,
            .transmitq = undefined,
        };

        try dev.receiveq.init(virtio.network.receiveq(0), regs);
        try dev.transmitq.init(virtio.network.transmitq(0), regs);

        regs.status |= virtio.DeviceStatus.driver_ok;

        while (dev.receive_buffers.alloc()) |buffer| {
            buffer.* = undefined;
            dev.receiveq.pushDescriptor(DeviceInfo.Buffer, buffer, .write, true, true);
        }
        dev.receiveq.exec();
    }
};
