const std = @import("std");
const ptk = @import("ptk");
const args_parser = @import("args");

const CliOptions = struct {
    output: []const u8 = "",
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var args = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer args.deinit();

    if (args.positionals.len != 1) {
        return 1;
    }

    if (args.options.output.len == 1) {
        return 1;
    }

    const input_text = try std.fs.cwd().readFileAlloc(
        allocator,
        args.positionals[0],
        1 << 20,
    );

    var tokenizer: Tokenizer = .init(input_text, args.positionals[0]);
    var parser: Parser = .{
        .allocator = allocator,
        .core = .init(&tokenizer),
    };

    const abi_spec = parser.accept_document() catch |err| {
        if (parser.bad_token) |bad_token| {
            std.log.err("unexpected token at {}: found {}", .{
                bad_token.location,
                bad_token,
            });
        }
        return err;
    };

    _ = abi_spec;

    return 1;
}

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
    @"return",
    @"const",
    @"align",
    resource,

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
    @"...",

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

        .create(.namespace, match.word("namespace")),
        .create(.@"error", match.word("error")),
        .create(.@"struct", match.word("struct")),
        .create(.@"union", match.word("union")),
        .create(.@"enum", match.word("enum")),
        .create(.bitstruct, match.word("bitstruct")),
        .create(.syscall, match.word("syscall")),
        .create(.async_call, match.word("async_call")),
        .create(.field, match.word("field")),
        .create(.item, match.word("item")),
        .create(.in, match.word("in")),
        .create(.out, match.word("out")),
        .create(.@"return", match.word("return")),
        .create(.@"const", match.word("const")),
        .create(.@"align", match.word("align")),

        .create(.identifier, match.identifier),
        .create(.identifier, match.sequenceOf(.{ match.literal("@\""), match.takeNoneOf("\"\n\r"), match.literal("\"") })),
        .create(.identifier, match.sequenceOf(.{ match.literal("@"), match.identifier, match.literal("()") })),

        .create(.doc_comment, match.sequenceOf(.{ match.literal("///"), match.takeNoneOf("\n") })),
        .create(.comment, match.sequenceOf(.{ match.literal("//?"), match.takeNoneOf("\n") })),

        .create(.number, match.sequenceOf(.{ match.literal("0x"), match.hexadecimalNumber })),
        .create(.number, match.sequenceOf(.{ match.literal("0b"), match.binaryNumber })),
        .create(.number, match.decimalNumber),

        .create(.whitespace, match.whitespace),
    };
    break :blk items;
};

const Tokenizer = ptk.Tokenizer(TokenType, &patterns);

const ParserCore = ptk.ParserCore(Tokenizer, .{ .whitespace, .comment });

const Location = ptk.Location;

const Token = Tokenizer.Token;

const RuleSet = ptk.RuleSet(TokenType);

