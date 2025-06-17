const std = @import("std");
const model = @import("model.zig");
const syntax = @import("syntax.zig");

const Location = syntax.Location;

pub fn analyze(allocator: std.mem.Allocator, document: syntax.Document) !model.Document {
    var analyzer: Analyzer = .{
        .allocator = allocator,
        .scope_stack = .init(allocator),
        .scope_map = .init(allocator),
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

    try analyzer.scope_map.put(&.{}, &analyzer.root_scope);

    try analyzer.map(document);

    try analyzer.resolve_named_types();

    // TODO: Resolve validity of bitstructs

    // TODO: Validate if all constant and default values fit their assignment

    // TODO: Compute type sizes, field offsets

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

const ScopeContext = struct {
    pub fn hash(self: @This(), s: []const []const u8) u32 {
        var hasher: std.hash.Wyhash = .init(s.len);
        for (s) |i| {
            hasher.update(std.mem.asBytes(&i.len));
            hasher.update(i);
        }
        _ = self;
        return @truncate(hasher.final());
    }
    pub fn eql(self: @This(), a: []const []const u8, b: []const []const u8, b_index: usize) bool {
        _ = self;
        _ = b_index;
        if (a.len != b.len)
            return false;
        for (a, b) |l, r| {
            if (!std.mem.eql(u8, l, r))
                return false;
        }
        return true;
    }
};

const Analyzer = struct {
    allocator: std.mem.Allocator,
    scope_stack: std.ArrayList([]const u8),
    scope_map: std.ArrayHashMap([]const []const u8, *Scope, ScopeContext, true),
    errors: std.ArrayList([]const u8),

    root_scope: Scope = .{
        .parent = null,
        .name = "<root>",
        .type = .namespace,
    },

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

    const Scope = struct {
        parent: ?*Scope,
        type: Type,
        name: []const u8,
        link: ?Link = null,
        children: std.StringArrayHashMapUnmanaged(*Scope) = .empty,

        const Type = std.meta.Tag(Link);

        const Link = model.Declaration.Data;

        pub fn set_link(scope: *Scope, link: Link) void {
            std.debug.assert(scope.link == null);
            std.debug.assert(scope.type == link);
            scope.link = link;
        }
    };

    fn push_scope(ana: *Analyzer, name: []const u8, scope_type: Scope.Type) !struct { model.FQN, *Scope } {
        const current_name = ana.current_scope_name();

        const current_scope = ana.scope_map.get(current_name) orelse {
            std.log.err("current scope: {s}", .{current_name});
            @panic("BUG: No current scope found!");
        };

        const inserted = if (current_scope.children.get(name)) |existing_child| blk: {
            if (scope_type != existing_child.type)
                @panic("scope mismatch");
            break :blk false;
        } else blk: {
            const child_scope: *Scope = try ana.allocator.create(Scope);
            child_scope.* = .{
                .parent = current_scope,
                .name = name,
                .type = scope_type,
            };

            try current_scope.children.put(ana.allocator, name, child_scope);
            break :blk true;
        };

        try ana.scope_stack.append(name);

        const scope = current_scope.children.get(name).?;

        const scope_name = try ana.allocator.dupe([]const u8, ana.scope_stack.items);

        if (inserted) {
            try ana.scope_map.putNoClobber(scope_name, scope);
        }

        return .{ scope_name, scope };
    }

    fn pop_scope(ana: *Analyzer) void {
        std.debug.assert(ana.scope_stack.pop() != null);
    }

    fn current_scope_name(ana: *Analyzer) []const []const u8 {
        return ana.scope_stack.items;
    }

    fn map(ana: *Analyzer, doc: syntax.Document) error{OutOfMemory}!void {
        try ana.root.resize(doc.nodes.len);
        for (ana.root.items, doc.nodes) |*out, node| {
            out.* = ana.map_node(node) catch |err| switch (err) {
                // swallow silently here, all nodes are independent from each other
                error.FatalAnalysisError => continue,

                error.OutOfMemory => |e| return e,
            };
        }
    }

    fn resolve_named_types(ana: *Analyzer) !void {
        element_resolution: for (ana.types.items) |*typedef| {
            if (typedef.* != .unknown_named_type)
                continue;
            const unknown_type = &typedef.unknown_named_type;

            // std.log.debug("unknown type @ scope {s}, references {s}", .{
            //     unknown_type.declared_scope,
            //     unknown_type.local_qualified_name,
            // });
            std.debug.assert(unknown_type.local_qualified_name.len > 0);

            var search_scope: ?*Scope = ana.scope_map.get(unknown_type.declared_scope) orelse @panic("BUG: declared_scope not found in scope_map");

            candidate_search: while (search_scope) |base_scope| : (search_scope = base_scope.parent) {
                const base_name = unknown_type.local_qualified_name[0];
                if (base_scope.children.get(base_name) != null) {
                    // std.log.debug("  candidate: {s}.{s}", .{ base_scope.name, child.name });

                    var sub_scope: *Scope = base_scope;
                    for (unknown_type.local_qualified_name) |local_name| {
                        const sub_item = sub_scope.children.get(local_name) orelse {
                            // std.log.debug("    discard: {s}.{s}…{s}", .{ base_scope.name, child.name, local_name });
                            continue :candidate_search;
                        };

                        sub_scope = sub_item;
                    }

                    if (sub_scope.type == .namespace) {
                        // std.log.debug("    ! candidate rejected: {s} is namespace!", .{sub_scope.name});
                        continue :candidate_search;
                    }

                    std.debug.assert(sub_scope.link != null);
                    std.debug.assert(sub_scope.link.? == sub_scope.type);

                    typedef.* = switch (sub_scope.link.?) {
                        .namespace => unreachable,
                        .@"struct" => |index| .{ .@"struct" = index },
                        .@"union" => |index| .{ .@"union" = index },
                        .@"enum" => |index| .{ .@"enum" = index },
                        .bitstruct => |index| .{ .bitstruct = index },
                        .resource => |index| .{ .resource = index },
                        .typedef => |index| .{ .alias = index },
                        .syscall => @panic("TODO: Invalid type reference!"),
                        .async_call => @panic("TODO: Invalid type reference!"),
                        .constant => @panic("TODO: Invalid type reference!"),
                    };

                    // std.log.debug("    ! candidate found {s} ({s})!", .{ sub_scope.name, @tagName(sub_scope.type) });

                    continue :element_resolution;
                }
            }
            std.log.err("no candidate found for type {s} at {s}!", .{
                unknown_type.local_qualified_name,
                unknown_type.declared_scope,
            });
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

            .in => return ana.fatal_error(node.location, "invalid top-level element: in", .{}),
            .out => return ana.fatal_error(node.location, "invalid top-level element: out", .{}),
            .field => return ana.fatal_error(node.location, "invalid top-level element: field", .{}),

            .item => return ana.fatal_error(node.location, "invalid top-level element: item", .{}),
            .@"error" => return ana.fatal_error(node.location, "invalid top-level element: error", .{}),
            .reserve => return ana.fatal_error(node.location, "invalid top-level element: reserve", .{}),
            .ellipse => return ana.fatal_error(node.location, "invalid top-level element: ...", .{}),
            .noreturn => return ana.fatal_error(node.location, "invalid top-level element: noreturn", .{}),
        };
    }

    fn map_typedef(ana: *Analyzer, node: syntax.Node) !model.Declaration {
        const typedef = node.type.typedef;

        const full_name, const scope = try ana.push_scope(typedef.name, .typedef);
        defer ana.pop_scope();

        const doc_comment = try ana.allocator.dupe([]const u8, node.doc_comment);

        const type_id = try ana.map_type(typedef.alias);

        scope.set_link(.{ .typedef = type_id });

        return .{
            .full_qualified_name = full_name,
            .docs = doc_comment,
            .children = &.{},
            .data = .{ .typedef = type_id },
        };
    }

    fn map_const(ana: *Analyzer, node: syntax.Node) !model.Declaration {
        const constant = node.type.@"const";

        const full_name, const scope = try ana.push_scope(constant.name, .constant);
        defer ana.pop_scope();

        const doc_comment = try ana.allocator.dupe([]const u8, node.doc_comment);

        const value = try ana.resolve_value(constant.value.?);

        // TODO: Implement explicit constant typing!
        const type_id: ?model.TypeIndex = null;

        const index = try ana.constants.append(.{
            .docs = doc_comment,
            .full_qualified_name = full_name,
            .type = type_id,
            .value = value,
        });

        scope.set_link(.{ .constant = index });

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

        const full_name, const scope = try ana.push_scope(decl.name, convert_enum(Scope.Type, decl.type));
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
            .syscall => try ana.map_syscall(info, decl),
            .async_call => try ana.map_async_call(info, decl),
            .resource => try ana.map_resource(info, decl),
        };

        scope.set_link(data);

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

        var items = ana.make_collector(
            model.EnumItem,
            "name",
            "duplicate enum item: {s}",
        );

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
                    const value: model.Value = if (data.value) |raw|
                        try ana.resolve_value(raw)
                    else
                        .{ .int = last_index + 1 };
                    if (value != .int)
                        return ana.fatal_error(child.location, "enum item value must be an integer, not a {s}", .{@tagName(value)});

                    try items.append(child.location, .{
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
            .items = try items.resolve(),
            .kind = kind,
        });

        return .{ .@"enum" = index };
    }

    fn map_syscall(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        return ana.map_any_call(.syscall, info, decl);
    }

    fn map_async_call(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        return ana.map_any_call(.async_call, info, decl);
    }

    fn map_any_call(ana: *Analyzer, mode: enum { syscall, async_call }, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        std.debug.assert(info.sub_type == null);

        var inputs = ana.make_collector(
            model.Parameter,
            "name",
            "duplicate in parameter: {s}",
        );
        var outputs = ana.make_collector(
            model.Parameter,
            "name",
            "duplicate out parameter: {s}",
        );

        var errors = ana.make_collector(
            model.Error,
            "name",
            "duplicate error: {s}",
        );

        var no_return = false;

        for (decl.children) |child| {
            if (child.is_declaration())
                continue;
            switch (child.type) {
                .in, .out => |data| {
                    const type_id = try ana.map_type(data.field_type);

                    const default_value = if (data.default_value) |value| blk: {
                        if (child.type == .out)
                            try ana.emit_error(child.location, "output parameters cannot have default values", .{});

                        break :blk try ana.resolve_value(value);
                    } else null;

                    const param: model.Parameter = .{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = data.name,
                        .type = type_id,
                        .default = default_value,
                    };

                    if (child.type == .in) {
                        try inputs.append(child.location, param);
                    } else {
                        std.debug.assert(child.type == .out);
                        try outputs.append(child.location, param);
                    }
                },

                .@"error" => |data| {
                    try errors.append(child.location, .{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = data,
                    });
                },

                .noreturn => {
                    if (no_return) {
                        try ana.emit_error(child.location, "duplicate noreturn definition", .{});
                    }
                    no_return = true;
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        if (no_return and outputs.fields.items.len > 0) {
            try ana.emit_error(info.location, "calls that are noreturn cannot have out parameters", .{});
        }

        const output: model.GenericCall = .{
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .inputs = try inputs.resolve(),
            .outputs = try outputs.resolve(),
            .errors = try errors.resolve(),
            .no_return = no_return,
        };

        switch (mode) {
            .syscall => {
                const index = try ana.syscalls.append(output);
                return .{ .syscall = index };
            },
            .async_call => {
                const index = try ana.async_calls.append(output);
                return .{ .async_call = index };
            },
        }
    }

    fn map_struct(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        return try ana.map_struct_or_union(.@"struct", info, decl);
    }

    fn map_union(ana: *Analyzer, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        return try ana.map_struct_or_union(.@"union", info, decl);
    }

    fn map_struct_or_union(ana: *Analyzer, comptime mode: enum { @"union", @"struct" }, info: NodeInfo, decl: syntax.DeclarationNode) !model.Declaration.Data {
        std.debug.assert(info.sub_type == null);

        var fields = ana.make_collector(
            model.StructField,
            "name",
            "duplicate " ++ @tagName(mode) ++ " field: {s}",
        );

        for (decl.children) |child| {
            if (child.is_declaration())
                continue;
            switch (child.type) {
                .field => |data| {
                    const type_id = try ana.map_type(data.field_type);

                    const default_value = if (data.default_value) |value| blk: {
                        if (mode == .@"union")
                            try ana.emit_error(child.location, "union fields cannot have default values", .{});

                        break :blk try ana.resolve_value(value);
                    } else null;

                    try fields.append(child.location, .{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = data.name,
                        .type = type_id,
                        .default = default_value,
                    });
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        const output: model.Struct = .{
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .fields = try fields.resolve(),
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

        var fields = ana.make_collector(
            model.BitStructField,
            "name",
            "duplicate bitstruct field: {s}",
        );

        for (decl.children) |child| {
            if (child.is_declaration())
                continue;
            switch (child.type) {
                .field => |data| {
                    const type_id = try ana.map_type(data.field_type);

                    const default_value = if (data.default_value) |value|
                        try ana.resolve_value(value)
                    else
                        null;

                    try fields.append(child.location, .{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = data.name,
                        .type = type_id,
                        .default = default_value,
                    });
                },

                .reserve => |data| {
                    const type_id = try ana.map_type(data.type);

                    const padding_value = try ana.resolve_value(data.value);

                    try fields.append(child.location, .{
                        .docs = try ana.map_doc_comment(child.doc_comment),
                        .name = null,
                        .type = type_id,
                        .default = padding_value,
                    });
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        const index = try ana.bitstructs.append(.{
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .fields = try fields.resolve(),
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
                .alias,
                => |val, tag| val == @field(other, @tagName(tag)),

                // TODO: Check if it makes sense to compare these:
                .external => false,
                .typedef => false,

                .fnptr => |ptr| std.mem.eql(model.TypeIndex, ptr.parameters, other.fnptr.parameters) and ptr.return_type == other.fnptr.return_type,

                .ptr => |ptr| ptr.size == other.ptr.size and ptr.alignment == other.ptr.alignment and ptr.is_const == other.ptr.is_const and ptr.child == other.ptr.child,

                .array => |arr| arr.size == other.array.size and arr.child == other.array.child,

                .unknown_named_type => |unknown| blk: {
                    if (unknown.declared_scope.len != other.unknown_named_type.declared_scope.len)
                        break :blk false;
                    if (unknown.local_qualified_name.len != other.unknown_named_type.local_qualified_name.len)
                        break :blk false;

                    for (unknown.declared_scope, other.unknown_named_type.declared_scope) |lhs, rhs| {
                        if (!std.mem.eql(u8, lhs, rhs))
                            break :blk false;
                    }

                    for (unknown.local_qualified_name, other.unknown_named_type.local_qualified_name) |lhs, rhs| {
                        if (!std.mem.eql(u8, lhs, rhs))
                            break :blk false;
                    }

                    break :blk true;
                },
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
                var fqn: std.ArrayList([]const u8) = .init(ana.allocator);
                defer fqn.deinit();

                var iter = std.mem.splitScalar(u8, data, '.');

                while (iter.next()) |part| {
                    if (part.len == 0) {
                        @panic("TODO: Empty parts!");
                        // try ana.emit_error();
                        // continue;
                    }
                    try fqn.append(part);
                }

                std.debug.assert(fqn.items.len > 0);

                return .{
                    .unknown_named_type = .{
                        .declared_scope = try ana.allocator.dupe([]const u8, ana.current_scope_name()),
                        .local_qualified_name = try fqn.toOwnedSlice(),
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

    fn resolve_value(ana: *Analyzer, value: *const syntax.ValueNode) !model.Value {
        return switch (value.*) {
            .named => |name| switch (name) {
                .false => .{ .bool = false },
                .true => .{ .bool = true },
                .null => .null,
            },
            .uint => |int| .{ .int = int },
            .compound => |compound| {
                var out: model.CompoundType = .{
                    .fields = .init(ana.allocator),
                };
                errdefer out.fields.deinit();

                try out.fields.ensureTotalCapacity(compound.len);

                var available_fields: std.StringArrayHashMap(void) = .init(ana.allocator);
                defer available_fields.deinit();

                for (compound) |field_init| {
                    if (try available_fields.fetchPut(field_init.name, {}) != null) {
                        try ana.emit_error(field_init.location, "Duplicate field assignment '{s}'", .{field_init.name});
                        continue;
                    }

                    const field_value = try ana.resolve_value(field_init.value);
                    out.fields.putAssumeCapacityNoClobber(field_init.name, field_value);
                }

                return .{ .compound = out };
            },
        };
    }

    fn make_collector(ana: *Analyzer, comptime T: type, comptime name_field: []const u8, comptime error_fmt: []const u8) NamedItemCollector(T, name_field, error_fmt) {
        return .{
            .ana = ana,
            .fields = .init(ana.allocator),
            .defined = .init(ana.allocator),
        };
    }

    fn NamedItemCollector(comptime T: type, comptime name_field: []const u8, comptime error_fmt: []const u8) type {
        std.debug.assert(@hasField(T, name_field));
        return struct {
            ana: *Analyzer,
            fields: std.ArrayList(T),
            defined: std.StringArrayHashMap(void),

            pub fn append(col: *@This(), location: Location, item: T) !void {
                const maybe_name: ?[]const u8 = @field(item, name_field);
                try col.fields.append(item);

                if (maybe_name) |name| {
                    if (try col.defined.fetchPut(name, {}) != null) {
                        try col.ana.emit_error(location, error_fmt, .{name});
                    }
                }
            }

            pub fn resolve(col: *@This()) ![]T {
                const result = try col.fields.toOwnedSlice();
                col.defined.clearAndFree();
                return result;
            }
        };
    }
};

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

fn convert_enum(comptime T: type, src: anytype) T {
    return switch (src) {
        inline else => |tag| @field(T, @tagName(tag)),
    };
}
