const std = @import("std");
const hal = @import("hal");

pub const video = @import("components/video.zig");
pub const console = @import("components/console.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const storage = @import("components/storage.zig");
pub const memory = @import("components/memory.zig");

export fn ashet_kernelMain() void {
    // Populate RAM with the right sections
    memory.initialize();

    // Initialize all devices into a well-defined state
    hal.initialize();

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

    video.setMode(.text);
    console.clear();

    inline for ("Hello, World!") |c, i| {
        console.set(51 + i, 31, c, 0xD5);
    }

    console.write("The line printer\r\nprints two lines.\r\n");

    for ("Very long string in which we print some") |char, i| {
        console.writer().print("{d:0>2}: {c}\r\n", .{ i, char }) catch unreachable;
    }

    if (video.is_present_required) {
        // start "present" kernel loop
        video.present(); // fire at least once for now…
    }

    // test flash chip via CFI
    {
        var devices = storage.enumerate();
        while (devices.next()) |dev| {
            std.log.info("device: {s}, present={}, block count={}, size={}", .{
                dev.name,
                dev.isPresent(),
                dev.blockCount(),
                std.fmt.fmtIntSizeBin(dev.byteSize()),
            });

            if (dev.isPresent()) {
                var block: [2048]u8 align(4) = undefined;
                dev.readBlock(0, block[0..dev.blockSize()]) catch @panic("failed to read first block!");

                var i: usize = 0;
                while (i < dev.blockSize()) : (i += 32) {
                    std.log.info("0x{X:0>4} | {}", .{
                        i,
                        std.fmt.fmtSliceHexUpper(block[i .. i + 32]),
                    });
                }

                std.mem.copy(u8, &block, "Hello from Ashet OS!\r\n\x00");

                dev.writeBlock(0, block[0..dev.blockSize()]) catch @panic("failed to write first block!");
            }
        }
    }

    while (true) {
        //
    }
}

var runtime_data_string = "Hello, well initialized .data!\r\n".*;
var runtime_sdata_string = "Hello, well initialized .sdata!\r\n".*;

extern fn hang() callconv(.C) noreturn;

comptime {
    asm (
        \\.section .text
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

    hang();
}
