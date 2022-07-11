const std = @import("std");
const hal = @import("hal");

pub const abi = @import("ashet-abi");
pub const video = @import("components/video.zig");
pub const console = @import("components/console.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const storage = @import("components/storage.zig");
pub const memory = @import("components/memory.zig");
pub const serial = @import("components/serial.zig");
pub const scheduler = @import("components/scheduler.zig");
pub const syscalls = @import("components/syscalls.zig");
pub const filesystem = @import("components/filesystem.zig");

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
    filesystem.initialize();

    // hal.serial.write(.COM1, "Hello, World!\r\n");

    // hal.serial.write(.COM1, &runtime_data_string);
    // hal.serial.write(.COM1, &runtime_sdata_string);

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

    // {
    //     try console.writer().writeAll("Available apps:\r\n");

    //     var dir = try fatfs.Dir.open("/apps");
    //     defer dir.close();

    //     while (try dir.next()) |ent| {
    //         const name = std.fmt.fmtSliceEscapeUpper(std.mem.sliceTo(&ent.fname, 0));
    //         std.log.info("entry: {{ fsize={}, fdate={}, ftime={}, fattrib={}, altname='{}', fname='{}' }}", .{
    //             ent.fsize,
    //             ent.fdate,
    //             ent.ftime,
    //             ent.fattrib,
    //             std.fmt.fmtSliceEscapeUpper(std.mem.sliceTo(&ent.altname, 0)),
    //             name,
    //         });
    //         try console.writer().print("- {s}\r\n", .{name});
    //     }
    // }

    try console.writer().writeAll("Starting app \"shell\"...\r\n");

    // Start "init" process
    {
        const app_file = "PF0:/apps/shell/code";
        const stat = try filesystem.stat(app_file);

        const proc_byte_size = stat.size;

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
            var file = try filesystem.open(app_file, .read_only, .open_existing);
            defer filesystem.close(file);

            const len = try filesystem.read(file, process_memory[0..proc_byte_size]);
            if (len != proc_byte_size)
                @panic("could not read all bytes on one go!");
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
