const std = @import("std");

/// A fully emulated system.
pub const System = struct {
    rom: []align(4) const u8,
    ram: []align(4) u8,

    pub fn step(system: *System, steps: usize) !void {
        //
        _ = system;
        _ = steps;
    }

    pub fn bus_read(system: *System, address: u32, comptime size: MemAccessSize) BusError!size.get_type() {
        if (!size.get_alignment().check(address))
            return error.UnalignedAccess;
        const access_size = size.get_alignment().toByteUnits();
        if (address < 0x40000000) {
            // 0x00000000..0x3FFFFFFF
            if (address +| access_size >= system.rom.len)
                return error.Unmapped;
            return std.mem.readInt(size.get_type(), system.rom[address..][0..access_size], .little);
        } else if (address < 0x80000000) {
            // 0x40000000..0x7FFFFFFF
            const periph_id: u16 = @intCast(address >> 12);
            switch (periph_id) {
                0x4000_0000,
                0x4000_1000,
                0x4000_2000,
                0x4000_3000,
                => @panic("TODO: VMEM"),
                0x4004_0000 => @panic("TODO: VCTRL"),
                0x4004_1000 => @panic("TODO: DBG"),
                0x4004_2000 => @panic("TODO: KBD"),
                0x4004_3000 => @panic("TODO: MOUSE"),
                0x4004_4000 => @panic("TODO: TIMER"),
                0x4004_5000 => @panic("TODO: SYSINFO"),
                0x4004_6000 => @panic("TODO: BLOCK0"),
                0x4004_7000 => @panic("TODO: BLOCK1"),
                else => return error.Unmapped,
            }
        } else {
            // 0x80000000..0xFFFFFFFF
            if (address +| access_size >= system.ram.len)
                return error.Unmapped;
            return std.mem.readInt(size.get_type(), system.ram[address..][0..access_size], .little);
        }
    }

    pub fn bus_write(system: *System, address: u32, comptime size: MemAccessSize, value: size.get_type()) BusError!void {
        if (!size.get_alignment().check(address))
            return error.UnalignedAccess;
        const access_size = size.get_alignment().toByteUnits();
        if (address < 0x40000000) {
            // 0x00000000..0x3FFFFFFF
            return error.WriteProtected;
        } else if (address < 0x80000000) {
            // 0x40000000..0x7FFFFFFF
            const periph_id: u16 = @intCast(address >> 12);
            switch (periph_id) {
                0x4000_0000,
                0x4000_1000,
                0x4000_2000,
                0x4000_3000,
                => @panic("TODO: VMEM"),
                0x4004_0000 => @panic("TODO: VCTRL"),
                0x4004_1000 => @panic("TODO: DBG"),
                0x4004_2000 => @panic("TODO: KBD"),
                0x4004_3000 => @panic("TODO: MOUSE"),
                0x4004_4000 => @panic("TODO: TIMER"),
                0x4004_5000 => @panic("TODO: SYSINFO"),
                0x4004_6000 => @panic("TODO: BLOCK0"),
                0x4004_7000 => @panic("TODO: BLOCK1"),
                else => return error.Unmapped,
            }
        } else {
            // 0x80000000..0xFFFFFFFF
            if (address +| access_size >= system.ram.len)
                return error.Unmapped;
            return std.mem.writeInt(size.get_type(), system.ram[address..][0..access_size], value, .little);
        }
    }
};

pub const MemAccessSize = enum(u8) {
    u8 = 0,
    u16 = 1,
    u32 = 2,

    inline fn get_alignment(mas: MemAccessSize) std.mem.Alignment {
        return @enumFromInt(@intFromEnum(mas));
    }

    fn get_type(comptime mas: MemAccessSize) type {
        return switch (mas) {
            .u8 => u8,
            .u16 => u16,
            .u32 => u32,
        };
    }
};

pub const BusError = error{
    /// The memory is not mapped inside the register
    Unmapped,

    /// Bad access to a memory register (size mismatch).
    InvalidSize,

    /// Bad access to a memory address (address is not properly aligned).
    UnalignedAccess,

    /// Memory is not writable.
    WriteProtected,
};

pub const Peripheral = struct {
    /// Bus function access
    vtable: *const VTable,

    /// Size of the peripheral in bytes.
    size: u32,

    pub const VTable = struct {
        read8_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u8,
        read16_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u16,
        read32_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u32,

        write8_fn: *const fn (peri: *Peripheral, offset: u32, value: u8) BusError!void,
        write16_fn: *const fn (peri: *Peripheral, offset: u32, value: u16) BusError!void,
        write32_fn: *const fn (peri: *Peripheral, offset: u32, value: u32) BusError!void,
    };
};