const Parser = struct {
    allocator: std.mem.Allocator,

    core: ParserCore,
    bad_token: ?Token = null,

    named_types: std.StringArrayHashMapUnmanaged(*TypeNode) = .empty,

    pub fn accept_document(parser: *Parser) !Document {
        var doc: std.ArrayList(Node) = .init(parser.allocator);
        defer doc.deinit();

        while (parser.core.tokenizer.offset < parser.core.tokenizer.source.len) {
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
            .namespace,
            .@"error",
            .@"struct",
            .@"union",
            .@"enum",
            .bitstruct,
            .syscall,
            .async_call,
            .field,
            .item,
            .in,
            .out,
            .@"return",
            .@"const",
            .@"...",
        });

        const node_type: Node.Data = switch (tok.type) {
            .namespace,
            .@"struct",
            .@"union",
            .@"enum",
            .bitstruct,
            .syscall,
            .async_call,
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
                try parser.expect(.@";");
                break :blk .{
                    .field = .{
                        .type = switch (tok.type) {
                            inline .field,
                            .in,
                            .out,
                            => |tag| @field(FieldType, @tagName(tag)),
                            else => unreachable,
                        },
                        .name = identifier,
                        .field_type = field_type,
                    },
                };
            },

            .@"error" => blk: {
                const name, _ = try parser.accept_identifier();

                try parser.expect(.@";");

                break :blk .{
                    .name = .{
                        .type = .@"error",
                        .name = name,
                    },
                };
            },

            .@"return" => blk: {
                const return_type = try parser.accept_type();
                try parser.expect(.@";");

                break :blk .{
                    .typedef = .{
                        .type = .@"return",
                        .definition = return_type,
                    },
                };
            },

            .@"const" => blk: {
                const name, _ = try parser.accept_identifier();
                try parser.expect(.@"=");
                const value = try parser.accept_value();
                try parser.expect(.@";");

                break :blk .{
                    .value = .{
                        .type = .item,
                        .name = name,
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
                    .value = .{
                        .type = .item,
                        .name = name,
                        .value = initial,
                    },
                };
            },

            .@"..." => .ellipse,

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

            std.log.warn("new named type: {*} '{'}'", .{ node, std.zig.fmtEscapes(node.named) });
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
            const maybe_array_size = if (try parser.try_accept(.number)) |array_size|
                std.fmt.parseInt(u64, array_size.text, 0) catch unreachable
            else
                null;

            const is_unbound = if (maybe_array_size != null)
                false
            else
                (try parser.try_accept(.@"*")) != null;

            try parser.expect(.@"]");

            if (maybe_array_size) |array_size| {
                std.debug.assert(is_unbound == false);
                const child = try parser.accept_type();
                return .{
                    .array = .{
                        .child = child,
                        .size = array_size,
                    },
                };
            } else {
                return .{
                    .pointer = try parser.accept_pointer(
                        if (is_unbound) .unknown else .slice,
                    ),
                };
            }
        }

        const name, _ = try parser.accept_identifier();

        if (std.meta.stringToEnum(BuiltinType, name)) |builtin| {
            return .{ .builtin = builtin };
        } else {
            return .{
                .named = name,
            };
        }
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
    value,
    typedef,
    name,
    ellipse,
};

pub const Document = struct {
    nodes: []const Node,
};

const Node = struct {
    location: Location,
    doc_comment: []const []const u8,
    type: Data,

    pub const Data = union(NodeType) {
        declaration: DeclarationNode,
        field: FieldNode,
        value: AssignmentNode,
        typedef: TypeDefNode,
        name: NameNode,
        ellipse,
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
    type: ValueType,
    name: []const u8,
    value: ?*const ValueNode,
};

pub const ValueType = enum {
    @"const", // "const <name> = <value>,"
    item, // "item <name> = <value>,"
};

pub const NameNode = struct {
    type: NameType,
    name: []const u8,
};

pub const NameType = enum {
    @"error", // "error OutOfMemory,"
    item, // "item foo,"
};

pub const FieldNode = struct {
    type: FieldType,
    name: []const u8,
    field_type: ?*const TypeNode,
};

pub const FieldType = enum {
    field, // "field <name>: <type>,"
    in, // "in <name>: <type>,"
    out, // "out <name>: <type>,"
};

pub const TypeDefNode = struct {
    type: TypeDefType,
    definition: *const TypeNode,
};

pub const TypeDefType = enum {
    @"return", // "return <type>,"
};

pub const ValueNode = union(enum) {
    uint: u64,
};

pub const TypeNode = union(enum) {
    builtin: BuiltinType,
    named: []const u8,
    optional: *const TypeNode,
    pointer: PointerTypeNode,
    array: struct {
        child: *const TypeNode,
        size: u64,
    },
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

    // data specials:
    str, // Immutable UTF-8 string
    bytestr, // Immutable unencoded byte string
    bytebuf, // Mutable, sized byte buffer

    // integers:
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

    // floats:
    f32,
    f64,

    // magics:
    @"@SystemResourceType",
};
