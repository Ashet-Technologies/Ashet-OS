const std = @import("std");

pub const MmioConfig = struct {
    access: enum {
        read_only,
        write_only,
        read_write,

        pub fn can_read(access: @This()) bool {
            return switch (access) {
                .read_only => true,
                .read_write => true,
                .write_only => false,
            };
        }

        pub fn can_write(access: @This()) bool {
            return switch (access) {
                .read_only => false,
                .read_write => true,
                .write_only => true,
            };
        }
    } = .read_write,
};

/// Returns a pointer to an mmio register.
pub inline fn mmioRegister(address: usize, comptime Reg: type, comptime config: MmioConfig) *volatile MmioRegister(Reg, config) {
    return @ptrFromInt(address);
}

/// A wrapper around a memory-mapped register.
/// `Reg` must be a packed struct which encodes the fields of the register.
pub fn MmioRegister(comptime Reg: type, comptime config: MmioConfig) type {
    @setEvalBranchQuota(10_000);
    std.debug.assert(
        // Registers must be the size of a standard integer:
        @bitSizeOf(Reg) == 8 or
            @bitSizeOf(Reg) == 16 or
            @bitSizeOf(Reg) == 32 or
            @bitSizeOf(Reg) == 64,
    );
    std.debug.assert(
        // Registers must be atomically writable
        @sizeOf(Reg) <= @sizeOf(usize),
    );
    std.debug.assert(@typeInfo(Reg) == .Struct);
    std.debug.assert(@typeInfo(Reg).Struct.layout == .@"packed");
    std.debug.assert(@typeInfo(Reg).Struct.backing_integer != null);

    return extern union {
        pub const Int = @typeInfo(Reg).Struct.backing_integer.?;

        pub const access = config.access;

        const MmioReg = @This();
        comptime {
            // This struct must be exactly the same size and align as the original register:
            std.debug.assert(@alignOf(@This()) == @alignOf(Reg));
            std.debug.assert(@sizeOf(@This()) == @sizeOf(Reg));
        }

        direct_access: Reg,
        integer_access: Int,

        /// Reads the full register.
        pub fn read(mmio: *volatile MmioReg) Reg {
            if (!comptime config.access.can_read())
                @compileError("Register is write-only!");
            return mmio.direct_access;
        }

        /// Writes the full register.
        pub fn write(mmio: *volatile MmioReg, value: Reg) void {
            if (!comptime config.access.can_write())
                @compileError("Register is read-only!");
            mmio.direct_access = value;
        }

        /// Writes the full register.
        pub fn write_default(mmio: *volatile MmioReg, value: FieldUpdate) void {
            const default_value: Reg = @bitCast(@as(Int, 0));
            const new_value = change_fields(default_value, value);
            mmio.write(new_value);
        }

        /// Replaces the register with a new value.
        pub fn replace(mmio: *volatile MmioReg, value: Reg) Reg {
            const old_value = mmio.read();
            mmio.write(value);
            return old_value;
        }

        /// Reads the register, replaces all set fields in `changes` and writes it back.
        pub fn modify(mmio: *volatile MmioReg, changes: FieldUpdate) void {
            const current = mmio.read();
            const new = change_fields(current, changes);
            mmio.write(new);
        }

        fn change_fields(value: Reg, changes: FieldUpdate) Reg {
            var new_value = value;
            inline for (std.meta.fields(FieldUpdate)) |fld| {
                if (@field(changes, fld.name)) |updated| {
                    @field(new_value, fld.name) = updated;
                }
            }
            return new_value;
        }

        pub fn write_raw(mmio: *volatile MmioReg, value: Int) void {
            mmio.integer_access = value;
        }

        pub const FieldUpdate: type = blk: {
            const src_info = @typeInfo(Reg).Struct;

            var new_info: std.builtin.Type = .{
                .Struct = .{
                    .backing_integer = null,
                    .decls = &.{},
                    .is_tuple = false,
                    .layout = .auto,
                    .fields = &.{},
                },
            };

            for (src_info.fields) |old_field| {
                const FieldType = ?old_field.type;
                const field_default: FieldType = null;

                const new_field: std.builtin.Type.StructField = .{
                    .type = FieldType,
                    .name = old_field.name,
                    .is_comptime = false,
                    .alignment = @alignOf(FieldType),
                    .default_value = &field_default,
                };

                new_info.Struct.fields = new_info.Struct.fields ++ &[_]std.builtin.Type.StructField{new_field};
            }

            break :blk @Type(new_info);
        };
    };
}
