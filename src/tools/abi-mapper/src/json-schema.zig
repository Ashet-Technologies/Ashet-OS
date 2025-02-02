const std = @import("std");

pub const Document = struct {
    root_container: RootNamespace,

    sys_resources: []const []const u8,

    iops: []const Declaration,

    syscalls: []const Declaration,

    pub fn from_json_str(allocator: std.mem.Allocator, string: []const u8) !std.json.Parsed(Document) {
        //
        return try std.json.parseFromSlice(Document, allocator, string, .{
            .allocate = .alloc_always,
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = false,
            .max_value_len = null,
        });
    }
};

pub const RootNamespace = struct {
    decls: []const Declaration,
    rest: []const u8,

    pub fn as_namespace(root: RootNamespace) Namespace {
        return .{ .decls = root.decls };
    }
};

pub const Namespace = struct {
    decls: []const Declaration,
};

pub const Declaration = struct {
    name: []const u8,
    docs: ?[]const u8,
    full_qualified_name: ?[]const u8,
    value: DeclarationKind,
};

pub const DeclarationKind = union(enum) {
    Namespace: Namespace,
    Function: Function,
    AsyncOp: AsyncOp,
    SystemResource: SystemResource,
    ErrorSet: ErrorSet,
};

pub const SystemResource = struct {};

pub const AsyncOp = struct {
    inputs: ParameterCollection,
    outputs: ParameterCollection,
    @"error": struct { ErrorSet: *ErrorSet },
};

pub const Function = struct {
    params: ParameterCollection,

    abi_return_type: *Type,

    key: []const u8,
    value: u32,
};

pub const ParameterCollection = struct {
    abi: []const Parameter,
    native: []const Parameter,
    annotations: []const ParameterTags,
};

pub const Parameter = struct {
    name: []const u8,
    docs: ?[]const u8,
    type: *Type,
};

pub const ParameterTags = struct {
    is_slice: bool,
    is_optional: bool,
    is_out: bool,
    technical: bool,
};

pub const Type = union(enum) {
    ReferenceType: ReferenceType,
    PointerType: PointerType,
    OptionalType: OptionalType,
    ArrayType: ArrayType,
    ErrorSet: ErrorSet,
    ErrorUnion: ErrorUnion,
};

pub const ReferenceType = struct {
    name: []const u8,
};

pub const OptionalType = struct {
    inner: *Type,
};

pub const PointerType = struct {
    size: Size,
    sentinel: ?[]const u8,
    @"const": bool,
    @"volatile": bool,
    alignment: ?u32,
    inner: *Type,

    pub const Size = enum {
        @"*",
        @"[]",
        @"[*]",
    };
};

pub const ArrayType = struct {
    size: []const u8,
    sentinel: ?[]const u8,
    inner: *Type,
};

pub const ErrorUnion = struct {
    @"error": struct {
        ErrorSet: *ErrorSet,
    },
    result: *Type,
};

pub const ErrorSet = struct {
    errors: []const []const u8,
};

test {
    const schema = try Document.from_json_str(
        std.testing.allocator,
        @embedFile("coverage.json"),
    );

    defer schema.deinit();
}
