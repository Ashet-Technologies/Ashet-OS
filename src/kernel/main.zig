const std = @import("std");
const hal = @import("hal");
const fatfs = @import("fatfs");

pub const abi = @import("ashet-abi");
pub const video = @import("components/video.zig");
pub const console = @import("components/console.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const storage = @import("components/storage.zig");
pub const memory = @import("components/memory.zig");
pub const serial = @import("components/serial.zig");
pub const scheduler = @import("components/scheduler.zig");
pub const syscalls = @import("components/syscalls.zig");

var filesystem: fatfs.FileSystem = undefined;

var root_disk: Disk = .{};

export fn ashet_kernelMain() void {
    // Populate RAM with the right sections, and compute how much dynamic memory we have available
    memory.initialize();

    // Initialize scheduler before HAL as it doesn't require anything except memory pages for thread
    // storage, queues and stacks.
    scheduler.initialize();

    // Initialize the hardware into a well-defined state. After this, we can safely perform I/O ops.
    hal.initialize();

    main() catch |err| {
        std.log.err("main() failed with {}", .{err});
        @panic("system failure");
    };
}

fn main() !void {
    hal.serial.write(.COM1, "Hello, World!\r\n");

    hal.serial.write(.COM1, &runtime_data_string);
    hal.serial.write(.COM1, &runtime_sdata_string);

    // var rng = std.rand.DefaultPrng.init(0x1337);
    // while (true) {
    //     const num = rng.random().intRangeLessThan(u32, 1, 32);
    //     const pages = memory.allocPages(num) catch {
    //         std.log.info("out of memory when allocating {} pages", .{num});

    //         break;
    //     };
    //     std.log.info("allocated some pages: {}+{}", .{ pages, num });
    //     memory.freePages(pages, rng.random().intRangeAtMost(u32, 0, num)); // leaky boi
    // }

    // memory.debug.dumpPageMap();

    // video.setMode(.text);
    // console.clear();

    // inline for ("Hello, World!") |c, i| {
    //     console.set(51 + i, 31, c, 0xD5);
    // }

    // console.write("The line printer\r\nprints two lines.\r\n");

    // for ("Very long string in which we print some") |char, i| {
    //     console.writer().print("{d:0>2}: {c}\r\n", .{ i, char }) catch unreachable;
    // }

    {
        var devices = storage.enumerate();
        while (devices.next()) |dev| {
            std.log.info("device: {s}, present={}, block count={}, size={}", .{
                dev.name,
                dev.isPresent(),
                dev.blockCount(),
                std.fmt.fmtIntSizeBin(dev.byteSize()),
            });

            if (root_disk.blockdev == null) {
                root_disk.blockdev = dev;
                fatfs.disks[0] = &root_disk.interface;
            }
        }
    }

    if (root_disk.blockdev == null) {
        @panic("no root file system");
    }

    try filesystem.mount("0:", true);
    defer fatfs.FileSystem.unmount("0:") catch |e| std.log.err("failed to unmount filesystem: {s}", .{@errorName(e)});

    if (video.is_flush_required) {
        // if the HAL requires regular flushing of the screen,
        // we start a thread here that will do this.
        const thread = scheduler.Thread.spawn(periodicScreenFlush, null, null) catch @panic("could not create screen updater thread.");
        try thread.start();
        thread.detach();
    }

    syscalls.initialize();

    console.clear();
    video.setMode(.text);

    {
        try console.writer().writeAll("Available apps:\r\n");

        var dir = try fatfs.Dir.open("/apps");
        defer dir.close();

        while (try dir.next()) |ent| {
            const name = std.fmt.fmtSliceEscapeUpper(std.mem.sliceTo(&ent.fname, 0));
            std.log.info("entry: {{ fsize={}, fdate={}, ftime={}, fattrib={}, altname='{}', fname='{}' }}", .{
                ent.fsize,
                ent.fdate,
                ent.ftime,
                ent.fattrib,
                std.fmt.fmtSliceEscapeUpper(std.mem.sliceTo(&ent.altname, 0)),
                name,
            });
            try console.writer().print("- {s}\r\n", .{name});
        }
    }

    try console.writer().writeAll("Starting app \"shell\"...\r\n");

    // Start "init" process
    {
        const app_file = "0:/apps/shell/code";
        const stat = try fatfs.stat(app_file);

        const proc_byte_size = stat.fsize;

        const process_memory = @as([]align(memory.page_size) u8, @intToPtr([*]align(memory.page_size) u8, 0x80800000)[0..std.mem.alignForward(proc_byte_size, memory.page_size)]);

        const app_pages = memory.ptrToPage(process_memory.ptr) orelse unreachable;
        const proc_size = memory.getRequiredPages(process_memory.len);

        {
            var i: usize = 0;
            while (i < proc_size) : (i += 1) {
                if (!memory.isFree(app_pages + i)) {
                    @panic("app memory is not free");
                }
            }
            i = 0;
            while (i < proc_size) : (i += 1) {
                memory.markUsed(app_pages + i);
            }
        }

        {
            var file = try fatfs.File.openRead(app_file);
            defer file.close();

            try file.reader().readNoEof(process_memory[0..proc_byte_size]);
        }

        const thread = try scheduler.Thread.spawn(@ptrCast(scheduler.ThreadFunction, process_memory.ptr), null, null);
        errdefer thread.kill();

        try thread.start();
    }

    scheduler.start();

    // All tasks stopped, what should we do now?
    std.log.warn("All threads stopped. System is now halting.", .{});
}

fn periodicScreenFlush(_: ?*anyopaque) callconv(.C) u32 {
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        video.flush();

        // TODO: replace with actual waiting code instead of burning up all CPU
        scheduler.yield();
    }

    return 0;
}

