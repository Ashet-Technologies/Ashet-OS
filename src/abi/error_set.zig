const std = @import("std");

const ErrorSetTag = opaque {};

/// Returns `true` if the given type is an error set created with `ErrorSet`.
pub fn isErrorSet(comptime T: type) bool {
    return @hasDecl(T, "error_set_marker") and (T.error_set_marker == ErrorSetTag);
}

/// Constructions an ABI compatible error type.
/// `options` contains a "key value" map of error name to numeric value.
pub fn ErrorSet(comptime options: anytype) type {
    const Int = u32;

    comptime var error_fields: []const std.builtin.Type.Error = &.{};
    inline for (@typeInfo(@TypeOf(options)).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, "ok"))
            @compileError("ErrorSet items cannot be called \"ok\"!");
        if (std.mem.eql(u8, field.name, "Unexpected"))
            @compileError("ErrorSet implicitly contains Unexpected error!");
        error_fields = error_fields ++ [1]std.builtin.Type.Error{
            .{ .name = field.name },
        };
    }
    error_fields = error_fields ++ [_]std.builtin.Type.Error{
        .{ .name = "Unexpected" },
    };

    const error_type = @Type(std.builtin.Type{
        .ErrorSet = error_fields,
    });

    comptime var enum_items: []const std.builtin.Type.EnumField = &.{};
    inline for (@typeInfo(@TypeOf(options)).Struct.fields) |field| {
        const value: Int = @field(options, field.name);
        if (value == 0)
            @compileError("ErrorSet items cannot have the reserved value 0!");
        enum_items = enum_items ++ [1]std.builtin.Type.EnumField{
            .{ .name = field.name, .value = value },
        };
    }

    enum_items = enum_items ++ [_]std.builtin.Type.EnumField{
        .{ .name = "ok", .value = 0 },
        .{ .name = "Unexpected", .value = ~@as(Int, 0) },
    };

    const enum_type = @Type(std.builtin.Type{
        .Enum = .{
            .tag_type = Int,
            .fields = enum_items,
            .decls = &.{},
            .is_exhaustive = false, // this is important so the value passed is actually just a bare integer with all values legal
        },
    });

    comptime var error_list: []const error_type = &.{};
    comptime var enum_list: []const enum_type = &.{};
    inline for (@typeInfo(@TypeOf(options)).Struct.fields) |field| {
        error_list = error_list ++ [1]error_type{@field(error_type, field.name)};
        enum_list = enum_list ++ [1]enum_type{@field(enum_type, field.name)};
    }

    return struct {
        const error_set_marker = ErrorSetTag;

        /// The actual Zig error set.
        pub const Error = error_type;

        /// An enumeration that contains all possible error codes.
        pub const Enum = enum_type;

        /// Unwraps the enumeration value and returns an error Union
        pub fn throw(val: Enum) Error!void {
            if (val == .ok)
                return; // 0 is the success code
            for (enum_list, 0..) |match, index| {
                if (match == val)
                    return error_list[index];
            }
            return error.Unexpected;
        }

        /// Maps an error union of the error set to the enumeration value.
        pub fn map(err_union: Error!void) Enum {
            if (err_union) |_| {
                return .ok;
            } else |err| {
                for (error_list, 0..) |match, index| {
                    if (match == err)
                        return enum_list[index];
                }
                unreachable;
            }
        }
    };
}
