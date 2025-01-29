const std = @import("std");

/// Wrapper around an integer
/// When using the legacy interface, transitional devices and drivers MUST format the fields in struct virtio_-
/// blk_config according to the native endian of the guest rather than (necessarily when not using the legacy
/// interface) little-endian.
pub fn Integer(comptime I: type, comptime endian: std.builtin.Endian) type {
    switch (I) {
        u16, u32, u64 => {},
        i16, i32, i64 => {},
        else => @compileError("illegal type for Integer!"),
    }

    return enum(I) {
        pub const endianess: std.builtin.Endian = endian;

        zero = 0,

        _,

        pub inline fn write(self: *@This(), value: I, legacy: bool) void {
            self.* = @enumFromInt(if (legacy)
                value
            else
                std.mem.nativeTo(I, value, endianess));
        }

        pub inline fn read(self: @This(), legacy: bool) I {
            const native_value = @intFromEnum(self);
            return if (legacy)
                native_value
            else
                std.mem.toNative(I, native_value, endianess);
        }
    };
}

pub const le16 = Integer(u16, .little);
pub const le32 = Integer(u32, .little);
pub const le64 = Integer(u64, .little);

pub const be16 = Integer(u16, .big);
pub const be32 = Integer(u32, .big);
pub const be64 = Integer(u64, .big);
