const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.drivers);

pub const block = struct {
    // pub const ata = @import("block-device/ata.zig");
    pub const CFI_NOR_Flash = @import("block/CFI_NOR_Flash.zig");
    pub const AT_Attachment = @import("block/AT_Attachment.zig");
    pub const RAM_Disk = @import("block/ram-disk.zig").RAM_Disk;
};

pub const serial = struct {
    pub const ns16c550 = @import("serial/NS16C550.zig");
    pub const PL011 = @import("serial/PL011.zig");
};

pub const timer = struct {
    pub const Programmable_Interval_Timer = @import("timer/Programmable_Interval_Timer.zig");
};

pub const filesystem = struct {
    pub const AshetFS = @import("filesystem/AshetFS.zig");
    pub const VFAT = @import("filesystem/VFAT.zig");
};

pub const rtc = struct {
    pub const Dummy = @import("rtc/Dummy.zig");
    pub const CMOS = @import("rtc/CMOS.zig");
    pub const Goldfish = @import("rtc/Goldfish.zig");
    pub const PL031 = @import("rtc/PL031.zig");
    pub const HostedSystemClock = @import("rtc/HostedSystemClock.zig");
};

pub const video = struct {
    /// Memory mapped virtio GPU
    pub const Virtio_GPU_Device = @import("video/Virtio_GPU_Device.zig");
    pub const VESA_BIOS_Extension = @import("video/VESA_BIOS_Extension.zig");
    pub const VGA = @import("video/VGA.zig");
    pub const Virtual_Video_Output = @import("video/Virtual_Video_Output.zig");
};

pub const network = struct {
    /// Memory mapped virtio network device
    pub const Virtio_Net_Device = @import("network/Virtio_Net_Device.zig");
};

pub const input = struct {
    /// Memory mapped virtio input device
    pub const Virtio_Input_Device = @import("input/Virtio_Input_Device.zig");

    /// PC Keyboard (and mouse) Controller
    pub const PC_KBC = @import("input/PC_KBC.zig");
};

var driver_lists = std.EnumArray(DriverClass, ?*Driver).initFill(null);

/// Adds a driver to the system.
pub fn install(driver: *Driver) void {
    std.debug.assert(driver.next == null);

    std.debug.assert(!ashet.memory.isPointerToKernelStack(driver));

    const head = driver_lists.getPtr(driver.class);
    driver.next = head.*;
    head.* = driver;

    logger.info("installed {s} driver '{s}'", .{ @tagName(driver.class), driver.name });
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
            item.validate(class);
            return &@field(item.class, @tagName(class));
        }
    };
}

fn ResolvedDriverInterface(comptime class: DriverClass) type {
    return std.meta.fields(DriverInterface)[std.meta.fieldIndex(DriverInterface, @tagName(class)).?].type;
}

pub fn getDriverName(comptime class: DriverClass, intf: *ResolvedDriverInterface(class)) []const u8 {
    // if (@offsetOf(DriverInterface, @tagName(class)) != 0) @compileError("oh no!");

    std.debug.assert(@as(*DriverInterface, @ptrFromInt(0x1000)) == @as(*DriverInterface, @ptrCast(&@field(@as(*DriverInterface, @ptrFromInt(0x1000)), @tagName(class)))));

    const di: *DriverInterface = @as(*DriverInterface, @ptrCast(intf));

    const dri: *Driver = @fieldParentPtr(Driver, "class", di);
    dri.validate(class);
    return dri.name;
}

/// Generic driver interface, used to chain drivers together.
/// Drivers provide hardware interfaces.
pub const Driver = struct {
    name: []const u8,
    next: ?*Driver = null,
    class: DriverInterface,

    fn validate(dri: *Driver, comptime class: DriverClass) void {
        if (dri.class != class) {
            logger.err("bad driver {}", .{ashet.CodeLocation{ .pointer = @intFromPtr(dri) }});
            logger.err("expected class {s}, but found {s}", .{ comptime @tagName(class), @tagName(dri.class) });
            logger.err("driver data: {}", .{dri.*});
            @panic("driver corrupted");
        }
    }
};

pub const DriverClass = enum {
    block,
    rtc,
    video,
    sound,
    input,
    serial,
    network,
    filesystem,
};

pub const DriverInterface = union(DriverClass) {
    block: BlockDevice,
    rtc: RTC,
    video: VideoDevice,
    sound: SoundDevice,
    input: InputDevice,
    serial: SerialPort,
    network: NetworkInterface,
    filesystem: FileSystemDriver,
};

