const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const meta = std.meta;
const Ast = std.zig.Ast;
const Token = std.zig.Token;
const primitives = std.zig.primitives;

pub const Error = Ast.RenderError;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const file_source = try std.fs.cwd().readFileAllocOptions(
        allocator,
        "/home/felix/projects/ashet/os/src/abi/syscalls.zig",
        (1 << 20),
        null,
        1,
        0,
    );
    defer allocator.free(file_source);

    var tree = try std.zig.Ast.parse(
        allocator,
        file_source,
        .zig,
    );
    defer tree.deinit(allocator);

    if (tree.errors.len > 0) {
        for (tree.errors) |err| {
            try tree.renderError(err, std.io.getStdErr().writer());
        }
        return 1;
    }

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try renderTree(&buffer, tree);

    try std.io.getStdOut().writeAll(buffer.items);

    return 0;
}

const indent_delta = 4;

const Ais = AutoIndentingStream(std.ArrayList(u8).Writer);

pub fn renderTree(buffer: *std.ArrayList(u8), tree: Ast) Error!void {
    assert(tree.errors.len == 0); // Cannot render an invalid tree.
    var auto_indenting_stream = Ais{
        .indent_delta = indent_delta,
        .underlying_writer = buffer.writer(),
    };
    const ais = &auto_indenting_stream;

    // Render all the line comments at the beginning of the file.
    const comment_end_loc = tree.tokens.items(.start)[0];
    _ = try renderComments(ais, tree, 0, comment_end_loc);

    if (tree.tokens.items(.tag)[0] == .container_doc_comment) {
        try renderContainerDocComments(ais, tree, 0);
    }

    try renderMembers(buffer.allocator, ais, tree, tree.rootDecls());

    if (ais.disabled_offset) |disabled_offset| {
        try writeFixingWhitespace(ais.underlying_writer, tree.source[disabled_offset..]);
    }
}

/// Render all members in the given slice, keeping empty lines where appropriate
fn renderMembers(gpa: Allocator, ais: *Ais, tree: Ast, members: []const Ast.Node.Index) Error!void {
    if (members.len == 0) return;
    const container: Container = for (members) |member| {
        if (tree.fullContainerField(member)) |field| if (!field.ast.tuple_like) break .other;
    } else .tuple;
    try renderMember(gpa, ais, tree, container, members[0], .newline);
    for (members[1..]) |member| {
        try renderExtraNewline(ais, tree, member);
        try renderMember(gpa, ais, tree, container, member, .newline);
    }
}

const Container = enum {
    @"enum",
    tuple,
    other,
};

fn renderMember(
    gpa: Allocator,
    ais: *Ais,
    tree: Ast,
    container: Container,
    decl: Ast.Node.Index,
    space: Space,
) Error!void {
    _ = container;

    const token_tags = tree.tokens.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    const datas = tree.nodes.items(.data);
    try renderDocComments(ais, tree, tree.firstToken(decl));
    switch (tree.nodes.items(.tag)[decl]) {
        .fn_decl => {
            // Some examples:
            // pub extern "foo" fn ...
            // export fn ...
            const fn_proto = datas[decl].lhs;
            const fn_token = main_tokens[fn_proto];
            // Go back to the first token we should render here.
            var i = fn_token;
            while (i > 0) {
                i -= 1;
                switch (token_tags[i]) {
                    .keyword_extern,
                    .keyword_export,
                    .keyword_pub,
                    .string_literal,
                    .keyword_inline,
                    .keyword_noinline,
                    => continue,

                    else => {
                        i += 1;
                        break;
                    },
                }
            }
            while (i < fn_token) : (i += 1) {
                try renderToken(ais, tree, i, .space);
            }
            switch (tree.nodes.items(.tag)[fn_proto]) {
                .fn_proto_one, .fn_proto => {
                    const callconv_expr = if (tree.nodes.items(.tag)[fn_proto] == .fn_proto_one)
                        tree.extraData(datas[fn_proto].lhs, Ast.Node.FnProtoOne).callconv_expr
                    else
                        tree.extraData(datas[fn_proto].lhs, Ast.Node.FnProto).callconv_expr;
                    if (callconv_expr != 0 and tree.nodes.items(.tag)[callconv_expr] == .enum_literal) {
                        if (mem.eql(u8, "Inline", tree.tokenSlice(main_tokens[callconv_expr]))) {
                            try ais.writer().writeAll("inline ");
                        }
                    }
                },
                .fn_proto_simple, .fn_proto_multi => {},
                else => unreachable,
            }
            assert(datas[decl].rhs != 0);
            try renderExpression(gpa, ais, tree, fn_proto, .space);
            return renderExpression(gpa, ais, tree, datas[decl].rhs, space);
        },
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => {
            // Extern function prototypes are parsed as these tags.
            // Go back to the first token we should render here.
            const fn_token = main_tokens[decl];
            var i = fn_token;
            while (i > 0) {
                i -= 1;
                switch (token_tags[i]) {
                    .keyword_extern,
                    .keyword_export,
                    .keyword_pub,
                    .string_literal,
                    .keyword_inline,
                    .keyword_noinline,
                    => continue,

                    else => {
                        i += 1;
                        break;
                    },
                }
            }
            while (i < fn_token) : (i += 1) {
                try renderToken(ais, tree, i, .space);
            }
            try renderExpression(gpa, ais, tree, decl, .none);
            return renderToken(ais, tree, tree.lastToken(decl) + 1, space); // semicolon
        },

        .global_var_decl,
        .local_var_decl,
        .simple_var_decl,
        .aligned_var_decl,
        => return renderVarDecl(gpa, ais, tree, tree.fullVarDecl(decl).?),

        .test_decl => {
            const test_token = main_tokens[decl];
            try renderToken(ais, tree, test_token, .space);
            const test_name_tag = token_tags[test_token + 1];
            switch (test_name_tag) {
                .string_literal => try renderToken(ais, tree, test_token + 1, .space),
                .identifier => try renderIdentifier(ais, tree, test_token + 1, .space, .preserve_when_shadowing),
                else => {},
            }
            try renderExpression(gpa, ais, tree, datas[decl].rhs, space);
        },

        .container_field_init,
        .container_field_align,
        .container_field,
        .@"comptime",
        .@"usingnamespace",
        => @panic("unsupported container-level construct"),

        .root => unreachable,
        else => unreachable,
    }
}

/// Render all expressions in the slice, keeping empty lines where appropriate
fn renderExpressions(gpa: Allocator, ais: *Ais, tree: Ast, expressions: []const Ast.Node.Index, space: Space) Error!void {
    if (expressions.len == 0) return;
    try renderExpression(gpa, ais, tree, expressions[0], space);
    for (expressions[1..]) |expression| {
        try renderExtraNewline(ais, tree, expression);
        try renderExpression(gpa, ais, tree, expression, space);
    }
}