var runtime_data_string = "Hello, well initialized .data!\r\n".*;
var runtime_sdata_string = "Hello, well initialized .sdata!\r\n".*;

extern fn hang() callconv(.C) noreturn;

comptime {
    asm (
        \\.section .text._start
        \\.global _start
        \\_start:
        \\  la   sp, kernel_stack // defined in linker script 
        \\
        \\  call ashet_kernelMain
        \\
        \\  li      t0, 0x38 
        \\  csrc    mstatus, t0
        \\
        \\hang:
        \\wfi
        \\  j hang
        \\
    );
}

pub const Debug = struct {
    const Error = error{};
    fn write(port: hal.serial.Port, bytes: []const u8) Error!usize {
        hal.serial.write(port, bytes);
        return bytes.len;
    }

    const Writer = std.io.Writer(hal.serial.Port, Error, write);

    pub fn writer() Writer {
        return Writer{ .context = .COM1 };
    }
};

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    Debug.writer().print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}

pub fn panic(message: []const u8, maybe_stack_trace: ?*std.builtin.StackTrace) noreturn {
    _ = maybe_stack_trace;

    var writer = Debug.writer();

    writer.writeAll("\r\n") catch {};
    writer.writeAll("=========================================================================\r\n") catch {};
    writer.writeAll("Kernel Panic: ") catch {};
    writer.writeAll(message) catch {};
    writer.writeAll("\r\n") catch {};
    writer.writeAll("=========================================================================\r\n") catch {};
    writer.writeAll("\r\n") catch {};

    writer.print("return address: 0x{X:0>8}\r\n", .{@returnAddress()}) catch {};

    if (maybe_stack_trace) |stack_trace| {
        writer.print("{}\r\n", .{stack_trace}) catch {};
    }

    hang();
}

pub const Disk = struct {
    const logger = std.log.scoped(.disk);
    const sector_size = 512;

    interface: fatfs.Disk = fatfs.Disk{
        .getStatusFn = getStatus,
        .initializeFn = initialize,
        .readFn = read,
        .writeFn = write,
        .ioctlFn = ioctl,
    },
    blockdev: ?storage.BlockDevice = null,

    pub fn getStatus(interface: *fatfs.Disk) fatfs.Disk.Status {
        const self = @fieldParentPtr(Disk, "interface", interface);
        return fatfs.Disk.Status{
            .initialized = (self.blockdev != null),
            .disk_present = if (self.blockdev) |dev| dev.isPresent() else false,
            .write_protected = false,
        };
    }

    pub fn initialize(interface: *fatfs.Disk) fatfs.Disk.Error!fatfs.Disk.Status {
        const self = @fieldParentPtr(Disk, "interface", interface);

        return self.interface.getStatus();
    }

    pub fn read(interface: *fatfs.Disk, buff: [*]u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        logger.info("read({*}, {}, {})", .{ buff, sector, count });

        var dev = self.blockdev orelse return error.IoError;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const off = i * sector_size;
            const mem = @alignCast(4, buff[off .. off + sector_size]);
            dev.readBlock(sector + i, mem) catch return error.IoError;
        }
    }

    pub fn write(interface: *fatfs.Disk, buff: [*]const u8, sector: fatfs.LBA, count: c_uint) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);

        logger.info("write({*}, {}, {})", .{ buff, sector, count });

        var dev = self.blockdev orelse return error.IoError;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const off = (sector + i) * sector_size;
            const mem = @alignCast(4, buff[off .. off + sector_size]);
            dev.writeBlock(sector + i, mem) catch return error.IoError;
        }
    }

    pub fn ioctl(interface: *fatfs.Disk, cmd: fatfs.IoCtl, buff: [*]u8) fatfs.Disk.Error!void {
        const self = @fieldParentPtr(Disk, "interface", interface);
        if (self.blockdev) |dev| {
            _ = buff;
            _ = dev;
            switch (cmd) {
                .sync => {
                    //
                },

                else => return error.InvalidParameter,
            }
        } else {
            return error.DiskNotReady;
        }
    }
};
