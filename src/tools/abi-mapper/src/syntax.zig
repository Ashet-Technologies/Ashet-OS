const std = @import("std");
const ptk = @import("ptk");

const TokenType = enum {
    // keywords:
    namespace,
    @"error",
    @"struct",
    @"union",
    @"enum",
    bitstruct,
    syscall,
    async_call,
    field,
    item,
    in,
    out,
    @"const",
    @"align",
    reserve,
    fnptr,
    resource,
    typedef,
    noreturn,

    // symbols
    @"(",
    @")",
    @"{",
    @"}",
    @"[",
    @"]",
    @":",
    @";",
    @"=",
    @"?",
    @"*",
    @",",
    @".",
    @"...",
    magic_type_start,
    magic_type_stop,

    // values
    identifier,
    doc_comment,
    number,

    // other
    whitespace,
    comment,

    pub fn format(tt: TokenType, comptime fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;

        var buf: [64]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, ".{}", .{std.zig.fmtId(@tagName(tt))});

        try std.fmt.formatBuf(str, opt, writer);
    }
};

pub fn match_identifier(str: []const u8) ?usize {
    const first_char = "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const all_chars = first_char ++ "0123456789.";
    for (str, 0..) |c, i| {
        if (std.mem.indexOfScalar(u8, if (i > 0) all_chars else first_char, c) == null) {
            return i;
        }
    }
    return str.len;
}

const patterns = blk: {
    const match = ptk.matchers;

    const items = [_]ptk.Pattern(TokenType){
        .create(.@"...", match.literal("...")),

        .create(.@";", match.literal(";")),
        .create(.@"{", match.literal("{")),
        .create(.@"}", match.literal("}")),
        .create(.@"[", match.literal("[")),
        .create(.@"]", match.literal("]")),
        .create(.@"(", match.literal("(")),
        .create(.@")", match.literal(")")),
        .create(.@":", match.literal(":")),
        .create(.@"=", match.literal("=")),
        .create(.@"?", match.literal("?")),
        .create(.@"*", match.literal("*")),
        .create(.@",", match.literal(",")),
        .create(.@".", match.literal(".")),

        .create(.namespace, match.word("namespace")),
        .create(.@"error", match.word("error")),
        .create(.@"struct", match.word("struct")),
        .create(.@"union", match.word("union")),
        .create(.@"enum", match.word("enum")),
        .create(.bitstruct, match.word("bitstruct")),
        .create(.typedef, match.word("typedef")),
        .create(.syscall, match.word("syscall")),
        .create(.async_call, match.word("async_call")),
        .create(.field, match.word("field")),
        .create(.item, match.word("item")),
        .create(.in, match.word("in")),
        .create(.out, match.word("out")),
        .create(.resource, match.word("resource")),
        .create(.reserve, match.word("reserve")),
        .create(.fnptr, match.word("fnptr")),
        .create(.@"const", match.word("const")),
        .create(.typedef, match.word("typedef")),
        .create(.@"align", match.word("align")),
        .create(.noreturn, match.word("noreturn")),
        .create(.magic_type_start, match.literal("<<")),
        .create(.magic_type_stop, match.literal(">>")),

        .create(.identifier, match_identifier),
        .create(.identifier, match.sequenceOf(.{ match.literal("@\""), match.takeNoneOf("\"\n\r"), match.literal("\"") })),

        .create(.doc_comment, match.sequenceOf(.{ match.literal("///"), match.takeNoneOf("\r\n") })),
        .create(.doc_comment, match.literal("///")),
        .create(.comment, match.sequenceOf(.{ match.literal("//?"), match.takeNoneOf("\r\n") })),
        .create(.comment, match.literal("//?")),

        .create(.number, match.sequenceOf(.{ match.literal("0x"), match.hexadecimalNumber })),
        .create(.number, match.sequenceOf(.{ match.literal("0b"), match.binaryNumber })),
        .create(.number, match.decimalNumber),

        .create(.whitespace, match.whitespace),
    };
    break :blk items;
};

pub const Tokenizer = ptk.Tokenizer(TokenType, &patterns);

const ParserCore = ptk.ParserCore(Tokenizer, .{ .whitespace, .comment });

pub const Location = ptk.Location;

pub const Token = Tokenizer.Token;

const RuleSet = ptk.RuleSet(TokenType);