fn renderExpression(gpa: Allocator, ais: *Ais, tree: Ast, node: Ast.Node.Index, space: Space) Error!void {
    const token_tags = tree.tokens.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    const node_tags = tree.nodes.items(.tag);
    const datas = tree.nodes.items(.data);
    switch (node_tags[node]) {
        .identifier => {
            const token_index = main_tokens[node];
            return renderIdentifier(ais, tree, token_index, space, .preserve_when_shadowing);
        },

        .number_literal,
        .char_literal,
        .unreachable_literal,
        .anyframe_literal,
        .string_literal,
        => return renderToken(ais, tree, main_tokens[node], space),

        .multiline_string_literal => {
            var locked_indents = ais.lockOneShotIndent();
            try ais.maybeInsertNewline();

            var i = datas[node].lhs;
            while (i <= datas[node].rhs) : (i += 1) try renderToken(ais, tree, i, .newline);

            while (locked_indents > 0) : (locked_indents -= 1) ais.popIndent();

            switch (space) {
                .none, .space, .newline, .skip => {},
                .semicolon => if (token_tags[i] == .semicolon) try renderToken(ais, tree, i, .newline),
                .comma => if (token_tags[i] == .comma) try renderToken(ais, tree, i, .newline),
                .comma_space => if (token_tags[i] == .comma) try renderToken(ais, tree, i, .space),
            }
        },

        .block_two,
        .block_two_semicolon,
        => {
            const statements = [2]Ast.Node.Index{ datas[node].lhs, datas[node].rhs };
            if (datas[node].lhs == 0) {
                return renderBlock(gpa, ais, tree, node, statements[0..0], space);
            } else if (datas[node].rhs == 0) {
                return renderBlock(gpa, ais, tree, node, statements[0..1], space);
            } else {
                return renderBlock(gpa, ais, tree, node, statements[0..2], space);
            }
        },
        .block,
        .block_semicolon,
        => {
            const statements = tree.extra_data[datas[node].lhs..datas[node].rhs];
            return renderBlock(gpa, ais, tree, node, statements, space);
        },

        .field_access => {
            const main_token = main_tokens[node];
            const field_access = datas[node];

            try renderExpression(gpa, ais, tree, field_access.lhs, .none);

            // Allow a line break between the lhs and the dot if the lhs and rhs
            // are on different lines.
            const lhs_last_token = tree.lastToken(field_access.lhs);
            const same_line = tree.tokensOnSameLine(lhs_last_token, main_token + 1);
            if (!same_line) {
                if (!hasComment(tree, lhs_last_token, main_token)) try ais.insertNewline();
                ais.pushIndentOneShot();
            }

            try renderToken(ais, tree, main_token, .none); // .

            // This check ensures that zag() is indented in the following example:
            // const x = foo
            //     .bar()
            //     . // comment
            //     zag();
            if (!same_line and hasComment(tree, main_token, main_token + 1)) {
                ais.pushIndentOneShot();
            }

            return renderIdentifier(ais, tree, field_access.rhs, space, .eagerly_unquote); // field
        },

        .error_union => {
            const infix = datas[node];
            try renderExpression(gpa, ais, tree, infix.lhs, .none);
            try renderToken(ais, tree, main_tokens[node], .none);
            return renderExpression(gpa, ais, tree, infix.rhs, space);
        },

        .optional_type => {
            try renderToken(ais, tree, main_tokens[node], .none);
            return renderExpression(gpa, ais, tree, datas[node].lhs, space);
        },

        .array_type,
        .array_type_sentinel,
        => return renderArrayType(gpa, ais, tree, tree.fullArrayType(node).?, space),

        .ptr_type_aligned,
        .ptr_type_sentinel,
        .ptr_type,
        => return renderPtrType(gpa, ais, tree, tree.fullPtrType(node).?, space),

        .grouped_expression => {
            try renderToken(ais, tree, main_tokens[node], .none); // lparen
            ais.pushIndentOneShot();
            try renderExpression(gpa, ais, tree, datas[node].lhs, .none);
            return renderToken(ais, tree, datas[node].rhs, space); // rparen
        },

        .container_decl,
        .container_decl_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        .container_decl_two,
        .container_decl_two_trailing,
        => {
            var buf: [2]Ast.Node.Index = undefined;
            return renderContainerDecl(gpa, ais, tree, node, tree.fullContainerDecl(&buf, node).?, space);
        },

        .error_set_decl => {
            const error_token = main_tokens[node];
            const lbrace = error_token + 1;
            const rbrace = datas[node].rhs;

            try renderToken(ais, tree, error_token, .none);

            if (lbrace + 1 == rbrace) {
                // There is nothing between the braces so render condensed: `error{}`
                try renderToken(ais, tree, lbrace, .none);
                return renderToken(ais, tree, rbrace, space);
            } else if (lbrace + 2 == rbrace and token_tags[lbrace + 1] == .identifier) {
                // There is exactly one member and no trailing comma or
                // comments, so render without surrounding spaces: `error{Foo}`
                try renderToken(ais, tree, lbrace, .none);
                try renderIdentifier(ais, tree, lbrace + 1, .none, .eagerly_unquote); // identifier
                return renderToken(ais, tree, rbrace, space);
            } else if (token_tags[rbrace - 1] == .comma) {
                // There is a trailing comma so render each member on a new line.
                ais.pushIndentNextLine();
                try renderToken(ais, tree, lbrace, .newline);
                var i = lbrace + 1;
                while (i < rbrace) : (i += 1) {
                    if (i > lbrace + 1) try renderExtraNewlineToken(ais, tree, i);
                    switch (token_tags[i]) {
                        .doc_comment => try renderToken(ais, tree, i, .newline),
                        .identifier => try renderIdentifier(ais, tree, i, .comma, .eagerly_unquote),
                        .comma => {},
                        else => unreachable,
                    }
                }
                ais.popIndent();
                return renderToken(ais, tree, rbrace, space);
            } else {
                // There is no trailing comma so render everything on one line.
                try renderToken(ais, tree, lbrace, .space);
                var i = lbrace + 1;
                while (i < rbrace) : (i += 1) {
                    switch (token_tags[i]) {
                        .doc_comment => unreachable, // TODO
                        .identifier => try renderIdentifier(ais, tree, i, .comma_space, .eagerly_unquote),
                        .comma => {},
                        else => unreachable,
                    }
                }
                return renderToken(ais, tree, rbrace, space);
            }
        },

        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => {
            var buf: [1]Ast.Node.Index = undefined;
            return renderFnProto(gpa, ais, tree, tree.fullFnProto(&buf, node).?, space);
        },

        .slice_open,
        .slice,
        .slice_sentinel,
        .ptr_type_bit_range,
        .switch_range,
        .tagged_union,
        .tagged_union_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        .anyframe_type,
        .bit_not,
        .bool_not,
        .negation,
        .negation_wrap,
        .address_of,
        .add,
        .add_wrap,
        .add_sat,
        .array_cat,
        .array_mult,
        .assign,
        .assign_bit_and,
        .assign_bit_or,
        .assign_shl,
        .assign_shl_sat,
        .assign_shr,
        .assign_bit_xor,
        .assign_div,
        .assign_sub,
        .assign_sub_wrap,
        .assign_sub_sat,
        .assign_mod,
        .assign_add,
        .assign_add_wrap,
        .assign_add_sat,
        .assign_mul,
        .assign_mul_wrap,
        .assign_mul_sat,
        .bang_equal,
        .bit_and,
        .bit_or,
        .shl,
        .shl_sat,
        .shr,
        .bit_xor,
        .bool_and,
        .bool_or,
        .div,
        .equal_equal,
        .greater_or_equal,
        .greater_than,
        .less_or_equal,
        .less_than,
        .merge_error_sets,
        .mod,
        .mul,
        .mul_wrap,
        .mul_sat,
        .sub,
        .sub_wrap,
        .sub_sat,
        .@"orelse",
        .for_range,
        .@"try",
        .@"resume",
        .@"await",
        .error_value,
        .@"errdefer",
        .@"defer",
        .@"comptime",
        .@"nosuspend",
        .@"suspend",
        .@"catch",
        .array_init_one,
        .array_init_one_comma,
        .array_init_dot_two,
        .array_init_dot_two_comma,
        .array_init_dot,
        .array_init_dot_comma,
        .array_init,
        .array_init_comma,
        .struct_init_one,
        .struct_init_one_comma,
        .struct_init_dot_two,
        .struct_init_dot_two_comma,
        .struct_init_dot,
        .struct_init_dot_comma,
        .struct_init,
        .struct_init_comma,
        .call_one,
        .call_one_comma,
        .async_call_one,
        .async_call_one_comma,
        .call,
        .call_comma,
        .async_call,
        .async_call_comma,
        .array_access,
        .deref,
        .unwrap_optional,
        .@"break",
        .@"continue",
        .@"return",
        .builtin_call_two,
        .builtin_call_two_comma,
        .builtin_call,
        .builtin_call_comma,
        .@"switch",
        .switch_comma,
        .switch_case_one,
        .switch_case_inline_one,
        .switch_case,
        .switch_case_inline,
        .while_simple,
        .while_cont,
        .@"while",
        .for_simple,
        .@"for",
        .if_simple,
        .@"if",
        .asm_simple,
        .@"asm",
        => @panic("unsupported ast node"),

        .enum_literal => {
            try renderToken(ais, tree, main_tokens[node] - 1, .none); // .
            return renderIdentifier(ais, tree, main_tokens[node], space, .eagerly_unquote); // name
        },

        .fn_decl => unreachable,
        .container_field => unreachable,
        .container_field_init => unreachable,
        .container_field_align => unreachable,
        .root => unreachable,
        .global_var_decl => unreachable,
        .local_var_decl => unreachable,
        .simple_var_decl => unreachable,
        .aligned_var_decl => unreachable,
        .@"usingnamespace" => unreachable,
        .test_decl => unreachable,
        .asm_output => unreachable,
        .asm_input => unreachable,
    }
}

fn renderArrayType(
    gpa: Allocator,
    ais: *Ais,
    tree: Ast,
    array_type: Ast.full.ArrayType,
    space: Space,
) Error!void {
    const rbracket = tree.firstToken(array_type.ast.elem_type) - 1;
    const one_line = tree.tokensOnSameLine(array_type.ast.lbracket, rbracket);
    const inner_space = if (one_line) Space.none else Space.newline;
    ais.pushIndentNextLine();
    try renderToken(ais, tree, array_type.ast.lbracket, inner_space); // lbracket
    try renderExpression(gpa, ais, tree, array_type.ast.elem_count, inner_space);
    if (array_type.ast.sentinel != 0) {
        try renderToken(ais, tree, tree.firstToken(array_type.ast.sentinel) - 1, inner_space); // colon
        try renderExpression(gpa, ais, tree, array_type.ast.sentinel, inner_space);
    }
    ais.popIndent();
    try renderToken(ais, tree, rbracket, .none); // rbracket
    return renderExpression(gpa, ais, tree, array_type.ast.elem_type, space);
}

