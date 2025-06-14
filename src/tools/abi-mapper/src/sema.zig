const std = @import("std");
const model = @import("model.zig");
const syntax = @import("syntax.zig");

pub fn analyze(allocator: std.mem.Allocator, document: syntax.Document) !model.Document {
    var analyzer: Analyzer = .{
        .allocator = allocator,
        .scope = .init(allocator),

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

const Analyzer = struct {
    allocator: std.mem.Allocator,
    scope: std.ArrayList([]const u8),

    root: std.ArrayList(model.Declaration),

    structs: std.ArrayList(model.Struct),
    unions: std.ArrayList(model.Struct),
    enums: std.ArrayList(model.Enumeration),
    bitstructs: std.ArrayList(model.BitStruct),
    syscalls: std.ArrayList(model.SystemCall),
    async_calls: std.ArrayList(model.AsyncCall),
    resources: std.ArrayList(model.Resource),
    constants: std.ArrayList(model.Constant),

    types: std.ArrayList(model.Type),

    fn push_scope(ana: *Analyzer, name: []const u8) !model.FQN {
        try ana.scope.append(name);
        return try ana.allocator.dupe([]const u8, ana.scope.items);
    }

    fn pop_scope(ana: *Analyzer) void {
        std.debug.assert(ana.scope.pop() != null);
    }

    fn run(ana: *Analyzer, doc: syntax.Document) !void {
        try ana.root.resize(doc.nodes.len);
        for (ana.root.items, doc.nodes) |*out, node| {
            out.* = try ana.map_node(node);
        }
    }

    const MapError = error{
        OutOfMemory,
    };

    fn map_node(ana: *Analyzer, node: syntax.Node) MapError!model.Declaration {
        errdefer std.log.err("failed to map node at {}", .{node.location});

        return switch (node.type) {
            .declaration => try ana.map_decl(node),
            .typedef => try ana.map_typedef(node),
            .@"const" => try ana.map_const(node),

            .return_type => @panic("return_type not implemented yet!"),
            .field => @panic("field not implemented yet!"),
            .item => @panic("item not implemented yet!"),
            .name => @panic("name not implemented yet!"),
            .reserve => @panic("reserve not implemented yet!"),
            .ellipse => @panic("ellipse not implemented yet!"),
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

        return .{
            .full_qualified_name = full_name,
            .docs = doc_comment,
            .children = &.{},
            .data = .{ .constant = 0 }, // TODO: Implement this!
        };
    }

    fn map_decl(ana: *Analyzer, node: syntax.Node) !model.Declaration {
        const decl = node.type.declaration;

        const full_name = try ana.push_scope(decl.name);
        defer ana.pop_scope();

        const doc_comment = try ana.allocator.dupe([]const u8, node.doc_comment);

        var children: std.ArrayList(model.Declaration) = .init(ana.allocator);
        defer children.deinit();

        for (decl.children) |src| {
            switch (src.type) {
                .declaration, .typedef, .@"const" => try children.append(try ana.map_node(src)),
                .ellipse, .field, .name, .reserve, .return_type, .item => continue,
            }
        }

        return .{
            .full_qualified_name = full_name,
            .docs = doc_comment,
            .children = try children.toOwnedSlice(),
            .data = .namespace,
        };
    }

    const MapTypeError = error{OutOfMemory};

    fn map_type(ana: *Analyzer, type_node: *const syntax.TypeNode) MapTypeError!usize {
        const decl: model.Type = try ana.map_type_inner(type_node);

        if (ana.find_type(decl)) |index|
            return index;

        const index = ana.types.items.len;
        try ana.types.append(decl);
        return index;
    }

    fn find_type(ana: *Analyzer, decl: model.Type) ?usize {
        for (ana.types.items, 0..) |other, index| {
            if (@as(model.TypeId, other) != decl)
                continue;

            const eql = switch (decl) {
                // simple cases:

                inline .@"enum",
                .@"union",
                .@"struct",
                .bitstruct,
                .optional,
                .well_known,
                .uint,
                .int,
                => |val, tag| val == @field(other, @tagName(tag)),

                // TODO: Check if it makes sense to compare these:
                .external => false,
                .typedef => false,

                .fnptr => |ptr| std.mem.eql(usize, ptr.parameters, other.fnptr.parameters) and ptr.return_type == other.fnptr.return_type,

                .ptr => |ptr| ptr.size == other.ptr.size and ptr.alignment == other.ptr.alignment and ptr.is_const == other.ptr.is_const and ptr.child == other.ptr.child,
            };
            if (eql)
                return index;
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
                _ = data;
                @panic("array is not supported yet!");
            },

            .fnptr => |data| {
                var params: std.ArrayList(usize) = .init(ana.allocator);
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
};