pub const Parser = struct {
    allocator: std.mem.Allocator,

    core: ParserCore,
    bad_token: ?Token = null,

    named_types: std.StringArrayHashMapUnmanaged(*TypeNode) = .empty,

    pub fn accept_document(parser: *Parser) !Document {
        var doc: std.ArrayList(Node) = .init(parser.allocator);
        defer doc.deinit();

        while (try parser.core.peek() != null) {
            const node = try parser.accept_node();
            try doc.append(node);
        }

        return .{
            .nodes = try doc.toOwnedSlice(),
        };
    }

    fn accept_node(parser: *Parser) !Node {
        var docs: std.ArrayList([]const u8) = .init(parser.allocator);
        defer docs.deinit();

        while (parser.accept(.doc_comment)) |token| {
            std.debug.assert(token.type == .doc_comment);

            std.debug.assert(std.mem.startsWith(u8, token.text, "///"));

            const comment = token.text[3..];

            try docs.append(comment);
        } else |_| {}

        const tok = try parser.accept_any(&.{
            // declarations:
            .namespace,
            .@"struct",
            .@"union",
            .@"enum",
            .bitstruct,
            .syscall,
            .async_call,
            .resource,
            .typedef,
            .@"const",

            // child fields:
            .@"error",
            .field,
            .item,
            .in,
            .out,
            .reserve,
            .@"...",
            .noreturn,
        });

        const node_type: Node.Data = switch (tok.type) {
            .namespace,
            .@"struct",
            .@"union",
            .@"enum",
            .bitstruct,
            .syscall,
            .async_call,
            .resource,
            => blk: {
                const identifier, _ = try parser.accept_identifier();

                const subtype = if (try parser.try_accept(.@":")) |_|
                    try parser.accept_type()
                else
                    null;

                try parser.expect(.@"{");

                var children: std.ArrayList(Node) = .init(parser.allocator);
                defer children.deinit();

                while (true) {
                    if (try parser.try_accept(.@"}")) |_|
                        break;

                    const child = try children.addOne();
                    errdefer _ = children.pop();

                    child.* = try parser.accept_node();
                }
                break :blk .{
                    .declaration = .{
                        .name = identifier,
                        .subtype = subtype,
                        .type = switch (tok.type) {
                            inline .namespace,
                            .@"struct",
                            .@"union",
                            .@"enum",
                            .bitstruct,
                            .syscall,
                            .async_call,
                            .resource,
                            => |tag| @field(DeclarationType, @tagName(tag)),
                            else => unreachable,
                        },
                        .children = try children.toOwnedSlice(),
                    },
                };
            },

            .field,
            .in,
            .out,
            => blk: {
                const identifier, _ = try parser.accept_identifier();
                try parser.expect(.@":");
                const field_type = try parser.accept_type();

                const default_value = if (try parser.try_accept(.@"=")) |_|
                    try parser.accept_value()
                else
                    null;

                try parser.expect(.@";");

                const value: FieldNode = .{
                    .name = identifier,
                    .field_type = field_type,
                    .default_value = default_value,
                };

                break :blk switch (tok.type) {
                    .field => .{ .field = value },
                    .in => .{ .in = value },
                    .out => .{ .out = value },
                    else => unreachable,
                };
            },

            .@"error" => blk: {
                const name, _ = try parser.accept_identifier();

                try parser.expect(.@";");

                break :blk .{ .@"error" = name };
            },

            .@"const" => blk: {
                const name, _ = try parser.accept_identifier();

                const maybe_type_node = if (try parser.try_accept(.@":")) |_|
                    try parser.accept_type()
                else
                    null;

                try parser.expect(.@"=");
                const value = try parser.accept_value();
                try parser.expect(.@";");

                break :blk .{
                    .@"const" = .{
                        .name = name,
                        .type = maybe_type_node,
                        .value = value,
                    },
                };
            },

            .item => blk: {
                const name, _ = try parser.accept_identifier();

                const initial = if (try parser.try_accept(.@"=")) |_|
                    try parser.accept_value()
                else
                    null;
                try parser.expect(.@";");

                break :blk .{
                    .item = .{
                        .name = name,
                        .type = null,
                        .value = initial,
                    },
                };
            },

            .reserve => blk: {
                const pad_type = try parser.accept_type();
                try parser.expect(.@"=");
                const value = try parser.accept_value();
                try parser.expect(.@";");

                break :blk .{
                    .reserve = .{
                        .type = pad_type,
                        .value = value,
                    },
                };
            },

            .typedef => blk: {
                const name, _ = try parser.accept_identifier();
                try parser.expect(.@"=");
                const deftype = try parser.accept_type();
                try parser.expect(.@";");

                break :blk .{
                    .typedef = .{
                        .name = name,
                        .alias = deftype,
                    },
                };
            },

            .@"..." => .ellipse,

            .noreturn => blk: {
                try parser.expect(.@";");
                break :blk .noreturn;
            },

            else => unreachable,
        };

        return .{
            .doc_comment = try docs.toOwnedSlice(),
            .location = tok.location,
            .type = node_type,
        };
    }

    const AcceptError = error{
        UnexpectedCharacter,
        EndOfStream,
        UnexpectedToken,
    };
    const AcceptNodeError = AcceptError || error{OutOfMemory};

    fn accept_value(parser: *Parser) AcceptNodeError!*const ValueNode {
        const node = try parser.allocator.create(ValueNode);
        errdefer parser.allocator.destroy(node);
        node.* = try parser.accept_value_val();
        return node;
    }

    fn accept_value_val(parser: *Parser) AcceptNodeError!ValueNode {
        if (try parser.try_accept(.@".")) |_| {
            // compound type
            try parser.expect(.@"{");

            var children: std.ArrayList(FieldInitNode) = .init(parser.allocator);
            defer children.deinit();

            if (try parser.try_accept(.@"}")) |_| {
                // done
            } else {
                while (true) {
                    try parser.expect(.@".");
                    const name, const tok = try parser.accept_identifier();
                    try parser.expect(.@"=");
                    const value = try parser.accept_value();

                    try children.append(.{
                        .location = tok.location,
                        .name = name,
                        .value = value,
                    });

                    if (try parser.try_accept(.@"}")) |_|
                        break;

                    try parser.expect(.@",");
                }
            }

            return .{
                .compound = try children.toOwnedSlice(),
            };
        }

        if (parser.accept_identifier()) |wrap| {
            // identifier
            const identifier, _ = wrap;

            if (std.meta.stringToEnum(NamedValue, identifier)) |named_value| {
                return .{ .named = named_value };
            }

            return .{
                .symbol_name = identifier,
            };
        } else |_| {}

        // else: must be a number

        const tok = try parser.accept(.number);

        const num = std.fmt.parseInt(u64, tok.text, 0) catch unreachable;

        return .{
            .uint = num,
        };
    }

    fn accept_type(parser: *Parser) AcceptNodeError!*const TypeNode {
        const tvalue = try parser.accept_type_val();

        const maybe_named_ref = if (tvalue == .named) blk: {
            const gop = try parser.named_types.getOrPut(parser.allocator, tvalue.named);
            if (gop.found_existing) {
                return gop.value_ptr.*;
            }
            break :blk gop;
        } else null;

        const node = try parser.allocator.create(TypeNode);
        node.* = tvalue;

        if (maybe_named_ref) |gop| {
            std.debug.assert(!gop.found_existing);
            std.debug.assert(tvalue == .named);
            std.debug.assert(node.* == .named);

            gop.value_ptr.* = node;
        }

        return node;
    }

    fn accept_pointer(parser: *Parser, size: PointerSize) AcceptNodeError!PointerTypeNode {
        const is_const = (try parser.try_accept(.@"const")) != null;

        const alignment = if (try parser.try_accept(.@"align")) |_| blk: {
            try parser.expect(.@"(");
            const num_tok = try parser.accept(.number);
            try parser.expect(.@")");

            break :blk std.fmt.parseInt(u64, num_tok.text, 0) catch unreachable;
        } else null;

        const child = try parser.accept_type();

        return .{
            .child = child,
            .is_const = is_const,
            .alignment = alignment,
            .size = size,
        };
    }

    fn accept_type_val(parser: *Parser) AcceptNodeError!TypeNode {
        if (try parser.try_accept(.magic_type_start)) |start| {
            const name, _ = try parser.accept_identifier();

            try parser.expect(.@":");

            const sub_type_token = try parser.accept(.identifier);

            const sub_type = std.meta.stringToEnum(MagicTypeNode.Size, sub_type_token.text) orelse {
                return error.UnexpectedToken;
            };

            try parser.expect(.magic_type_stop);

            return .{
                .magic = .{
                    .location = start.location,
                    .name = name,
                    .sub_type = sub_type,
                },
            };
        }

        if (try parser.try_accept(.@"?")) |_| {
            const child = try parser.accept_type();

            return .{ .optional = child };
        }

        if (try parser.try_accept(.@"*")) |_| {
            return .{
                .pointer = try parser.accept_pointer(.one),
            };
        }

        if (try parser.try_accept(.@"[")) |_| {
            const DeclType = union(enum) {
                basic,
                unbound,
                array: *const ValueNode,
            };

            const decl: DeclType = if (try parser.try_accept(.@"]")) |_|
                .basic
            else blk: {
                if (try parser.try_accept(.@"*")) |_| {
                    try parser.expect(.@"]");
                    break :blk .unbound;
                }

                const array_size = try parser.accept_value();

                try parser.expect(.@"]");
                break :blk .{ .array = array_size };
            };

            switch (decl) {
                .array => |array_size| {
                    const child = try parser.accept_type();
                    return .{
                        .array = .{
                            .child = child,
                            .size = array_size,
                        },
                    };
                },
                .basic, .unbound => {
                    return .{
                        .pointer = try parser.accept_pointer(
                            if (decl == .unbound) .unknown else .slice,
                        ),
                    };
                },
            }
        }

        if (try parser.try_accept(.fnptr)) |_| {
            var params: std.ArrayList(*const TypeNode) = .init(parser.allocator);
            defer params.deinit();

            try parser.expect(.@"(");
            blk: {
                if (try parser.try_accept(.@")")) |_|
                    break :blk;
                while (true) {
                    const param = try parser.accept_type();

                    try params.append(param);

                    if (try parser.try_accept(.@")")) |_|
                        break :blk;

                    try parser.expect(.@",");
                }
            }

            const return_type = try parser.accept_type();

            return .{
                .fnptr = .{
                    .parameters = try params.toOwnedSlice(),
                    .return_type = return_type,
                },
            };
        }

        const name, _ = try parser.accept_identifier();

        if (std.meta.stringToEnum(BuiltinType, name)) |builtin| {
            return .{ .builtin = builtin };
        }

        if (std.mem.startsWith(u8, name, "i")) {
            if (std.fmt.parseInt(u8, name[1..], 10)) |size| {
                return .{ .signed_int = size };
            } else |err| switch (err) {
                error.Overflow => return error.UnexpectedToken,
                error.InvalidCharacter => {},
            }
        }
        if (std.mem.startsWith(u8, name, "u")) {
            if (std.fmt.parseInt(u8, name[1..], 10)) |size| {
                return .{ .unsigned_int = size };
            } else |err| switch (err) {
                error.Overflow => return error.UnexpectedToken,
                error.InvalidCharacter => {},
            }
        }

        return .{
            .named = name,
        };
    }

    fn accept_identifier(parser: *Parser) !struct { []const u8, Token } {
        const tok = try parser.accept(.identifier);

        const ident = if (std.mem.startsWith(u8, tok.text, "@\"")) blk: {
            std.debug.assert(tok.text.len > 3); // @""

            std.debug.assert(tok.text[0] == '@');
            std.debug.assert(tok.text[1] == '"');
            std.debug.assert(tok.text[tok.text.len - 1] == '"');

            break :blk tok.text[2 .. tok.text.len - 1];
        } else tok.text;

        return .{ ident, tok };
    }

    fn expect(parser: *Parser, tok: TokenType) AcceptError!void {
        if (parser.accept(tok)) |_| {
            // ok
        } else |err| {
            //
            return err;
        }
    }

    fn try_accept(parser: *Parser, tok: TokenType) AcceptError!?Token {
        return parser.accept_any(&.{tok}) catch |err| switch (err) {
            error.UnexpectedToken => return null,
            else => |e| return e,
        };
    }

    fn accept(parser: *Parser, tok: TokenType) AcceptError!Token {
        return parser.accept_any(&.{tok});
    }

    fn accept_any(parser: *Parser, toks: []const TokenType) AcceptError!Token {
        const state = parser.core.saveState();
        errdefer parser.core.restoreState(state);

        const maybe_next = parser.core.nextToken() catch |err| switch (err) {
            error.UnexpectedCharacter => {
                std.log.err("unexpected character at {}", .{parser.core.tokenizer.current_location});
                return error.UnexpectedCharacter;
            },
        };

        const token = maybe_next orelse return error.EndOfStream;
        for (toks) |expected| {
            if (token.type == expected) {
                parser.bad_token = null;
                return token;
            }
        }

        parser.bad_token = token;

        return error.UnexpectedToken;
    }
};