fn renderPtrType(
    gpa: Allocator,
    ais: *Ais,
    tree: Ast,
    ptr_type: Ast.full.PtrType,
    space: Space,
) Error!void {
    switch (ptr_type.size) {
        .One => {
            // Since ** tokens exist and the same token is shared by two
            // nested pointer types, we check to see if we are the parent
            // in such a relationship. If so, skip rendering anything for
            // this pointer type and rely on the child to render our asterisk
            // as well when it renders the ** token.
            if (tree.tokens.items(.tag)[ptr_type.ast.main_token] == .asterisk_asterisk and
                ptr_type.ast.main_token == tree.nodes.items(.main_token)[ptr_type.ast.child_type])
            {
                return renderExpression(gpa, ais, tree, ptr_type.ast.child_type, space);
            }
            try renderToken(ais, tree, ptr_type.ast.main_token, .none); // asterisk
        },
        .Many => {
            if (ptr_type.ast.sentinel == 0) {
                try renderToken(ais, tree, ptr_type.ast.main_token - 1, .none); // lbracket
                try renderToken(ais, tree, ptr_type.ast.main_token, .none); // asterisk
                try renderToken(ais, tree, ptr_type.ast.main_token + 1, .none); // rbracket
            } else {
                try renderToken(ais, tree, ptr_type.ast.main_token - 1, .none); // lbracket
                try renderToken(ais, tree, ptr_type.ast.main_token, .none); // asterisk
                try renderToken(ais, tree, ptr_type.ast.main_token + 1, .none); // colon
                try renderExpression(gpa, ais, tree, ptr_type.ast.sentinel, .none);
                try renderToken(ais, tree, tree.lastToken(ptr_type.ast.sentinel) + 1, .none); // rbracket
            }
        },
        .C => {
            try renderToken(ais, tree, ptr_type.ast.main_token - 1, .none); // lbracket
            try renderToken(ais, tree, ptr_type.ast.main_token, .none); // asterisk
            try renderToken(ais, tree, ptr_type.ast.main_token + 1, .none); // c
            try renderToken(ais, tree, ptr_type.ast.main_token + 2, .none); // rbracket
        },
        .Slice => {
            if (ptr_type.ast.sentinel == 0) {
                try renderToken(ais, tree, ptr_type.ast.main_token, .none); // lbracket
                try renderToken(ais, tree, ptr_type.ast.main_token + 1, .none); // rbracket
            } else {
                try renderToken(ais, tree, ptr_type.ast.main_token, .none); // lbracket
                try renderToken(ais, tree, ptr_type.ast.main_token + 1, .none); // colon
                try renderExpression(gpa, ais, tree, ptr_type.ast.sentinel, .none);
                try renderToken(ais, tree, tree.lastToken(ptr_type.ast.sentinel) + 1, .none); // rbracket
            }
        },
    }

    if (ptr_type.allowzero_token) |allowzero_token| {
        try renderToken(ais, tree, allowzero_token, .space);
    }

    if (ptr_type.ast.align_node != 0) {
        const align_first = tree.firstToken(ptr_type.ast.align_node);
        try renderToken(ais, tree, align_first - 2, .none); // align
        try renderToken(ais, tree, align_first - 1, .none); // lparen
        try renderExpression(gpa, ais, tree, ptr_type.ast.align_node, .none);
        if (ptr_type.ast.bit_range_start != 0) {
            assert(ptr_type.ast.bit_range_end != 0);
            try renderToken(ais, tree, tree.firstToken(ptr_type.ast.bit_range_start) - 1, .none); // colon
            try renderExpression(gpa, ais, tree, ptr_type.ast.bit_range_start, .none);
            try renderToken(ais, tree, tree.firstToken(ptr_type.ast.bit_range_end) - 1, .none); // colon
            try renderExpression(gpa, ais, tree, ptr_type.ast.bit_range_end, .none);
            try renderToken(ais, tree, tree.lastToken(ptr_type.ast.bit_range_end) + 1, .space); // rparen
        } else {
            try renderToken(ais, tree, tree.lastToken(ptr_type.ast.align_node) + 1, .space); // rparen
        }
    }

    if (ptr_type.ast.addrspace_node != 0) {
        const addrspace_first = tree.firstToken(ptr_type.ast.addrspace_node);
        try renderToken(ais, tree, addrspace_first - 2, .none); // addrspace
        try renderToken(ais, tree, addrspace_first - 1, .none); // lparen
        try renderExpression(gpa, ais, tree, ptr_type.ast.addrspace_node, .none);
        try renderToken(ais, tree, tree.lastToken(ptr_type.ast.addrspace_node) + 1, .space); // rparen
    }

    if (ptr_type.const_token) |const_token| {
        try renderToken(ais, tree, const_token, .space);
    }

    if (ptr_type.volatile_token) |volatile_token| {
        try renderToken(ais, tree, volatile_token, .space);
    }

    try renderExpression(gpa, ais, tree, ptr_type.ast.child_type, space);
}

fn renderVarDecl(gpa: Allocator, ais: *Ais, tree: Ast, var_decl: Ast.full.VarDecl) Error!void {
    if (var_decl.visib_token) |visib_token| {
        try renderToken(ais, tree, visib_token, Space.space); // pub
    }

    if (var_decl.extern_export_token) |extern_export_token| {
        try renderToken(ais, tree, extern_export_token, Space.space); // extern

        if (var_decl.lib_name) |lib_name| {
            try renderToken(ais, tree, lib_name, Space.space); // "lib"
        }
    }

    if (var_decl.threadlocal_token) |thread_local_token| {
        try renderToken(ais, tree, thread_local_token, Space.space); // threadlocal
    }

    if (var_decl.comptime_token) |comptime_token| {
        try renderToken(ais, tree, comptime_token, Space.space); // comptime
    }

    try renderToken(ais, tree, var_decl.ast.mut_token, .space); // var

    const name_space = if (var_decl.ast.type_node == 0 and
        (var_decl.ast.align_node != 0 or
        var_decl.ast.addrspace_node != 0 or
        var_decl.ast.section_node != 0 or
        var_decl.ast.init_node != 0))
        Space.space
    else
        Space.none;
    try renderIdentifier(ais, tree, var_decl.ast.mut_token + 1, name_space, .preserve_when_shadowing); // name

    if (var_decl.ast.type_node != 0) {
        try renderToken(ais, tree, var_decl.ast.mut_token + 2, Space.space); // :
        if (var_decl.ast.align_node != 0 or var_decl.ast.addrspace_node != 0 or
            var_decl.ast.section_node != 0 or var_decl.ast.init_node != 0)
        {
            try renderExpression(gpa, ais, tree, var_decl.ast.type_node, .space);
        } else {
            try renderExpression(gpa, ais, tree, var_decl.ast.type_node, .none);
            const semicolon = tree.lastToken(var_decl.ast.type_node) + 1;
            return renderToken(ais, tree, semicolon, Space.newline); // ;
        }
    }

    if (var_decl.ast.align_node != 0) {
        const lparen = tree.firstToken(var_decl.ast.align_node) - 1;
        const align_kw = lparen - 1;
        const rparen = tree.lastToken(var_decl.ast.align_node) + 1;
        try renderToken(ais, tree, align_kw, Space.none); // align
        try renderToken(ais, tree, lparen, Space.none); // (
        try renderExpression(gpa, ais, tree, var_decl.ast.align_node, Space.none);
        if (var_decl.ast.addrspace_node != 0 or var_decl.ast.section_node != 0 or
            var_decl.ast.init_node != 0)
        {
            try renderToken(ais, tree, rparen, .space); // )
        } else {
            try renderToken(ais, tree, rparen, .none); // )
            return renderToken(ais, tree, rparen + 1, Space.newline); // ;
        }
    }

    if (var_decl.ast.addrspace_node != 0) {
        const lparen = tree.firstToken(var_decl.ast.addrspace_node) - 1;
        const addrspace_kw = lparen - 1;
        const rparen = tree.lastToken(var_decl.ast.addrspace_node) + 1;
        try renderToken(ais, tree, addrspace_kw, Space.none); // addrspace
        try renderToken(ais, tree, lparen, Space.none); // (
        try renderExpression(gpa, ais, tree, var_decl.ast.addrspace_node, Space.none);
        if (var_decl.ast.section_node != 0 or var_decl.ast.init_node != 0) {
            try renderToken(ais, tree, rparen, .space); // )
        } else {
            try renderToken(ais, tree, rparen, .none); // )
            return renderToken(ais, tree, rparen + 1, Space.newline); // ;
        }
    }

    if (var_decl.ast.section_node != 0) {
        const lparen = tree.firstToken(var_decl.ast.section_node) - 1;
        const section_kw = lparen - 1;
        const rparen = tree.lastToken(var_decl.ast.section_node) + 1;
        try renderToken(ais, tree, section_kw, Space.none); // linksection
        try renderToken(ais, tree, lparen, Space.none); // (
        try renderExpression(gpa, ais, tree, var_decl.ast.section_node, Space.none);
        if (var_decl.ast.init_node != 0) {
            try renderToken(ais, tree, rparen, .space); // )
        } else {
            try renderToken(ais, tree, rparen, .none); // )
            return renderToken(ais, tree, rparen + 1, Space.newline); // ;
        }
    }

    if (var_decl.ast.init_node != 0) {
        const eq_token = tree.firstToken(var_decl.ast.init_node) - 1;
        const eq_space: Space = if (tree.tokensOnSameLine(eq_token, eq_token + 1)) .space else .newline;
        {
            ais.pushIndent();
            try renderToken(ais, tree, eq_token, eq_space); // =
            ais.popIndent();
        }
        ais.pushIndentOneShot();
        return renderExpression(gpa, ais, tree, var_decl.ast.init_node, .semicolon); // ;
    }
    return renderToken(ais, tree, var_decl.ast.mut_token + 2, .newline); // ;
}

