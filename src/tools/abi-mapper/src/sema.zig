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

    try analyzer.resolve_magic_types();

    // TODO: resolve_magic_types must also rewrite the tree to change 'typedef' references into the fitting 'enum' or whatever ref

    try analyzer.validate_bit_structs();

    try analyzer.compute_native_items();

    // TODO: Validate if all constant and default values fit their assignment

    // TODO: Compute type sizes, field offsets

    if (analyzer.errors.items.len > 0) {
        for (analyzer.errors.items) |err| {
            std.log.err("{s}", .{err});
        }
        return error.AnalysisFailed;
    }

    // TODO: Implement garbage collection for unreferenced things

    // analyzer.validate_constraints();

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

    uid_base: u32 = 1,

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

    /// Returns a unique ID based on the `fqn` of the object.
    fn get_uid(ana: *Analyzer, fqn: model.FQN) error{OutOfMemory}!model.UniqueID {
        _ = fqn; // TODO: Implement derivation from FQN and a UID database.
        const uid: model.UniqueID = @enumFromInt(ana.uid_base);
        ana.uid_base += 1;
        return uid;
    }

    fn format(ana: *Analyzer, comptime fmt: []const u8, args: anytype) ![]const u8 {
        return try std.fmt.allocPrint(ana.allocator, fmt, args);
    }

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

    fn resolve_magic_types(ana: *Analyzer) !void {
        // TODO: Ensure all potentially required types exist.

        for (ana.types.items) |*type_ref| {
            if (type_ref.* != .typedef)
                continue;

            const type_def = type_ref.typedef;

            const aliased_type = ana.types.get(type_def.alias);
            if (aliased_type.* != .unset_magic_type)
                continue;
            const magic_type = aliased_type.unset_magic_type;

            // std.log.err("reify {s} into {s}: {s} ", .{
            //     type_def.full_qualified_name,
            //     @tagName(magic_type.kind),
            //     @tagName(magic_type.size),
            // });

            var items: std.ArrayList(model.EnumItem) = .init(ana.allocator);
            defer items.deinit();

            switch (magic_type.kind) {
                inline else => |tag| {
                    const tag_name = @tagName(tag);
                    comptime std.debug.assert(std.mem.endsWith(u8, tag_name, "_enum"));

                    const collector_name = tag_name[0 .. tag_name.len - "_enum".len] ++ "s";

                    const collector = &@field(ana, collector_name);

                    for (collector.items, 1..) |item, index| {
                        var item_name: std.ArrayList(u8) = .init(ana.allocator);
                        defer item_name.deinit();

                        try item_name.ensureTotalCapacity(120);

                        for (item.full_qualified_name, 0..) |local_name, i| {
                            if (i > 0) {
                                try item_name.append('_');
                            }

                            for (local_name, 0..) |c, j| {
                                if (j > 0 and std.ascii.isUpper(c)) {
                                    try item_name.append('_');
                                }
                                try item_name.append(std.ascii.toLower(c));
                            }
                        }

                        // TODO: Implement stable item id assignment!

                        try items.append(.{
                            .docs = &.{},
                            .name = try item_name.toOwnedSlice(),
                            .value = @intCast(index),
                        });
                    }
                },
            }

            const enum_id = try ana.enums.append(.{
                .uid = try ana.get_uid(type_def.full_qualified_name),
                .backing_type = convert_enum(model.StandardType, magic_type.size),

                .docs = type_def.docs,
                .full_qualified_name = type_def.full_qualified_name,
                .kind = .closed,
                .items = try items.toOwnedSlice(),
            });

            type_ref.* = .{ .@"enum" = enum_id };
        }

        const Patch = struct {
            ana: *Analyzer,
            //
            pub fn apply(patch: @This(), decl: *model.Declaration) !void {
                if (decl.data != .typedef)
                    return;

                const target_type = patch.ana.types.get(decl.data.typedef);

                const new_decl: model.Declaration.Data = switch (target_type.*) {

                    // no change, the type is still an indirection
                    .typedef => return,

                    .@"enum" => |idx| .{ .@"enum" = idx },

                    .unset_magic_type => @panic("BUG: Magic type was not properly resolved in the code block above"),

                    .@"struct",
                    .@"union",
                    .bitstruct,
                    .resource,
                    .well_known,
                    .external,
                    .alias,
                    .optional,
                    .array,
                    .uint,
                    .int,
                    .ptr,
                    .fnptr,
                    .unknown_named_type,
                    => unreachable,
                };

                decl.data = new_decl;
            }
        };

        try ana.patch_tree(Patch{ .ana = ana });
    }

    fn validate_bit_structs(ana: *Analyzer) !void {
        for (ana.bitstructs.items) |bitstruct| {
            std.debug.assert(bitstruct.backing_type.is_integer());
            std.debug.assert(bitstruct.backing_type.size_in_bits() != null); // Assert we don't use `usize` or `isize` here!

            const expected_size = bitstruct.backing_type.size_in_bits().?;

            // std.log.err("bitstruct {s}", .{bitstruct.full_qualified_name});

            var struct_size: u8 = 0;
            for (@constCast(bitstruct.fields)) |*field| {
                const field_type = ana.get_resolved_type(field.type);
                const maybe_type_size = get_type_bit_size(field_type);
                // std.log.err("  {?s} => {} ({?} bits)", .{ field.name, field_type, maybe_type_size });

                const type_size = maybe_type_size orelse {
                    @panic("TODO: error report for 'type not bit-packable'");
                };

                field.bit_shift = struct_size;
                field.bit_count = type_size;

                struct_size += type_size;
            }

            if (struct_size > expected_size) {
                @panic("TODO: error reporting for 'fields too big'");
            } else if (struct_size < expected_size) {
                @panic("TODO: error reporting for 'fields too little'");
            }
        }
    }

    /// `tvalue` must be fully resolved and must not be any type alias
    fn get_type_bit_size(tvalue: model.Type) ?u8 {
        return switch (tvalue) {
            .alias => unreachable,
            .typedef => unreachable,
            .unknown_named_type => unreachable,
            .unset_magic_type => unreachable,

            .uint => |bits| bits,
            .int => |bits| bits,

            .well_known => |stdtype| stdtype.size_in_bits(),

            .@"enum" => @panic("TODO"),
            .bitstruct => @panic("TODO"),

            .fnptr => null,
            .ptr => null,
            .array => null,
            .optional => null,
            .external => null,
            .resource => null,

            .@"union" => null,
            .@"struct" => null,
        };
    }

    fn compute_native_items(ana: *Analyzer) !void {
        for (ana.syscalls.items) |*syscall| {
            try ana.compute_native_params(syscall, .function_call);
        }

        for (ana.async_calls.items) |*syscall| {
            try ana.compute_native_params(syscall, .structure);
        }

        for (ana.structs.items) |*container| {
            try ana.compute_native_fields(container);
        }

        for (ana.unions.items) |*container| {
            try ana.compute_native_fields(container);
        }
    }

    const NativeParamMode = enum { function_call, structure };
    fn compute_native_params(ana: *Analyzer, call: *model.GenericCall, emit_mode: NativeParamMode) !void {
        std.debug.assert(call.native_inputs.len == 0);
        std.debug.assert(call.native_outputs.len == 0);

        var native_inputs: std.ArrayList(model.Parameter) = .init(ana.allocator);
        defer native_inputs.deinit();

        var native_outputs: std.ArrayList(model.Parameter) = .init(ana.allocator);
        defer native_outputs.deinit();

        const Helper = struct {
            fn remap_outputs(a: *Analyzer, ni: *std.ArrayList(model.Parameter), no: *std.ArrayList(model.Parameter)) !void {
                try ni.ensureUnusedCapacity(no.items.len);
                for (no.items) |item| {
                    var copy = item;
                    copy.type = try a.map_model_type(.{ .ptr = .{
                        .alignment = null,
                        .is_const = false,
                        .size = .one,
                        .child = item.type,
                    } });
                    if (copy.role == .default) {
                        copy.role = .output;
                    }
                    ni.appendAssumeCapacity(copy);
                }
                no.clearAndFree();
            }

            const RenderMode = enum { input, output };

            fn render(a: *Analyzer, list: *std.ArrayList(model.Parameter), params: []model.Parameter, mode: RenderMode) !void {
                for (params) |*param| {
                    const resolved = a.get_resolved_type(param.type);
                    if (resolved.is_c_abi_compatible()) {
                        try list.append(param.*);
                        continue;
                    }

                    switch (resolved) {
                        .well_known => |id| switch (id) {
                            .bytestr, .bytebuf, .str => {
                                try emit_slice(a, list, param, .{
                                    .ptr = .{
                                        .alignment = null,
                                        .is_const = (id != .bytebuf),
                                        .size = .unknown,
                                        .child = try a.map_model_type(.{ .well_known = .u8 }),
                                    },
                                }, mode);
                            },
                            else => unreachable, // all others are C-abi compatible
                        },

                        .ptr => |ptr| {
                            std.debug.assert(ptr.size == .slice);
                            try emit_slice(a, list, param, .{
                                .ptr = .{
                                    .alignment = ptr.alignment,
                                    .is_const = ptr.is_const,
                                    .size = .unknown,
                                    .child = ptr.child,
                                },
                            }, mode);
                        },

                        .optional => |inner_id| {
                            const inner = a.get_resolved_type(inner_id);
                            switch (inner) {
                                .well_known => |id| switch (id) {
                                    .bytestr, .bytebuf, .str => {
                                        try emit_slice(a, list, param, .{
                                            .optional = try a.map_model_type(.{
                                                .ptr = .{
                                                    .alignment = null,
                                                    .is_const = (id != .bytebuf),
                                                    .size = .unknown,
                                                    .child = try a.map_model_type(.{ .well_known = .u8 }),
                                                },
                                            }),
                                        }, mode);
                                    },
                                    .anyptr, .anyfnptr => {
                                        try list.append(param.*);
                                    },
                                    else => {
                                        std.log.err("unsupported optional builtin type {}", .{inner});
                                    },
                                },
                                .ptr => |ptr| switch (ptr.size) {
                                    .one, .unknown => {
                                        try list.append(param.*);
                                    },
                                    .slice => {
                                        try emit_slice(a, list, param, .{
                                            .optional = try a.map_model_type(.{
                                                .ptr = .{
                                                    .alignment = ptr.alignment,
                                                    .is_const = ptr.is_const,
                                                    .size = .unknown,
                                                    .child = ptr.child,
                                                },
                                            }),
                                        }, mode);
                                    },
                                },
                                .resource => {
                                    // TODO: How to handle optional system resources properly?
                                    var copy = param.*;
                                    copy.type = inner_id;
                                    try list.append(copy);
                                },
                                else => {
                                    std.log.err("unsupported optional type {}", .{inner});
                                },
                            }
                        },

                        else => {

                            // TODO!
                            std.log.err("implement type resolution for {}", .{a.get_resolved_type(param.type)});
                        },
                    }
                }
            }

            fn emit_slice(
                a: *Analyzer,
                list: *std.ArrayList(model.Parameter),
                param: *model.Parameter,
                ptr_type: model.Type,
                mode: RenderMode,
            ) !void {
                const ptr_name = try a.format("{s}_ptr", .{param.name});
                const len_name = try a.format("{s}_len", .{param.name});

                param.role = switch (mode) {
                    .input => .{ .input_slice = .{ .ptr = ptr_name, .len = len_name } },
                    .output => .{ .output_slice = .{ .ptr = ptr_name, .len = len_name } },
                };

                try list.append(.{
                    .docs = param.docs,
                    .name = ptr_name,
                    .type = try a.map_model_type(ptr_type),
                    .role = switch (mode) {
                        .input => .{ .input_ptr = param.name },
                        .output => .{ .output_ptr = param.name },
                    },
                    .default = null,
                });
                try list.append(.{
                    .docs = try a.allocator.dupe([]const u8, &.{
                        try a.format("The number of elements referenced by {s}_ptr.", .{param.name}),
                    }),
                    .name = len_name,
                    .type = try a.map_model_type(.{ .well_known = .usize }),
                    .role = switch (mode) {
                        .input => .{ .input_len = param.name },
                        .output => .{ .output_len = param.name },
                    },
                    .default = null,
                });
            }
        };

        // @constCast is fine here, as we do still own all the data
        try Helper.render(ana, &native_inputs, @constCast(call.logic_inputs), .input);
        try Helper.render(ana, &native_outputs, @constCast(call.logic_outputs), .output);

        switch (emit_mode) {
            .function_call => {
                if (call.errors.len > 0) {
                    // function has errors, append all output parameters to the inputs,
                    // then replace with error return value

                    try Helper.remap_outputs(ana, &native_inputs, &native_outputs);

                    try native_outputs.append(.{
                        .name = "error_code",
                        .default = null,
                        .docs = &.{},
                        .role = .@"error",
                        .type = try ana.map_model_type(.{ .well_known = .u16 }),
                    });
                } else if (native_outputs.items.len == 1) {
                    // function has a (true) single return value, we can keep that for C

                } else {
                    // function must return `void` as we cannot return more than a single value through C ABI.
                    // also convert all outputs to input parameters with pointers:
                    try Helper.remap_outputs(ana, &native_inputs, &native_outputs);
                }

                std.debug.assert(native_outputs.items.len <= 1);
            },
            .structure => {},
        }

        call.native_inputs = try native_inputs.toOwnedSlice();
        call.native_outputs = try native_outputs.toOwnedSlice();
    }

    fn compute_native_fields(ana: *Analyzer, container: *model.Struct) !void {
        std.debug.assert(container.native_fields.len == 0);

        var native_fields: std.ArrayList(model.StructField) = .init(ana.allocator);
        defer native_fields.deinit();

        const Helper = struct {
            ana: *Analyzer,
            nf: *std.ArrayList(model.StructField),

            fn emit_slice(
                h: @This(),
                basename: []const u8,
                docs: model.DocString,
                ptr_type: model.Type,
            ) !void {
                try h.nf.append(.{
                    .docs = docs,
                    .name = try h.ana.format("{s}_ptr", .{basename}),
                    .type = try h.ana.map_model_type(ptr_type),
                    .role = .{ .slice_ptr = basename },
                    .default = null,
                });
                try h.nf.append(.{
                    .docs = try h.ana.allocator.dupe([]const u8, &.{
                        try h.ana.format("The number of elements referenced by {s}_ptr.", .{basename}),
                    }),
                    .name = try h.ana.format("{s}_len", .{basename}),
                    .type = try h.ana.map_model_type(.{ .well_known = .usize }),
                    .role = .{ .slice_len = basename },
                    .default = null,
                });
            }
        };

        const helper: Helper = .{ .nf = &native_fields, .ana = ana };

        for (container.logic_fields) |fld| {
            const fld_type = ana.get_resolved_type(fld.type);

            const forward: enum { keep, discard } = blk: switch (fld_type) {
                .well_known => |id| switch (id) {
                    .bytestr, .bytebuf, .str => {
                        try native_fields.append(.{
                            .docs = fld.docs,
                            .name = try ana.format("{s}_ptr", .{fld.name}),
                            .type = try ana.map_model_type(.{ .ptr = .{
                                .size = .unknown,
                                .is_const = (id != .bytebuf),
                                .alignment = null,
                                .child = try ana.map_model_type(.{ .well_known = .u8 }),
                            } }),
                            .role = .{ .slice_ptr = fld.name },
                            .default = null,
                        });
                        try native_fields.append(.{
                            .docs = try ana.allocator.dupe([]const u8, &.{
                                try ana.format("The amount of bytes referenced by {s}_ptr.", .{fld.name}),
                            }),
                            .name = try ana.format("{s}_len", .{fld.name}),
                            .type = try ana.map_model_type(.{ .well_known = .usize }),
                            .role = .{ .slice_len = fld.name },
                            .default = null,
                        });
                        break :blk .discard;
                    },

                    else => .keep,
                },

                .optional => |child_idx| {
                    const child = ana.get_resolved_type(child_idx);
                    switch (child) {
                        .well_known => |id| switch (id) {
                            .bytestr, .bytebuf, .str => {
                                try native_fields.append(.{
                                    .docs = fld.docs,
                                    .name = try ana.format("{s}_ptr", .{fld.name}),
                                    .type = try ana.map_model_type(.{
                                        .optional = try ana.map_model_type(.{ .ptr = .{
                                            .size = .unknown,
                                            .is_const = (id != .bytebuf),
                                            .alignment = null,
                                            .child = try ana.map_model_type(.{ .well_known = .u8 }),
                                        } }),
                                    }),
                                    .role = .{ .slice_ptr = fld.name },
                                    .default = null,
                                });
                                try native_fields.append(.{
                                    .docs = try ana.allocator.dupe([]const u8, &.{
                                        try ana.format("The amount of bytes referenced by {s}_ptr.", .{fld.name}),
                                    }),
                                    .name = try ana.format("{s}_len", .{fld.name}),
                                    .type = try ana.map_model_type(.{ .well_known = .usize }),
                                    .role = .{ .slice_len = fld.name },
                                    .default = null,
                                });
                                break :blk .discard;
                            },

                            else => break :blk .keep,
                        },

                        .ptr => |ptr| {
                            if (ptr.size != .slice)
                                break :blk .keep;
                            try helper.emit_slice(
                                fld.name,
                                fld.docs,
                                .{
                                    .optional = try ana.map_model_type(.{ .ptr = .{
                                        .size = .unknown,
                                        .is_const = ptr.is_const,
                                        .alignment = ptr.alignment,
                                        .child = ptr.child,
                                    } }),
                                },
                            );

                            break :blk .discard;
                        },
                        else => break :blk .keep,
                    }
                },

                .ptr => |ptr| switch (ptr.size) {
                    .one, .unknown => .keep,
                    .slice => {
                        try helper.emit_slice(
                            fld.name,
                            fld.docs,
                            .{ .ptr = .{
                                .size = .unknown,
                                .is_const = ptr.is_const,
                                .alignment = ptr.alignment,
                                .child = ptr.child,
                            } },
                        );
                        break :blk .discard;
                    },
                },

                .resource, .@"struct", .@"union", .@"enum", .bitstruct => .keep,

                .fnptr => .keep,
                .uint, .int => .keep,
                .array => .keep,
                .typedef => .keep, // TODO: Check if slice!
                .external => .keep,

                .alias => unreachable,
                .unknown_named_type => unreachable,
                .unset_magic_type => unreachable,
            };

            if (forward == .keep) {
                try native_fields.append(fld);
            }
        }

        container.native_fields = try native_fields.toOwnedSlice();
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

        const alias_id = try ana.map_type(typedef.alias);

        const typedef_id = try ana.types.append(.{
            .typedef = .{
                .docs = doc_comment,
                .full_qualified_name = full_name,
                .alias = alias_id,
            },
        });

        scope.set_link(.{ .typedef = typedef_id });

        return .{
            .full_qualified_name = full_name,
            .docs = doc_comment,
            .children = &.{},
            .data = .{ .typedef = typedef_id },
        };
    }

    fn map_const(ana: *Analyzer, node: syntax.Node) !model.Declaration {
        const constant = node.type.@"const";

        const full_name, const scope = try ana.push_scope(constant.name, .constant);
        defer ana.pop_scope();

        const doc_comment = try ana.allocator.dupe([]const u8, node.doc_comment);

        const value = try ana.resolve_value(constant.value.?);

        // TODO: Implement explicit constant typing!
        const type_id: ?model.TypeIndex = if (constant.type) |type_node|
            try ana.map_type(type_node)
        else
            null;

        const index = try ana.constants.append(.{
            .uid = try ana.get_uid(full_name),
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
            .uid = try ana.get_uid(info.full_name),
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
            .uid = try ana.get_uid(info.full_name),
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
                        .role = .default,
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
                        .value = @intCast(errors.fields.items.len + 1), // TODO: Implement fqn + error name based caching in database file
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
            .uid = try ana.get_uid(info.full_name),
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .logic_inputs = try inputs.resolve(),
            .logic_outputs = try outputs.resolve(),
            .native_inputs = &.{},
            .native_outputs = &.{},
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
                        .role = .default,
                    });
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        const output: model.Struct = .{
            .uid = try ana.get_uid(info.full_name),
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .logic_fields = try fields.resolve(),
            .native_fields = &.{},
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

                        .bit_shift = null,
                        .bit_count = null,
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

                        .bit_shift = null,
                        .bit_count = null,
                    });
                },

                else => try ana.emit_unexpected_node(child),
            }
        }

        const index = try ana.bitstructs.append(.{
            .uid = try ana.get_uid(info.full_name),
            .docs = info.docs,
            .full_qualified_name = info.full_name,
            .fields = try fields.resolve(),
            .backing_type = info.sub_type.?,

            .bit_count = info.sub_type.?.size_in_bits() orelse 0,
        });
        return .{ .bitstruct = index };
    }

    const MapTypeError = error{OutOfMemory};

    fn map_type(ana: *Analyzer, type_node: *const syntax.TypeNode) MapTypeError!model.TypeIndex {
        const decl: model.Type = try ana.map_type_inner(type_node);

        return try ana.map_model_type(decl);
    }

    fn map_model_type(ana: *Analyzer, decl: model.Type) MapTypeError!model.TypeIndex {
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

                .unset_magic_type => |magic| magic.kind == other.unset_magic_type.kind and magic.size == other.unset_magic_type.size,
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

                const size_val = try ana.resolve_value(data.size);

                const size: u32 = switch (size_val) {
                    .int => |int| std.math.cast(u32, int) orelse blk: {
                        std.log.err("TODO: Array size too large: {}", .{int});
                        break :blk 0;
                    },
                    else => blk: {
                        std.log.err("TODO: Invalid array size {}", .{size_val});
                        break :blk 0;
                    },
                };

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

            .magic => |node| {
                const kind = std.meta.stringToEnum(model.MagicType.Kind, node.name) orelse b: {
                    try ana.emit_error(node.location, "Unknown built-in type <<{s}:{s}>>", .{
                        node.name,
                        @tagName(node.sub_type),
                    });
                    break :b .resource_enum;
                };

                return .{
                    .unset_magic_type = .{
                        .kind = kind,
                        .size = convert_enum(model.MagicType.Size, node.sub_type),
                    },
                };
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
            .symbol_name => |symbol_name| {
                std.log.err("resolve symbol '{}'", .{std.zig.fmtEscapes(symbol_name)});
                @panic("symbol resolution not done yet");
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

    /// Returns the actual type and skips over 'alias' types, and seeks through
    /// typedefs to get a concrete type value.
    fn get_resolved_type(ana: *Analyzer, type_id: model.TypeIndex) model.Type {
        var index = type_id;
        while (true) {
            const type_val = ana.types.get(index);
            switch (type_val.*) {
                .alias => |aliased| index = aliased,
                .typedef => |typedef| index = typedef.alias,
                else => return type_val.*,
            }
        }
    }

    fn patch_tree(ana: *Analyzer, patch: anytype) !void {
        try ana.patch_tree_inner(@constCast(ana.root.items), patch);
    }

    fn patch_tree_inner(ana: *Analyzer, decls: []model.Declaration, patch: anytype) !void {
        for (decls) |*decl| {
            try ana.patch_tree_inner(@constCast(decl.children), patch);

            try patch.apply(decl);
        }
    }

    fn validate_constraints(ana: *Analyzer) void {
        for (ana.syscalls.items) |sc| {
            // native calls must have either a return value
            // or none.
            std.debug.assert(sc.native_outputs.len <= 1);

            std.debug.assert(sc.logic_inputs.len <= sc.native_inputs.len);
            std.debug.assert(sc.logic_outputs.len <= sc.native_outputs.len);

            for (sc.logic_inputs) |inp| {
                switch (inp.role) {
                    .default => {},
                    .input_slice => {},
                    else => unreachable,
                }
            }

            for (sc.logic_outputs) |outp| {
                switch (outp.role) {
                    .default => {},
                    .output_slice => {},
                    else => unreachable,
                }
            }

            for (sc.native_inputs) |inp| {
                std.debug.assert(ana.get_resolved_type(inp.type).is_c_abi_compatible());

                // inputs cannot be the error role
                std.debug.assert(inp.role != .@"error");

                // TODO: Assert that referenced parameters exist, and that they have the right pointer type
            }

            var has_error_output = false;
            const needs_error_output = (sc.errors.len > 0);
            for (sc.native_outputs) |outp| {
                std.debug.assert(ana.get_resolved_type(outp.type).is_c_abi_compatible());
                switch (outp.role) {
                    .default => {},
                    .@"error" => {
                        std.debug.assert(!has_error_output);
                        std.debug.assert(needs_error_output);
                        has_error_output = true;
                    },
                    .input_len, .input_ptr => {
                        // TODO: Assert that referenced parameters exist, and that they have the right pointer type
                    },
                    .output_len, .output_ptr => {
                        // TODO: Assert that referenced parameters exist, and that they have the right pointer type
                    },
                }
            }
            if (needs_error_output) {
                std.debug.assert(has_error_output);
            }
        }

        for (ana.unions.items) |un| {
            std.debug.assert(un.logic_fields.len == un.native_fields.len);
            for (un.logic_fields) |fld| {
                std.debug.assert(fld.role == .default);
            }
            for (un.native_fields) |fld| {
                std.debug.assert(fld.role == .default);
                std.debug.assert(ana.get_resolved_type(fld.type).is_c_abi_compatible());
            }
        }

        for (ana.structs.items) |str| {
            std.debug.assert(str.logic_fields.len <= str.native_fields.len);
            for (str.logic_fields) |fld| {
                std.debug.assert(fld.role == .default);
            }
            for (str.native_fields) |fld| {
                switch (fld.role) {
                    .default => {},
                    .slice_len, .slice_ptr => {
                        // TODO: Assert the referenced slice exists
                    },
                }
                std.debug.assert(ana.get_resolved_type(fld.type).is_c_abi_compatible());
            }
        }

        for (ana.bitstructs.items) |bs| {
            std.debug.assert(bs.backing_type.is_integer());

            var bit_count: usize = 0;
            for (bs.fields) |fld| {
                const fld_type = ana.get_resolved_type(fld.type);
                switch (fld_type) {
                    .well_known => |id| std.debug.assert(id.size_in_bits() != null),
                    .@"enum", .bitstruct => {},
                    else => unreachable,
                }

                std.debug.assert(fld.bit_count != null);
                std.debug.assert(fld.bit_shift != null);

                std.debug.assert(bit_count == fld.bit_shift.?);
                bit_count += fld.bit_count.?;
            }

            std.debug.assert(bs.bit_count == bit_count);
        }
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

        pub fn get(col: *Collect, index: Index) *Item {
            return &col.items[@intFromEnum(index)];
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
