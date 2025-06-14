const std = @import("std");
const model = @import("model.zig");
const syntax = @import("syntax.zig");

const Location = syntax.Location;

pub fn analyze(allocator: std.mem.Allocator, document: syntax.Document) !model.Document {
    var analyzer: Analyzer = .{
        .allocator = allocator,
        .scope = .init(allocator),
        .errors = .init(allocator),

        .root = .init(allocator),
        .structs = .init(allocator),
        .unions = .init(allocator),
        .enums = .init(allocator),
        .bitstructs = .init(allocator),
        .syscalls = .init(allocator),
        .async_calls = .init(allocator),
        .resources = .init(allocator),
        .constants = .init(allocator),
        .types = .init(allocator),
    };

    try analyzer.run(document);

    if (analyzer.errors.items.len > 0) {
        for (analyzer.errors.items) |err| {
            std.log.err("{s}", .{err});
        }
        return error.AnalysisFailed;
    }

    return .{
        .root = try analyzer.root.toOwnedSlice(),

        .structs = try analyzer.structs.toOwnedSlice(),
        .unions = try analyzer.unions.toOwnedSlice(),
        .enums = try analyzer.enums.toOwnedSlice(),
        .bitstructs = try analyzer.bitstructs.toOwnedSlice(),
        .syscalls = try analyzer.syscalls.toOwnedSlice(),
        .async_calls = try analyzer.async_calls.toOwnedSlice(),
        .resources = try analyzer.resources.toOwnedSlice(),
        .constants = try analyzer.constants.toOwnedSlice(),

        .types = try analyzer.types.toOwnedSlice(),
    };
}

fn Collector(comptime I: type) type {
    return struct {
        const Collect = @This();

        pub const Item = I.Pointee;
        pub const Index = I;

        allocator: std.mem.Allocator,
        items: []Item,
        capacity: usize,

        pub fn init(allocator: std.mem.Allocator) Collect {
            return .{
                .allocator = allocator,
                .items = &.{},
                .capacity = 0,
            };
        }

        pub fn append(col: *Collect, item: Item) !Index {
            var list = col.to_list();
            defer col.from_list(list);

            const index = list.items.len;
            try list.append(item);
            return .from_int(index);
        }

        pub fn toOwnedSlice(col: *Collect) ![]Item {
            var list = col.to_list();
            defer col.from_list(list);

            return try list.toOwnedSlice();
        }

        fn to_list(col: *Collect) std.ArrayList(Item) {
            return .{ .allocator = col.allocator, .capacity = col.capacity, .items = col.items };
        }

        fn from_list(col: *Collect, list: std.ArrayList(Item)) void {
            col.capacity = list.capacity;
            col.items = list.items;
        }
    };
}

