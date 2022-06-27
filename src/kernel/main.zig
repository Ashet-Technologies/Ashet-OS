const std = @import("std");
const hal = @import("hal");

export fn ashet_kernelMain() void {
    // Populate RAM with the right sections
    memory.initialize();

    // Initialize all devices into a well-defined state
    hal.initialize();

    hal.serial.write(.COM1, "Hello, World!\r\n");

    hal.serial.write(.COM1, &runtime_string);

    // while (true) {
    //     const pages = memory.allocPages(7) catch break;
    //     std.log.info("allocated some pages: {}+4", .{pages});
    //     memory.freePages(pages, 7); // leaky boi
    // }

    // memory.debug.dumpPageMap();

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
    const BitMap = std.bit_set.ArrayBitSet(u32, page_count);

    pub const Section = struct {
        offset: u32,
        length: u32,
    };

    pub const page_size = 4096;
    pub const page_count = hal.memory.ram.length / page_size;

    var free_pages: BitMap = undefined;

    extern const __kernel_flash_start: anyopaque align(4);
    extern const __kernel_flash_end: anyopaque align(4);
    extern const __kernel_data_start: anyopaque align(4);
    extern const __kernel_data_end: anyopaque align(4);
    extern const __kernel_bss_start: anyopaque align(4);
    extern const __kernel_bss_end: anyopaque align(4);

    fn initialize() void {
        // First, populate all RAM sections from flash
        const flash_start = @ptrToInt(&__kernel_flash_start);
        const flash_end = @ptrToInt(&__kernel_flash_end);
        const data_start = @ptrToInt(&__kernel_data_start);
        const data_end = @ptrToInt(&__kernel_data_end);
        const bss_start = @ptrToInt(&__kernel_bss_start);
        const bss_end = @ptrToInt(&__kernel_bss_end);

        std.log.debug("flash_start = 0x{X:0>8}", .{flash_start});
        std.log.debug("flash_end   = 0x{X:0>8}", .{flash_end});
        std.log.debug("data_start  = 0x{X:0>8}", .{data_start});
        std.log.debug("data_end    = 0x{X:0>8}", .{data_end});
        std.log.debug("bss_start   = 0x{X:0>8}", .{bss_start});
        std.log.debug("bss_end     = 0x{X:0>8}", .{bss_end});

        const data_size = data_end - data_start;
        const bss_size = bss_end - bss_start;

        std.log.debug("data_size   = 0x{X:0>8}", .{data_size});
        std.log.debug("bss_size    = 0x{X:0>8}", .{bss_size});

        std.mem.copy(
            u32,
            @intToPtr([*]u32, data_start)[0 .. data_size / 4],
            @intToPtr([*]u32, flash_end)[0 .. data_size / 4],
        );
        std.mem.set(u32, @intToPtr([*]u32, bss_start)[0 .. bss_size / 4], 0);

        // compute the free memory map

        free_pages = BitMap.initEmpty();

        var free_memory: usize = 0;
        {
            const start_index = std.mem.alignForward(bss_end - hal.memory.ram.offset, page_size) / page_size;
            const end_index = std.mem.alignBackward(hal.memory.ram.length, page_size) / page_size;
            std.log.debug("freeing pages from {} to {}...", .{ start_index, end_index });

            var i: u32 = start_index;
            while (i < end_index) : (i += 1) {
                free_pages.set(i);
                free_memory += page_size;
            }
        }

        std.log.info("free ram: {:.2} ({}/{} pages)", .{ std.fmt.fmtIntSizeBin(free_memory), free_memory / page_size, page_count });
    }

    /// Allocates `count` physical pages and returns the page index.
    /// Use `pageToPtr` to obtain a physical pointer to it.
    /// Returned memory must be freed with `freePages` using the same `count` as in the `allocPages` call.
    pub fn allocPages(count: usize) error{OutOfMemory}!usize {
        if (count == 0) return error.OutOfMemory;
        if (count >= page_count) return error.OutOfMemory;

        var first_page = free_pages.findFirstSet() orelse return error.OutOfMemory;

        if (count == 1) {
            free_pages.unset(first_page);
            return first_page;
        }

        while (first_page < page_count - count) {
            var i: usize = 0;
            const ok = while (i < count) : (i += 1) {
                if (!free_pages.isSet(first_page + i))
                    break false;
            } else true;

            if (ok) {
                i = 0;
                while (i < count) : (i += 1) {
                    std.debug.assert(free_pages.isSet(first_page + i));
                    free_pages.unset(first_page + i);
                }
                return first_page;
            } else {
                first_page += (i + 1); // skip over all checked pages as well as the unset page
            }
        }

        return error.OutOfMemory;
    }

    /// Frees physical pages previously allocated with `allocPages`.
    pub fn freePages(first_page: usize, count: usize) void {
        std.debug.assert(first_page + count < page_count);
        var i = first_page;
        while (i < first_page + count) : (i += 1) {
            free_pages.set(i);
        }
    }

    fn ptrToPage(ptr: anytype) ?u32 {
        const offset = @ptrToInt(ptr);
        if (offset < hal.memory.ram.offset)
            return null;
        if (offset >= hal.memory.ram.offset + hal.memory.ram.length)
            return null;
        return (offset - hal.memory.ram.offset) / page_size;
    }

    fn pageToPtr(page: u32) ?*anyopaque {
        if (page >= page_count)
            return null;
        return @intToPtr(*anyopaque, hal.memory.ram.offset + page_size * page);
    }

    pub const debug = struct {
        pub fn dumpPageMap() void {
            var writer = Debug.writer();

            var free_memory: usize = 0;

            const items_per_line = 64;

            var i: usize = 0;
            while (i < page_count) : (i += 1) {
                if (i % items_per_line == 0) {
                    writer.print("]\n0x{X:0>4}: [", .{i}) catch {};
                }
                if (free_pages.isSet(i)) {
                    free_memory += page_count;
                    writer.writeAll(" ") catch {};
                } else {
                    writer.writeAll("#") catch {};
                }
            }

            writer.writeAll("]\n") catch {};

            writer.print("free ram: {:.2} ({}/{} pages)\n", .{ std.fmt.fmtIntSizeBin(free_memory), free_memory / page_size, page_count }) catch {};
        }
    };
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
