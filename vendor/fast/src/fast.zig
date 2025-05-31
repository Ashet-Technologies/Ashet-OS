//!
//! This is a doc comment!
//!
const std = @import("std");
const logger = std.log.scoped(.fast);

const render = @import("render.zig");

pub fn parse(allocator: std.mem.Allocator, source: [:0]const u8) !Parsed(Container) {
    var ast = try std.zig.Ast.parse(allocator, source, .zig);
    defer ast.deinit(allocator);

    if (ast.errors.len != 0)
        return error.SyntaxError;

    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = .init(allocator);
    errdefer {
        arena.deinit();
        allocator.destroy(arena);
    }

    const root: Container = try render.renderTree(arena.allocator(), ast);

    return .{
        .arena = arena,
        .value = root,
    };
}

pub fn Parsed(comptime T: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

pub const Container = struct {
    doc_comment: ?[]const u8 = null,
    members: []const Member,
};

pub const Member = union(enum) {
    fn_decl: FunctionDeclaration,
    @"usingnamespace": UsingNamespace,
    var_decl: VariableDeclaration,
    @"test": TestDeclaration,
    field: FieldDeclaration,
    comptime_block: *const Expression,
};

pub const UsingNamespace = struct {
    @"pub": bool = false,
    namespace: *const Expression,
};

pub const ExternSpecifier = union(enum) {
    none,
    generic,
    library: []const u8,
};

pub const FunctionDeclaration = struct {
    doc_comment: ?[]const u8,

    @"pub": bool = false,
    @"extern": ExternSpecifier = .none,
    @"export": bool = false,
    @"inline": bool = false,
    @"noinline": bool = false,

    prototype: *const Expression,
    body: ?*const Expression,
};

pub const TestDeclaration = struct {
    type: union(enum) {
        blank,
        decl: []const u8,
        named: []const u8,
    },
    body: *const Expression,
};

pub const VariableDeclaration = struct {
    doc_comment: ?[]const u8 = null,

    @"pub": bool = false,
    @"extern": ExternSpecifier = .none,
    @"threadlocal": bool = false,
    @"comptime": bool = false,

    mutability: enum { @"var", @"const" },
    name: []const u8,
    type: ?*const Expression = null,

    @"align": ?*const Expression = null,
    @"addrspace": ?*const Expression = null,
    @"linksection": ?*const Expression = null,

    value: ?*const Expression = null,
};

pub const FieldDeclaration = struct {
    doc_comment: ?[]const u8 = null,
    name: []const u8,
};

pub const Expression = union(enum) {
    number: []const u8,
    char: []const u8,
    string: []const u8,
    @"unreachable",
    @"anyframe",
};

test parse {
    const source = @embedFile(@src().file);

    var parsed = try parse(std.testing.allocator, source);
    defer parsed.deinit();

    const file: Container = parsed.value;

    logger.err("{?s}", .{file.doc_comment});
}
