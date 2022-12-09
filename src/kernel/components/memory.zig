const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.memory);

pub const Section = struct {
    offset: u32,
    length: u32,
};

pub const page_size = ashet.platform.page_size;

var page_manager: RawPageStorageManager = undefined;

extern const __kernel_flash_start: anyopaque align(4);
extern const __kernel_flash_end: anyopaque align(4);
extern const __kernel_data_start: anyopaque align(4);
extern const __kernel_data_end: anyopaque align(4);
extern const __kernel_bss_start: anyopaque align(4);
extern const __kernel_bss_end: anyopaque align(4);

/// First stage in memory initialization:
/// Copy the `.data` section into RAM, and zero out `.bss`.
/// This is needed to have all globals have a well-defined state.
pub fn loadKernelMemory() void {
    // First, populate all RAM sections from flash
    const flash_start = @ptrToInt(&__kernel_flash_start);
    const flash_end = @ptrToInt(&__kernel_flash_end);
    const data_start = @ptrToInt(&__kernel_data_start);
    const data_end = @ptrToInt(&__kernel_data_end);
    const bss_start = @ptrToInt(&__kernel_bss_start);
    const bss_end = @ptrToInt(&__kernel_bss_end);

    logger.debug("flash_start = 0x{X:0>8}", .{flash_start});
    logger.debug("flash_end   = 0x{X:0>8}", .{flash_end});
    logger.debug("data_start  = 0x{X:0>8}", .{data_start});
    logger.debug("data_end    = 0x{X:0>8}", .{data_end});
    logger.debug("bss_start   = 0x{X:0>8}", .{bss_start});
    logger.debug("bss_end     = 0x{X:0>8}", .{bss_end});

    const data_size = data_end - data_start;
    const bss_size = bss_end - bss_start;

    logger.debug("data_size   = 0x{X:0>8}", .{data_size});
    logger.debug("bss_size    = 0x{X:0>8}", .{bss_size});

    std.mem.copy(
        u32,
        @intToPtr([*]u32, data_start)[0 .. data_size / 4],
        @intToPtr([*]u32, flash_end)[0 .. data_size / 4],
    );
    std.mem.set(u32, @intToPtr([*]u32, bss_start)[0 .. bss_size / 4], 0);
}

