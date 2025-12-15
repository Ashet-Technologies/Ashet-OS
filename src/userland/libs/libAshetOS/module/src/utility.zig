//!
//! This file implements some convenience utilities that make implementing
//! libashet easier.
//!

const std = @import("std");

pub fn wrap_abi_union(
    comptime Output: type,
    input: anytype,
    comptime field_map: std.enums.EnumFieldStruct(
        std.meta.Tag(Output),
        ?std.meta.FieldEnum(@TypeOf(input)),
        null,
    ),
) Output {
    const Input = @TypeOf(input);

    const OutputField = std.meta.Tag(Output);
    const InputField = std.meta.FieldEnum(Input);

    const fields: std.EnumArray(OutputField, ?InputField) = comptime .init(field_map);

    const event_type: std.meta.Tag(Output) = input.event_type;

    return switch (event_type) {
        inline else => |tag| @unionInit(
            Output,
            @tagName(tag),
            if (comptime fields.get(tag)) |src_fld|
                @field(input, @tagName(src_fld))
            else {},
        ),
    };
}
