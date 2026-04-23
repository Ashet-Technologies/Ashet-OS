const std = @import("std");

pub fn from_json_str(allocator: std.mem.Allocator, string: []const u8) !std.json.Parsed(Document) {
    const options: std.json.ParseOptions = .{
        .allocate = .alloc_always,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .max_value_len = null,
        .parse_numbers = true,
    };
    return try std.json.parseFromSlice(Document, allocator, string, options);
}

pub fn to_json_str(document: Document, writer: anytype) !void {
    const options: std.json.Stringify.Options = .{
        .emit_nonportable_numbers_as_strings = false,
        .emit_null_optional_fields = true,
        .emit_strings_as_arrays = false,
        .escape_unicode = false,
        .whitespace = .indent_2,
    };
    try writer.print("{f}", .{std.json.fmt(document, options)});
}

pub const DocLines = []const []const u8;

pub const TypeKind = enum {
    builtin,
    named,
};

pub const BuiltinType = enum {
    bool,
    i8,
    i16,
    i32,
    u8,
    u16,
    u32,
    isize,
    usize,
    str,
    strbuf,
    contextptr,
    framebuf,
};

pub fn builtin_raw_slot_width(builtin: BuiltinType) u8 {
    return switch (builtin) {
        .str, .strbuf => 2,
        .bool,
        .i8,
        .i16,
        .i32,
        .u8,
        .u16,
        .u32,
        .isize,
        .usize,
        .contextptr,
        .framebuf,
        => 1,
    };
}

pub const TypeRef = struct {
    name: []const u8,
    kind: TypeKind,
    builtin: ?BuiltinType,
    raw_slot_width: u8,
};

pub const Parameter = struct {
    name: []const u8,
    type: TypeRef,
};

pub const TypeDeclaration = struct {
    name: []const u8,
    zig_type: []const u8,
};

pub const Message = struct {
    identifier: u32,
    name: []const u8,
    docs: DocLines,
    parameters: []const Parameter,
    parameter_raw_slots: u8,
    return_type: ?TypeRef,
    return_raw_slots: u8,
};

pub const Widget = struct {
    name: []const u8,
    uuid: []const u8,
    docs: DocLines,
    controls: []const Message,
    events: []const Message,
    types: []const TypeDeclaration,
};

pub const Document = struct {
    types: []const TypeDeclaration,
    widgets: []const Widget,
};