/// Initialize the linear system memory and allocators.
pub fn initializeLinearMemory() void {
    const flash_start = @ptrToInt(&__kernel_flash_start);
    const flash_end = @ptrToInt(&__kernel_flash_end);
    const data_start = @ptrToInt(&__kernel_data_start);
    const data_end = @ptrToInt(&__kernel_data_end);
    const bss_start = @ptrToInt(&__kernel_bss_start);
    const bss_end = @ptrToInt(&__kernel_bss_end);

    // compute and initialize the memory map
    const linear_memory_region: Section = ashet.machine.getLinearMemoryRegion();

    logger.info("linear memory starts at 0x{X:0>8} and is {d:.3} ({} pages) large", .{
        linear_memory_region.offset,
        std.fmt.fmtIntSizeBin(linear_memory_region.length),
        linear_memory_region.length / page_size,
    });

    // make sure we have at least some pages to play with.
    if (linear_memory_region.length < 8 * page_size) {
        @panic("not enough linear memory.");
    }

    // Now that we're ready for action and the kernel has all predefined variables loaded,
    // let's initialize linear memory management
    page_manager = RawPageStorageManager.init(linear_memory_region);

    // mark all kernel regions that overlap with the linear memory
    // as "used", so we don't allocate them later.
    const kernel_regions = [_]Section{
        Section{ .offset = flash_start, .length = flash_end - flash_start },
        Section{ .offset = data_start, .length = data_end - data_start },
        Section{ .offset = bss_start, .length = bss_end - bss_start },
    };
    for (kernel_regions) |region, region_id| {
        logger.debug("disable region {}", .{region_id});
        var base_ptr = @intToPtr([*]u8, region.offset);
        var i: usize = 0;
        while (i < region.length) : (i += page_size) {
            if (page_manager.ptrToPage(base_ptr + i)) |page| {
                page_manager.markUsed(page);
                logger.debug("mark {} used", .{page});
            }
        }
    }

    const free_memory = page_manager.getFreePageCount();

    logger.info("free ram: {:.2} ({}/{} pages)", .{ std.fmt.fmtIntSizeBin(page_size * free_memory), free_memory, page_manager.pageCount() });
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
                writer.print("\n0x{X:0>8}: [", .{page_manager.region.offset + i * page_size}) catch {};
            }
            if (page_manager.isFree(@intToEnum(Page, i))) {
                free_memory += page_size;
                writer.writeAll(" ") catch {};
            } else {
                writer.writeAll("#") catch {};
            }
        }

        writer.writeAll("]\n") catch {};

        for (page_manager.bitmap()) |item, index| {
            writer.print("{X:0>4}: {b:0>32}\r\n", .{ index, item }) catch {};
        }

        writer.print("free ram: {:.2} ({}/{} pages)\n", .{ std.fmt.fmtIntSizeBin(free_memory), free_memory / page_size, page_manager.pageCount() }) catch {};
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

        std.debug.assert(ptr_align <= page_size);

        const aligned_len = std.mem.alignForward(len, page_size);

        const alloc_page_count = page_manager.getRequiredPages(aligned_len);

        const page_slice = page_manager.allocPages(alloc_page_count) catch return null;

        return @ptrCast([*]align(page_size) u8, page_manager.pageToPtr(page_slice.page));
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

        const buf_aligned_len = std.mem.alignForward(buf.len, page_size);
        const ptr = @alignCast(page_size, buf.ptr);

        page_manager.freePages(PageSlice{
            .page = page_manager.ptrToPage(ptr) orelse @panic("invalid address in free!"),
            .len = @divExact(buf_aligned_len, page_size),
        });
    }
};

/////////////////////////////////////////
// Physical page management:

/// A reference to a memory page.
///
/// We're using a 32 bit integer for indexing pages.
/// This allows us to index up to 16 TB of memory when the page size
/// is 4096. This is enough, as Ashet OS is mostly meant to target
/// 32 bit systems.
const Page = enum(u32) {
    _,

    /// Returns the index into the bitmap.
    fn wordIndex(page: Page) u32 {
        return @enumToInt(page) / @bitSizeOf(usize);
    }

    /// Returns the number of the bit inside the bitmap.
    fn bitIndex(page: Page) USizeIndex {
        return @intCast(USizeIndex, @enumToInt(page) % @bitSizeOf(usize));
    }
};

/// Similar to a Zig slice contains a range of pages.
const PageSlice = struct {
    page: Page,
    len: u32,
};

const USizeIndex = @Type(.{ .Int = .{ .bits = @intCast(comptime_int, std.math.log2_int_ceil(u32, @bitSizeOf(usize))), .signedness = .unsigned } });