fn renderFnProto(gpa: Allocator, ais: *Ais, tree: Ast, fn_proto: Ast.full.FnProto, space: Space) Error!void {
    const token_tags = tree.tokens.items(.tag);
    const token_starts = tree.tokens.items(.start);

    const after_fn_token = fn_proto.ast.fn_token + 1;
    const lparen = if (token_tags[after_fn_token] == .identifier) blk: {
        try renderToken(ais, tree, fn_proto.ast.fn_token, .space); // fn
        try renderIdentifier(ais, tree, after_fn_token, .none, .preserve_when_shadowing); // name
        break :blk after_fn_token + 1;
    } else blk: {
        try renderToken(ais, tree, fn_proto.ast.fn_token, .space); // fn
        break :blk fn_proto.ast.fn_token + 1;
    };
    assert(token_tags[lparen] == .l_paren);

    const maybe_bang = tree.firstToken(fn_proto.ast.return_type) - 1;
    const rparen = blk: {
        // These may appear in any order, so we have to check the token_starts array
        // to find out which is first.
        var rparen = if (token_tags[maybe_bang] == .bang) maybe_bang - 1 else maybe_bang;
        var smallest_start = token_starts[maybe_bang];
        if (fn_proto.ast.align_expr != 0) {
            const tok = tree.firstToken(fn_proto.ast.align_expr) - 3;
            const start = token_starts[tok];
            if (start < smallest_start) {
                rparen = tok;
                smallest_start = start;
            }
        }
        if (fn_proto.ast.addrspace_expr != 0) {
            const tok = tree.firstToken(fn_proto.ast.addrspace_expr) - 3;
            const start = token_starts[tok];
            if (start < smallest_start) {
                rparen = tok;
                smallest_start = start;
            }
        }
        if (fn_proto.ast.section_expr != 0) {
            const tok = tree.firstToken(fn_proto.ast.section_expr) - 3;
            const start = token_starts[tok];
            if (start < smallest_start) {
                rparen = tok;
                smallest_start = start;
            }
        }
        if (fn_proto.ast.callconv_expr != 0) {
            const tok = tree.firstToken(fn_proto.ast.callconv_expr) - 3;
            const start = token_starts[tok];
            if (start < smallest_start) {
                rparen = tok;
                smallest_start = start;
            }
        }
        break :blk rparen;
    };
    assert(token_tags[rparen] == .r_paren);

    // The params list is a sparse set that does *not* include anytype or ... parameters.

    const trailing_comma = token_tags[rparen - 1] == .comma;
    if (!trailing_comma and !hasComment(tree, lparen, rparen)) {
        // Render all on one line, no trailing comma.
        try renderToken(ais, tree, lparen, .none); // (

        var param_i: usize = 0;
        var last_param_token = lparen;
        while (true) {
            last_param_token += 1;
            switch (token_tags[last_param_token]) {
                .doc_comment => {
                    try renderToken(ais, tree, last_param_token, .newline);
                    continue;
                },
                .ellipsis3 => {
                    try renderToken(ais, tree, last_param_token, .none); // ...
                    break;
                },
                .keyword_noalias, .keyword_comptime => {
                    try renderToken(ais, tree, last_param_token, .space);
                    last_param_token += 1;
                },
                .identifier => {},
                .keyword_anytype => {
                    try renderToken(ais, tree, last_param_token, .none); // anytype
                    continue;
                },
                .r_paren => break,
                .comma => {
                    try renderToken(ais, tree, last_param_token, .space); // ,
                    continue;
                },
                else => {}, // Parameter type without a name.
            }
            if (token_tags[last_param_token] == .identifier and
                token_tags[last_param_token + 1] == .colon)
            {
                try renderIdentifier(ais, tree, last_param_token, .none, .preserve_when_shadowing); // name
                last_param_token += 1;
                try renderToken(ais, tree, last_param_token, .space); // :
                last_param_token += 1;
            }
            if (token_tags[last_param_token] == .keyword_anytype) {
                try renderToken(ais, tree, last_param_token, .none); // anytype
                continue;
            }
            const param = fn_proto.ast.params[param_i];
            param_i += 1;
            try renderExpression(gpa, ais, tree, param, .none);
            last_param_token = tree.lastToken(param);
        }
    } else {
        // One param per line.
        ais.pushIndent();
        try renderToken(ais, tree, lparen, .newline); // (

        var param_i: usize = 0;
        var last_param_token = lparen;
        while (true) {
            last_param_token += 1;
            switch (token_tags[last_param_token]) {
                .doc_comment => {
                    try renderToken(ais, tree, last_param_token, .newline);
                    continue;
                },
                .ellipsis3 => {
                    try renderToken(ais, tree, last_param_token, .comma); // ...
                    break;
                },
                .keyword_noalias, .keyword_comptime => {
                    try renderToken(ais, tree, last_param_token, .space);
                    last_param_token += 1;
                },
                .identifier => {},
                .keyword_anytype => {
                    try renderToken(ais, tree, last_param_token, .comma); // anytype
                    if (token_tags[last_param_token + 1] == .comma)
                        last_param_token += 1;
                    continue;
                },
                .r_paren => break,
                else => {}, // Parameter type without a name.
            }
            if (token_tags[last_param_token] == .identifier and
                token_tags[last_param_token + 1] == .colon)
            {
                try renderIdentifier(ais, tree, last_param_token, .none, .preserve_when_shadowing); // name
                last_param_token += 1;
                try renderToken(ais, tree, last_param_token, .space); // :
                last_param_token += 1;
            }
            if (token_tags[last_param_token] == .keyword_anytype) {
                try renderToken(ais, tree, last_param_token, .comma); // anytype
                if (token_tags[last_param_token + 1] == .comma)
                    last_param_token += 1;
                continue;
            }
            const param = fn_proto.ast.params[param_i];
            param_i += 1;
            try renderExpression(gpa, ais, tree, param, .comma);
            last_param_token = tree.lastToken(param);
            if (token_tags[last_param_token + 1] == .comma) last_param_token += 1;
        }
        ais.popIndent();
    }

    try renderToken(ais, tree, rparen, .space); // )

    if (fn_proto.ast.align_expr != 0) {
        const align_lparen = tree.firstToken(fn_proto.ast.align_expr) - 1;
        const align_rparen = tree.lastToken(fn_proto.ast.align_expr) + 1;

        try renderToken(ais, tree, align_lparen - 1, .none); // align
        try renderToken(ais, tree, align_lparen, .none); // (
        try renderExpression(gpa, ais, tree, fn_proto.ast.align_expr, .none);
        try renderToken(ais, tree, align_rparen, .space); // )
    }

    if (fn_proto.ast.addrspace_expr != 0) {
        const align_lparen = tree.firstToken(fn_proto.ast.addrspace_expr) - 1;
        const align_rparen = tree.lastToken(fn_proto.ast.addrspace_expr) + 1;

        try renderToken(ais, tree, align_lparen - 1, .none); // addrspace
        try renderToken(ais, tree, align_lparen, .none); // (
        try renderExpression(gpa, ais, tree, fn_proto.ast.addrspace_expr, .none);
        try renderToken(ais, tree, align_rparen, .space); // )
    }

    if (fn_proto.ast.section_expr != 0) {
        const section_lparen = tree.firstToken(fn_proto.ast.section_expr) - 1;
        const section_rparen = tree.lastToken(fn_proto.ast.section_expr) + 1;

        try renderToken(ais, tree, section_lparen - 1, .none); // section
        try renderToken(ais, tree, section_lparen, .none); // (
        try renderExpression(gpa, ais, tree, fn_proto.ast.section_expr, .none);
        try renderToken(ais, tree, section_rparen, .space); // )
    }

    const is_callconv_inline = mem.eql(u8, "Inline", tree.tokenSlice(tree.nodes.items(.main_token)[fn_proto.ast.callconv_expr]));
    const is_declaration = fn_proto.name_token != null;
    if (fn_proto.ast.callconv_expr != 0 and !(is_declaration and is_callconv_inline)) {
        const callconv_lparen = tree.firstToken(fn_proto.ast.callconv_expr) - 1;
        const callconv_rparen = tree.lastToken(fn_proto.ast.callconv_expr) + 1;

        try renderToken(ais, tree, callconv_lparen - 1, .none); // callconv
        try renderToken(ais, tree, callconv_lparen, .none); // (
        try renderExpression(gpa, ais, tree, fn_proto.ast.callconv_expr, .none);
        try renderToken(ais, tree, callconv_rparen, .space); // )
    }

    if (token_tags[maybe_bang] == .bang) {
        try renderToken(ais, tree, maybe_bang, .none); // !
    }
    return renderExpression(gpa, ais, tree, fn_proto.ast.return_type, space);
}

