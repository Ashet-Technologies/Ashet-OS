const std = @import("std");

const ErrorSetTag = opaque {};
pub fn is_error_set(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .Enum)
        return false;
    const einfo = info.Enum;
    if (einfo.is_exhaustive)
        return false;
    if (einfo.decls.len > 0)
        return false;
    if (einfo.fields.len < 1)
        return false;
    if (!std.mem.eql(u8, einfo.fields[0].name, "ok"))
        return false;
    if (einfo.fields[0].value != 0)
        return false;
    // seems okayish now
    return true;
}

pub fn ErrorSet(comptime ErrorType: type) type {
    const raw_errors = @typeInfo(ErrorType).ErrorSet orelse @compileError("anyerror is not a legal error set");

    var errors = raw_errors[0..raw_errors.len].*;

    std.sort.heap(std.builtin.Type.Error, &errors, {}, struct {
        fn lt(_: void, lhs: std.builtin.Type.Error, rhs: std.builtin.Type.Error) bool {
            return std.mem.lessThan(u8, lhs.name, rhs.name);
        }
    }.lt);

    var enum_fields: [1 + errors.len]std.builtin.Type.EnumField = undefined;

    enum_fields[0] = .{ .name = "ok", .value = 0 };

    for (enum_fields[1..], errors, 1..) |*uf, err, index| {
        uf.* = .{
            .name = err.name,
            .value = index,
        };
    }

    const backing_int = if (enum_fields.len <= std.math.maxInt(u8))
        u8
    else if (enum_fields.len <= std.math.maxInt(u16))
        u8
    else if (enum_fields.len <= std.math.maxInt(u32))
        u8
    else
        u64; // you mad person

    return @Type(.{
        .Enum = .{
            .tag_type = backing_int,
            .fields = &enum_fields,
            .decls = &.{},
            .is_exhaustive = false,
        },
    });
}