const RawPageStorageManager = struct {
    //! - `0` means the page is currently free.
    //! - `1` means that page is currently in use

    region: Section,

    inline fn bitMask(index: USizeIndex) usize {
        return (@as(usize, 1) << index);
    }
    inline fn bitMarkedFree(value: usize, index: USizeIndex) bool {
        return ((value & bitMask(index)) == 0);
    }
    inline fn markBitFree(value: *usize, index: USizeIndex) void {
        value.* &= ~bitMask(index);
    }
    inline fn markBitUsed(value: *usize, index: USizeIndex) void {
        value.* |= bitMask(index);
    }

    // compute the "all free" and "all used" marker
    const all_bits_free = blk: {
        var val: usize = 0;

        var i = 0;
        while (i < @bitSizeOf(usize)) : (i += 1) {
            markBitFree(&val, i);
        }

        break :blk val;
    };
    const all_bits_used = blk: {
        var val: usize = 0;

        var i = 0;
        while (i < @bitSizeOf(usize)) : (i += 1) {
            markBitUsed(&val, i);
        }

        break :blk val;
    };

    comptime {
        std.debug.assert(all_bits_used == ~all_bits_free);
        std.debug.assert(bitMarkedFree(all_bits_free, 0) == true);
        std.debug.assert(bitMarkedFree(all_bits_used, 0) == false);
    }

    pub fn init(section: Section) RawPageStorageManager {
        var pm = RawPageStorageManager{
            .region = Section{
                // make sure that we've aligned our memory section forward to a page boundary.
                .offset = std.mem.alignForward(section.offset, page_size),
                .length = undefined,
            },
        };
        // adjust the memory length to be a multiple of page_size, including our (potentially now) aligned
        // memory start.
        pm.region.length = std.mem.alignBackward(section.length -| (pm.region.offset - section.offset), page_size);

        const bmp = pm.bitmap();

        // Initialize the memory to "all pages free"
        std.mem.set(usize, bmp, all_bits_free);

        // compute the amount of pages we need to store the allocation state of pages.
        // we have to round up here, as we need to use all bits in the bitmap.
        const bitmap_page_count = (bmp.len * @sizeOf(usize) + page_size - 1) / page_size;

        logger.debug("bitmap takes up {} pages", .{bitmap_page_count});

        { // mark each page used by the bitmap as "used"
            var i: usize = 0;
            while (i < bitmap_page_count) : (i += 1) {
                pm.markUsed(@intToEnum(Page, i));
            }
        }

        return pm;
    }

    /// Returns a slice of usize bit groups.
    /// Each bit (LSB to MSB) marks the usage of a page.
    /// - `0` means that page is currently in use
    /// - `1` means the page is currently free.
    /// This is chosen that way as our primary task in allocation is
    /// to search for free pages. If a free page means a bit is set, we can trivially
    /// check for "val != 0" to figure out if the current word contains any free pages.
    fn bitmap(pm: RawPageStorageManager) []usize {

        // if length is not page aligned, we're losing up to page_size bytes, which is okay.
        // as it's not a full page, we would violate the guarantees by the memory system, which
        // is to provide fullly usable memory pages.
        const total_page_count = (pm.region.length / pm.pageCount());

        // compute the amount of pages we require to store which pages are allocated or not.
        // we orginize the bitmap in `usize` elements, as we can efficiently manipulate them
        // on most hardware.
        const bitmap_length = (total_page_count + @bitSizeOf(usize) - 1) / @bitSizeOf(usize);

        // We put the bitmap at the start of our memory, as we know we have the place for it.
        // This is guaranteed as we store only one bit per page_size (often 4096) byte, so
        // the bitmap always fits.
        return @intToPtr([*]usize, pm.region.offset)[0..bitmap_length];
    }

    /// Returns the number of pages managed by `pm`.
    pub fn pageCount(pm: RawPageStorageManager) u32 {
        return pm.region.length / page_size;
    }

    /// Returns the number of currently free pages.
    pub fn getFreePageCount(pm: RawPageStorageManager) u32 {
        var free: u32 = 0;
        for (pm.bitmap()) |item| {
            if (item == all_bits_free) {
                free += @bitSizeOf(usize);
            } else {
                free += @bitSizeOf(usize) - @popCount(item);
            }
        }
        return free;
    }

    /// Returns the number of pages required for a given number of `bytes`.
    pub fn getRequiredPages(pm: RawPageStorageManager, bytes: usize) u32 {
        _ = pm;
        return @intCast(u32, std.mem.alignForward(bytes, page_size) / page_size);
    }

    /// Allocates `count` physical pages and returns a slice to the allocated pages.
    /// Use `pageToPtr` to obtain a physical pointer to it.
    /// Returned memory must be freed with `freePages` using the same return value as returned by `allocPages`.
    pub fn allocPages(pm: *RawPageStorageManager, count: u32) error{OutOfMemory}!PageSlice {
        if (count == 0) return error.OutOfMemory;
        if (count >= pm.pageCount()) return error.OutOfMemory;

        const bmp = pm.bitmap();

        logger.debug("allocate {} pages", .{count});

        // if (count > 100) @panic("wtf");
        // defer debug.dumpPageMap();

        var first_page = search_loop: for (bmp) |val, pi| {
            // logger.debug("elaborate group {} [{b:0>32}]", .{ pi, val });
            if (val == all_bits_free)
                break @bitSizeOf(usize) * pi;

            if (val == all_bits_used)
                continue;

            var i: USizeIndex = 0;
            while (true) : (i += 1) {
                // logger.debug("test bit {}", .{i});
                if (bitMarkedFree(val, i))
                    break :search_loop @bitSizeOf(usize) * pi + i;
            }
        } else return error.OutOfMemory;

        // logger.debug("selected first page {}", .{first_page});

        if (count == 1) {
            const page = @intToEnum(Page, first_page);
            pm.markUsed(page);
            return PageSlice{ .page = page, .len = 1 };
        }

        while (first_page < pm.pageCount() - count) {
            var i: usize = 1;
            const ok = while (i < count) : (i += 1) {
                if (!pm.isFree(@intToEnum(Page, first_page + i)))
                    break false;
            } else true;

            if (ok) {
                i = 0;
                while (i < count) : (i += 1) {
                    const page = @intToEnum(Page, first_page + i);
                    std.debug.assert(pm.isFree(page));
                    pm.markUsed(page);
                }
                return PageSlice{ .page = @intToEnum(Page, first_page), .len = count };
            } else {
                // skip over all checked pages as well as the unset page
                first_page += i;
            }
        }

        return error.OutOfMemory;
    }

    /// Frees physical pages previously allocated with `allocPages`.
    pub fn freePages(pm: *RawPageStorageManager, slice: PageSlice) void {
        const first = @enumToInt(slice.page);
        std.debug.assert(first + slice.len <= pm.pageCount());
        var i: u32 = first;
        while (i < first +| slice.len) : (i += 1) {
            pm.markFree(@intToEnum(Page, i));
        }
    }

    /// Returns whether the `page` is currently available for allocation or
    /// not.
    fn isFree(pm: *RawPageStorageManager, page: Page) bool {
        const bmp = pm.bitmap();
        return bitMarkedFree(bmp[page.wordIndex()], page.bitIndex());
    }

    /// Marks the `page` as "free" (sets the bit).
    fn markFree(pm: *RawPageStorageManager, page: Page) void {
        // logger.debug("markFree({})", .{page});
        const bmp = pm.bitmap();
        markBitFree(&bmp[page.wordIndex()], page.bitIndex());
    }

    /// Marks the `page` as "used" (clears the bit).
    fn markUsed(pm: *RawPageStorageManager, page: Page) void {
        // logger.debug("markUsed({})", .{page});
        const bmp = pm.bitmap();
        markBitUsed(&bmp[page.wordIndex()], page.bitIndex());
    }

    /// Checks if the given `ptr` is in the range managed by `pm` and
    /// returns the page index into `pm` if so.
    fn ptrToPage(pm: *RawPageStorageManager, ptr: anytype) ?Page {
        const offset = @ptrToInt(ptr);
        if (offset < pm.region.offset)
            return null;
        if (offset >= pm.region.offset + pm.region.length)
            return null;
        return @intToEnum(Page, @truncate(u32, (offset - pm.region.offset) / page_size));
    }

    /// Converts a given `page` index for `pm` into a physical memory address.
    fn pageToPtr(pm: *RawPageStorageManager, page: Page) ?*align(page_size) anyopaque {
        const num = @enumToInt(page);
        if (num >= pm.pageCount())
            return null;
        return @intToPtr(*align(page_size) anyopaque, pm.region.offset + page_size * num);
    }
};
