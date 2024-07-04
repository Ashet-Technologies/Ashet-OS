const std = @import("std");
const ashet = @import("../main.zig");
const machine = @import("machine");
const logger = std.log.scoped(.memory);

pub const protection = @import("memory/protection.zig");

pub const Section = struct {
    offset: u32,
    length: u32,
};

pub const ProtectedRange = struct {
    base: u32,
    length: u32,
    protection: ashet.memory.protection.Protection,

    fn to_section(pr: ProtectedRange) Section {
        return .{
            .offset = pr.base,
            .length = pr.length,
        };
    }
};

pub const USizeIndex = @Type(.{
    .Int = .{
        .bits = std.math.log2_int_ceil(u32, @bitSizeOf(usize)),
        .signedness = .unsigned,
    },
});

const RawPageStorageManager = @import("memory/RawPageStorageManager.zig");

pub const page_size = ashet.platform.page_size;

var page_manager: RawPageStorageManager = undefined;

extern const kernel_stack_start: u8 align(4);
extern const kernel_stack: u8 align(4);
extern const __kernel_flash_start: u8 align(4);
extern const __kernel_flash_end: u8 align(4);
extern const __kernel_data_start: u8 align(4);
extern const __kernel_data_end: u8 align(4);
extern const __kernel_bss_start: u8 align(4);
extern const __kernel_bss_end: u8 align(4);

pub const MemorySections = struct {
    data: bool,
    bss: bool,
};

pub fn get_protected_ranges() []const ProtectedRange {
    const Static = struct {
        var ranges: [5]ProtectedRange = undefined;
    };

    const flash_start = @intFromPtr(&__kernel_flash_start);
    const flash_end = @intFromPtr(&__kernel_flash_end);
    const stack_start = @intFromPtr(&kernel_stack_start);
    const stack_end = @intFromPtr(&kernel_stack);
    const data_start = @intFromPtr(&__kernel_data_start);
    const data_end = @intFromPtr(&__kernel_data_end);
    const bss_start = @intFromPtr(&__kernel_bss_start);
    const bss_end = @intFromPtr(&__kernel_bss_end);

    const linear_memory = ashet.machine.getLinearMemoryRegion();

    Static.ranges = [_]ProtectedRange{
        .{ .base = linear_memory.offset, .length = linear_memory.length, .protection = .read_write },
        .{ .base = flash_start, .length = flash_end - flash_start, .protection = .read_only },
        .{ .base = data_start, .length = data_end - data_start, .protection = .read_write },
        .{ .base = bss_start, .length = bss_end - bss_start, .protection = .read_write },
        .{ .base = stack_start, .length = stack_end - kernel_stack_start, .protection = .read_write },
    };

    return &Static.ranges;
}

/// First stage in memory initialization:
/// Copy the `.data` section into RAM, and zero out `.bss`.
/// This is needed to have all globals have a well-defined state.
pub fn loadKernelMemory(comptime sections: MemorySections) void {
    ashet.Debug.setTraceLoc(@src());

    if (sections.bss) {
        ashet.Debug.setTraceLoc(@src());

        const bss_start = @intFromPtr(&__kernel_bss_start);
        const bss_end = @intFromPtr(&__kernel_bss_end);

        const bss_size = bss_end - bss_start;

        ashet.Debug.setTraceLoc(@src());

        logger.debug("bss_start   = 0x{X:0>8}", .{bss_start});
        logger.debug("bss_end     = 0x{X:0>8}", .{bss_end});
        logger.debug("bss_size    = 0x{X:0>8}", .{bss_size});

        ashet.Debug.setTraceLoc(@src());

        @memset(@as([*]u32, @ptrFromInt(bss_start))[0 .. bss_size / 4], 0);

        ashet.Debug.setTraceLoc(@src());
    }

    if (sections.data) {
        ashet.Debug.setTraceLoc(@src());

        // const flash_start = @ptrToInt(&__kernel_flash_start);
        const flash_end = @intFromPtr(&__kernel_flash_end);
        const data_start = @intFromPtr(&__kernel_data_start);
        const data_end = @intFromPtr(&__kernel_data_end);

        const data_size = data_end - data_start;

        ashet.Debug.setTraceLoc(@src());

        // logger.debug("flash_start = 0x{X:0>8}", .{flash_start});
        logger.debug("flash_end   = 0x{X:0>8}", .{flash_end});
        logger.debug("data_start  = 0x{X:0>8}", .{data_start});
        logger.debug("data_end    = 0x{X:0>8}", .{data_end});
        logger.debug("data_size   = 0x{X:0>8}", .{data_size});

        ashet.Debug.setTraceLoc(@src());

        @memcpy(
            @as([*]u32, @ptrFromInt(data_start))[0 .. data_size / 4],
            @as([*]u32, @ptrFromInt(flash_end))[0 .. data_size / 4],
        );

        ashet.Debug.setTraceLoc(@src());
    }
}

