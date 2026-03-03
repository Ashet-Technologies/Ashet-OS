const std = @import("std");
const emu = @import("emulator");

pub const Access = struct {
    offset: u32,
    mode: Mode,
    expected: emu.BusError!u32,

    pub const Mode = enum { read8, read16, read32, write8, write16, write32 };

    pub fn init(offset: u32, mode: Mode, expected: emu.BusError!u32) Access {
        return .{ .offset = offset, .mode = mode, .expected = expected };
    }
};

pub fn testPeripheralAccess(peri: *emu.Peripheral, seq: []const Access) !void {
    for (seq) |access| {
        if (access.expected) |expected_val| {
            // Success case: perform the access and check the returned value.
            switch (access.mode) {
                .read8 => try std.testing.expectEqual(expected_val, try peri.read(access.offset, .u8)),
                .read16 => try std.testing.expectEqual(expected_val, try peri.read(access.offset, .u16)),
                .read32 => try std.testing.expectEqual(expected_val, try peri.read(access.offset, .u32)),
                .write8 => try peri.write(access.offset, .u8, @truncate(expected_val)),
                .write16 => try peri.write(access.offset, .u16, @truncate(expected_val)),
                .write32 => try peri.write(access.offset, .u32, expected_val),
            }
        } else |expected_err| {
            // Error case: perform the access and verify the expected error.
            switch (access.mode) {
                .read8 => try std.testing.expectError(expected_err, peri.read(access.offset, .u8)),
                .read16 => try std.testing.expectError(expected_err, peri.read(access.offset, .u16)),
                .read32 => try std.testing.expectError(expected_err, peri.read(access.offset, .u32)),
                .write8 => try std.testing.expectError(expected_err, peri.write(access.offset, .u8, 0)),
                .write16 => try std.testing.expectError(expected_err, peri.write(access.offset, .u16, 0)),
                .write32 => try std.testing.expectError(expected_err, peri.write(access.offset, .u32, 0)),
            }
        }
    }
}