fn renderBlock(
    gpa: Allocator,
    ais: *Ais,
    tree: Ast,
    block_node: Ast.Node.Index,
    statements: []const Ast.Node.Index,
    space: Space,
) Error!void {
    const token_tags = tree.tokens.items(.tag);
    const node_tags = tree.nodes.items(.tag);
    const lbrace = tree.nodes.items(.main_token)[block_node];

    if (token_tags[lbrace - 1] == .colon and
        token_tags[lbrace - 2] == .identifier)
    {
        try renderIdentifier(ais, tree, lbrace - 2, .none, .eagerly_unquote); // identifier
        try renderToken(ais, tree, lbrace - 1, .space); // :
    }

    ais.pushIndentNextLine();
    if (statements.len == 0) {
        try renderToken(ais, tree, lbrace, .none);
    } else {
        try renderToken(ais, tree, lbrace, .newline);
        for (statements, 0..) |stmt, i| {
            if (i != 0) try renderExtraNewline(ais, tree, stmt);
            switch (node_tags[stmt]) {
                .global_var_decl,
                .local_var_decl,
                .simple_var_decl,
                .aligned_var_decl,
                => try renderVarDecl(gpa, ais, tree, tree.fullVarDecl(stmt).?),
                else => try renderExpression(gpa, ais, tree, stmt, .semicolon),
            }
        }
    }
    ais.popIndent();

    try renderToken(ais, tree, tree.lastToken(block_node), space); // rbrace
}

fn renderContainerDecl(
    gpa: Allocator,
    ais: *Ais,
    tree: Ast,
    container_decl_node: Ast.Node.Index,
    container_decl: Ast.full.ContainerDecl,
    space: Space,
) Error!void {
    const token_tags = tree.tokens.items(.tag);

    if (container_decl.layout_token) |layout_token| {
        try renderToken(ais, tree, layout_token, .space);
    }

    const container: Container = switch (token_tags[container_decl.ast.main_token]) {
        .keyword_enum => .@"enum",
        .keyword_struct => for (container_decl.ast.members) |member| {
            if (tree.fullContainerField(member)) |field| if (!field.ast.tuple_like) break .other;
        } else .tuple,
        else => .other,
    };

    var lbrace: Ast.TokenIndex = undefined;
    if (container_decl.ast.enum_token) |enum_token| {
        try renderToken(ais, tree, container_decl.ast.main_token, .none); // union
        try renderToken(ais, tree, enum_token - 1, .none); // lparen
        try renderToken(ais, tree, enum_token, .none); // enum
        if (container_decl.ast.arg != 0) {
            try renderToken(ais, tree, enum_token + 1, .none); // lparen
            try renderExpression(gpa, ais, tree, container_decl.ast.arg, .none);
            const rparen = tree.lastToken(container_decl.ast.arg) + 1;
            try renderToken(ais, tree, rparen, .none); // rparen
            try renderToken(ais, tree, rparen + 1, .space); // rparen
            lbrace = rparen + 2;
        } else {
            try renderToken(ais, tree, enum_token + 1, .space); // rparen
            lbrace = enum_token + 2;
        }
    } else if (container_decl.ast.arg != 0) {
        try renderToken(ais, tree, container_decl.ast.main_token, .none); // union
        try renderToken(ais, tree, container_decl.ast.main_token + 1, .none); // lparen
        try renderExpression(gpa, ais, tree, container_decl.ast.arg, .none);
        const rparen = tree.lastToken(container_decl.ast.arg) + 1;
        try renderToken(ais, tree, rparen, .space); // rparen
        lbrace = rparen + 1;
    } else {
        try renderToken(ais, tree, container_decl.ast.main_token, .space); // union
        lbrace = container_decl.ast.main_token + 1;
    }

    const rbrace = tree.lastToken(container_decl_node);
    if (container_decl.ast.members.len == 0) {
        ais.pushIndentNextLine();
        if (token_tags[lbrace + 1] == .container_doc_comment) {
            try renderToken(ais, tree, lbrace, .newline); // lbrace
            try renderContainerDocComments(ais, tree, lbrace + 1);
        } else {
            try renderToken(ais, tree, lbrace, .none); // lbrace
        }
        ais.popIndent();
        return renderToken(ais, tree, rbrace, space); // rbrace
    }

    const src_has_trailing_comma = token_tags[rbrace - 1] == .comma;
    if (!src_has_trailing_comma) one_line: {
        // We print all the members in-line unless one of the following conditions are true:

        // 1. The container has comments or multiline strings.
        if (hasComment(tree, lbrace, rbrace) or hasMultilineString(tree, lbrace, rbrace)) {
            break :one_line;
        }

        // 2. The container has a container comment.
        if (token_tags[lbrace + 1] == .container_doc_comment) break :one_line;

        // 3. A member of the container has a doc comment.
        for (token_tags[lbrace + 1 .. rbrace - 1]) |tag| {
            if (tag == .doc_comment) break :one_line;
        }

        // 4. The container has non-field members.
        for (container_decl.ast.members) |member| {
            if (tree.fullContainerField(member) == null) break :one_line;
        }

        // Print all the declarations on the same line.
        try renderToken(ais, tree, lbrace, .space); // lbrace
        for (container_decl.ast.members) |member| {
            try renderMember(gpa, ais, tree, container, member, .space);
        }
        return renderToken(ais, tree, rbrace, space); // rbrace
    }

    // One member per line.
    ais.pushIndentNextLine();
    try renderToken(ais, tree, lbrace, .newline); // lbrace
    if (token_tags[lbrace + 1] == .container_doc_comment) {
        try renderContainerDocComments(ais, tree, lbrace + 1);
    }
    for (container_decl.ast.members, 0..) |member, i| {
        if (i != 0) try renderExtraNewline(ais, tree, member);
        switch (tree.nodes.items(.tag)[member]) {
            // For container fields, ensure a trailing comma is added if necessary.
            .container_field_init,
            .container_field_align,
            .container_field,
            => try renderMember(gpa, ais, tree, container, member, .comma),

            else => try renderMember(gpa, ais, tree, container, member, .newline),
        }
    }
    ais.popIndent();

    return renderToken(ais, tree, rbrace, space); // rbrace
}

/// Renders the given expression indented, popping the indent before rendering
/// any following line comments
fn renderExpressionIndented(gpa: Allocator, ais: *Ais, tree: Ast, node: Ast.Node.Index, space: Space) Error!void {
    const token_starts = tree.tokens.items(.start);
    const token_tags = tree.tokens.items(.tag);

    ais.pushIndent();

    var last_token = tree.lastToken(node);
    const punctuation = switch (space) {
        .none, .space, .newline, .skip => false,
        .comma => true,
        .comma_space => token_tags[last_token + 1] == .comma,
        .semicolon => token_tags[last_token + 1] == .semicolon,
    };

    try renderExpression(gpa, ais, tree, node, if (punctuation) .none else .skip);

    switch (space) {
        .none, .space, .newline, .skip => {},
        .comma => {
            if (token_tags[last_token + 1] == .comma) {
                try renderToken(ais, tree, last_token + 1, .skip);
                last_token += 1;
            } else {
                try ais.writer().writeByte(',');
            }
        },
        .comma_space => if (token_tags[last_token + 1] == .comma) {
            try renderToken(ais, tree, last_token + 1, .skip);
            last_token += 1;
        },
        .semicolon => if (token_tags[last_token + 1] == .semicolon) {
            try renderToken(ais, tree, last_token + 1, .skip);
            last_token += 1;
        },
    }

    ais.popIndent();

    if (space == .skip) return;

    const comment_start = token_starts[last_token] + tokenSliceForRender(tree, last_token).len;
    const comment = try renderComments(ais, tree, comment_start, token_starts[last_token + 1]);

    if (!comment) switch (space) {
        .none => {},
        .space,
        .comma_space,
        => try ais.writer().writeByte(' '),
        .newline,
        .comma,
        .semicolon,
        => try ais.insertNewline(),
        .skip => unreachable,
    };
}

