const std = @import("std");
const log = std.log.scoped(.rv32_vmm);
const ashet = @import("../../../main.zig");
const csr = @import("csr.zig");
const rv32 = @import("../rv32.zig");

const page_size = rv32.page_size;

const assert = std.debug.assert;
const ControlStatusRegister = csr.ControlStatusRegister;

pub const Range = ashet.memory.Range;

pub fn initialize() !void {
    // for sv32 to work, the satp register must be active.
    // this means the privilege mode must be S-mode or U-mode.
    const mrw = ControlStatusRegister.read(.mstatus);
    const mode = (mrw >> 11) & 0x3;
    assert(mode == 0 or mode == 1);

    // we allocate the 1024 PTEs to create the first level table
    const root_page_table = try ashet.memory.page_allocator.alloc(PTE, 1024);

    // clear the page table
    @memset(root_page_table, std.mem.zeroes(PTE));

    // allocating the second level page table used in sv32
    const second_page_table = try ashet.memory.page_allocator.alloc(PTE, 1024);

    // similarly clear it
    @memset(second_page_table, std.mem.zeroes(PTE));

    // map va 0x00000000 to pa 0x00000000 with RWX
    second_page_table[0].flags.valid = true;
    second_page_table[0].flags.xwr = .read_write_exec;
    second_page_table[0].ppn = @enumFromInt(0);

    // now we set the root page table entry to point at the second-level page table
    const second_ppn: u22 = @truncate(@intFromPtr(second_page_table.ptr) >> 12);
    root_page_table[0].ppn = @enumFromInt(second_ppn);
    root_page_table[0].flags.valid = true;

    const root_ppn: u22 = @truncate(@intFromPtr(root_page_table.ptr) >> 12);
    log.info("root ptr: {*}", .{root_page_table.ptr});
    log.info("root ppn: 0x{x:0>6}", .{root_ppn});

    const layout: Satp = .{
        .ppn = @enumFromInt(root_ppn),
        .asid = 0, // the root has an ASID of 0
        .mode = .bare, // we don't enable the protection yet
    };
    ControlStatusRegister.write(.satp, @bitCast(layout));
}

pub fn activate() void {
    var current: Satp = @bitCast(ControlStatusRegister.read(.satp));
    assert(current.mode == .bare); // it shouldn't be enabled yet
    current.mode = .sv32;
    ControlStatusRegister.write(.satp, @bitCast(current));
}

/// Layout of the Superviser Address Translation and Protection (`satp`) register.
const Satp = packed struct(usize) {
    /// Physical Page Number
    ///
    /// represents the physical address of the base of the page table.
    ppn: PageNumber,
    /// Address Spoace Identifier
    ///
    /// Each process has a unique address space.
    asid: u9,
    /// rv32 only has 2 possible modes
    ///
    /// - `bare` No protection is provided. Can be equated to just "off".
    /// - `sv32` 2-level page table with 4KiB pages.
    mode: enum(u1) {
        bare,
        sv32,
    },
};

const PageNumber = enum(u22) {
    _,

    fn to_table(pn: PageNumber) []PTE {
        return @as([*]PTE, @ptrFromInt(@as(usize, @intFromEnum(pn)) << 12))[0..1024];
    }
};

/// Page Table Entry
const PTE = packed struct(u32) {
    flags: Flags,
    ppn: PageNumber,

    const Flags = packed struct(u10) {
        valid: bool,
        /// If `xwr` isn't a pointer this can be considered a leaf page.
        xwr: enum(u3) {
            pointer,
            read_only,
            _reserved1,
            read_write,
            exec_only,
            read_exec,
            _reserved2,
            read_write_exec,
        } = .pointer, // default 0
        user_mode: bool = false,
        global: bool = false,
        accessed: bool = false,
        dirty: bool = false,
        _no_touchy: u2 = 0, // shouldn't be accessed
    };

    fn create(addr: usize, flags: Flags) PTE {
        return .{
            .ppn = @enumFromInt(@as(u22, @truncate(addr >> 12))),
            .flags = flags,
        };
    }
};

pub fn update(range: Range, protection: ashet.memory.protection.Protection) void {
    errdefer |err| std.debug.panic("mprot update failed with: {s}", .{@errorName(err)});

    const layout: Satp = @bitCast(ControlStatusRegister.read(.satp));
    const root_page_table = layout.ppn.to_table();

    _ = range;
    _ = protection;
    _ = root_page_table;
}

pub fn get_protection(address: usize) ashet.memory.protection.Protection {
    _ = address;
    return .forbidden;
}

pub fn query_address(address: usize) ashet.memory.protection.AddressInfo {
    _ = address;
    return .{
        .protection = .forbidden,
        .was_accessed = false,
        .was_written = false,
    };
}
