const std = @import("std");
const hal = @import("hal");

pub const abi = @import("ashet-abi");
pub const video = @import("components/video.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const storage = @import("components/storage.zig");
pub const memory = @import("components/memory.zig");
pub const serial = @import("components/serial.zig");
pub const scheduler = @import("components/scheduler.zig");
pub const syscalls = @import("components/syscalls.zig");
pub const filesystem = @import("components/filesystem.zig");
pub const input = @import("components/input.zig");
// pub const splash_screen = @import("components/splash_screen.zig");
pub const multi_tasking = @import("components/multi_tasking.zig");
pub const ui = @import("components/ui.zig");
pub const apps = @import("components/apps.zig");

export fn ashet_kernelMain() void {
    if (@import("builtin").target.os.tag != .freestanding)
        return; // don't include this on an OS!

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

    input.initialize();

    if (video.is_flush_required) {
        // if the HAL requires regular flushing of the screen,
        // we start a thread here that will do this.
        const thread = try scheduler.Thread.spawn(periodicScreenFlush, null, .{});
        try thread.setName("video.flush");
        try thread.start();
        thread.detach();
    }

    syscalls.initialize();

    try ui.start();

    scheduler.start();

    // All tasks stopped, what should we do now?
    std.log.warn("All threads stopped. System is now halting.", .{});
}

pub const global_hotkeys = struct {
    pub fn handle(event: abi.KeyboardEvent) bool {
        if (!event.pressed)
            return false;
        if (event.modifiers.alt) {
            // const SwitchGroup = struct { key: abi.KeyCode, screen: multi_tasking.Screen };
            // const switch_groups = [10]SwitchGroup{
            //     .{ .key = .f1, .screen = .@"1" },
            //     .{ .key = .f2, .screen = .@"2" },
            //     .{ .key = .f3, .screen = .@"3" },
            //     .{ .key = .f4, .screen = .@"4" },
            //     .{ .key = .f5, .screen = .@"5" },
            //     .{ .key = .f6, .screen = .@"6" },
            //     .{ .key = .f7, .screen = .@"7" },
            //     .{ .key = .f8, .screen = .@"8" },
            //     .{ .key = .f9, .screen = .@"9" },
            //     .{ .key = .f10, .screen = .@"10" },
            // };

            // for (switch_groups) |grp| {
            //     if (event.key == grp.key) {
            //         multi_tasking.selectScreen(grp.screen) catch |err| std.log.err("failed to switch to screen {s}: {s}", .{ @tagName(grp.screen), @errorName(err) });
            //         return true;
            //     }
            // }
        }
        return false;
    }
};

fn periodicScreenFlush(_: ?*anyopaque) callconv(.C) u32 {
    while (true) {
        video.flush();

        // TODO: replace with actual waiting code instead of burning up all CPU
        scheduler.yield();
    }
}

var runtime_data_string = "Hello, well initialized .data!\r\n".*;
var runtime_sdata_string = "Hello, well initialized .sdata!\r\n".*;

extern fn hang() callconv(.C) noreturn;

export fn handleTrap() callconv(.C) noreturn {
    @panic("unhandled trap");
}

comptime {
    if (@import("builtin").target.os.tag == .freestanding) {
        // don't include this on an OS!
        const target = @import("builtin").target.cpu.arch;
        switch (target) {
            .riscv32 => asm (
                \\.section .text._start
                \\.global _start
                \\_start:
                \\  la   sp, kernel_stack // defined in linker script 
                \\
                \\  la     t0, handleTrap
                \\  csrw   mtvec, t0
                \\
                \\  call ashet_kernelMain
                \\
                \\  li      t0, 0x38 
                \\  csrc    mstatus, t0
                \\
                \\hang:
                \\  wfi
                \\  j hang
                \\
            ),

            .x86 => asm (
                \\.section .text._start
                \\.global _start
                \\_start:
                \\  mov kernel_stack, %esp // defined in linker script 
                \\
                \\  call ashet_kernelMain
                \\
                \\hang:
                \\  cli
                \\  jmp hang
                \\
            ),

            else => @compileError(std.fmt.comptimePrint("{s} is not a supported platform", .{@tagName(target)})),
        }
    }
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
    switch (scope) {
        .fatfs, .filesystem => return,
        else => {},
    }

    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    Debug.writer().print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}

extern var kernel_stack: anyopaque;
extern var kernel_stack_start: anyopaque;

pub fn panic(message: []const u8, maybe_error_trace: ?*std.builtin.StackTrace, maybe_return_address: ?usize) noreturn {
    @setCold(true);
    _ = maybe_return_address;
    _ = maybe_error_trace;

    const sp = asm (""
        : [sp] "={sp}" (-> usize),
    );

    var writer = Debug.writer();

    writer.writeAll("\r\n") catch {};
    writer.writeAll("=========================================================================\r\n") catch {};
    writer.writeAll("Kernel Panic: ") catch {};
    writer.writeAll(message) catch {};
    writer.writeAll("\r\n") catch {};
    writer.writeAll("=========================================================================\r\n") catch {};
    writer.writeAll("\r\n") catch {};

    writer.print("return address:\r\n      0x{X:0>8}\r\n\r\n", .{@returnAddress()}) catch {};

    {
        var stack_end: usize = @ptrToInt(&kernel_stack);
        var stack_start: usize = @ptrToInt(&kernel_stack_start);

        if (scheduler.Thread.current()) |thread| {
            stack_end = @ptrToInt(thread.getBasePointer());
            stack_start = stack_end - memory.page_size * thread.num_pages;
        }

        std.debug.assert(stack_end > stack_start);

        const stack_size: usize = stack_end - stack_start;

        writer.print("stack usage:\r\n", .{}) catch {};

        writer.print("  low:     0x{X:0>8}\r\n", .{stack_start}) catch {};
        writer.print("  pointer: 0x{X:0>8}\r\n", .{sp}) catch {};
        writer.print("  high:    0x{X:0>8}\r\n", .{stack_end}) catch {};
        writer.print("  size:    {d:.3}\r\n", .{std.fmt.fmtIntSizeBin(stack_size)}) catch {};

        if (sp > stack_end) {
            // stack underflow
            writer.print("  usage:   UNDERFLOW by {} bytes!\r\n", .{
                sp - stack_end,
            }) catch {};
        } else if (sp <= stack_start) {
            // stack overflow
            writer.print("  usage:   OVERFLOW by {} bytes!\r\n", .{
                stack_start - sp,
            }) catch {};
        } else {
            // stack nominal
            writer.print("  usage:   {d}%\r\n", .{
                100 - (100 * (sp - stack_start)) / stack_size,
            }) catch {};
        }
        writer.writeAll("\r\n") catch {};
    }

    if (@import("builtin").mode == .Debug) {
        if (scheduler.Thread.current()) |thread| {
            writer.print("current thread:\r\n", .{}) catch {};
            writer.print("  [!] {}\r\n\r\n", .{thread}) catch {};
        }

        writer.writeAll("waiting threads:\r\n") catch {};
        var index: usize = 0;
        var queue = scheduler.ThreadIterator.init();
        while (queue.next()) |thread| : (index += 1) {
            writer.print("  [{}] {}\r\n", .{ index, thread }) catch {};
        }
        writer.writeAll("\r\n") catch {};
    }

    {
        writer.writeAll("stack trace:\r\n") catch {};
        var index: usize = 0;
        var it = std.debug.StackIterator.init(@returnAddress(), null);
        while (it.next()) |addr| : (index += 1) {
            writer.print("{d: >4}: 0x{X:0>8}\r\n", .{ index, addr }) catch {};
        }
    }

    writer.writeAll("\r\n") catch {};

    hang();
}

test {
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
}