/// Render an expression, and the comma that follows it, if it is present in the source.
/// If a comma is present, and `space` is `Space.comma`, render only a single comma.
fn renderExpressionComma(gpa: Allocator, ais: *Ais, tree: Ast, node: Ast.Node.Index, space: Space) Error!void {
    const token_tags = tree.tokens.items(.tag);
    const maybe_comma = tree.lastToken(node) + 1;
    if (token_tags[maybe_comma] == .comma and space != .comma) {
        try renderExpression(gpa, ais, tree, node, .none);
        return renderToken(ais, tree, maybe_comma, space);
    } else {
        return renderExpression(gpa, ais, tree, node, space);
    }
}

/// Render a token, and the comma that follows it, if it is present in the source.
/// If a comma is present, and `space` is `Space.comma`, render only a single comma.
fn renderTokenComma(ais: *Ais, tree: Ast, token: Ast.TokenIndex, space: Space) Error!void {
    const token_tags = tree.tokens.items(.tag);
    const maybe_comma = token + 1;
    if (token_tags[maybe_comma] == .comma and space != .comma) {
        try renderToken(ais, tree, token, .none);
        return renderToken(ais, tree, maybe_comma, space);
    } else {
        return renderToken(ais, tree, token, space);
    }
}

/// Render an identifier, and the comma that follows it, if it is present in the source.
/// If a comma is present, and `space` is `Space.comma`, render only a single comma.
fn renderIdentifierComma(ais: *Ais, tree: Ast, token: Ast.TokenIndex, space: Space, quote: QuoteBehavior) Error!void {
    const token_tags = tree.tokens.items(.tag);
    const maybe_comma = token + 1;
    if (token_tags[maybe_comma] == .comma and space != .comma) {
        try renderIdentifier(ais, tree, token, .none, quote);
        return renderToken(ais, tree, maybe_comma, space);
    } else {
        return renderIdentifier(ais, tree, token, space, quote);
    }
}

const Space = enum {
    /// Output the token lexeme only.
    none,
    /// Output the token lexeme followed by a single space.
    space,
    /// Output the token lexeme followed by a newline.
    newline,
    /// If the next token is a comma, render it as well. If not, insert one.
    /// In either case, a newline will be inserted afterwards.
    comma,
    /// Additionally consume the next token if it is a comma.
    /// In either case, a space will be inserted afterwards.
    comma_space,
    /// Additionally consume the next token if it is a semicolon.
    /// In either case, a newline will be inserted afterwards.
    semicolon,
    /// Skip rendering whitespace and comments. If this is used, the caller
    /// *must* handle whitespace and comments manually.
    skip,
};

fn renderToken(ais: *Ais, tree: Ast, token_index: Ast.TokenIndex, space: Space) Error!void {
    const lexeme = tokenSliceForRender(tree, token_index);
    try ais.writer().writeAll(lexeme);
    try renderSpace(ais, tree, token_index, lexeme.len, space);
}

fn renderSpace(ais: *Ais, tree: Ast, token_index: Ast.TokenIndex, lexeme_len: usize, space: Space) Error!void {
    const token_tags = tree.tokens.items(.tag);
    const token_starts = tree.tokens.items(.start);

    const token_start = token_starts[token_index];

    if (space == .skip) return;

    if (space == .comma and token_tags[token_index + 1] != .comma) {
        try ais.writer().writeByte(',');
    }

    const comment = try renderComments(ais, tree, token_start + lexeme_len, token_starts[token_index + 1]);
    switch (space) {
        .none => {},
        .space => if (!comment) try ais.writer().writeByte(' '),
        .newline => if (!comment) try ais.insertNewline(),

        .comma => if (token_tags[token_index + 1] == .comma) {
            try renderToken(ais, tree, token_index + 1, .newline);
        } else if (!comment) {
            try ais.insertNewline();
        },

        .comma_space => if (token_tags[token_index + 1] == .comma) {
            try renderToken(ais, tree, token_index + 1, .space);
        } else if (!comment) {
            try ais.writer().writeByte(' ');
        },

        .semicolon => if (token_tags[token_index + 1] == .semicolon) {
            try renderToken(ais, tree, token_index + 1, .newline);
        } else if (!comment) {
            try ais.insertNewline();
        },

        .skip => unreachable,
    }
}

const QuoteBehavior = enum {
    preserve_when_shadowing,
    eagerly_unquote,
    eagerly_unquote_except_underscore,
};

fn renderIdentifier(ais: *Ais, tree: Ast, token_index: Ast.TokenIndex, space: Space, quote: QuoteBehavior) Error!void {
    const token_tags = tree.tokens.items(.tag);
    assert(token_tags[token_index] == .identifier);
    const lexeme = tokenSliceForRender(tree, token_index);
    if (lexeme[0] != '@') {
        return renderToken(ais, tree, token_index, space);
    }

    assert(lexeme.len >= 3);
    assert(lexeme[0] == '@');
    assert(lexeme[1] == '\"');
    assert(lexeme[lexeme.len - 1] == '\"');
    const contents = lexeme[2 .. lexeme.len - 1]; // inside the @"" quotation

    // Empty name can't be unquoted.
    if (contents.len == 0) {
        return renderQuotedIdentifier(ais, tree, token_index, space, false);
    }

    // Special case for _ which would incorrectly be rejected by isValidId below.
    if (contents.len == 1 and contents[0] == '_') switch (quote) {
        .eagerly_unquote => return renderQuotedIdentifier(ais, tree, token_index, space, true),
        .eagerly_unquote_except_underscore,
        .preserve_when_shadowing,
        => return renderQuotedIdentifier(ais, tree, token_index, space, false),
    };

    // Scan the entire name for characters that would (after un-escaping) be illegal in a symbol,
    // i.e. contents don't match: [A-Za-z_][A-Za-z0-9_]*
    var contents_i: usize = 0;
    while (contents_i < contents.len) {
        switch (contents[contents_i]) {
            '0'...'9' => if (contents_i == 0) return renderQuotedIdentifier(ais, tree, token_index, space, false),
            'A'...'Z', 'a'...'z', '_' => {},
            '\\' => {
                var esc_offset = contents_i;
                const res = std.zig.string_literal.parseEscapeSequence(contents, &esc_offset);
                switch (res) {
                    .success => |char| switch (char) {
                        '0'...'9' => if (contents_i == 0) return renderQuotedIdentifier(ais, tree, token_index, space, false),
                        'A'...'Z', 'a'...'z', '_' => {},
                        else => return renderQuotedIdentifier(ais, tree, token_index, space, false),
                    },
                    .failure => return renderQuotedIdentifier(ais, tree, token_index, space, false),
                }
                contents_i += esc_offset;
                continue;
            },
            else => return renderQuotedIdentifier(ais, tree, token_index, space, false),
        }
        contents_i += 1;
    }

    // Read enough of the name (while un-escaping) to determine if it's a keyword or primitive.
    // If it's too long to fit in this buffer, we know it's neither and quoting is unnecessary.
    // If we read the whole thing, we have to do further checks.
    const longest_keyword_or_primitive_len = comptime blk: {
        var longest = 0;
        for (primitives.names.kvs) |kv| {
            if (kv.key.len > longest) longest = kv.key.len;
        }
        for (std.zig.Token.keywords.kvs) |kv| {
            if (kv.key.len > longest) longest = kv.key.len;
        }
        break :blk longest;
    };
    var buf: [longest_keyword_or_primitive_len]u8 = undefined;

    contents_i = 0;
    var buf_i: usize = 0;
    while (contents_i < contents.len and buf_i < longest_keyword_or_primitive_len) {
        if (contents[contents_i] == '\\') {
            const res = std.zig.string_literal.parseEscapeSequence(contents, &contents_i).success;
            buf[buf_i] = @as(u8, @intCast(res));
            buf_i += 1;
        } else {
            buf[buf_i] = contents[contents_i];
            contents_i += 1;
            buf_i += 1;
        }
    }

    // We read the whole thing, so it could be a keyword or primitive.
    if (contents_i == contents.len) {
        if (!std.zig.isValidId(buf[0..buf_i])) {
            return renderQuotedIdentifier(ais, tree, token_index, space, false);
        }
        if (primitives.isPrimitive(buf[0..buf_i])) switch (quote) {
            .eagerly_unquote,
            .eagerly_unquote_except_underscore,
            => return renderQuotedIdentifier(ais, tree, token_index, space, true),
            .preserve_when_shadowing => return renderQuotedIdentifier(ais, tree, token_index, space, false),
        };
    }

    try renderQuotedIdentifier(ais, tree, token_index, space, true);
}

