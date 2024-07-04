//! - `0` means the page is currently free.
//! - `1` means that page is currently in use

const std = @import("std");
const memory = @import("../memory.zig");
const logger = std.log.scoped(.page_allocator);

const Section = memory.Section;
const USizeIndex = memory.USizeIndex;
const page_size = memory.page_size;

const RawPageStorageManager = @This();

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
            .offset = std.mem.alignForward(usize, section.offset, page_size),
            .length = undefined,
        },
    };
    // adjust the memory length to be a multiple of page_size, including our (potentially now) aligned
    // memory start.
    pm.region.length = std.mem.alignBackward(usize, section.length -| (pm.region.offset - section.offset), page_size);

    const bmp = pm.bitmap();

    // Initialize the memory to "all pages free"
    @memset(bmp, all_bits_free);

    // compute the amount of pages we need to store the allocation state of pages.
    // we have to round up here, as we need to use all bits in the bitmap.
    const bitmap_page_count = (bmp.len * @sizeOf(usize) + page_size - 1) / page_size;

    logger.debug("bitmap takes up {} pages", .{bitmap_page_count});

    { // mark each page used by the bitmap as "used"
        var i: usize = 0;
        while (i < bitmap_page_count) : (i += 1) {
            pm.markUsed(@as(Page, @enumFromInt(i)));
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
    return @as([*]usize, @ptrFromInt(pm.region.offset))[0..bitmap_length];
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
    return @intCast(std.mem.alignForward(usize, bytes, page_size) / page_size);
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

    var first_page = search_loop: for (bmp, 0..) |val, pi| {
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
        const page = @as(Page, @enumFromInt(first_page));
        pm.markUsed(page);
        return PageSlice{ .page = page, .len = 1 };
    }

    while (first_page < pm.pageCount() - count) {
        var i: usize = 1;
        const ok = while (i < count) : (i += 1) {
            if (!pm.isFree(@as(Page, @enumFromInt(first_page + i))))
                break false;
        } else true;

        if (ok) {
            i = 0;
            while (i < count) : (i += 1) {
                const page = @as(Page, @enumFromInt(first_page + i));
                std.debug.assert(pm.isFree(page));
                pm.markUsed(page);
            }
            return PageSlice{ .page = @as(Page, @enumFromInt(first_page)), .len = count };
        } else {
            // skip over all checked pages as well as the unset page
            first_page += i;
        }
    }

    return error.OutOfMemory;
}

/// Frees physical pages previously allocated with `allocPages`.
pub fn freePages(pm: *RawPageStorageManager, slice: PageSlice) void {
    const first = @intFromEnum(slice.page);
    std.debug.assert(first + slice.len <= pm.pageCount());
    var i: u32 = first;
    while (i < first +| slice.len) : (i += 1) {
        pm.markFree(@as(Page, @enumFromInt(i)));
    }
}

/// Returns whether the `page` is currently available for allocation or
/// not.
pub fn isFree(pm: *RawPageStorageManager, page: Page) bool {
    const bmp = pm.bitmap();
    return bitMarkedFree(bmp[page.wordIndex()], page.bitIndex());
}

/// Marks the `page` as "free" (sets the bit).
pub fn markFree(pm: *RawPageStorageManager, page: Page) void {
    // logger.debug("markFree({})", .{page});
    const bmp = pm.bitmap();
    markBitFree(&bmp[page.wordIndex()], page.bitIndex());
}

/// Marks the `page` as "used" (clears the bit).
pub fn markUsed(pm: *RawPageStorageManager, page: Page) void {
    // logger.debug("markUsed({})", .{page});
    const bmp = pm.bitmap();
    markBitUsed(&bmp[page.wordIndex()], page.bitIndex());
}

/// Checks if the given `ptr` is in the range managed by `pm` and
/// returns the page index into `pm` if so.
pub fn ptrToPage(pm: *RawPageStorageManager, ptr: anytype) ?Page {
    const offset = @intFromPtr(ptr);
    if (offset < pm.region.offset)
        return null;
    if (offset >= pm.region.offset + pm.region.length)
        return null;
    return @as(Page, @enumFromInt(@as(u32, @truncate((offset - pm.region.offset) / page_size))));
}

/// Converts a given `page` index for `pm` into a physical memory address.
pub fn pageToPtr(pm: *RawPageStorageManager, page: Page) ?*align(page_size) anyopaque {
    const num = @intFromEnum(page);
    if (num >= pm.pageCount())
        return null;
    return @as(*align(page_size) anyopaque, @ptrFromInt(pm.region.offset + page_size * num));
}

/// A reference to a memory page.
///
/// We're using a 32 bit integer for indexing pages.
/// This allows us to index up to 16 TB of memory when the page size
/// is 4096. This is enough, as Ashet OS is mostly meant to target
/// 32 bit systems.
pub const Page = enum(u32) {
    _,

    /// Returns the index into the bitmap.
    fn wordIndex(page: Page) u32 {
        return @intFromEnum(page) / @bitSizeOf(usize);
    }

    /// Returns the number of the bit inside the bitmap.
    fn bitIndex(page: Page) USizeIndex {
        return @as(USizeIndex, @intCast(@intFromEnum(page) % @bitSizeOf(usize)));
    }
};

/// Similar to a Zig slice contains a range of pages.
pub const PageSlice = struct {
    page: Page,
    len: u32,
};