const Analyzer = struct {
    allocator: std.mem.Allocator,
    scope: std.ArrayList([]const u8),
    errors: std.ArrayList([]const u8),

    root: std.ArrayList(model.Declaration),

    structs: Collector(model.StructIndex),
    unions: Collector(model.UnionIndex),
    enums: Collector(model.EnumerationIndex),
    bitstructs: Collector(model.BitStructIndex),
    syscalls: Collector(model.SystemCallIndex),
    async_calls: Collector(model.AsyncCallIndex),
    resources: Collector(model.ResourceIndex),
    constants: Collector(model.ConstantIndex),

    types: Collector(model.TypeIndex),

    fn push_scope(ana: *Analyzer, name: []const u8) !model.FQN {
        try ana.scope.append(name);
        return try ana.allocator.dupe([]const u8, ana.scope.items);
    }

    fn pop_scope(ana: *Analyzer) void {
        std.debug.assert(ana.scope.pop() != null);
    }

    fn run(ana: *Analyzer, doc: syntax.Document) error{OutOfMemory}!void {
        try ana.root.resize(doc.nodes.len);
        for (ana.root.items, doc.nodes) |*out, node| {
            out.* = ana.map_node(node) catch |err| switch (err) {
                // swallow silently here, all nodes are independent from each other
                error.FatalAnalysisError => continue,

                error.OutOfMemory => |e| return e,
            };
        }
    }

    fn fatal_error(ana: *Analyzer, location: Location, comptime fmt: []const u8, args: anytype) error{ OutOfMemory, FatalAnalysisError } {
        try ana.emit_error(location, fmt, args);
        return error.FatalAnalysisError;
    }

    fn emit_error(ana: *Analyzer, location: Location, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
        const msg = try std.fmt.allocPrint(
            ana.allocator,
            "{}: " ++ fmt,
            .{location} ++ args,
        );
        try ana.errors.append(msg);
    }

    fn emit_unexpected_node(ana: *Analyzer, node: syntax.Node) !void {
        try ana.emit_error(node.location, "Unexpected node: {s}", .{@tagName(node.type)});
    }

    const MapError = error{
        OutOfMemory,
        FatalAnalysisError,
    };

    fn map_node(ana: *Analyzer, node: syntax.Node) MapError!model.Declaration {
        errdefer std.log.err("failed to map node at {}", .{node.location});

        return switch (node.type) {
            .declaration => try ana.map_decl(node),
            .typedef => try ana.map_typedef(node),
            .@"const" => try ana.map_const(node),

            .return_type => return ana.fatal_error(node.location, "invalid top-level element: return", .{}),
            .field => return ana.fatal_error(node.location, "invalid top-level element: field", .{}),
            .item => return ana.fatal_error(node.location, "invalid top-level element: item", .{}),
            .@"error" => return ana.fatal_error(node.location, "invalid top-level element: error", .{}),
            .reserve => return ana.fatal_error(node.location, "invalid top-level element: reserve", .{}),
            .ellipse => return ana.fatal_error(node.location, "invalid top-level element: ...", .{}),
        };
    }

    fn map_typedef(ana: *Analyzer, node: syntax.Node) !model.Declaration {
        const typedef = node.type.typedef;

        const full_name = try ana.push_scope(typedef.name);
        defer ana.pop_scope();

        const doc_comment = try ana.allocator.dupe([]const u8, node.doc_comment);

        const type_id = try ana.map_type(typedef.alias);

        return .{
            .full_qualified_name = full_name,
            .docs = doc_comment,
            .children = &.{},
            .data = .{ .typedef = type_id },
        };
    }

    fn map_const(ana: *Analyzer, node: syntax.Node) !model.Declaration {
        const constant = node.type.@"const";

        const full_name = try ana.push_scope(constant.name);
        defer ana.pop_scope();

        const doc_comment = try ana.allocator.dupe([]const u8, node.doc_comment);

        const value = try ana.resolve_value(constant.value.?);
        _ = value;

        // TODO: Implement explicit constant typing!
        const type_id: ?model.TypeIndex = null;

        const index = try ana.constants.append(.{
            .docs = doc_comment,
            .full_qualified_name = full_name,
            .type = type_id,
            // TODO: Store value!
        });

        return .{
            .full_qualified_name = full_name,
            .docs = doc_comment,
            .children = &.{},
            .data = .{ .constant = index },
        };
    }

    const NodeInfo = struct {
        full_name: model.FQN,
        docs: model.DocString,
        sub_type: ?model.StandardType,
        location: Location,
    };

    /// Strips empty heads and tails, then left-aligns a doc comment
    fn map_doc_comment(ana: *Analyzer, doc_comment: []const []const u8) !model.DocString {
        const ws = " ";

        var output = try ana.allocator.dupe([]const u8, doc_comment);

        // right-trim all lines
        for (output) |*item| {
            item.* = std.mem.trimRight(u8, item.*, ws);
        }

        // trim empty heads:
        while (output.len > 0 and output[0].len == 0) {
            output = output[1..];
        }

        // trim empty tails:
        while (output.len > 0 and output[output.len - 1].len == 0) {
            output = output[0 .. output.len - 1];
        }

        // Determine common whitespace prefix length:
        var common_prefix_len: usize = std.math.maxInt(usize);
        for (output) |line| {
            if (line.len == 0)
                continue;

            const prefix_len = for (line, 0..) |c, i| {
                if (std.mem.indexOfScalar(u8, ws, c) == null)
                    break i;
            } else unreachable; // lines are non-empty, and they must contain at least a non-space char

            common_prefix_len = @min(common_prefix_len, prefix_len);
        }

        // trim common prefix:
        for (output) |*line| {
            if (line.len == 0)
                continue;

            const prefix = line.*[0..common_prefix_len];

            // Prefix must be only whitespace:
            std.debug.assert(for (prefix) |c| {
                if (std.mem.indexOfScalar(u8, ws, c) == null)
                    break false;
            } else true);

            line.* = line.*[common_prefix_len..];
        }

        return output;
    }

    fn map_decl(ana: *Analyzer, node: syntax.Node) !model.Declaration {
        const decl = node.type.declaration;

        const full_name = try ana.push_scope(decl.name);
        defer ana.pop_scope();

        const doc_comment = try ana.map_doc_comment(node.doc_comment);

        var children: std.ArrayList(model.Declaration) = .init(ana.allocator);
        defer children.deinit();

        for (decl.children) |src| {
            if (!src.is_declaration())
                continue;
            switch (src.type) {
                .declaration, .typedef, .@"const" => try children.append(try ana.map_node(src)),
                else => unreachable,
            }
        }

        const needs_subtype = switch (decl.type) {
            .@"enum", .bitstruct => true,
            .@"struct", .@"union", .async_call, .syscall, .namespace, .resource => false,
        };

        const has_subtype = (decl.subtype != null);
        if (needs_subtype != has_subtype) {
            if (needs_subtype) {
                return ana.fatal_error(node.location, "Sub-type expected, but none present", .{});
            } else {
                return ana.fatal_error(node.location, "No sub-type expected, but one is given", .{});
            }
        }

        const sub_type: ?model.StandardType = if (needs_subtype) blk: {
            const model_type = try ana.map_type_inner(decl.subtype.?);
            if (model_type != .well_known)
                return ana.fatal_error(node.location, "subtype must be standard type, not a {s}", .{@tagName(model_type)});
            break :blk model_type.well_known;
        } else null;

        const info: NodeInfo = .{
            .docs = doc_comment,
            .full_name = full_name,
            .sub_type = sub_type,
            .location = node.location,
        };

        const data: model.Declaration.Data = switch (decl.type) {
            .namespace => .namespace,
            .@"struct" => try ana.map_struct(info, decl),
            .@"union" => try ana.map_union(info, decl),
            .@"enum" => try ana.map_enum(info, decl),
            .bitstruct => try ana.map_bit_struct(info, decl),
            .syscall => .namespace,
            .async_call => .namespace,
            .resource => try ana.map_resource(info, decl),
        };

        return .{
            .full_qualified_name = full_name,
            .docs = doc_comment,
            .children = try children.toOwnedSlice(),
            .data = data,
        };
    }

    fn map_resource(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        std.debug.assert(info.sub_type == null);

        for (decl.children) |child| {
            if (child.is_declaration())
                continue;
            try ana.emit_unexpected_node(child);
        }

        const index = try ana.resources.append(.{
            .docs = info.docs,
            .full_qualified_name = info.full_name,
        });

        return .{ .resource = index };
    }

    fn map_enum(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        std.debug.assert(info.sub_type != null);

        if (!info.sub_type.?.is_integer()) {
            return ana.fatal_error(info.location, "enum sub-type must be an integer", .{});
        }

        var last_index: i65 = 0;
        var kind: model.Enumeration.Kind = .closed;

        var items: std.ArrayList(model.EnumItem) = .init(ana.allocator);
        var defined: std.StringArrayHashMap(void) = .init(ana.allocator);

        for (decl.children) |child| {
            if (child.is_declaration())
                continue;
            switch (child.type) {
                .ellipse => {
                    if (kind == .open)
                        try ana.emit_error(child.location, "... specified twice", .{});
                    kind = .open;
                },

                .item => |data| {
                    const value: Value = if (data.value) |raw|
                        try ana.resolve_value(raw)
                    else
                        .{ .int = last_index + 1 };
                    if (value != .int)
                        return ana.fatal_error(child.location, "enum item value must be an integer, not a {s}", .{@tagName(value)});

                    if (defined.get(data.name) != null) {
                        try ana.emit_error(child.location, "duplicate enum item: {s}", .{data.name});
                    }
                    try defined.put(data.name, {});

                    try items.append(.{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = data.name,
                        .value = value.int,
                    });

                    last_index = value.int;
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        const index = try ana.enums.append(.{
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .backing_type = info.sub_type.?,
            .items = try items.toOwnedSlice(),
            .kind = kind,
        });

        return .{ .@"enum" = index };
    }

    fn map_struct(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        return try ana.map_struct_or_union(.@"struct", info, decl);
    }

    fn map_union(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        return try ana.map_struct_or_union(.@"union", info, decl);
    }

    fn map_struct_or_union(ana: *Analyzer, mode: enum { @"union", @"struct" }, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        std.debug.assert(info.sub_type == null);

        var fields: std.ArrayList(model.StructField) = .init(ana.allocator);
        var defined: std.StringArrayHashMap(void) = .init(ana.allocator);

        for (decl.children) |child| {
            if (child.is_declaration())
                continue;
            switch (child.type) {
                .field => |data| {
                    const type_id = try ana.map_type(data.field_type);

                    if (defined.get(data.name) != null) {
                        try ana.emit_error(child.location, "duplicate {s} field: {s}", .{ @tagName(mode), data.name });
                    }
                    try defined.put(data.name, {});

                    const default_value = if (data.default_value) |value| blk: {
                        if (mode == .@"union")
                            try ana.emit_error(child.location, "union fields cannot have default values", .{});

                        break :blk try ana.resolve_value(value);
                    } else null;

                    // TODO: Process default_value !
                    _ = default_value;

                    try fields.append(.{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = data.name,
                        .type = type_id,
                    });
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        const output: model.Struct = .{
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .fields = try fields.toOwnedSlice(),
        };

        switch (mode) {
            .@"struct" => {
                const index = try ana.structs.append(output);
                return .{ .@"struct" = index };
            },
            .@"union" => {
                const index = try ana.unions.append(output);
                return .{ .@"union" = index };
            },
        }
    }

    fn map_bit_struct(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        std.debug.assert(info.sub_type != null);

        if (!info.sub_type.?.is_integer()) {
            return ana.fatal_error(info.location, "enum sub-type must be an integer", .{});
        }

        var fields: std.ArrayList(model.BitStructField) = .init(ana.allocator);
        var defined: std.StringArrayHashMap(void) = .init(ana.allocator);

        for (decl.children) |child| {
            if (child.is_declaration())
                continue;
            switch (child.type) {
                .field => |data| {
                    const type_id = try ana.map_type(data.field_type);

                    if (defined.get(data.name) != null) {
                        try ana.emit_error(child.location, "duplicate bitstruct field: {s}", .{data.name});
                    }
                    try defined.put(data.name, {});

                    const default_value = if (data.default_value) |value|
                        try ana.resolve_value(value)
                    else
                        null;

                    // TODO: Process default_value !
                    _ = default_value;

                    try fields.append(.{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = data.name,
                        .type = type_id,
                    });
                },

                .reserve => |data| {
                    const type_id = try ana.map_type(data.type);

                    // TODO: Process padding_value !
                    const padding_value = try ana.resolve_value(data.value);
                    _ = padding_value;

                    try fields.append(.{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = null,
                        .type = type_id,
                    });
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        const index = try ana.bitstructs.append(.{
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .fields = try fields.toOwnedSlice(),
            .backing_type = info.sub_type.?,
        });
        return .{ .bitstruct = index };
    }

    const MapTypeError = error{OutOfMemory};

    fn map_type(ana: *Analyzer, type_node: *const syntax.TypeNode) MapTypeError!model.TypeIndex {
        const decl: model.Type = try ana.map_type_inner(type_node);

        if (ana.find_type(decl)) |index|
            return index;

        return try ana.types.append(decl);
    }

    fn find_type(ana: *Analyzer, decl: model.Type) ?model.TypeIndex {
        for (ana.types.items, 0..) |other, index| {
            if (@as(model.TypeId, other) != decl)
                continue;

            const eql = switch (decl) {
                // simple cases:

                inline .@"enum",
                .@"union",
                .@"struct",
                .bitstruct,
                .resource,
                .optional,
                .well_known,
                .uint,
                .int,
                => |val, tag| val == @field(other, @tagName(tag)),

                // TODO: Check if it makes sense to compare these:
                .external => false,
                .typedef => false,

                .fnptr => |ptr| std.mem.eql(model.TypeIndex, ptr.parameters, other.fnptr.parameters) and ptr.return_type == other.fnptr.return_type,

                .ptr => |ptr| ptr.size == other.ptr.size and ptr.alignment == other.ptr.alignment and ptr.is_const == other.ptr.is_const and ptr.child == other.ptr.child,

                .array => |arr| arr.size == other.array.size and arr.child == other.array.child,
            };
            if (eql)
                return .from_int(index);
        }
        return null;
    }

    fn map_type_inner(ana: *Analyzer, type_node: *const syntax.TypeNode) !model.Type {
        switch (type_node.*) {
            .builtin => |data| {
                const builtin: model.StandardType = switch (data) {
                    .void => .void,
                    .bool => .bool,
                    .noreturn => .noreturn,
                    .anyptr => .anyptr,
                    .anyfnptr => .anyfnptr,
                    .str => .str,
                    .bytestr => .bytestr,
                    .bytebuf => .bytebuf,
                    .usize => .usize,
                    .isize => .isize,
                    .f32 => .f32,
                    .f64 => .f64,
                };

                return .{ .well_known = builtin };
            },

            .named => |data| {
                const fqn = try ana.allocator.alloc([]const u8, 1);
                fqn[0] = data;
                // TODO: Properly implement named/external types
                return .{
                    .external = .{
                        .alias = data,
                        .full_qualified_name = fqn,
                        .docs = &.{},
                    },
                };
            },

            .optional => |data| {
                const child = try ana.map_type(data);
                return .{ .optional = child };
            },

            .pointer => |data| {
                const child = try ana.map_type(data.child);

                return .{
                    .ptr = .{
                        .child = child,
                        .alignment = data.alignment,
                        .is_const = data.is_const,
                        .size = switch (data.size) {
                            .one => .one,
                            .slice => .slice,
                            .unknown => .unknown,
                        },
                    },
                };
            },

            .array => |data| {
                const child = try ana.map_type(data.child);

                const size: u32 = 0; // TODO:  Implement resolution of named array sizes

                return .{
                    .array = .{
                        .child = child,
                        .size = size,
                    },
                };
            },

            .fnptr => |data| {
                var params: std.ArrayList(model.TypeIndex) = .init(ana.allocator);
                defer params.deinit();

                try params.resize(data.parameters.len);

                for (params.items, data.parameters) |*out, dst| {
                    out.* = try ana.map_type(dst);
                }

                const return_type = try ana.map_type(data.return_type);

                return .{
                    .fnptr = .{
                        .parameters = try params.toOwnedSlice(),
                        .return_type = return_type,
                    },
                };
            },

            .unsigned_int => |data| return switch (data) {
                8 => .{ .well_known = .u8 },
                16 => .{ .well_known = .u16 },
                32 => .{ .well_known = .u32 },
                64 => .{ .well_known = .u64 },
                else => .{ .uint = data },
            },

            .signed_int => |data| return switch (data) {
                8 => .{ .well_known = .i8 },
                16 => .{ .well_known = .i16 },
                32 => .{ .well_known = .i32 },
                64 => .{ .well_known = .i64 },
                else => .{ .int = data },
            },
        }
    }

    fn resolve_value(ana: *Analyzer, value: *const syntax.ValueNode) !Value {
        _ = ana;
        return switch (value.*) {
            .named => |name| switch (name) {
                .false => .{ .bool = false },
                .true => .{ .bool = true },
                .null => .null,
            },
            .uint => |int| .{ .int = int },
        };
    }

    pub const Value = union(enum) {
        null,
        bool: bool,
        int: i65,
        string: []const u8,
    };
};