pub fn resolveDriver(comptime class: DriverClass, ptr: *ResolvedDriverInterface(class)) *Driver {
    const container = @as(*DriverInterface, @ptrCast(ptr));
    std.debug.assert(@intFromPtr(container) == @intFromPtr(&@field(container, @tagName(class))));

    const driver = @fieldParentPtr(Driver, "class", container);
    driver.validate(class);
    return driver;
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

pub const FileSystemDriver = struct {
    pub const CreateError = error{
        /// Returned when the filesystem cannot be identified,
        NoFilesystem,

        /// Returned when the driver assumes that the device has the
        /// correct filesystem, but it is corrupt.
        CorruptFileSystem,

        /// The underlying block device failed,
        DeviceError,

        /// An allocation failed
        OutOfMemory,
    };

    createInstanceFn: *const fn (*Driver, std.mem.Allocator, *BlockDevice) CreateError!*Instance,
    destroyInstanceFn: *const fn (*Driver, std.mem.Allocator, *Instance) void,

    pub fn createInstance(dri: *FileSystemDriver, allocator: std.mem.Allocator, block_device: *BlockDevice) CreateError!*Instance {
        return dri.createInstanceFn(resolveDriver(.filesystem, dri), allocator, block_device);
    }

    pub fn destroyInstance(dri: *FileSystemDriver, allocator: std.mem.Allocator, instance: *Instance) void {
        dri.destroyInstanceFn(resolveDriver(.filesystem, dri), allocator, instance);
    }

    pub const FileHandle = enum(u32) { invalid = std.math.maxInt(u32), _ };
    pub const DirectoryHandle = enum(u32) { invalid = std.math.maxInt(u32), _ };

    pub const BaseError = error{SystemResources};

    pub const AccessError = BaseError || error{DiskError};

    pub const ReadError = AccessError || error{InvalidHandle};
    pub const WriteError = AccessError || error{ InvalidHandle, WriteProtected };
    pub const StatFileError = AccessError || error{InvalidHandle};
    pub const ResizeError = AccessError || error{ InvalidHandle, NoSpaceLeft };
    pub const OpenDirAbsError = AccessError || error{ FileNotFound, InvalidPath };
    pub const OpenDirRelError = AccessError || error{ FileNotFound, InvalidPath, InvalidHandle };
    pub const OpenFileError = AccessError || error{ FileNotFound, InvalidPath, InvalidHandle, WriteProtected, FileAlreadyExists };
    pub const FlushFileError = AccessError || error{InvalidHandle};
    pub const CreateEnumeratorError = AccessError;
    pub const ResetEnumeratorError = AccessError;
    pub const EnumerateError = AccessError;

    pub const Instance = struct {
        driver: *Driver,
        vtable: *const VTable,

        pub fn openDirFromRoot(instance: *Instance, path: []const u8) !DirectoryHandle {
            return instance.vtable.openDirFromRootFn(instance, path);
        }
        pub fn openDirRelative(instance: *Instance, base_dir: DirectoryHandle, path: []const u8) !DirectoryHandle {
            return instance.vtable.openDirRelativeFn(instance, base_dir, path);
        }
        pub fn closeDir(instance: *Instance, handle: DirectoryHandle) void {
            return instance.vtable.closeDirFn(instance, handle);
        }
        pub fn createEnumerator(instance: *Instance, handle: DirectoryHandle) CreateEnumeratorError!*Enumerator {
            return instance.vtable.createEnumeratorFn(instance, handle);
        }
        pub fn destroyEnumerator(instance: *Instance, enumerator: *Enumerator) void {
            return instance.vtable.destroyEnumeratorFn(instance, enumerator);
        }
        pub fn delete(instance: *Instance) !void {
            return instance.vtable.deleteFn(instance);
        }
        pub fn mkdir(instance: *Instance) !void {
            return instance.vtable.mkdirFn(instance);
        }
        pub fn statEntry(instance: *Instance) !void {
            return instance.vtable.statEntryFn(instance);
        }
        pub fn nearMove(instance: *Instance) !void {
            return instance.vtable.nearMoveFn(instance);
        }
        pub fn farMove(instance: *Instance) !void {
            return instance.vtable.farMoveFn(instance);
        }
        pub fn copy(instance: *Instance) !void {
            return instance.vtable.copyFn(instance);
        }
        pub fn openFile(instance: *Instance, dir: DirectoryHandle, path: []const u8, access: ashet.abi.FileAccess, mode: ashet.abi.FileMode) !FileHandle {
            return instance.vtable.openFileFn(instance, dir, path, access, mode);
        }
        pub fn closeFile(instance: *Instance, handle: FileHandle) void {
            return instance.vtable.closeFileFn(instance, handle);
        }
        pub fn flushFile(instance: *Instance, handle: FileHandle) !void {
            return instance.vtable.flushFileFn(instance, handle);
        }
        pub fn read(instance: *Instance, handle: FileHandle, offset: u64, buffer: []u8) !usize {
            return instance.vtable.readFn(instance, handle, offset, buffer);
        }
        pub fn write(instance: *Instance, handle: FileHandle, offset: u64, buffer: []const u8) !usize {
            return instance.vtable.writeFn(instance, handle, offset, buffer);
        }
        pub fn statFile(instance: *Instance, handle: FileHandle) !ashet.abi.FileInfo {
            return instance.vtable.statFileFn(instance, handle);
        }
        pub fn resize(instance: *Instance, handle: FileHandle, length: u64) !void {
            return instance.vtable.resizeFn(instance, handle, length);
        }

        pub const VTable = struct {
            openDirFromRootFn: *const fn (*Instance, []const u8) OpenDirAbsError!DirectoryHandle,
            openDirRelativeFn: *const fn (*Instance, DirectoryHandle, []const u8) OpenDirRelError!DirectoryHandle,
            closeDirFn: *const fn (*Instance, DirectoryHandle) void,
            createEnumeratorFn: *const fn (*Instance, DirectoryHandle) CreateEnumeratorError!*Enumerator,
            destroyEnumeratorFn: *const fn (*Instance, *Enumerator) void,
            deleteFn: *const fn (*Instance) void,
            mkdirFn: *const fn (*Instance) void,
            statEntryFn: *const fn (*Instance) void,
            nearMoveFn: *const fn (*Instance) void,
            farMoveFn: *const fn (*Instance) void,
            copyFn: *const fn (*Instance) void,
            openFileFn: *const fn (*Instance, DirectoryHandle, []const u8, ashet.abi.FileAccess, ashet.abi.FileMode) OpenFileError!FileHandle,
            closeFileFn: *const fn (*Instance, FileHandle) void,
            flushFileFn: *const fn (*Instance, FileHandle) FlushFileError!void,
            readFn: *const fn (*Instance, FileHandle, offset: u64, buffer: []u8) ReadError!usize,
            writeFn: *const fn (*Instance, FileHandle, offset: u64, buffer: []const u8) WriteError!usize,
            statFileFn: *const fn (*Instance, FileHandle) StatFileError!ashet.abi.FileInfo,
            resizeFn: *const fn (*Instance, FileHandle, u64) ResizeError!void,
        };
    };

    pub const Enumerator = struct {
        instance: *Instance,
        vtable: *const VTable,

        pub fn reset(inst: *Enumerator) ResetEnumeratorError!void {
            return inst.vtable.resetFn(inst);
        }
        pub fn next(inst: *Enumerator) EnumerateError!?ashet.abi.FileInfo {
            return inst.vtable.nextFn(inst);
        }

        pub const VTable = struct {
            resetFn: *const fn (*Enumerator) ResetEnumeratorError!void,
            nextFn: *const fn (*Enumerator) EnumerateError!?ashet.abi.FileInfo,
        };
    };
};

pub const SerialPort = struct {
    pub const WriteMode = enum { blocking, only_fifo };

    writeFn: *const fn (*Driver, msg: []const u8, mode: WriteMode) usize,

    pub fn poll(idev: *SerialPort, msg: []const u8, mode: WriteMode) void {
        idev.writeFn(resolveDriver(.serial, idev), msg, mode);
    }
};

pub const NetworkInterface = ashet.network.NetworkInterface;

const virtio = @import("virtio");

pub const VirtIoConfiguration = struct {
    base: usize,
    max_count: usize,
    desc_size: usize,
};

/// Scans a memory area for virtio devices and installs all found device drivers.
pub fn scanVirtioDevices(allocator: std.mem.Allocator, comptime cfg: VirtIoConfiguration) !void {
    const virtio_base: [*]align(0x200) volatile virtio.ControlRegs = @ptrFromInt(cfg.base);

    if (virtio_base[0].magic != virtio.ControlRegs.magic) {
        @panic("not virt platform!");
    }

    logger.info("sizeof control regs: {}", .{@sizeOf(virtio.ControlRegs)});

    var reg_addr: usize = cfg.base;
    for (0..cfg.max_count) |_| {
        const regs: *align(0x200) volatile virtio.ControlRegs = @ptrFromInt(reg_addr);
        if (regs.magic != virtio.ControlRegs.magic)
            break;
        reg_addr += cfg.desc_size;

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
    const device: *T = try T.init(allocator, regs);
    install(&device.driver);
}

pub fn installBuiltinDrivers() void {
    install(&filesystem.AshetFS.driver);
    install(&filesystem.VFAT.driver);
}
