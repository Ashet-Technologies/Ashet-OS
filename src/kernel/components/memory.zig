const std = @import("std");
const ashet = @import("../main.zig");
const machine = @import("machine");
const logger = std.log.scoped(.memory);

pub const protection = @import("memory/protection.zig");

pub const Range = struct {
    base: usize,
    length: usize,

    pub fn from_slice(slice: anytype) Range {
        const bytes = std.mem.sliceAsBytes(slice);
        return .{
            .base = @intFromPtr(bytes.ptr),
            .length = bytes.len,
        };
    }
};

pub const ProtectedRange = struct {
    base: u32,
    length: u32,
    protection: ashet.memory.protection.Protection,

    fn to_range(pr: ProtectedRange) Range {
        return .{
            .base = pr.base,
            .length = pr.length,
        };
    }
};

pub const KernelMemoryRange = struct {
    base: u32,
    length: u32,
    protection: ashet.memory.protection.Protection,
    name: []const u8,

    fn to_protected_range(km: KernelMemoryRange) Range {
        return .{
            .base = km.base,
            .length = km.length,
            .protection = km.protection,
        };
    }

    fn to_range(km: KernelMemoryRange) Range {
        return .{
            .base = km.base,
            .length = km.length,
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

extern const __kernel_stack_start: anyopaque align(4);
extern const __kernel_stack_end: anyopaque align(4);
extern const __kernel_flash_start: anyopaque align(4);
extern const __kernel_flash_end: anyopaque align(4);
extern const __kernel_data_start: anyopaque align(4);
extern const __kernel_data_end: anyopaque align(4);
extern const __kernel_bss_start: anyopaque align(4);
extern const __kernel_bss_end: anyopaque align(4);

pub const MemorySections = struct {
    data: bool,
    bss: bool,
};

pub fn get_protected_ranges() []const KernelMemoryRange {
    const Static = struct {
        var ranges: [5]KernelMemoryRange = undefined;
    };

    const flash_start = @intFromPtr(&__kernel_flash_start);
    const flash_end = @intFromPtr(&__kernel_flash_end);
    const stack_start = @intFromPtr(&__kernel_stack_start);
    const stack_end = @intFromPtr(&__kernel_stack_end);
    const data_start = @intFromPtr(&__kernel_data_start);
    const data_end = @intFromPtr(&__kernel_data_end);
    const bss_start = @intFromPtr(&__kernel_bss_start);
    const bss_end = @intFromPtr(&__kernel_bss_end);

    const linear_memory = ashet.machine.getLinearMemoryRegion();

    Static.ranges = [_]KernelMemoryRange{
        .{ .name = "linear", .base = linear_memory.base, .length = linear_memory.length, .protection = .read_write },
        .{ .name = "flash", .base = flash_start, .length = flash_end - flash_start, .protection = .read_only },
        .{ .name = "data", .base = data_start, .length = data_end - data_start, .protection = .read_write },
        .{ .name = "bss", .base = bss_start, .length = bss_end - bss_start, .protection = .read_write },
        .{ .name = "stack", .base = stack_start, .length = stack_end - stack_start, .protection = .read_write },
    };

    return &Static.ranges;
}

pub fn enable_page_manager_protection() void {
    page_manager.enable_page_manager_protection();
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
    // compute and initialize the memory map
    ashet.Debug.setTraceLoc(@src());

    const memory_ranges = get_protected_ranges();

    logger.info("kernel memory ranges:", .{});
    for (memory_ranges) |range| {
        logger.info("  {s: >8} [base=0x{X:0>8}, length=0x{X:0>8}, protection={s}]", .{
            range.name,
            range.base,
            range.length,
            @tagName(range.protection),
        });
    }

    const linear_memory_region = memory_ranges[0].to_range();
    const kernel_memory_regions = memory_ranges[1..];

    ashet.Debug.setTraceLoc(@src());
    logger.info("linear memory starts at 0x{X:0>8} and is {} ({} pages) large", .{
        linear_memory_region.base,
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
    logger.info("free ram: {} ({}/{} pages allocated)", .{ page_size * free_memory, free_memory, page_manager.pageCount() });
}

pub fn isPointerToKernelStack(ptr: anytype) bool {
    const stack_end: usize = @intFromPtr(&__kernel_stack_end);
    const stack_start: usize = @intFromPtr(&__kernel_stack_start);

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

        if (protection.is_enabled()) {
            writer.writeAll("Legend:\r\n") catch {};
            writer.writeAll("       free ok: ' ' bad mprot: '!'\r\n") catch {};
            writer.writeAll("  read-only ok: '□' bad mprot: '◇'\r\n") catch {};
            writer.writeAll(" read-write ok: '▣' bad mprot: '◈'\r\n") catch {};
            writer.writeAll("     no access: '\x1B[90m▓\x1B[0m'\r\n") catch {};
            writer.writeAll("   read access: '\x1B[93m▓\x1B[0m'\r\n") catch {};
            writer.writeAll("  write access: '\x1B[91m▓\x1B[0m'\r\n") catch {};
        } else {
            writer.writeAll("Legend:\r\n") catch {};
            writer.writeAll("       free: ' '\r\n") catch {};
            writer.writeAll("  allocated: '#'\r\n") catch {};
        }

        var i: usize = 0;
        while (i < page_manager.pageCount()) : (i += 1) {
            if (i % items_per_line == 0) {
                if (i > 0) {
                    writer.writeAll("]") catch {};
                }
                writer.print("\r\n0x{X:0>8}: [", .{page_manager.region.base + i * page_size}) catch {};
            }

            const page: RawPageStorageManager.Page = @enumFromInt(i);

            const is_free = page_manager.isFree(page);
            if (is_free) {
                free_memory += page_size;
            }

            const sigil = if (protection.is_enabled()) blk: {
                const info = protection.get_address_info(@intFromPtr(page_manager.pageToPtr(page)));

                writer.writeAll(
                    if (info.was_written)
                        "\x1B[91m" // write => red
                    else if (info.was_accessed)
                        "\x1B[93m" // read => yellow
                    else
                        "\x1B[90m", // untouched => gray
                ) catch {};

                break :blk switch (info.protection) {
                    .forbidden => if (is_free) " " else "!",
                    .read_only => if (!is_free) "□" else "◇",
                    .read_write => if (!is_free) "▣" else "◈",
                };
            } else if (is_free)
                " "
            else
                "#";

            writer.writeAll(sigil) catch {};
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
///
/// The important difference of this allocator to regular Zig allocators is
/// that it does never `undefine` the memory after `free`. This is required
/// for the scheduler to work properly!
///
/// **DO NOT USE THE ALLOCATOR FOR ANYTHING ELSE**.
pub const ThreadAllocator = struct {
    pub fn alloc(len: usize) error{OutOfMemory}![]u8 {
        return if (PageAllocator.alloc(undefined, len, 12, @returnAddress())) |ptr|
            ptr[0..len]
        else
            error.OutOfMemory;
    }

    pub fn free(buf: []u8) void {
        @memset(buf, 0x55); // scream differently than zig
        PageAllocator.free(undefined, buf, 12, @returnAddress());
    }
};

/// Computes the key size for the memory pool we
/// use to allocate elements of the given `size`.
pub fn align_pool_element_size(size: usize) usize {
    return std.mem.alignForward(usize, size, 32);
}

/// Returns a memory pool for `T`. This pool might be shared with
/// other types, which does not affect allocation qualities.
pub fn type_pool(comptime T: type) type {
    comptime {
        std.debug.assert(@alignOf(T) < @sizeOf(T));
    }
    return struct {
        const element_size = align_pool_element_size(@sizeOf(T));
        const element_alignment = @max(@alignOf(T), std.math.floorPowerOfTwo(usize, element_size));

        // TODO: Determine element alignment such that it doesn't waste *too* much memory, but also keeps the number of pools small!

        const backing_pool = sized_aligned_element_pool(element_size, element_alignment);

        var allocated_items: usize = 0;

        /// Number of active items in the pool.
        pub fn get_count() usize {
            return allocated_items;
        }

        /// Allocates a new item.
        pub fn alloc() error{OutOfMemory}!*align(element_alignment) T {
            const item = try backing_pool.alloc();
            allocated_items += 1;
            return @ptrCast(item);
        }

        /// Frees a previously allocated item.
        pub fn free(res: *T) void {
            std.debug.assert(allocated_items > 0);
            backing_pool.free(@ptrCast(@alignCast(res)));
            allocated_items -= 1;
        }
    };
}

/// Memory pool with elements of equal size.
pub fn sized_element_pool(comptime element_size: usize) type {
    const alignment = std.math.floorPowerOfTwo(usize, element_size);
    return sized_aligned_element_pool(element_size, alignment);
}

/// A memory pool with elements of `element_size` that are aligned to `alignment`.
pub fn sized_aligned_element_pool(comptime element_size: usize, comptime alignment: usize) type {
    std.debug.assert(std.math.isPowerOfTwo(alignment));
    std.debug.assert(alignment <= element_size);
    return struct {
        pub const Buffer = [element_size]u8;

        pub const BufferPointer = *align(alignment) Buffer;

        var allocated_items: usize = 0;

        /// Number of active items in the pool.
        pub fn get_count() usize {
            return allocated_items;
        }

        // Dummy struct we need to specify the alignment of our elements.
        const Item = extern struct {
            raw: Buffer align(alignment),
        };

        var items = std.heap.MemoryPool(Item).init(ashet.memory.allocator);

        /// Creates a new chunk of `element_size` bytes.
        pub fn alloc() error{OutOfMemory}!BufferPointer {
            const item = try items.create();
            allocated_items += 1;
            return @ptrCast(item);
        }

        /// Frees a previously allocated chunk of `element_size` bytes.
        pub fn free(res: BufferPointer) void {
            res.* = undefined;
            items.destroy(@ptrCast(res));
            allocated_items -= 1;
        }
    };
}