// Renders a @"" quoted identifier, normalizing escapes.
// Unnecessary escapes are un-escaped, and \u escapes are normalized to \x when they fit.
// If unquote is true, the @"" is removed and the result is a bare symbol whose validity is asserted.
fn renderQuotedIdentifier(ais: *Ais, tree: Ast, token_index: Ast.TokenIndex, space: Space, comptime unquote: bool) !void {
    const token_tags = tree.tokens.items(.tag);
    assert(token_tags[token_index] == .identifier);
    const lexeme = tokenSliceForRender(tree, token_index);
    assert(lexeme.len >= 3 and lexeme[0] == '@');

    if (!unquote) try ais.writer().writeAll("@\"");
    const contents = lexeme[2 .. lexeme.len - 1];
    try renderIdentifierContents(ais.writer(), contents);
    if (!unquote) try ais.writer().writeByte('\"');

    try renderSpace(ais, tree, token_index, lexeme.len, space);
}

fn renderIdentifierContents(writer: anytype, bytes: []const u8) !void {
    var pos: usize = 0;
    while (pos < bytes.len) {
        const byte = bytes[pos];
        switch (byte) {
            '\\' => {
                const old_pos = pos;
                const res = std.zig.string_literal.parseEscapeSequence(bytes, &pos);
                const escape_sequence = bytes[old_pos..pos];
                switch (res) {
                    .success => |codepoint| {
                        if (codepoint <= 0x7f) {
                            const buf = [1]u8{@as(u8, @intCast(codepoint))};
                            try std.fmt.format(writer, "{}", .{std.zig.fmtEscapes(&buf)});
                        } else {
                            try writer.writeAll(escape_sequence);
                        }
                    },
                    .failure => {
                        try writer.writeAll(escape_sequence);
                    },
                }
            },
            0x00...('\\' - 1), ('\\' + 1)...0x7f => {
                const buf = [1]u8{byte};
                try std.fmt.format(writer, "{}", .{std.zig.fmtEscapes(&buf)});
                pos += 1;
            },
            0x80...0xff => {
                try writer.writeByte(byte);
                pos += 1;
            },
        }
    }
}

/// Returns true if there exists a line comment between any of the tokens from
/// `start_token` to `end_token`. This is used to determine if e.g. a
/// fn_proto should be wrapped and have a trailing comma inserted even if
/// there is none in the source.
fn hasComment(tree: Ast, start_token: Ast.TokenIndex, end_token: Ast.TokenIndex) bool {
    const token_starts = tree.tokens.items(.start);

    var i = start_token;
    while (i < end_token) : (i += 1) {
        const start = token_starts[i] + tree.tokenSlice(i).len;
        const end = token_starts[i + 1];
        if (mem.indexOf(u8, tree.source[start..end], "//") != null) return true;
    }

    return false;
}

/// Returns true if there exists a multiline string literal between the start
/// of token `start_token` and the start of token `end_token`.
fn hasMultilineString(tree: Ast, start_token: Ast.TokenIndex, end_token: Ast.TokenIndex) bool {
    const token_tags = tree.tokens.items(.tag);

    for (token_tags[start_token..end_token]) |tag| {
        switch (tag) {
            .multiline_string_literal_line => return true,
            else => continue,
        }
    }

    return false;
}

/// Assumes that start is the first byte past the previous token and
/// that end is the last byte before the next token.
fn renderComments(ais: *Ais, tree: Ast, start: usize, end: usize) Error!bool {
    var index: usize = start;
    while (mem.indexOf(u8, tree.source[index..end], "//")) |offset| {
        const comment_start = index + offset;

        // If there is no newline, the comment ends with EOF
        const newline_index = mem.indexOfScalar(u8, tree.source[comment_start..end], '\n');
        const newline = if (newline_index) |i| comment_start + i else null;

        const untrimmed_comment = tree.source[comment_start .. newline orelse tree.source.len];
        const trimmed_comment = mem.trimRight(u8, untrimmed_comment, &std.ascii.whitespace);

        // Don't leave any whitespace at the start of the file
        if (index != 0) {
            if (index == start and mem.containsAtLeast(u8, tree.source[index..comment_start], 2, "\n")) {
                // Leave up to one empty line before the first comment
                try ais.insertNewline();
                try ais.insertNewline();
            } else if (mem.indexOfScalar(u8, tree.source[index..comment_start], '\n') != null) {
                // Respect the newline directly before the comment.
                // Note: This allows an empty line between comments
                try ais.insertNewline();
            } else if (index == start) {
                // Otherwise if the first comment is on the same line as
                // the token before it, prefix it with a single space.
                try ais.writer().writeByte(' ');
            }
        }

        index = 1 + (newline orelse end - 1);

        const comment_content = mem.trimLeft(u8, trimmed_comment["//".len..], &std.ascii.whitespace);
        if (ais.disabled_offset != null and mem.eql(u8, comment_content, "zig fmt: on")) {
            // Write the source for which formatting was disabled directly
            // to the underlying writer, fixing up invalid whitespace.
            const disabled_source = tree.source[ais.disabled_offset.?..comment_start];
            try writeFixingWhitespace(ais.underlying_writer, disabled_source);
            // Write with the canonical single space.
            try ais.underlying_writer.writeAll("// zig fmt: on\n");
            ais.disabled_offset = null;
        } else if (ais.disabled_offset == null and mem.eql(u8, comment_content, "zig fmt: off")) {
            // Write with the canonical single space.
            try ais.writer().writeAll("// zig fmt: off\n");
            ais.disabled_offset = index;
        } else {
            // Write the comment minus trailing whitespace.
            try ais.writer().print("{s}\n", .{trimmed_comment});
        }
    }

    if (index != start and mem.containsAtLeast(u8, tree.source[index - 1 .. end], 2, "\n")) {
        // Don't leave any whitespace at the end of the file
        if (end != tree.source.len) {
            try ais.insertNewline();
        }
    }

    return index != start;
}

fn renderExtraNewline(ais: *Ais, tree: Ast, node: Ast.Node.Index) Error!void {
    return renderExtraNewlineToken(ais, tree, tree.firstToken(node));
}

/// Check if there is an empty line immediately before the given token. If so, render it.
fn renderExtraNewlineToken(ais: *Ais, tree: Ast, token_index: Ast.TokenIndex) Error!void {
    const token_starts = tree.tokens.items(.start);
    const token_start = token_starts[token_index];
    if (token_start == 0) return;
    const prev_token_end = if (token_index == 0)
        0
    else
        token_starts[token_index - 1] + tokenSliceForRender(tree, token_index - 1).len;

    // If there is a comment present, it will handle the empty line
    if (mem.indexOf(u8, tree.source[prev_token_end..token_start], "//") != null) return;

    // Iterate backwards to the end of the previous token, stopping if a
    // non-whitespace character is encountered or two newlines have been found.
    var i = token_start - 1;
    var newlines: u2 = 0;
    while (std.ascii.isWhitespace(tree.source[i])) : (i -= 1) {
        if (tree.source[i] == '\n') newlines += 1;
        if (newlines == 2) return ais.insertNewline();
        if (i == prev_token_end) break;
    }
}

/// end_token is the token one past the last doc comment token. This function
/// searches backwards from there.
fn renderDocComments(ais: *Ais, tree: Ast, end_token: Ast.TokenIndex) Error!void {
    // Search backwards for the first doc comment.
    const token_tags = tree.tokens.items(.tag);
    if (end_token == 0) return;
    var tok = end_token - 1;
    while (token_tags[tok] == .doc_comment) {
        if (tok == 0) break;
        tok -= 1;
    } else {
        tok += 1;
    }
    const first_tok = tok;
    if (first_tok == end_token) return;

    if (first_tok != 0) {
        const prev_token_tag = token_tags[first_tok - 1];

        // Prevent accidental use of `renderDocComments` for a function argument doc comment
        assert(prev_token_tag != .l_paren);

        if (prev_token_tag != .l_brace) {
            try renderExtraNewlineToken(ais, tree, first_tok);
        }
    }

    while (token_tags[tok] == .doc_comment) : (tok += 1) {
        try renderToken(ais, tree, tok, .newline);
    }
}

/// start_token is first container doc comment token.
fn renderContainerDocComments(ais: *Ais, tree: Ast, start_token: Ast.TokenIndex) Error!void {
    const token_tags = tree.tokens.items(.tag);
    var tok = start_token;
    while (token_tags[tok] == .container_doc_comment) : (tok += 1) {
        try renderToken(ais, tree, tok, .newline);
    }
    // Render extra newline if there is one between final container doc comment and
    // the next token. If the next token is a doc comment, that code path
    // will have its own logic to insert a newline.
    if (token_tags[tok] != .doc_comment) {
        try renderExtraNewlineToken(ais, tree, tok);
    }
}