/// Initialize the linear system memory and allocators.
pub fn initializeLinearMemory() void {
    ashet.Debug.setTraceLoc(@src());

    // compute and initialize the memory map
    ashet.Debug.setTraceLoc(@src());

    const memory_ranges = get_protected_ranges();

    const linear_memory_region = memory_ranges[0].to_section();
    const kernel_memory_regions = memory_ranges[1..];

    // logger.info("linear memory starts at 0x{X:0>8} and is {d:.3} ({} pages) large", .{
    //     linear_memory_region.base,
    //     std.fmt.fmtIntSizeBin(linear_memory_region.length),
    //     linear_memory_region.length / page_size,
    // });
    ashet.Debug.setTraceLoc(@src());
    logger.info("linear memory starts at 0x{X:0>8} and is {} ({} pages) large", .{
        linear_memory_region.offset,
        linear_memory_region.length,
        linear_memory_region.length / page_size,
    });

    // make sure we have at least some pages to play with.
    ashet.Debug.setTraceLoc(@src());
    if (linear_memory_region.length < 8 * page_size) {
        @panic("not enough linear memory.");
    }

    // Now that we're ready for action and the kernel has all predefined variables loaded,
    // let's initialize linear memory management
    ashet.Debug.setTraceLoc(@src());
    page_manager = RawPageStorageManager.init(linear_memory_region);

    // mark all kernel regions that overlap with the linear memory
    // as "used", so we don't allocate them later.

    for (kernel_memory_regions, 0..) |region, region_id| {
        logger.debug("disable region {}", .{region_id});
        ashet.Debug.setTraceLoc(@src());

        const base_ptr = @as([*]allowzero u8, @ptrFromInt(region.base));
        var i: usize = 0;
        while (i < region.length) : (i += page_size) {
            if (page_manager.ptrToPage(base_ptr + i)) |page| {
                page_manager.markUsed(page);
                logger.debug("mark {} used", .{page});
            }
        }
    }

    ashet.Debug.setTraceLoc(@src());
    const free_memory = page_manager.getFreePageCount();

    // TODO: logger.info("free ram: {:.2} ({}/{} pages)", .{ std.fmt.fmtIntSizeBin(page_size * free_memory), free_memory, page_manager.pageCount() });
    ashet.Debug.setTraceLoc(@src());
    logger.info("free ram: {} ({}/{} pages)", .{ page_size * free_memory, free_memory, page_manager.pageCount() });
}

pub fn isPointerToKernelStack(ptr: anytype) bool {
    const stack_end: usize = @intFromPtr(&kernel_stack);
    const stack_start: usize = @intFromPtr(&kernel_stack_start);

    const addr = @intFromPtr(ptr);

    return (addr >= stack_start) and (addr < stack_end);
}

pub const debug = struct {
    pub fn getPageCount() u32 {
        return page_manager.pageCount();
    }
    pub fn getFreePageCount() u32 {
        return page_manager.getFreePageCount();
    }

    pub fn dumpPageMap() void {
        var writer = ashet.Debug.writer();

        var free_memory: usize = 0;

        const items_per_line = 64;

        var i: usize = 0;
        while (i < page_manager.pageCount()) : (i += 1) {
            if (i % items_per_line == 0) {
                if (i > 0) {
                    writer.writeAll("]") catch {};
                }
                writer.print("\r\n0x{X:0>8}: [", .{page_manager.region.offset + i * page_size}) catch {};
            }
            if (page_manager.isFree(@as(RawPageStorageManager.Page, @enumFromInt(i)))) {
                free_memory += page_size;
                writer.writeAll(" ") catch {};
            } else {
                writer.writeAll("#") catch {};
            }
        }

        writer.writeAll("]\r\n") catch {};

        // for (page_manager.bitmap(), 0..) |item, index| {
        //     writer.print("{X:0>4}: {b:0>32}\r\n", .{ index, item }) catch {};
        // }

        writer.print("free ram: {} ({}/{} pages)\r\n", .{ free_memory, free_memory / page_size, page_manager.pageCount() }) catch {};
    }
};

pub const allocator = general_purpose_allocator_instance.allocator();
pub const page_allocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &PageAllocator.vtable,
};

var general_purpose_allocator_instance = std.heap.ArenaAllocator.init(page_allocator);
var page_allocator_instance: PageAllocator = .{};

const PageAllocator = struct {
    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };

    fn alloc(_: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;

        std.debug.assert(len > 0);
        if (len > std.math.maxInt(usize) - (page_size - 1)) {
            return null;
        }

        std.debug.assert(ptr_align <= std.math.log2(page_size));

        const aligned_len = std.mem.alignForward(usize, len, page_size);

        const alloc_page_count = page_manager.getRequiredPages(aligned_len);

        const page_slice = page_manager.allocPages(alloc_page_count) catch return null;

        return @as([*]align(page_size) u8, @ptrCast(page_manager.pageToPtr(page_slice.page)));
    }

    fn resize(
        _: *anyopaque,
        buf: []u8,
        buf_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn free(_: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;

        const buf_aligned_len = std.mem.alignForward(usize, buf.len, page_size);
        const ptr: *align(page_size) u8 = @ptrCast(@alignCast(buf.ptr));

        page_manager.freePages(RawPageStorageManager.PageSlice{
            .page = page_manager.ptrToPage(ptr) orelse @panic("invalid address in free!"),
            .len = @divExact(buf_aligned_len, page_size),
        });
    }
};

/// An allocator used for allocation/deletion of threads.
/// **DO NOT USE THE ALLOCATOR FOR ANYTHING ELSE**.
pub const ThreadAllocator = struct {
    pub fn alloc(len: usize) error{OutOfMemory}![]u8 {
        return if (ashet.memory.PageAllocator.alloc(undefined, len, 12, @returnAddress())) |ptr|
            ptr[0..len]
        else
            error.OutOfMemory;
    }

    pub fn free(buf: []u8) void {
        ashet.memory.PageAllocator.free(undefined, buf, 12, @returnAddress());
    }
};