const NodeType = enum {
    declaration,
    field,
    in,
    out,
    @"const",
    item,
    typedef,
    @"error",
    reserve,
    noreturn,
    ellipse,
};

pub const Document = struct {
    nodes: []const Node,
};

pub const Node = struct {
    location: Location,
    doc_comment: []const []const u8,
    type: Data,

    pub fn is_declaration(node: Node) bool {
        return switch (node.type) {
            .declaration,
            .typedef,
            .@"const",
            => true,

            .field,
            .in,
            .out,
            .item,
            .@"error",
            .reserve,
            .ellipse,
            .noreturn,
            => false,
        };
    }

    pub const Data = union(NodeType) {
        declaration: DeclarationNode,

        field: FieldNode, // "field <name>: <type>,"
        in: FieldNode, // "in <name>: <type>,"
        out: FieldNode, // "out <name>: <type>,"
        @"const": AssignmentNode, // "const <name> = <value>;"
        item: AssignmentNode, // "item <name> = <value>;"
        typedef: TypeDefNode,
        @"error": []const u8,
        reserve: PaddingNode,
        noreturn, // "noreturn;"
        ellipse, // "..."
    };
};

pub const DeclarationNode = struct {
    type: DeclarationType,
    name: []const u8,
    subtype: ?*const TypeNode,
    children: []const Node,
};

