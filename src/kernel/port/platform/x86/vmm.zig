const std = @import("std");
const log = std.log.scoped(.x86_vmm);
const ashet = @import("../../../main.zig");
const cr = @import("registers.zig");

const page_size = 4096;

pub const Range = ashet.memory.Range;

pub fn initialize() !void {
    const page = try ashet.memory.page_allocator.create(Page);
    page.directory = .{
        .entries = std.mem.zeroes([1024]PageDirectory.Entry),
    };

    set_page_directory(&page.directory);
}

pub fn update(range: Range, protection: ashet.memory.protection.Protection) void {
    change_protection(range, protection);
}

pub fn get_protection(address: usize) ashet.memory.protection.Protection {
    const entry = get_page_entry(address, false) orelse return .forbidden;

    if (!entry.in_use)
        return .forbidden;

    return if (entry.writable)
        .read_write
    else
        .read_only;
}

pub fn query_address(address: usize) ashet.memory.protection.AddressInfo {
    const entry = get_page_entry(address, false) orelse return .{
        .protection = .forbidden,
        .was_accessed = false,
        .was_written = false,
    };

    if (!entry.in_use)
        return .{
            .protection = .forbidden,
            .was_accessed = false,
            .was_written = false,
        };

    return .{
        .protection = if (entry.writable)
            .read_write
        else
            .read_only,
        .was_accessed = entry.was_accessed,
        .was_written = entry.was_written,
    };
}

pub fn ensure_accessible_obj(object: anytype) void {
    change_protection(Range.from_slice(std.mem.asBytes(object)), null);
}

pub fn ensure_accessible_slice(slice: anytype) void {
    change_protection(Range.from_slice(slice), null);
}

pub fn change_protection(range: Range, protection: ?ashet.memory.protection.Protection) void {
    const count: u32 = @intCast(std.mem.alignForward(usize, range.length, page_size) / page_size);
    for (0..count) |offset| {
        map_identity(range.base + page_size * offset, protection, true);
    }
}

pub fn activate() void {
    cr.CR0.modify(.{
        .paging = true,
    });
}

pub fn map_identity(address: u32, protection: ?ashet.memory.protection.Protection, auto_invalidate: bool) void {
    // Make sure the zero page is always non-accessible!
    std.debug.assert(address > page_size);

    const entry = get_page_entry(address, true);

    if (protection != .forbidden) {
        const vmm_addr: PageDirectoryAddress = @bitCast(address);

        const is_writable = if (protection) |prot|
            (prot == .read_write)
        else if (entry.in_use)
            entry.writable
        else
            false;

        entry.* = .{
            .in_use = true,
            .writable = is_writable,
            .access_level = .everyone,
            .use_write_through_caching = false,
            .disable_caching = false,
            .was_accessed = false,
            .was_written = false,
            .pat_index_2 = 0,
            .global = false,
            .unused = 0,

            .address_top_bits = vmm_addr.address_top_bits,
        };
    } else {
        entry.* = @bitCast(@as(u32, 0));
    }

    const page_addr: PageAddress = @bitCast(address);
    log.debug("map_identity(0x{X:0>8} (0x{X:0>5}:{X:0>3}:{X:0>3}), .{s}, {})", .{
        address,
        page_addr.page_directory_index,
        page_addr.page_table_index,
        page_addr.offset,
        if (protection) |prot| @tagName(prot) else "<keep>",
        auto_invalidate,
    });

    if (auto_invalidate) {
        invalidate_address(address);
    }
}

pub fn invalidate_address(address: u32) void {
    if (!cr.CR0.read().paging) {
        return;
    }

    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (address),
    );
}

