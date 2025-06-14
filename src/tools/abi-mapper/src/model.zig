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
    const options: std.json.StringifyOptions = .{
        .emit_nonportable_numbers_as_strings = false,
        .emit_null_optional_fields = true,
        .emit_strings_as_arrays = false,
        .escape_unicode = false,
        .whitespace = .indent_2,
    };
    try std.json.stringify(document, options, writer);
}

/// A full qualified name is a name consisting of a sequence of namespaces and ending with the actual name.
pub const FQN = []const []const u8;

/// A documentation string is a sequence of text lines.
pub const DocString = []const []const u8;

pub const Document = struct {
    root: []const Declaration,

    structs: []const Struct,
    unions: []const Struct,
    enums: []const Enumeration,
    bitstructs: []const BitStruct,
    syscalls: []const SystemCall,
    async_calls: []const AsyncCall,
    resources: []const Resource,
    constants: []const Constant,

    types: []const Type,
};

pub const StructIndex = GenericIndex(Struct, "structs");
pub const UnionIndex = GenericIndex(Struct, "unions");
pub const EnumerationIndex = GenericIndex(Enumeration, "enums");
pub const BitStructIndex = GenericIndex(BitStruct, "bitstructs");
pub const SystemCallIndex = GenericIndex(SystemCall, "syscalls");
pub const AsyncCallIndex = GenericIndex(AsyncCall, "async_calls");
pub const ResourceIndex = GenericIndex(Resource, "resources");
pub const ConstantIndex = GenericIndex(Constant, "constants");
pub const TypeIndex = GenericIndex(Type, "types");

pub const Declaration = struct {
    docs: DocString,
    full_qualified_name: FQN,
    children: []const Declaration,
    data: Data,

    pub const Data = union(enum) {
        namespace: void,
        @"struct": StructIndex,
        @"union": UnionIndex,
        @"enum": EnumerationIndex,
        bitstruct: BitStructIndex,
        syscall: SystemCallIndex,
        async_call: AsyncCallIndex,
        resource: ResourceIndex,
        constant: ConstantIndex,
        typedef: TypeIndex, // .types[] == .typedef
    };
};

pub const Type = union(enum) {
    @"struct": StructIndex,
    @"union": UnionIndex,
    @"enum": EnumerationIndex,
    bitstruct: BitStructIndex,
    resource: ResourceIndex,
    well_known: StandardType,

    external: ExternalType,
    typedef: TypeDefition,

    optional: TypeIndex,
    array: ArrayType,

    uint: u8,
    int: u8,

    ptr: DataPointer,
    fnptr: FunctionPointer,
};

pub const DataPointer = struct {
    child: TypeIndex,
    is_const: bool,
    alignment: ?u64,
    size: PointerSize,
};

pub const PointerSize = enum {
    one,
    slice,
    unknown,
};

pub const FunctionPointer = struct {
    parameters: []const TypeIndex,
    return_type: TypeIndex,
};

pub const ArrayType = struct {
    child: TypeIndex,
    size: u32,
};

pub const TypeId = std.meta.Tag(Type);

pub const ExternalType = struct {
    docs: DocString,
    full_qualified_name: FQN,
    alias: []const u8,
};

pub const TypeDefition = struct {
    docs: DocString,
    full_qualified_name: FQN,
    alias: usize, // .types[]
};

pub const BitStruct = struct {
    docs: DocString,
    full_qualified_name: FQN,
    //
};

pub const Struct = struct {
    docs: DocString,
    full_qualified_name: FQN,
    fields: []const StructField,
};

pub const StructField = struct {
    docs: DocString,
    name: []const u8,
    type: TypeIndex,
    // TODO: default: ???
};

pub const Enumeration = struct {
    docs: DocString,
    full_qualified_name: FQN,
    backing_type: StandardType,
    kind: Kind,

    items: []const EnumItem,

    pub const Kind = enum {
        open,
        closed,
    };
};

pub const EnumItem = struct {
    docs: DocString,
    name: []const u8,
    value: i65,
};

pub const SystemCall = struct {
    docs: DocString,
    full_qualified_name: FQN,

    inputs: []const Parameter,
    errors: []const Error,

    return_type: TypeIndex,
};

pub const AsyncCall = struct {
    docs: DocString,
    full_qualified_name: FQN,

    inputs: []const Parameter,
    outputs: []const Parameter,

    errors: []const Error,
};

pub const Parameter = struct {
    docs: DocString,
    name: []const u8,
    type: TypeIndex,
    // TODO: default: ???
};

pub const Resource = struct {
    docs: DocString,
    full_qualified_name: FQN,
};

pub const Error = struct {
    docs: DocString,
    name: []const u8,
};

pub const Constant = struct {
    docs: DocString,
    full_qualified_name: FQN,
    type: ?TypeIndex,
    // TODO: value: ???
};

/// The standard types are the ones that can be reified into actual
/// language primitives for most programming languages.
/// Not every language can do `u11`
pub const StandardType = enum {
    void,
    bool,
    noreturn,

    anyptr,
    anyfnptr,

    str,
    bytestr,
    bytebuf,

    u8,
    u16,
    u32,
    u64,
    usize,

    i8,
    i16,
    i32,
    i64,
    isize,

    f32,
    f64,

    pub fn size_in_bytes(st: StandardType, ptrsize: u8) u8 {
        return switch (st) {
            .void => 0,
            .bool => 1,
            .noreturn => 0,

            .anyptr => ptrsize,
            .anyfnptr => ptrsize,

            .str => 2 * ptrsize, // ptr + len
            .bytestr => 2 * ptrsize, // ptr + len
            .bytebuf => 2 * ptrsize, // ptr + len

            .u8 => 1,
            .u16 => 2,
            .u32 => 4,
            .u64 => 8,
            .usize => ptrsize,

            .i8 => 1,
            .i16 => 2,
            .i32 => 4,
            .i64 => 8,
            .isize => ptrsize,

            .f32 => 4,
            .f64 => 8,
        };
    }

    pub fn is_float(st: StandardType) bool {
        return switch (st) {
            .f32,
            .f64,
            => true,

            .void,
            .bool,
            .noreturn,

            .anyptr,
            .anyfnptr,

            .str,
            .bytestr,
            .bytebuf,

            .u8,
            .u16,
            .u32,
            .u64,
            .usize,

            .i8,
            .i16,
            .i32,
            .i64,
            .isize,
            => false,
        };
    }

    pub fn is_integer(st: StandardType) bool {
        return switch (st) {
            .u8,
            .u16,
            .u32,
            .u64,
            .usize,

            .i8,
            .i16,
            .i32,
            .i64,
            .isize,
            => true,

            .void,
            .bool,
            .noreturn,
            .anyptr,
            .anyfnptr,
            .str,
            .bytestr,
            .bytebuf,
            .f32,
            .f64,
            => false,
        };
    }
};

fn GenericIndex(comptime T: type, comptime field: []const u8) type {
    return enum(usize) {
        pub const Pointee = T;

        _,

        pub fn from_int(i: usize) @This() {
            return @enumFromInt(i);
        }

        pub fn get(index: @This(), doc: *Document) *Pointee {
            return @field(doc, field)[@intFromEnum(index)];
        }
    };
}