pub const DeclarationType = enum {
    namespace, // namespace <name> { … }
    @"struct", // struct <name> { … }
    @"union", // union <name> { … }
    @"enum", // enum <name> { … }
    bitstruct, // bitstruct <name> { … }
    syscall, // syscall <name> { … }
    async_call, // async_call <name> { … }
    resource, // resource <name> { … }
};

pub const AssignmentNode = struct {
    name: []const u8,
    type: ?*const TypeNode,
    value: ?*const ValueNode,
};

pub const PaddingNode = struct {
    type: *const TypeNode,
    value: *const ValueNode,
};

pub const FieldNode = struct {
    name: []const u8,
    field_type: *const TypeNode,
    default_value: ?*const ValueNode,
};

pub const TypeDefNode = struct {
    name: []const u8,
    alias: *const TypeNode,
};

pub const ValueNode = union(enum) {
    uint: u64,
    named: NamedValue,
    compound: []const FieldInitNode,
    symbol_name: []const u8,
};

pub const FieldInitNode = struct {
    location: Location,
    name: []const u8,
    value: *const ValueNode,
};

pub const NamedValue = enum {
    null,
    false,
    true,
};

pub const TypeNode = union(enum) {
    builtin: BuiltinType,
    named: []const u8,
    optional: *const TypeNode,
    pointer: PointerTypeNode,
    array: struct {
        child: *const TypeNode,
        size: *const ValueNode,
    },
    fnptr: struct {
        parameters: []const *const TypeNode,
        return_type: *const TypeNode,
    },
    unsigned_int: u8,
    signed_int: u8,
    magic: MagicTypeNode, // <<...>>
};

pub const MagicTypeNode = struct {
    location: Location,

    name: []const u8,

    sub_type: Size,

    pub const Size = enum { u8, u16, u32, u64, usize };
};

pub const PointerTypeNode = struct {
    child: *const TypeNode,
    is_const: bool,
    alignment: ?u64,
    size: PointerSize,
};

pub const PointerSize = enum {
    one,
    slice,
    unknown,
};

pub const BuiltinType = enum {
    // primitives:
    void,
    bool,
    noreturn,

    anyptr, // Pointer to any value
    anyfnptr, // Pointer to any function

    // data specials:
    str, // Immutable UTF-8 string
    bytestr, // Immutable unencoded byte string
    bytebuf, // Mutable, sized byte buffer

    // integers:
    usize,
    isize,

    // floats:
    f32,
    f64,
};
