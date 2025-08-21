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
pub fn MmioRegister(comptime _Reg: type, comptime config: MmioConfig) type {
    @setEvalBranchQuota(10_000);
    std.debug.assert(
        // Registers must be the size of a standard integer:
        @bitSizeOf(_Reg) == 8 or
            @bitSizeOf(_Reg) == 16 or
            @bitSizeOf(_Reg) == 32 or
            @bitSizeOf(_Reg) == 64,
    );
    std.debug.assert(
        // Registers must be atomically writable
        @sizeOf(_Reg) <= @sizeOf(usize),
    );
    std.debug.assert(@typeInfo(_Reg) == .@"struct");
    std.debug.assert(@typeInfo(_Reg).@"struct".layout == .@"packed");
    std.debug.assert(@typeInfo(_Reg).@"struct".backing_integer != null);

    return extern union {
        pub const Reg = _Reg;
        pub const Int = @typeInfo(_Reg).@"struct".backing_integer.?;

        pub const access = config.access;
        pub const underlying_type = Reg;

        const MmioReg = @This();
        comptime {
            // This struct must be exactly the same size and align as the original register:
            std.debug.assert(@alignOf(@This()) == @alignOf(_Reg));
            std.debug.assert(@sizeOf(@This()) == @sizeOf(_Reg));
        }

        direct_access: _Reg,
        integer_access: Int,
        raw: Int,

        /// Reads the full register.
        pub inline fn read(mmio: *volatile MmioReg) _Reg {
            if (!comptime config.access.can_read())
                @compileError("Register is write-only!");
            return mmio.direct_access;
        }

        /// Writes the full register.
        pub inline fn write(mmio: *volatile MmioReg, value: _Reg) void {
            if (!comptime config.access.can_write())
                @compileError("Register is read-only!");
            mmio.direct_access = value;
        }

        /// Writes the full register.
        pub inline fn write_default(mmio: *volatile MmioReg, value: anytype) void {
            const default_value: _Reg = @bitCast(@as(Int, 0));
            const new_value = change_fields(default_value, value);
            mmio.write(new_value);
        }

        /// Replaces the register with a new value.
        pub inline fn replace(mmio: *volatile MmioReg, value: _Reg) _Reg {
            const old_value = mmio.read();
            mmio.write(value);
            return old_value;
        }

        /// Reads the register, replaces all set fields in `changes` and writes it back.
        pub inline fn modify(mmio: *volatile MmioReg, changes: anytype) void {
            const current = mmio.read();
            const new = change_fields(current, changes);
            mmio.write(new);
        }

        inline fn change_fields(value: _Reg, changes: anytype) _Reg {
            var new_value = value;
            const UpdateType = @TypeOf(changes);
            inline for (std.meta.fields(UpdateType)) |fld| {
                if (!@hasField(FieldUpdate, fld.name))
                    @compileError(fld.name);

                if (@hasField(UpdateType, fld.name)) {
                    @field(new_value, fld.name) = @field(changes, fld.name);
                }
            }
            return new_value;
        }

        pub inline fn write_raw(mmio: *volatile MmioReg, value: Int) void {
            mmio.integer_access = value;
        }

        pub const FieldUpdate: type = blk: {
            const src_info = @typeInfo(_Reg).@"struct";

            var new_info: std.builtin.Type = .{
                .@"struct" = .{
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
                    .default_value_ptr = &field_default,
                };

                new_info.@"struct".fields = new_info.@"struct".fields ++ &[_]std.builtin.Type.StructField{new_field};
            }

            break :blk @Type(new_info);
        };
    };
}
