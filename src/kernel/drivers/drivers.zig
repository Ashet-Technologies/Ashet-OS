const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.drivers);

pub const block = struct {
    // pub const ata = @import("block-device/ata.zig");
    pub const CFI_NOR_Flash = @import("block/CFI_NOR_Flash.zig");
};

pub const serial = struct {
    pub const ns16c550 = @import("serial/ns16c550.zig");
};

pub const rtc = struct {
    pub const Dummy = @import("rtc/Dummy.zig");
    pub const Goldfish = @import("rtc/Goldfish.zig");
};

pub const video = struct {
    /// Memory mapped virtio GPU
    pub const Virtio_GPU_Device = @import("video/Virtio_GPU_Device.zig");
    pub const VESA_BIOS_Extension = @import("video/VESA_BIOS_Extension.zig");
};

pub const network = struct {
    /// Memory mapped virtio network device
    pub const Virtio_Net_Device = @import("network/Virtio_Net_Device.zig");
};

pub const input = struct {
    /// Memory mapped virtio input device
    pub const Virtio_Input_Device = @import("input/Virtio_Input_Device.zig");
};

var driver_lists = std.EnumArray(DriverClass, ?*Driver).initFill(null);

/// Adds a driver to the system.
pub fn install(driver: *Driver) void {
    std.debug.assert(driver.next == null);

    const head = driver_lists.getPtr(driver.class);
    driver.next = head.*;
    head.* = driver;

    logger.debug("installed driver '{s}'", .{driver.name});
}

pub fn first(comptime class: DriverClass) ?*ResolvedDriverInterface(class) {
    const head = driver_lists.get(class) orelse return null;
    std.debug.assert(head.class == class);
    return &@field(head.class, @tagName(class));
}

/// Returns an iterator that will return all devices currently registered for that `class`.
pub fn enumerate(comptime class: DriverClass) DriverIterator(class) {
    return DriverIterator(class).init();
}

/// An iterator type that will return all devices currently registered for that `class`.
pub fn DriverIterator(comptime class: DriverClass) type {
    return struct {
        const Iterator = @This();

        next_item: ?*Driver,

        pub fn init() Iterator {
            return Iterator{ .next_item = driver_lists.get(class) };
        }

        pub fn next(iter: *Iterator) ?*ResolvedDriverInterface(class) {
            const item = iter.next_item orelse return null;
            iter.next_item = item.next;
            std.debug.assert(item.class == class);
            return &@field(item.class, @tagName(class));
        }
    };
}

fn ResolvedDriverInterface(comptime class: DriverClass) type {
    return std.meta.fields(DriverInterface)[std.meta.fieldIndex(DriverInterface, @tagName(class)).?].field_type;
}

/// Generic driver interface, used to chain drivers together.
/// Drivers provide hardware interfaces.
pub const Driver = struct {
    name: []const u8,
    next: ?*Driver = null,
    class: DriverInterface,
};

pub const DriverClass = enum {
    block,
    rtc,
    video,
    sound,
    input,
    serial,
    network,
};

pub const DriverInterface = union(DriverClass) {
    block: BlockDevice,
    rtc: RTC,
    video: VideoDevice,
    sound: SoundDevice,
    input: InputDevice,
    serial: SerialPort,
    network: NetworkInterface,
};

pub fn resolveDriver(comptime class: DriverClass, ptr: *ResolvedDriverInterface(class)) *Driver {
    const container = @ptrCast(*DriverInterface, ptr);
    std.debug.assert(@ptrToInt(container) == @ptrToInt(&@field(container, @tagName(class))));
    return @fieldParentPtr(Driver, "class", container);
}

pub const BlockDevice = ashet.storage.BlockDevice;

pub const RTC = struct {
    nanoTimestampFn: *const fn (driver: *Driver) i128,

    pub fn nanoTimestamp(clk: *RTC) i128 {
        return clk.nanoTimestampFn(resolveDriver(.rtc, clk));
    }
};