fn tokenSliceForRender(tree: Ast, token_index: Ast.TokenIndex) []const u8 {
    var ret = tree.tokenSlice(token_index);
    switch (tree.tokens.items(.tag)[token_index]) {
        .multiline_string_literal_line => {
            if (ret[ret.len - 1] == '\n') ret.len -= 1;
        },
        .container_doc_comment, .doc_comment => {
            ret = mem.trimRight(u8, ret, &std.ascii.whitespace);
        },
        else => {},
    }
    return ret;
}

fn hasSameLineComment(tree: Ast, token_index: Ast.TokenIndex) bool {
    const token_starts = tree.tokens.items(.start);
    const between_source = tree.source[token_starts[token_index]..token_starts[token_index + 1]];
    for (between_source) |byte| switch (byte) {
        '\n' => return false,
        '/' => return true,
        else => continue,
    };
    return false;
}

/// Returns `true` if and only if there are any tokens or line comments between
/// start_token and end_token.
fn anythingBetween(tree: Ast, start_token: Ast.TokenIndex, end_token: Ast.TokenIndex) bool {
    if (start_token + 1 != end_token) return true;
    const token_starts = tree.tokens.items(.start);
    const between_source = tree.source[token_starts[start_token]..token_starts[start_token + 1]];
    for (between_source) |byte| switch (byte) {
        '/' => return true,
        else => continue,
    };
    return false;
}

fn writeFixingWhitespace(writer: std.ArrayList(u8).Writer, slice: []const u8) Error!void {
    for (slice) |byte| switch (byte) {
        '\t' => try writer.writeAll(" " ** 4),
        '\r' => {},
        else => try writer.writeByte(byte),
    };
}

fn nodeIsBlock(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .block,
        .block_semicolon,
        .block_two,
        .block_two_semicolon,
        => true,
        else => false,
    };
}

fn nodeIsIfForWhileSwitch(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .@"if",
        .if_simple,
        .@"for",
        .for_simple,
        .@"while",
        .while_simple,
        .while_cont,
        .@"switch",
        .switch_comma,
        => true,
        else => false,
    };
}

fn nodeCausesSliceOpSpace(tag: Ast.Node.Tag) bool {
    return switch (tag) {
        .@"catch",
        .add,
        .add_wrap,
        .array_cat,
        .array_mult,
        .assign,
        .assign_bit_and,
        .assign_bit_or,
        .assign_shl,
        .assign_shr,
        .assign_bit_xor,
        .assign_div,
        .assign_sub,
        .assign_sub_wrap,
        .assign_mod,
        .assign_add,
        .assign_add_wrap,
        .assign_mul,
        .assign_mul_wrap,
        .bang_equal,
        .bit_and,
        .bit_or,
        .shl,
        .shr,
        .bit_xor,
        .bool_and,
        .bool_or,
        .div,
        .equal_equal,
        .error_union,
        .greater_or_equal,
        .greater_than,
        .less_or_equal,
        .less_than,
        .merge_error_sets,
        .mod,
        .mul,
        .mul_wrap,
        .sub,
        .sub_wrap,
        .@"orelse",
        => true,

        else => false,
    };
}

// Returns the number of nodes in `exprs` that are on the same line as `rtoken`.
fn rowSize(tree: Ast, exprs: []const Ast.Node.Index, rtoken: Ast.TokenIndex) usize {
    const token_tags = tree.tokens.items(.tag);

    const first_token = tree.firstToken(exprs[0]);
    if (tree.tokensOnSameLine(first_token, rtoken)) {
        const maybe_comma = rtoken - 1;
        if (token_tags[maybe_comma] == .comma)
            return 1;
        return exprs.len; // no newlines
    }

    var count: usize = 1;
    for (exprs, 0..) |expr, i| {
        if (i + 1 < exprs.len) {
            const expr_last_token = tree.lastToken(expr) + 1;
            if (!tree.tokensOnSameLine(expr_last_token, tree.firstToken(exprs[i + 1]))) return count;
            count += 1;
        } else {
            return count;
        }
    }
    unreachable;
}

/// Automatically inserts indentation of written data by keeping
/// track of the current indentation level
fn AutoIndentingStream(comptime UnderlyingWriter: type) type {
    return struct {
        const Self = @This();
        pub const WriteError = UnderlyingWriter.Error;
        pub const Writer = std.io.Writer(*Self, WriteError, write);

        underlying_writer: UnderlyingWriter,

        /// Offset into the source at which formatting has been disabled with
        /// a `zig fmt: off` comment.
        ///
        /// If non-null, the AutoIndentingStream will not write any bytes
        /// to the underlying writer. It will however continue to track the
        /// indentation level.
        disabled_offset: ?usize = null,

        indent_count: usize = 0,
        indent_delta: usize,
        current_line_empty: bool = true,
        /// automatically popped when applied
        indent_one_shot_count: usize = 0,
        /// the most recently applied indent
        applied_indent: usize = 0,
        /// not used until the next line
        indent_next_line: usize = 0,

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0)
                return @as(usize, 0);

            try self.applyIndent();
            return self.writeNoIndent(bytes);
        }

        // Change the indent delta without changing the final indentation level
        pub fn setIndentDelta(self: *Self, new_indent_delta: usize) void {
            if (self.indent_delta == new_indent_delta) {
                return;
            } else if (self.indent_delta > new_indent_delta) {
                assert(self.indent_delta % new_indent_delta == 0);
                self.indent_count = self.indent_count * (self.indent_delta / new_indent_delta);
            } else {
                // assert that the current indentation (in spaces) in a multiple of the new delta
                assert((self.indent_count * self.indent_delta) % new_indent_delta == 0);
                self.indent_count = self.indent_count / (new_indent_delta / self.indent_delta);
            }
            self.indent_delta = new_indent_delta;
        }

        fn writeNoIndent(self: *Self, bytes: []const u8) WriteError!usize {
            if (bytes.len == 0)
                return @as(usize, 0);

            if (self.disabled_offset == null) try self.underlying_writer.writeAll(bytes);
            if (bytes[bytes.len - 1] == '\n')
                self.resetLine();
            return bytes.len;
        }

        pub fn insertNewline(self: *Self) WriteError!void {
            _ = try self.writeNoIndent("\n");
        }

        fn resetLine(self: *Self) void {
            self.current_line_empty = true;
            self.indent_next_line = 0;
        }

        /// Insert a newline unless the current line is blank
        pub fn maybeInsertNewline(self: *Self) WriteError!void {
            if (!self.current_line_empty)
                try self.insertNewline();
        }

        /// Push default indentation
        /// Doesn't actually write any indentation.
        /// Just primes the stream to be able to write the correct indentation if it needs to.
        pub fn pushIndent(self: *Self) void {
            self.indent_count += 1;
        }

        /// Push an indent that is automatically popped after being applied
        pub fn pushIndentOneShot(self: *Self) void {
            self.indent_one_shot_count += 1;
            self.pushIndent();
        }

        /// Turns all one-shot indents into regular indents
        /// Returns number of indents that must now be manually popped
        pub fn lockOneShotIndent(self: *Self) usize {
            var locked_count = self.indent_one_shot_count;
            self.indent_one_shot_count = 0;
            return locked_count;
        }

        /// Push an indent that should not take effect until the next line
        pub fn pushIndentNextLine(self: *Self) void {
            self.indent_next_line += 1;
            self.pushIndent();
        }

        pub fn popIndent(self: *Self) void {
            assert(self.indent_count != 0);
            self.indent_count -= 1;

            if (self.indent_next_line > 0)
                self.indent_next_line -= 1;
        }

        /// Writes ' ' bytes if the current line is empty
        fn applyIndent(self: *Self) WriteError!void {
            const current_indent = self.currentIndent();
            if (self.current_line_empty and current_indent > 0) {
                if (self.disabled_offset == null) {
                    try self.underlying_writer.writeByteNTimes(' ', current_indent);
                }
                self.applied_indent = current_indent;
            }

            self.indent_count -= self.indent_one_shot_count;
            self.indent_one_shot_count = 0;
            self.current_line_empty = false;
        }

        /// Checks to see if the most recent indentation exceeds the currently pushed indents
        pub fn isLineOverIndented(self: *Self) bool {
            if (self.current_line_empty) return false;
            return self.applied_indent > self.currentIndent();
        }

        fn currentIndent(self: *Self) usize {
            var indent_current: usize = 0;
            if (self.indent_count > 0) {
                const indent_count = self.indent_count - self.indent_next_line;
                indent_current = indent_count * self.indent_delta;
            }
            return indent_current;
        }
    };
}
