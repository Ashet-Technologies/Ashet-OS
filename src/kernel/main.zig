const std = @import("std");
const hal = @import("hal");

export fn ashet_kernelMain() void {
    memory.initialize();

    hal.initialize();

    hal.serial.write(.COM1, "Hello, World!\r\n");

    hal.serial.write(.COM1, &runtime_string);

    while (true) {
        //
    }
}

var runtime_string = "Hello, well initialized RAM!\r\n".*;

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

pub const memory = struct {
    pub const Section = struct {
        offset: u32,
        length: u32,
    };

    extern const __kernel_flash_start: anyopaque align(4);
    extern const __kernel_flash_end: anyopaque align(4);
    extern const __kernel_data_start: anyopaque align(4);
    extern const __kernel_data_end: anyopaque align(4);
    extern const __kernel_bss_start: anyopaque align(4);
    extern const __kernel_bss_end: anyopaque align(4);

    const BitMap = std.bit_set.ArrayBitSet(u32, hal.memory.ram.length / 4096);

    fn initialize() void {
        const flash_start = @ptrToInt(&__kernel_flash_start);
        const flash_end = @ptrToInt(&__kernel_flash_end);
        const data_start = @ptrToInt(&__kernel_data_start);
        const data_end = @ptrToInt(&__kernel_data_end);
        const bss_start = @ptrToInt(&__kernel_bss_start);
        const bss_end = @ptrToInt(&__kernel_bss_end);

        std.log.info("flash_start = 0x{X:0>8}", .{flash_start});
        std.log.info("flash_end   = 0x{X:0>8}", .{flash_end});
        std.log.info("data_start  = 0x{X:0>8}", .{data_start});
        std.log.info("data_end    = 0x{X:0>8}", .{data_end});
        std.log.info("bss_start   = 0x{X:0>8}", .{bss_start});
        std.log.info("bss_end     = 0x{X:0>8}", .{bss_end});

        const data_size = data_end - data_start;
        const bss_size = bss_end - bss_start;

        std.log.info("data_size   = 0x{X:0>8}", .{data_size});
        std.log.info("bss_size    = 0x{X:0>8}", .{bss_size});

        std.mem.copy(
            u32,
            @intToPtr([*]u32, data_start)[0 .. data_size / 4],
            @intToPtr([*]u32, flash_end)[0 .. data_size / 4],
        );
        std.mem.set(u32, @intToPtr([*]u32, bss_start)[0 .. bss_size / 4], 0);
    }
};

const Debug = struct {
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