pub const VideoDevice = struct {
    const ColorIndex = ashet.video.ColorIndex;
    const Color = ashet.video.Color;
    const Resolution = ashet.video.Resolution;

    getVideoMemoryFn: *const fn (*Driver) []align(ashet.memory.page_size) ColorIndex,
    getPaletteMemoryFn: *const fn (*Driver) *[256]Color,
    setBorderFn: *const fn (*Driver, ColorIndex) void,
    flushFn: *const fn (*Driver) void,
    getResolutionFn: *const fn (*Driver) Resolution,
    getMaxResolutionFn: *const fn (*Driver) Resolution,
    getBorderFn: *const fn (*Driver) ColorIndex,
    setResolutionFn: *const fn (*Driver, width: u15, height: u15) void,

    pub fn getVideoMemory(vd: *VideoDevice) []align(ashet.memory.page_size) ColorIndex {
        return vd.getVideoMemoryFn(resolveDriver(.video, vd));
    }

    pub fn getPaletteMemory(vd: *VideoDevice) *[256]Color {
        return vd.getPaletteMemoryFn(resolveDriver(.video, vd));
    }

    pub fn setBorder(vd: *VideoDevice, b: ColorIndex) void {
        vd.setBorderFn(resolveDriver(.video, vd), b);
    }

    pub fn flush(vd: *VideoDevice) void {
        vd.flushFn(resolveDriver(.video, vd));
    }

    pub fn getResolution(vd: *VideoDevice) Resolution {
        return vd.getResolutionFn(resolveDriver(.video, vd));
    }

    pub fn getMaxResolution(vd: *VideoDevice) Resolution {
        return vd.getMaxResolutionFn(resolveDriver(.video, vd));
    }

    pub fn getBorder(vd: *VideoDevice) ColorIndex {
        return vd.getBorderFn(resolveDriver(.video, vd));
    }

    pub fn setResolution(vd: *VideoDevice, width: u15, height: u15) void {
        vd.setResolutionFn(resolveDriver(.video, vd), width, height);
    }
};

pub const SoundDevice = struct {
    //
    dummy: u8,
};

pub const InputDevice = struct {
    pollFn: *const fn (*Driver) void,

    pub fn poll(idev: *InputDevice) void {
        idev.pollFn(resolveDriver(.input, idev));
    }
};

pub const SerialPort = struct {
    //
    dummy: u8,
};

pub const NetworkInterface = ashet.network.NetworkInterface;

const virtio = @import("virtio");

/// Scans a memory area for virtio devices and installs all found device drivers.
pub fn scanVirtioDevices(allocator: std.mem.Allocator, base_address: usize, max_count: usize) !void {
    const virtio_base = @intToPtr([*]align(4096) volatile virtio.ControlRegs, base_address);

    if (virtio_base[0].magic != virtio.ControlRegs.magic) {
        @panic("not virt platform!");
    }

    var i: usize = 0;

    while (i < max_count and virtio_base[i].magic == virtio.ControlRegs.magic) : (i += 1) {
        const regs = &virtio_base[i];

        if (regs.version != 1 and regs.version != 2) {
            continue;
        }

        switch (regs.device_id) {
            .reserved => continue,
            .gpu => installVirtioDriver(video.Virtio_GPU_Device, allocator, regs) catch |err| @panic(@errorName(err)),
            .input => installVirtioDriver(input.Virtio_Input_Device, allocator, regs) catch |err| @panic(@errorName(err)),
            .network => installVirtioDriver(network.Virtio_Net_Device, allocator, regs) catch |err| @panic(@errorName(err)),
            else => logger.warn("Found unsupported virtio device: {s}", .{@tagName(regs.device_id)}),
        }
    }
}

fn installVirtioDriver(comptime T: type, allocator: std.mem.Allocator, regs: *volatile virtio.ControlRegs) !void {
    const device = try T.init(allocator, regs);
    install(&device.driver);
}