fn get_page_table(address: u32, comptime force_exist: bool) if (force_exist) *PageTable else ?*PageTable {
    const vmm_addr: PageAddress = @bitCast(address);

    const page_directory = get_page_directory();

    const entry = &page_directory.entries[vmm_addr.page_directory_index];

    if (!entry.in_use) {
        if (force_exist) {
            const sub_page = ashet.memory.page_allocator.create(Page) catch @panic("failed to allocate backing memory for page table!");
            sub_page.table = .{
                .entries = std.mem.zeroes([1024]PageTable.Entry),
            };

            const page_table_addr = PageDirectoryAddress.from_ptr(sub_page);

            entry.* = .{
                .in_use = true,
                .writable = true,
                .access_level = .kernel,
                .use_write_through_caching = false,
                .disable_caching = false,
                .was_accessed = false,
                .was_written = false,
                .page_size = .@"4kiB",
                .global = false,
                .unused = 0,
                .address_top_bits = page_table_addr.address_top_bits,
            };
        } else {
            return null;
        }
    }

    const addr: PageDirectoryAddress = @bitCast(entry.*);

    return addr.to_ptr(PageTable, 0).?;
}

fn get_page_entry(address: u32, comptime force_exist: bool) if (force_exist) *PageTable.Entry else ?*PageTable.Entry {
    const vmm_addr: PageAddress = @bitCast(address);

    const maybe_table = get_page_table(address, force_exist);

    const table = if (force_exist)
        maybe_table
    else
        maybe_table orelse return null;

    return &table.entries[vmm_addr.page_table_index];
}

fn get_page_directory() *PageDirectory {
    const dir_address: PageDirectoryAddress = .{
        .offset = 0,
        .address_top_bits = cr.CR3.read().page_directory_base,
    };
    return dir_address.to_ptr(PageDirectory, 0).?;
}

fn set_page_directory(directory: *PageDirectory) void {
    const dir_address = PageDirectoryAddress.from_ptr(directory);
    cr.CR3.modify(.{
        .page_directory_base = dir_address.address_top_bits,
    });
}

const PageAddress = packed struct(u32) {
    offset: u12,
    page_table_index: u10,
    page_directory_index: u10,
};

const PageDirectoryAddress = packed struct(u32) {
    offset: u12,
    address_top_bits: u20,

    fn from_ptr(ptr: anytype) PageDirectoryAddress {
        return @bitCast(@intFromPtr(ptr));
    }

    fn to_ptr(pda: PageDirectoryAddress, comptime T: type, replace_offset: ?u12) ?*T {
        const changed = if (replace_offset) |offset|
            PageDirectoryAddress{ .address_top_bits = pda.address_top_bits, .offset = offset }
        else
            pda;
        return @ptrFromInt(@as(u32, @bitCast(changed)));
    }
};

const Page = extern union {
    raw: [page_size]u8 align(page_size),
    directory: PageDirectory,
    table: PageTable,
    entries: [1024]Entry,

    const Entry = packed struct(u32) {
        in_use: bool,
        _padding: u11,
        address_top_bits: u20,
    };
};

const PageDirectory = extern struct {
    entries: [1024]Entry align(page_size),

    const Entry = packed struct(u32) {
        in_use: bool, // 0
        writable: bool, // 1
        access_level: AccessLevel, // 2
        use_write_through_caching: bool, // 3
        disable_caching: bool, // 4
        was_accessed: bool, // 5
        was_written: bool, // 6
        page_size: PageSize, // 7
        global: bool, // 8
        unused: u3, // 9,10,11
        address_top_bits: u20, // 12...31
    };
};

const PageTable = extern struct {
    entries: [1024]Entry align(page_size),

    const Entry = packed struct(u32) {
        in_use: bool, // 0
        writable: bool, // 1
        access_level: AccessLevel, // 2
        use_write_through_caching: bool, // 3
        disable_caching: bool, // 4
        was_accessed: bool, // 5
        was_written: bool, // 6
        pat_index_2: u1, // 7
        global: bool, // 8
        unused: u3, // 9,10,11
        address_top_bits: u20, // 12..31
    };
};

const AccessLevel = enum(u1) { kernel = 0, everyone = 1 };

const PageSize = enum(u1) { @"4kiB" = 0, @"4MiB" = 1 };

comptime {
    std.debug.assert(@sizeOf(Page) == page_size);
    std.debug.assert(@sizeOf(PageDirectory) == page_size);
    std.debug.assert(@sizeOf(PageTable) == page_size);

    std.debug.assert(@alignOf(Page) == page_size);
    std.debug.assert(@alignOf(PageDirectory) == page_size);
    std.debug.assert(@alignOf(PageTable) == page_size);
}
