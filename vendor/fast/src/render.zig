//!
//! This file is based on "std.zig.Ast.render" which originally renders
//! a Zig AST.
//!
//! Now it converts the AST into an equivalent AST which is much easier
//! to process for humans.
//!
const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const meta = std.meta;
const Ast = std.zig.Ast;
const Token = std.zig.Token;
const primitives = std.zig.primitives;

const fast = @import("fast.zig");

pub const Error = Ast.RenderError;

const Render = struct {
    arena: Allocator,
    tree: Ast,
};

pub fn renderTree(arena: std.mem.Allocator, tree: Ast) Error!fast.Container {
    assert(tree.errors.len == 0); // Cannot render an invalid tree.

    var r: Render = .{
        .arena = arena,
        .tree = tree,
    };

    const doc_comment = if (tree.tokens.items(.tag)[0] == .container_doc_comment)
        try renderContainerDocComments(&r, 0)
    else
        null;

    const members = try renderMembers(&r, tree.rootDecls());

    return .{
        .doc_comment = doc_comment,
        .members = members,
    };
}

/// Render all members in the given slice, keeping empty lines where appropriate
fn renderMembers(r: *Render, members: []const Ast.Node.Index) Error![]const fast.Member {
    const tree = r.tree;
    if (members.len == 0) return &.{};
    const container: Container = for (members) |member| {
        if (tree.fullContainerField(member)) |field| if (!field.ast.tuple_like) break .other;
    } else .tuple;

    var memberlist: std.ArrayList(fast.Member) = .init(r.arena);
    defer memberlist.deinit();

    try memberlist.ensureTotalCapacityPrecise(members.len);

    for (members) |member| {
        memberlist.appendAssumeCapacity(try renderMember(r, container, member));
    }

    return try memberlist.toOwnedSlice();
}

const Container = enum {
    @"enum",
    tuple,
    other,
};

fn renderMember(
    r: *Render,
    container: Container,
    decl: Ast.Node.Index,
) Error!fast.Member {
    const tree = r.tree;
    // const node_tags = tree.nodes.items(.tag);
    const token_tags = tree.tokens.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    const datas = tree.nodes.items(.data);
    const doc_comment: ?[]const u8 = try renderDocComments(r, tree.firstToken(decl));

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

            var fndecl: fast.FunctionDeclaration = .{
                .doc_comment = doc_comment,
                .prototype = undefined,
                .body = undefined,
            };

            while (i < fn_token) : (i += 1) {
                switch (token_tags[i]) {
                    .keyword_extern => fndecl.@"extern" = .generic,
                    .keyword_export => fndecl.@"export" = true,
                    .keyword_pub => fndecl.@"pub" = true,
                    .string_literal => {
                        std.debug.assert(fndecl.@"extern" == .generic);
                        fndecl.@"extern" = .{ .library = tokenSliceForRender(tree, i) };
                    },
                    .keyword_inline => fndecl.@"inline" = true,
                    .keyword_noinline => fndecl.@"noinline" = true,

                    else => unreachable,
                }
            }

            switch (tree.nodes.items(.tag)[fn_proto]) {
                .fn_proto_one, .fn_proto => {
                    const callconv_expr = if (tree.nodes.items(.tag)[fn_proto] == .fn_proto_one)
                        tree.extraData(datas[fn_proto].lhs, Ast.Node.FnProtoOne).callconv_expr
                    else
                        tree.extraData(datas[fn_proto].lhs, Ast.Node.FnProto).callconv_expr;
                    // Keep in sync with logic in `renderFnProto`. Search this file for the marker PROMOTE_CALLCONV_INLINE
                    if (callconv_expr != 0 and tree.nodes.items(.tag)[callconv_expr] == .enum_literal) {
                        if (mem.eql(u8, "@\"inline\"", tree.tokenSlice(main_tokens[callconv_expr]))) {
                            fndecl.@"inline" = true;
                        }
                    }
                },
                .fn_proto_simple, .fn_proto_multi => {},
                else => unreachable,
            }
            assert(datas[decl].rhs != 0);
            fndecl.prototype = try renderExpression(r, fn_proto);

            const body_node = datas[decl].rhs;
            fndecl.body = try renderExpression(r, body_node);

            return .{ .fn_decl = fndecl };
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

            var fndecl: fast.FunctionDeclaration = .{
                .doc_comment = doc_comment,
                .prototype = undefined,
                .body = null,
            };

            while (i < fn_token) : (i += 1) {
                switch (token_tags[i]) {
                    .keyword_extern => fndecl.@"extern" = .generic,
                    .keyword_export => fndecl.@"export" = true,
                    .keyword_pub => fndecl.@"pub" = true,
                    .string_literal => {
                        std.debug.assert(fndecl.@"extern" == .generic);
                        fndecl.@"extern" = .{ .library = tokenSliceForRender(tree, i) };
                    },
                    .keyword_inline => fndecl.@"inline" = true,
                    .keyword_noinline => fndecl.@"noinline" = true,

                    else => unreachable,
                }
            }

            fndecl.prototype = try renderExpression(r, decl);
            return .{ .fn_decl = fndecl };
        },

        .@"usingnamespace" => {
            var uns: fast.UsingNamespace = .{
                .namespace = undefined,
            };
            const main_token = main_tokens[decl];
            const expr = datas[decl].lhs;
            if (main_token > 0 and token_tags[main_token - 1] == .keyword_pub) {
                uns.@"pub" = true;
            }

            uns.namespace = try renderExpression(r, expr);

            return .{ .@"usingnamespace" = uns };
        },

        .global_var_decl,
        .local_var_decl,
        .simple_var_decl,
        .aligned_var_decl,
        => {
            var vardecl = try renderVarDecl(r, tree.fullVarDecl(decl).?, false);
            vardecl.doc_comment = doc_comment;
            return .{ .var_decl = vardecl };
        },

        .test_decl => {
            var testdecl: fast.TestDeclaration = .{
                .type = .blank,
                .body = undefined,
            };

            const test_token = main_tokens[decl];
            const test_name_tag = token_tags[test_token + 1];
            switch (test_name_tag) {
                .string_literal => testdecl.type = .{ .named = tokenSliceForRender(r.tree, test_token + 1) },
                .identifier => testdecl.type = .{ .decl = try renderIdentifier(r, test_token + 1, .preserve_when_shadowing) },
                else => {},
            }

            testdecl.body = try renderExpression(r, datas[decl].rhs);

            return .{ .@"test" = testdecl };
        },

        .container_field_init,
        .container_field_align,
        .container_field,
        => return .{
            .field = try renderContainerField(r, container, tree.fullContainerField(decl).?),
        },

        .@"comptime" => return .{
            .comptime_block = try renderExpression(r, decl),
        },

        .root => unreachable,
        else => unreachable,
    }
}

/// Render all expressions in the slice, keeping empty lines where appropriate
fn renderExpressions(r: *Render, expressions: []const Ast.Node.Index) Error!void {
    if (expressions.len == 0) return;
    try renderExpression(r, expressions[0]);
    for (expressions[1..]) |expression| {
        try renderExtraNewline(r, expression);
        try renderExpression(r, expression);
    }
}

fn renderExpression(r: *Render, node: Ast.Node.Index) Error!*const fast.Expression {
    const expr = try r.arena.create(fast.Expression);
    errdefer r.arena.destroy(expr);
    _ = node;
    @panic("not done yet");
    // expr.* = try renderExpressionValue(r, node);
    // return expr;
}

fn renderExpressionValue(r: *Render, node: Ast.Node.Index) Error!*const fast.Expression {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    const node_tags = tree.nodes.items(.tag);
    const datas = tree.nodes.items(.data);

    switch (node_tags[node]) {
        .identifier => {
            const token_index = main_tokens[node];
            return renderIdentifier(r, token_index, .preserve_when_shadowing);
        },

        .number_literal,
        .char_literal,
        .unreachable_literal,
        .anyframe_literal,
        .string_literal,
        => return renderToken(r, main_tokens[node]),

        .multiline_string_literal => {
            var i = datas[node].lhs;
            while (i <= datas[node].rhs) : (i += 1) try renderToken(r, i, .newline);

            try renderToken(r, i, .space);
        },

        .error_value => {
            try renderToken(r, main_tokens[node], .none);
            try renderToken(r, main_tokens[node] + 1, .none);
            return renderIdentifier(r, main_tokens[node] + 2, .eagerly_unquote);
        },

        .block_two,
        .block_two_semicolon,
        => {
            const statements = [2]Ast.Node.Index{ datas[node].lhs, datas[node].rhs };
            if (datas[node].lhs == 0) {
                return renderBlock(r, node, statements[0..0]);
            } else if (datas[node].rhs == 0) {
                return renderBlock(r, node, statements[0..1]);
            } else {
                return renderBlock(r, node, statements[0..2]);
            }
        },
        .block,
        .block_semicolon,
        => {
            const statements = tree.extra_data[datas[node].lhs..datas[node].rhs];
            return renderBlock(r, node, statements);
        },

        .@"errdefer" => {
            const defer_token = main_tokens[node];
            const payload_token = datas[node].lhs;
            const expr = datas[node].rhs;

            try renderToken(r, defer_token, .space);
            if (payload_token != 0) {
                try renderToken(r, payload_token - 1, .none); // |
                try renderIdentifier(r, payload_token, .none, .preserve_when_shadowing); // identifier
                try renderToken(r, payload_token + 1, .space); // |
            }
            return renderExpression(r, expr);
        },

        .@"defer" => {
            const defer_token = main_tokens[node];
            const expr = datas[node].rhs;
            try renderToken(r, defer_token, .space);
            return renderExpression(r, expr);
        },
        .@"comptime", .@"nosuspend" => {
            const comptime_token = main_tokens[node];
            const block = datas[node].lhs;
            try renderToken(r, comptime_token, .space);
            return renderExpression(r, block);
        },

        .@"suspend" => {
            const suspend_token = main_tokens[node];
            const body = datas[node].lhs;
            try renderToken(r, suspend_token, .space);
            return renderExpression(r, body);
        },

        .@"catch" => {
            const main_token = main_tokens[node];
            const fallback_first = tree.firstToken(datas[node].rhs);

            try renderExpression(r, datas[node].lhs, .space); // target

            if (token_tags[fallback_first - 1] == .pipe) {
                try renderToken(r, main_token, .space); // catch keyword
                try renderToken(r, main_token + 1, .none); // pipe
                try renderIdentifier(r, main_token + 2, .none, .preserve_when_shadowing); // payload identifier
                try renderToken(r, main_token + 3); // pipe
            } else {
                assert(token_tags[fallback_first - 1] == .keyword_catch);
                try renderToken(r, main_token); // catch keyword
            }
            try renderExpression(r, datas[node].rhs); // fallback

        },

        .field_access => {
            const main_token = main_tokens[node];
            const field_access = datas[node];

            try renderExpression(r, field_access.lhs, .none);

            // Allow a line break between the lhs and the dot if the lhs and rhs
            // are on different lines.
            const lhs_last_token = tree.lastToken(field_access.lhs);
            const same_line = tree.tokensOnSameLine(lhs_last_token, main_token + 1);
            if (!same_line and !hasComment(tree, lhs_last_token, main_token))
                try renderToken(r, main_token, .none); // .

            try renderIdentifier(r, field_access.rhs, .eagerly_unquote); // field

        },

        .error_union,
        .switch_range,
        => {
            const infix = datas[node];
            try renderExpression(r, infix.lhs, .none);
            try renderToken(r, main_tokens[node], .none);
            return renderExpression(r, infix.rhs);
        },
        .for_range => {
            const infix = datas[node];
            try renderExpression(r, infix.lhs, .none);
            if (infix.rhs != 0) {
                try renderToken(r, main_tokens[node], .none);
                return renderExpression(r, infix.rhs);
            } else {
                return renderToken(r, main_tokens[node]);
            }
        },

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
        => {
            const infix = datas[node];
            try renderExpression(r, infix.lhs, .space);
            const op_token = main_tokens[node];
            if (tree.tokensOnSameLine(op_token, op_token + 1)) {
                try renderToken(r, op_token, .space);
            } else {
                try renderToken(r, op_token, .newline);
            }
            try renderExpression(r, infix.rhs);
        },

        .add,
        .add_wrap,
        .add_sat,
        .array_cat,
        .array_mult,
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
        => {
            const infix = datas[node];
            try renderExpression(r, infix.lhs, .space);
            const op_token = main_tokens[node];

            if (tree.tokensOnSameLine(op_token, op_token + 1)) {
                try renderToken(r, op_token, .space);
            } else {
                try renderToken(r, op_token, .newline);
            }
            try renderExpression(r, infix.rhs);
        },

        .assign_destructure => {
            const full = tree.assignDestructure(node);
            if (full.comptime_token) |comptime_token| {
                try renderToken(r, comptime_token, .space);
            }

            for (full.ast.variables) |variable_node| {
                switch (node_tags[variable_node]) {
                    .global_var_decl,
                    .local_var_decl,
                    .simple_var_decl,
                    .aligned_var_decl,
                    => {
                        try renderVarDecl(r, tree.fullVarDecl(variable_node).?, true);
                    },
                    else => try renderExpression(r, variable_node),
                }
            }

            if (tree.tokensOnSameLine(full.ast.equal_token, full.ast.equal_token + 1)) {
                try renderToken(r, full.ast.equal_token, .space);
            } else {
                try renderToken(r, full.ast.equal_token, .newline);
            }
            try renderExpression(r, full.ast.value_expr);
        },

        .bit_not,
        .bool_not,
        .negation,
        .negation_wrap,
        .optional_type,
        .address_of,
        => {
            try renderToken(r, main_tokens[node], .none);
            return renderExpression(r, datas[node].lhs);
        },

        .@"try",
        .@"resume",
        .@"await",
        => {
            try renderToken(r, main_tokens[node], .space);
            return renderExpression(r, datas[node].lhs);
        },

        .array_type,
        .array_type_sentinel,
        => return renderArrayType(r, tree.fullArrayType(node).?),

        .ptr_type_aligned,
        .ptr_type_sentinel,
        .ptr_type,
        .ptr_type_bit_range,
        => return renderPtrType(r, tree.fullPtrType(node).?),

        .array_init_one,
        .array_init_one_comma,
        .array_init_dot_two,
        .array_init_dot_two_comma,
        .array_init_dot,
        .array_init_dot_comma,
        .array_init,
        .array_init_comma,
        => {
            var elements: [2]Ast.Node.Index = undefined;
            return renderArrayInit(r, tree.fullArrayInit(&elements, node).?);
        },

        .struct_init_one,
        .struct_init_one_comma,
        .struct_init_dot_two,
        .struct_init_dot_two_comma,
        .struct_init_dot,
        .struct_init_dot_comma,
        .struct_init,
        .struct_init_comma,
        => {
            var buf: [2]Ast.Node.Index = undefined;
            return renderStructInit(r, node, tree.fullStructInit(&buf, node).?);
        },

        .call_one,
        .call_one_comma,
        .async_call_one,
        .async_call_one_comma,
        .call,
        .call_comma,
        .async_call,
        .async_call_comma,
        => {
            var buf: [1]Ast.Node.Index = undefined;
            return renderCall(r, tree.fullCall(&buf, node).?);
        },

        .array_access => {
            const suffix = datas[node];
            const lbracket = tree.firstToken(suffix.rhs) - 1;
            const rbracket = tree.lastToken(suffix.rhs) + 1;
            try renderExpression(r, suffix.lhs);

            try renderToken(r, lbracket); // [
            try renderExpression(r, suffix.rhs);

            return renderToken(r, rbracket); // ]
        },

        .slice_open, .slice, .slice_sentinel => return renderSlice(r, node, tree.fullSlice(node).?),

        .deref => {
            try renderExpression(r, datas[node].lhs);
            return renderToken(r, main_tokens[node]);
        },

        .unwrap_optional => {
            try renderExpression(r, datas[node].lhs, .none);
            try renderToken(r, main_tokens[node], .none);
            return renderToken(r, datas[node].rhs);
        },

        .@"break", .@"continue" => {
            const main_token = main_tokens[node];
            const label_token = datas[node].lhs;
            const target = datas[node].rhs;
            if (label_token == 0 and target == 0) {
                try renderToken(r, main_token); // break/continue
            } else if (label_token == 0 and target != 0) {
                try renderToken(r, main_token, .space); // break/continue
                try renderExpression(r, target);
            } else if (label_token != 0 and target == 0) {
                try renderToken(r, main_token, .space); // break/continue
                try renderToken(r, label_token - 1, .none); // :
                try renderIdentifier(r, label_token, .eagerly_unquote); // identifier
            } else if (label_token != 0 and target != 0) {
                try renderToken(r, main_token, .space); // break/continue
                try renderToken(r, label_token - 1, .none); // :
                try renderIdentifier(r, label_token, .space, .eagerly_unquote); // identifier
                try renderExpression(r, target);
            }
        },

        .@"return" => {
            if (datas[node].lhs != 0) {
                try renderToken(r, main_tokens[node], .space);
                try renderExpression(r, datas[node].lhs);
            } else {
                try renderToken(r, main_tokens[node]);
            }
        },

        .grouped_expression => {
            try renderToken(r, main_tokens[node], .none); // lparen
            try renderExpression(r, datas[node].lhs, .none);

            return renderToken(r, datas[node].rhs); // rparen
        },

        .container_decl,
        .container_decl_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        .container_decl_two,
        .container_decl_two_trailing,
        .tagged_union,
        .tagged_union_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        => {
            var buf: [2]Ast.Node.Index = undefined;
            return renderContainerDecl(r, node, tree.fullContainerDecl(&buf, node).?);
        },

        .error_set_decl => {
            const error_token = main_tokens[node];
            const lbrace = error_token + 1;
            const rbrace = datas[node].rhs;

            try renderToken(r, error_token, .none);

            if (lbrace + 1 == rbrace) {
                // There is nothing between the braces so render condensed: `error{}`
                try renderToken(r, lbrace, .none);
                return renderToken(r, rbrace);
            } else if (lbrace + 2 == rbrace and token_tags[lbrace + 1] == .identifier) {
                // There is exactly one member and no trailing comma or
                // comments, so render without surrounding spaces: `error{Foo}`
                try renderToken(r, lbrace, .none);
                try renderIdentifier(r, lbrace + 1, .none, .eagerly_unquote); // identifier
                return renderToken(r, rbrace);
            } else if (token_tags[rbrace - 1] == .comma) {
                // There is a trailing comma so render each member on a new line.

                try renderToken(r, lbrace, .newline);
                var i = lbrace + 1;
                while (i < rbrace) : (i += 1) {
                    if (i > lbrace + 1) try renderExtraNewlineToken(r, i);
                    switch (token_tags[i]) {
                        .doc_comment => try renderToken(r, i, .newline),
                        .identifier => {
                            try renderIdentifier(r, i, .comma, .eagerly_unquote);
                        },
                        .comma => {},
                        else => unreachable,
                    }
                }

                return renderToken(r, rbrace);
            } else {
                // There is no trailing comma so render everything on one line.
                try renderToken(r, lbrace, .space);
                var i = lbrace + 1;
                while (i < rbrace) : (i += 1) {
                    switch (token_tags[i]) {
                        .doc_comment => unreachable, // TODO
                        .identifier => try renderIdentifier(r, i, .comma_space, .eagerly_unquote),
                        .comma => {},
                        else => unreachable,
                    }
                }
                return renderToken(r, rbrace);
            }
        },

        .builtin_call_two, .builtin_call_two_comma => {
            if (datas[node].lhs == 0) {
                return renderBuiltinCall(r, main_tokens[node], &.{});
            } else if (datas[node].rhs == 0) {
                return renderBuiltinCall(r, main_tokens[node], &.{datas[node].lhs});
            } else {
                return renderBuiltinCall(r, main_tokens[node], &.{ datas[node].lhs, datas[node].rhs });
            }
        },
        .builtin_call, .builtin_call_comma => {
            const params = tree.extra_data[datas[node].lhs..datas[node].rhs];
            return renderBuiltinCall(r, main_tokens[node], params);
        },

        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => {
            var buf: [1]Ast.Node.Index = undefined;
            return renderFnProto(r, tree.fullFnProto(&buf, node).?);
        },

        .anyframe_type => {
            const main_token = main_tokens[node];
            if (datas[node].rhs != 0) {
                try renderToken(r, main_token, .none); // anyframe
                try renderToken(r, main_token + 1, .none); // ->
                return renderExpression(r, datas[node].rhs);
            } else {
                return renderToken(r, main_token); // anyframe
            }
        },

        .@"switch",
        .switch_comma,
        => {
            const full = tree.switchFull(node);

            if (full.label_token) |label_token| {
                try renderIdentifier(r, label_token, .none, .eagerly_unquote); // label
                try renderToken(r, label_token + 1, .space); // :
            }

            const rparen = tree.lastToken(full.ast.condition) + 1;

            try renderToken(r, full.ast.switch_token, .space); // switch
            try renderToken(r, full.ast.switch_token + 1, .none); // (
            try renderExpression(r, full.ast.condition, .none); // condition expression
            try renderToken(r, rparen, .space); // )

            if (full.ast.cases.len == 0) {
                try renderToken(r, rparen + 1, .none); // {
            } else {
                try renderToken(r, rparen + 1, .newline); // {

                try renderExpressions(r, full.ast.cases, .comma);
            }

            return renderToken(r, tree.lastToken(node)); // }
        },

        .switch_case_one,
        .switch_case_inline_one,
        .switch_case,
        .switch_case_inline,
        => return renderSwitchCase(r, tree.fullSwitchCase(node).?),

        .while_simple,
        .while_cont,
        .@"while",
        => return renderWhile(r, tree.fullWhile(node).?),

        .for_simple,
        .@"for",
        => return renderFor(r, tree.fullFor(node).?),

        .if_simple,
        .@"if",
        => return renderIf(r, tree.fullIf(node).?),

        .asm_simple,
        .@"asm",
        => return renderAsm(r, tree.fullAsm(node).?),

        .enum_literal => {
            try renderToken(r, main_tokens[node] - 1, .none); // .
            return renderIdentifier(r, main_tokens[node], .eagerly_unquote); // name
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

/// Same as `renderExpression`, but afterwards looks for any
/// append_string_after_node fixups to apply
fn renderExpressionFixup(r: *Render, node: Ast.Node.Index) Error!void {
    const ais = r.ais;
    try renderExpression(r, node);
    if (r.fixups.append_string_after_node.get(node)) |bytes| {
        try ais.writer().writeAll(bytes);
    }
}

fn renderArrayType(
    r: *Render,
    array_type: Ast.full.ArrayType,
) Error!void {
    const tree = r.tree;
    const rbracket = tree.firstToken(array_type.ast.elem_type) - 1;

    try renderToken(r, array_type.ast.lbracket); // lbracket
    try renderExpression(r, array_type.ast.elem_count);
    if (array_type.ast.sentinel != 0) {
        try renderToken(r, tree.firstToken(array_type.ast.sentinel) - 1); // colon
        try renderExpression(r, array_type.ast.sentinel);
    }

    try renderToken(r, rbracket, .none); // rbracket
    return renderExpression(r, array_type.ast.elem_type);
}

fn renderPtrType(r: *Render, ptr_type: Ast.full.PtrType) Error!void {
    const tree = r.tree;
    switch (ptr_type.size) {
        .one => {
            // Since ** tokens exist and the same token is shared by two
            // nested pointer types, we check to see if we are the parent
            // in such a relationship. If so, skip rendering anything for
            // this pointer type and rely on the child to render our asterisk
            // as well when it renders the ** token.
            if (tree.tokens.items(.tag)[ptr_type.ast.main_token] == .asterisk_asterisk and
                ptr_type.ast.main_token == tree.nodes.items(.main_token)[ptr_type.ast.child_type])
            {
                return renderExpression(r, ptr_type.ast.child_type);
            }
            try renderToken(r, ptr_type.ast.main_token, .none); // asterisk
        },
        .many => {
            if (ptr_type.ast.sentinel == 0) {
                try renderToken(r, ptr_type.ast.main_token, .none); // lbracket
                try renderToken(r, ptr_type.ast.main_token + 1, .none); // asterisk
                try renderToken(r, ptr_type.ast.main_token + 2, .none); // rbracket
            } else {
                try renderToken(r, ptr_type.ast.main_token, .none); // lbracket
                try renderToken(r, ptr_type.ast.main_token + 1, .none); // asterisk
                try renderToken(r, ptr_type.ast.main_token + 2, .none); // colon
                try renderExpression(r, ptr_type.ast.sentinel, .none);
                try renderToken(r, tree.lastToken(ptr_type.ast.sentinel) + 1, .none); // rbracket
            }
        },
        .c => {
            try renderToken(r, ptr_type.ast.main_token, .none); // lbracket
            try renderToken(r, ptr_type.ast.main_token + 1, .none); // asterisk
            try renderToken(r, ptr_type.ast.main_token + 2, .none); // c
            try renderToken(r, ptr_type.ast.main_token + 3, .none); // rbracket
        },
        .slice => {
            if (ptr_type.ast.sentinel == 0) {
                try renderToken(r, ptr_type.ast.main_token, .none); // lbracket
                try renderToken(r, ptr_type.ast.main_token + 1, .none); // rbracket
            } else {
                try renderToken(r, ptr_type.ast.main_token, .none); // lbracket
                try renderToken(r, ptr_type.ast.main_token + 1, .none); // colon
                try renderExpression(r, ptr_type.ast.sentinel, .none);
                try renderToken(r, tree.lastToken(ptr_type.ast.sentinel) + 1, .none); // rbracket
            }
        },
    }

    if (ptr_type.allowzero_token) |allowzero_token| {
        try renderToken(r, allowzero_token, .space);
    }

    if (ptr_type.ast.align_node != 0) {
        const align_first = tree.firstToken(ptr_type.ast.align_node);
        try renderToken(r, align_first - 2, .none); // align
        try renderToken(r, align_first - 1, .none); // lparen
        try renderExpression(r, ptr_type.ast.align_node, .none);
        if (ptr_type.ast.bit_range_start != 0) {
            assert(ptr_type.ast.bit_range_end != 0);
            try renderToken(r, tree.firstToken(ptr_type.ast.bit_range_start) - 1, .none); // colon
            try renderExpression(r, ptr_type.ast.bit_range_start, .none);
            try renderToken(r, tree.firstToken(ptr_type.ast.bit_range_end) - 1, .none); // colon
            try renderExpression(r, ptr_type.ast.bit_range_end, .none);
            try renderToken(r, tree.lastToken(ptr_type.ast.bit_range_end) + 1, .space); // rparen
        } else {
            try renderToken(r, tree.lastToken(ptr_type.ast.align_node) + 1, .space); // rparen
        }
    }

    if (ptr_type.ast.addrspace_node != 0) {
        const addrspace_first = tree.firstToken(ptr_type.ast.addrspace_node);
        try renderToken(r, addrspace_first - 2, .none); // addrspace
        try renderToken(r, addrspace_first - 1, .none); // lparen
        try renderExpression(r, ptr_type.ast.addrspace_node, .none);
        try renderToken(r, tree.lastToken(ptr_type.ast.addrspace_node) + 1, .space); // rparen
    }

    if (ptr_type.const_token) |const_token| {
        try renderToken(r, const_token, .space);
    }

    if (ptr_type.volatile_token) |volatile_token| {
        try renderToken(r, volatile_token, .space);
    }

    try renderExpression(r, ptr_type.ast.child_type);
}

fn renderSlice(
    r: *Render,
    slice_node: Ast.Node.Index,
    slice: Ast.full.Slice,
) Error!void {
    const tree = r.tree;

    try renderExpression(r, slice.ast.sliced);
    try renderToken(r, slice.ast.lbracket); // lbracket

    const start_last = tree.lastToken(slice.ast.start);
    try renderExpression(r, slice.ast.start);
    try renderToken(r, start_last + 1); // ellipsis2 ("..")

    if (slice.ast.end != 0) {
        try renderExpression(r, slice.ast.end);
    }

    if (slice.ast.sentinel != 0) {
        try renderToken(r, tree.firstToken(slice.ast.sentinel) - 1); // colon
        try renderExpression(r, slice.ast.sentinel);
    }

    try renderToken(r, tree.lastToken(slice_node)); // rbracket
}

fn renderAsmOutput(
    r: *Render,
    asm_output: Ast.Node.Index,
) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const node_tags = tree.nodes.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    const datas = tree.nodes.items(.data);
    assert(node_tags[asm_output] == .asm_output);
    const symbolic_name = main_tokens[asm_output];

    try renderToken(r, symbolic_name - 1); // lbracket
    try renderIdentifier(r, symbolic_name, .eagerly_unquote); // ident
    try renderToken(r, symbolic_name + 1); // rbracket
    try renderToken(r, symbolic_name + 2); // "constraint"
    try renderToken(r, symbolic_name + 3); // lparen

    if (token_tags[symbolic_name + 4] == .arrow) {
        try renderToken(r, symbolic_name + 4, .space); // ->
        try renderExpression(r, datas[asm_output].lhs);
        return renderToken(r, datas[asm_output].rhs); // rparen
    } else {
        try renderIdentifier(r, symbolic_name + 4, .eagerly_unquote); // ident
        return renderToken(r, symbolic_name + 5); // rparen
    }
}

fn renderAsmInput(
    r: *Render,
    asm_input: Ast.Node.Index,
) Error!void {
    const tree = r.tree;
    const node_tags = tree.nodes.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    const datas = tree.nodes.items(.data);
    assert(node_tags[asm_input] == .asm_input);
    const symbolic_name = main_tokens[asm_input];

    try renderToken(r, symbolic_name - 1); // lbracket
    try renderIdentifier(r, symbolic_name, .eagerly_unquote); // ident
    try renderToken(r, symbolic_name + 1); // rbracket
    try renderToken(r, symbolic_name + 2); // "constraint"
    try renderToken(r, symbolic_name + 3); // lparen
    try renderExpression(r, datas[asm_input].lhs);
    return renderToken(r, datas[asm_input].rhs); // rparen
}

fn renderVarDecl(
    r: *Render,
    var_decl: Ast.full.VarDecl,
    /// Destructures intentionally ignore leading `comptime` tokens.
    ignore_comptime_token: bool,
) Error!fast.VariableDeclaration {
    var decl: fast.VariableDeclaration = .{
        .name = undefined,
        .mutability = undefined,
    };

    if (var_decl.visib_token != null) {
        decl.@"pub" = true;
    }

    if (var_decl.extern_export_token != null) {
        if (var_decl.lib_name) |lib_name| {
            decl.@"extern" = .{ .library = tokenSliceForRender(r.tree, lib_name) };
        } else {
            decl.@"extern" = .generic;
        }
    }

    if (var_decl.threadlocal_token != null) {
        decl.@"threadlocal" = true;
    }

    if (!ignore_comptime_token and var_decl.comptime_token != null) {
        decl.@"comptime" = true;
    }

    if (std.mem.eql(u8, tokenSliceForRender(r.tree, var_decl.ast.mut_token), "var")) {
        decl.mutability = .@"var";
    } else {
        decl.mutability = .@"const";
    }

    decl.name = try renderIdentifier(r, var_decl.ast.mut_token + 1, .preserve_when_shadowing); // name

    if (var_decl.ast.type_node != 0) {
        decl.type = try renderExpression(r, var_decl.ast.type_node);
    }

    if (var_decl.ast.align_node != 0) {
        decl.@"align" = try renderExpression(r, var_decl.ast.align_node);
    }

    if (var_decl.ast.addrspace_node != 0) {
        decl.@"addrspace" = try renderExpression(r, var_decl.ast.addrspace_node);
    }

    if (var_decl.ast.section_node != 0) {
        decl.@"linksection" = try renderExpression(r, var_decl.ast.section_node);
    }

    if (var_decl.ast.init_node != 0) {
        decl.value = try renderExpression(r, var_decl.ast.init_node);
    }

    return decl;
}

fn renderIf(r: *Render, if_node: Ast.full.If) Error!void {
    return renderWhile(r, .{
        .ast = .{
            .while_token = if_node.ast.if_token,
            .cond_expr = if_node.ast.cond_expr,
            .cont_expr = 0,
            .then_expr = if_node.ast.then_expr,
            .else_expr = if_node.ast.else_expr,
        },
        .inline_token = null,
        .label_token = null,
        .payload_token = if_node.payload_token,
        .else_token = if_node.else_token,
        .error_token = if_node.error_token,
    });
}

/// Note that this function is additionally used to render if expressions, with
/// respective values set to null.
fn renderWhile(r: *Render, while_node: Ast.full.While) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);

    if (while_node.label_token) |label| {
        try renderIdentifier(r, label, .none, .eagerly_unquote); // label
        try renderToken(r, label + 1, .space); // :
    }

    if (while_node.inline_token) |inline_token| {
        try renderToken(r, inline_token); // inline
    }

    try renderToken(r, while_node.ast.while_token); // if/for/while
    try renderToken(r, while_node.ast.while_token + 1); // lparen
    try renderExpression(r, while_node.ast.cond_expr); // condition

    var last_prefix_token = tree.lastToken(while_node.ast.cond_expr) + 1; // rparen

    if (while_node.payload_token) |payload_token| {
        try renderToken(r, last_prefix_token);
        try renderToken(r, payload_token - 1); // |
        const ident = blk: {
            if (token_tags[payload_token] == .asterisk) {
                try renderToken(r, payload_token); // *
                break :blk payload_token + 1;
            } else {
                break :blk payload_token;
            }
        };
        try renderIdentifier(r, ident, .preserve_when_shadowing); // identifier
        const pipe = blk: {
            if (token_tags[ident + 1] == .comma) {
                try renderToken(r, ident + 1); // ,
                try renderIdentifier(r, ident + 2, .preserve_when_shadowing); // index
                break :blk ident + 3;
            } else {
                break :blk ident + 1;
            }
        };
        last_prefix_token = pipe;
    }

    if (while_node.ast.cont_expr != 0) {
        try renderToken(r, last_prefix_token);
        const lparen = tree.firstToken(while_node.ast.cont_expr) - 1;
        try renderToken(r, lparen - 1); // :
        try renderToken(r, lparen); // lparen
        try renderExpression(r, while_node.ast.cont_expr);
        last_prefix_token = tree.lastToken(while_node.ast.cont_expr) + 1; // rparen
    }

    try renderThenElse(
        r,
        last_prefix_token,
        while_node.ast.then_expr,
        while_node.else_token,
        while_node.error_token,
        while_node.ast.else_expr,
    );
}

fn renderThenElse(
    r: *Render,
    last_prefix_token: Ast.TokenIndex,
    then_expr: Ast.Node.Index,
    else_token: Ast.TokenIndex,
    maybe_error_token: ?Ast.TokenIndex,
    else_expr: Ast.Node.Index,
) Error!void {
    const tree = r.tree;
    const node_tags = tree.nodes.items(.tag);
    const then_expr_is_block = nodeIsBlock(node_tags[then_expr]);
    const indent_then_expr = !then_expr_is_block and
        !tree.tokensOnSameLine(last_prefix_token, tree.firstToken(then_expr));

    try renderToken(r, last_prefix_token, .space);

    if (else_expr != 0) {
        try renderExpression(r, then_expr, .space);

        var last_else_token = else_token;

        if (maybe_error_token) |error_token| {
            try renderToken(r, else_token, .space); // else
            try renderToken(r, error_token - 1, .none); // |
            try renderIdentifier(r, error_token, .none, .preserve_when_shadowing); // identifier
            last_else_token = error_token + 1; // |
        }

        const indent_else_expr = indent_then_expr and
            !nodeIsBlock(node_tags[else_expr]) and
            !nodeIsIfForWhileSwitch(node_tags[else_expr]);
        if (indent_else_expr) {
            try renderToken(r, last_else_token, .newline);
            try renderExpression(r, else_expr);
        } else {
            try renderToken(r, last_else_token, .space);
            try renderExpression(r, else_expr);
        }
    } else {
        try renderExpression(r, then_expr);
    }
}

fn renderFor(r: *Render, for_node: Ast.full.For) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);

    if (for_node.label_token) |label| {
        try renderIdentifier(r, label, .none, .eagerly_unquote); // label
        try renderToken(r, label + 1, .space); // :
    }

    if (for_node.inline_token) |inline_token| {
        try renderToken(r, inline_token, .space); // inline
    }

    try renderToken(r, for_node.ast.for_token, .space); // if/for/while

    const lparen = for_node.ast.for_token + 1;
    try renderParamList(r, lparen, for_node.ast.inputs, .space);

    var cur = for_node.payload_token;
    const pipe = std.mem.indexOfScalarPos(std.zig.Token.Tag, token_tags, cur, .pipe).?;
    if (token_tags[pipe - 1] == .comma) {
        try renderToken(r, cur - 1, .newline); // |
        while (true) {
            if (token_tags[cur] == .asterisk) {
                try renderToken(r, cur, .none); // *
                cur += 1;
            }
            try renderIdentifier(r, cur, .none, .preserve_when_shadowing); // identifier
            cur += 1;
            if (token_tags[cur] == .comma) {
                try renderToken(r, cur, .newline); // ,
                cur += 1;
            }
            if (token_tags[cur] == .pipe) {
                break;
            }
        }
    } else {
        try renderToken(r, cur - 1, .none); // |
        while (true) {
            if (token_tags[cur] == .asterisk) {
                try renderToken(r, cur, .none); // *
                cur += 1;
            }
            try renderIdentifier(r, cur, .none, .preserve_when_shadowing); // identifier
            cur += 1;
            if (token_tags[cur] == .comma) {
                try renderToken(r, cur, .space); // ,
                cur += 1;
            }
            if (token_tags[cur] == .pipe) {
                break;
            }
        }
    }

    try renderThenElse(
        r,
        cur,
        for_node.ast.then_expr,
        for_node.else_token,
        null,
        for_node.ast.else_expr,
    );
}

fn renderContainerField(
    r: *Render,
    container: Container,
    field_param: Ast.full.ContainerField,
) Error!fast.FieldDeclaration {
    const tree = r.tree;
    var field = field_param;
    if (container != .tuple) field.convertToNonTupleLike(tree.nodes);
    const quote: QuoteBehavior = switch (container) {
        .@"enum" => .eagerly_unquote_except_underscore,
        .tuple, .other => .eagerly_unquote,
    };

    if (field.comptime_token) |t| {
        try renderToken(r, t); // comptime
    }
    if (field.ast.type_expr == 0 and field.ast.value_expr == 0) {
        if (field.ast.align_expr != 0) {
            try renderIdentifier(r, field.ast.main_token, .space, quote); // name
            const lparen_token = tree.firstToken(field.ast.align_expr) - 1;
            const align_kw = lparen_token - 1;
            const rparen_token = tree.lastToken(field.ast.align_expr) + 1;
            try renderToken(r, align_kw, .none); // align
            try renderToken(r, lparen_token, .none); // (
            try renderExpression(r, field.ast.align_expr, .none); // alignment
            return renderToken(r, rparen_token, .space); // )
        }
        return renderIdentifierComma(r, field.ast.main_token, quote); // name
    }
    if (field.ast.type_expr != 0 and field.ast.value_expr == 0) {
        if (!field.ast.tuple_like) {
            try renderIdentifier(r, field.ast.main_token, .none, quote); // name
            try renderToken(r, field.ast.main_token + 1, .space); // :
        }

        if (field.ast.align_expr != 0) {
            try renderExpression(r, field.ast.type_expr, .space); // type
            const align_token = tree.firstToken(field.ast.align_expr) - 2;
            try renderToken(r, align_token, .none); // align
            try renderToken(r, align_token + 1, .none); // (
            try renderExpression(r, field.ast.align_expr, .none); // alignment
            const rparen = tree.lastToken(field.ast.align_expr) + 1;
            return renderTokenComma(r, rparen); // )
        } else {
            return renderExpressionComma(r, field.ast.type_expr); // type
        }
    }
    if (field.ast.type_expr == 0 and field.ast.value_expr != 0) {
        try renderIdentifier(r, field.ast.main_token, .space, quote); // name
        if (field.ast.align_expr != 0) {
            const lparen_token = tree.firstToken(field.ast.align_expr) - 1;
            const align_kw = lparen_token - 1;
            const rparen_token = tree.lastToken(field.ast.align_expr) + 1;
            try renderToken(r, align_kw, .none); // align
            try renderToken(r, lparen_token, .none); // (
            try renderExpression(r, field.ast.align_expr, .none); // alignment
            try renderToken(r, rparen_token, .space); // )
        }
        try renderToken(r, field.ast.main_token + 1, .space); // =
        return renderExpressionComma(r, field.ast.value_expr); // value
    }
    if (!field.ast.tuple_like) {
        try renderIdentifier(r, field.ast.main_token, .none, quote); // name
        try renderToken(r, field.ast.main_token + 1, .space); // :
    }
    try renderExpression(r, field.ast.type_expr, .space); // type

    if (field.ast.align_expr != 0) {
        const lparen_token = tree.firstToken(field.ast.align_expr) - 1;
        const align_kw = lparen_token - 1;
        const rparen_token = tree.lastToken(field.ast.align_expr) + 1;
        try renderToken(r, align_kw, .none); // align
        try renderToken(r, lparen_token, .none); // (
        try renderExpression(r, field.ast.align_expr, .none); // alignment
        try renderToken(r, rparen_token, .space); // )
    }
    const eq_token = tree.firstToken(field.ast.value_expr) - 1;

    try renderToken(r, eq_token); // =

    const token_tags = tree.tokens.items(.tag);
    const maybe_comma = tree.lastToken(field.ast.value_expr) + 1;

    if (token_tags[maybe_comma] == .comma) {
        try renderExpression(r, field.ast.value_expr); // value

        try renderToken(r, maybe_comma);
    } else {
        try renderExpression(r, field.ast.value_expr); // value

    }
}

fn renderBuiltinCall(
    r: *Render,
    builtin_token: Ast.TokenIndex,
    params: []const Ast.Node.Index,
) Error!void {
    const tree = r.tree;
    const ais = r.ais;
    const token_tags = tree.tokens.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);

    try renderToken(r, builtin_token, .none); // @name

    if (params.len == 0) {
        try renderToken(r, builtin_token + 1, .none); // (
        return renderToken(r, builtin_token + 2); // )
    }

    if (r.fixups.rebase_imported_paths) |prefix| {
        const slice = tree.tokenSlice(builtin_token);
        if (mem.eql(u8, slice, "@import")) f: {
            const param = params[0];
            const str_lit_token = main_tokens[param];
            assert(token_tags[str_lit_token] == .string_literal);
            const token_bytes = tree.tokenSlice(str_lit_token);
            const imported_string = std.zig.string_literal.parseAlloc(r.gpa, token_bytes) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidLiteral => break :f,
            };
            defer r.gpa.free(imported_string);
            const new_string = try std.fs.path.resolvePosix(r.gpa, &.{ prefix, imported_string });
            defer r.gpa.free(new_string);

            try renderToken(r, builtin_token + 1, .none); // (
            try ais.writer().print("\"{}\"", .{std.zig.fmtEscapes(new_string)});
            return renderToken(r, str_lit_token + 1); // )
        }
    }

    const last_param = params[params.len - 1];
    const after_last_param_token = tree.lastToken(last_param) + 1;

    if (token_tags[after_last_param_token] != .comma) {
        // Render all on one line, no trailing comma.
        try renderToken(r, builtin_token + 1, .none); // (

        for (params, 0..) |param_node, i| {
            const first_param_token = tree.firstToken(param_node);
            if (token_tags[first_param_token] == .multiline_string_literal_line or
                hasSameLineComment(tree, first_param_token - 1))
            {
                try renderExpression(r, param_node);
            } else {
                try renderExpression(r, param_node);
            }

            if (i + 1 < params.len) {
                const comma_token = tree.lastToken(param_node) + 1;
                try renderToken(r, comma_token); // ,
            }
        }
        return renderToken(r, after_last_param_token); // )
    } else {
        // Render one param per line.

        try renderToken(r, builtin_token + 1); // (

        for (params) |param_node| {
            try renderExpression(r, param_node);
        }

        return renderToken(r, after_last_param_token + 1); // )
    }
}

fn renderFnProto(r: *Render, fn_proto: Ast.full.FnProto) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const token_starts = tree.tokens.items(.start);

    const after_fn_token = fn_proto.ast.fn_token + 1;
    const lparen = if (token_tags[after_fn_token] == .identifier) blk: {
        try renderToken(r, fn_proto.ast.fn_token, .space); // fn
        try renderIdentifier(r, after_fn_token, .none, .preserve_when_shadowing); // name
        break :blk after_fn_token + 1;
    } else blk: {
        try renderToken(r, fn_proto.ast.fn_token, .space); // fn
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
        try renderToken(r, lparen, .none); // (

        var param_i: usize = 0;
        var last_param_token = lparen;
        while (true) {
            last_param_token += 1;
            switch (token_tags[last_param_token]) {
                .doc_comment => {
                    try renderToken(r, last_param_token, .newline);
                    continue;
                },
                .ellipsis3 => {
                    try renderToken(r, last_param_token, .none); // ...
                    break;
                },
                .keyword_noalias, .keyword_comptime => {
                    try renderToken(r, last_param_token, .space);
                    last_param_token += 1;
                },
                .identifier => {},
                .keyword_anytype => {
                    try renderToken(r, last_param_token, .none); // anytype
                    continue;
                },
                .r_paren => break,
                .comma => {
                    try renderToken(r, last_param_token, .space); // ,
                    continue;
                },
                else => {}, // Parameter type without a name.
            }
            if (token_tags[last_param_token] == .identifier and
                token_tags[last_param_token + 1] == .colon)
            {
                try renderIdentifier(r, last_param_token, .none, .preserve_when_shadowing); // name
                last_param_token += 1;
                try renderToken(r, last_param_token, .space); // :
                last_param_token += 1;
            }
            if (token_tags[last_param_token] == .keyword_anytype) {
                try renderToken(r, last_param_token, .none); // anytype
                continue;
            }
            const param = fn_proto.ast.params[param_i];
            param_i += 1;
            try renderExpression(r, param, .none);
            last_param_token = tree.lastToken(param);
        }
    } else {
        // One param per line.

        try renderToken(r, lparen, .newline); // (

        var param_i: usize = 0;
        var last_param_token = lparen;
        while (true) {
            last_param_token += 1;
            switch (token_tags[last_param_token]) {
                .doc_comment => {
                    try renderToken(r, last_param_token, .newline);
                    continue;
                },
                .ellipsis3 => {
                    try renderToken(r, last_param_token, .comma); // ...
                    break;
                },
                .keyword_noalias, .keyword_comptime => {
                    try renderToken(r, last_param_token, .space);
                    last_param_token += 1;
                },
                .identifier => {},
                .keyword_anytype => {
                    try renderToken(r, last_param_token, .comma); // anytype
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
                try renderIdentifier(r, last_param_token, .none, .preserve_when_shadowing); // name
                last_param_token += 1;
                try renderToken(r, last_param_token, .space); // :
                last_param_token += 1;
            }
            if (token_tags[last_param_token] == .keyword_anytype) {
                try renderToken(r, last_param_token, .comma); // anytype
                if (token_tags[last_param_token + 1] == .comma)
                    last_param_token += 1;
                continue;
            }
            const param = fn_proto.ast.params[param_i];
            param_i += 1;

            try renderExpression(r, param, .comma);

            last_param_token = tree.lastToken(param);
            if (token_tags[last_param_token + 1] == .comma) last_param_token += 1;
        }
    }

    try renderToken(r, rparen, .space); // )

    if (fn_proto.ast.align_expr != 0) {
        const align_lparen = tree.firstToken(fn_proto.ast.align_expr) - 1;
        const align_rparen = tree.lastToken(fn_proto.ast.align_expr) + 1;

        try renderToken(r, align_lparen - 1, .none); // align
        try renderToken(r, align_lparen, .none); // (
        try renderExpression(r, fn_proto.ast.align_expr, .none);
        try renderToken(r, align_rparen, .space); // )
    }

    if (fn_proto.ast.addrspace_expr != 0) {
        const align_lparen = tree.firstToken(fn_proto.ast.addrspace_expr) - 1;
        const align_rparen = tree.lastToken(fn_proto.ast.addrspace_expr) + 1;

        try renderToken(r, align_lparen - 1, .none); // addrspace
        try renderToken(r, align_lparen, .none); // (
        try renderExpression(r, fn_proto.ast.addrspace_expr, .none);
        try renderToken(r, align_rparen, .space); // )
    }

    if (fn_proto.ast.section_expr != 0) {
        const section_lparen = tree.firstToken(fn_proto.ast.section_expr) - 1;
        const section_rparen = tree.lastToken(fn_proto.ast.section_expr) + 1;

        try renderToken(r, section_lparen - 1, .none); // section
        try renderToken(r, section_lparen, .none); // (
        try renderExpression(r, fn_proto.ast.section_expr, .none);
        try renderToken(r, section_rparen, .space); // )
    }

    // Keep in sync with logic in `renderMember`. Search this file for the marker PROMOTE_CALLCONV_INLINE
    const is_callconv_inline = mem.eql(u8, "@\"inline\"", tree.tokenSlice(tree.nodes.items(.main_token)[fn_proto.ast.callconv_expr]));
    const is_declaration = fn_proto.name_token != null;
    if (fn_proto.ast.callconv_expr != 0 and !(is_declaration and is_callconv_inline)) {
        const callconv_lparen = tree.firstToken(fn_proto.ast.callconv_expr) - 1;
        const callconv_rparen = tree.lastToken(fn_proto.ast.callconv_expr) + 1;

        try renderToken(r, callconv_lparen - 1, .none); // callconv
        try renderToken(r, callconv_lparen, .none); // (
        try renderExpression(r, fn_proto.ast.callconv_expr, .none);
        try renderToken(r, callconv_rparen, .space); // )
    }

    if (token_tags[maybe_bang] == .bang) {
        try renderToken(r, maybe_bang, .none); // !
    }
    return renderExpression(r, fn_proto.ast.return_type);
}

fn renderSwitchCase(
    r: *Render,
    switch_case: Ast.full.SwitchCase,
) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const trailing_comma = token_tags[switch_case.ast.arrow_token - 1] == .comma;
    const has_comment_before_arrow = blk: {
        if (switch_case.ast.values.len == 0) break :blk false;
        break :blk hasComment(tree, tree.firstToken(switch_case.ast.values[0]), switch_case.ast.arrow_token);
    };

    // render inline keyword
    if (switch_case.inline_token) |some| {
        try renderToken(r, some, .space);
    }

    // Render everything before the arrow
    if (switch_case.ast.values.len == 0) {
        try renderToken(r, switch_case.ast.arrow_token - 1, .space); // else keyword
    } else if (trailing_comma or has_comment_before_arrow) {
        // Render each value on a new line

        try renderExpressions(r, switch_case.ast.values, .comma);
    } else {
        // Render on one line
        for (switch_case.ast.values) |value_expr| {
            try renderExpression(r, value_expr, .comma_space);
        }
    }

    try renderToken(r, switch_case.ast.arrow_token); // =>

    if (switch_case.payload_token) |payload_token| {
        try renderToken(r, payload_token - 1); // pipe
        const ident = payload_token + @intFromBool(token_tags[payload_token] == .asterisk);
        if (token_tags[payload_token] == .asterisk) {
            try renderToken(r, payload_token); // asterisk
        }
        try renderIdentifier(r, ident, .preserve_when_shadowing); // identifier
        if (token_tags[ident + 1] == .comma) {
            try renderToken(r, ident + 1); // ,
            try renderIdentifier(r, ident + 2, .preserve_when_shadowing); // identifier
            try renderToken(r, ident + 3); // pipe
        } else {
            try renderToken(r, ident + 1); // pipe
        }
    }

    try renderExpression(r, switch_case.ast.target_expr);
}

fn renderBlock(
    r: *Render,
    block_node: Ast.Node.Index,
    statements: []const Ast.Node.Index,
) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const lbrace = tree.nodes.items(.main_token)[block_node];

    if (token_tags[lbrace - 1] == .colon and
        token_tags[lbrace - 2] == .identifier)
    {
        try renderIdentifier(r, lbrace - 2, .none, .eagerly_unquote); // identifier
        try renderToken(r, lbrace - 1, .space); // :
    }

    if (statements.len == 0) {
        try renderToken(r, lbrace, .none);

        try renderToken(r, tree.lastToken(block_node)); // rbrace
        return;
    }
    try renderToken(r, lbrace, .newline);
    return finishRenderBlock(r, block_node, statements);
}

fn finishRenderBlock(
    r: *Render,
    block_node: Ast.Node.Index,
    statements: []const Ast.Node.Index,
) Error!void {
    const tree = r.tree;
    const node_tags = tree.nodes.items(.tag);
    for (statements, 0..) |stmt, i| {
        if (i != 0) try renderExtraNewline(r, stmt);
        if (r.fixups.omit_nodes.contains(stmt)) continue;

        switch (node_tags[stmt]) {
            .global_var_decl,
            .local_var_decl,
            .simple_var_decl,
            .aligned_var_decl,
            => try renderVarDecl(r, tree.fullVarDecl(stmt).?, false, .semicolon),

            else => try renderExpression(r, stmt, .semicolon),
        }
    }

    try renderToken(r, tree.lastToken(block_node)); // rbrace
}

fn renderStructInit(
    r: *Render,
    struct_node: Ast.Node.Index,
    struct_init: Ast.full.StructInit,
) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    if (struct_init.ast.type_expr == 0) {
        try renderToken(r, struct_init.ast.lbrace - 1, .none); // .
    } else {
        try renderExpression(r, struct_init.ast.type_expr, .none); // T
    }
    if (struct_init.ast.fields.len == 0) {
        try renderToken(r, struct_init.ast.lbrace, .none); // lbrace

        return renderToken(r, struct_init.ast.lbrace + 1); // rbrace
    }

    const rbrace = tree.lastToken(struct_node);
    const trailing_comma = token_tags[rbrace - 1] == .comma;
    if (trailing_comma or hasComment(tree, struct_init.ast.lbrace, rbrace)) {
        // Render one field init per line.

        try renderToken(r, struct_init.ast.lbrace, .newline);

        try renderToken(r, struct_init.ast.lbrace + 1, .none); // .
        try renderIdentifier(r, struct_init.ast.lbrace + 2, .space, .eagerly_unquote); // name
        // Don't output a space after the = if expression is a multiline string,
        // since then it will start on the next line.
        const field_node = struct_init.ast.fields[0];
        try renderToken(r, struct_init.ast.lbrace + 3); // =

        try renderExpressionFixup(r, field_node);

        for (struct_init.ast.fields[1..]) |field_init| {
            const init_token = tree.firstToken(field_init);
            try renderExtraNewlineToken(r, init_token - 3);
            try renderToken(r, init_token - 3); // .
            try renderIdentifier(r, init_token - 2, .eagerly_unquote); // name
            try renderToken(r, init_token - 1); // =

            try renderExpressionFixup(r, field_init);
        }
    } else {
        // Render all on one line, no trailing comma.
        try renderToken(r, struct_init.ast.lbrace, .space);

        for (struct_init.ast.fields) |field_init| {
            const init_token = tree.firstToken(field_init);
            try renderToken(r, init_token - 3, .none); // .
            try renderIdentifier(r, init_token - 2, .space, .eagerly_unquote); // name
            try renderToken(r, init_token - 1, .space); // =
            try renderExpressionFixup(r, field_init, .comma_space);
        }
    }

    return renderToken(r, rbrace);
}

fn renderArrayInit(
    r: *Render,
    array_init: Ast.full.ArrayInit,
) Error!void {
    const tree = r.tree;
    const ais = r.ais;
    const gpa = r.gpa;
    const token_tags = tree.tokens.items(.tag);

    if (array_init.ast.type_expr == 0) {
        try renderToken(r, array_init.ast.lbrace - 1, .none); // .
    } else {
        try renderExpression(r, array_init.ast.type_expr, .none); // T
    }

    if (array_init.ast.elements.len == 0) {
        try renderToken(r, array_init.ast.lbrace, .none); // lbrace

        return renderToken(r, array_init.ast.lbrace + 1); // rbrace
    }

    const last_elem = array_init.ast.elements[array_init.ast.elements.len - 1];
    const last_elem_token = tree.lastToken(last_elem);
    const trailing_comma = token_tags[last_elem_token + 1] == .comma;
    const rbrace = if (trailing_comma) last_elem_token + 2 else last_elem_token + 1;
    assert(token_tags[rbrace] == .r_brace);

    if (array_init.ast.elements.len == 1) {
        const only_elem = array_init.ast.elements[0];
        const first_token = tree.firstToken(only_elem);
        if (token_tags[first_token] != .multiline_string_literal_line and
            !anythingBetween(tree, last_elem_token, rbrace))
        {
            try renderToken(r, array_init.ast.lbrace, .none);
            try renderExpression(r, only_elem, .none);
            return renderToken(r, rbrace);
        }
    }

    const contains_comment = hasComment(tree, array_init.ast.lbrace, rbrace);
    const contains_multiline_string = hasMultilineString(tree, array_init.ast.lbrace, rbrace);

    if (!trailing_comma and !contains_comment and !contains_multiline_string) {
        // Render all on one line, no trailing comma.
        if (array_init.ast.elements.len == 1) {
            // If there is only one element, we don't use spaces
            try renderToken(r, array_init.ast.lbrace, .none);
            try renderExpression(r, array_init.ast.elements[0], .none);
        } else {
            try renderToken(r, array_init.ast.lbrace, .space);
            for (array_init.ast.elements) |elem| {
                try renderExpression(r, elem, .comma_space);
            }
        }
        return renderToken(r, last_elem_token + 1); // rbrace
    }

    try renderToken(r, array_init.ast.lbrace, .newline);

    var expr_index: usize = 0;
    while (true) {
        const row_size = rowSize(tree, array_init.ast.elements[expr_index..], rbrace);
        const row_exprs = array_init.ast.elements[expr_index..];
        // A place to store the width of each expression and its column's maximum
        const widths = try gpa.alloc(usize, row_exprs.len + row_size);
        defer gpa.free(widths);
        @memset(widths, 0);

        const expr_newlines = try gpa.alloc(bool, row_exprs.len);
        defer gpa.free(expr_newlines);
        @memset(expr_newlines, false);

        const expr_widths = widths[0..row_exprs.len];
        const column_widths = widths[row_exprs.len..];

        // Find next row with trailing comment (if any) to end the current section.
        const section_end = sec_end: {
            var this_line_first_expr: usize = 0;
            var this_line_size = rowSize(tree, row_exprs, rbrace);
            for (row_exprs, 0..) |expr, i| {
                // Ignore comment on first line of this section.
                if (i == 0) continue;
                const expr_last_token = tree.lastToken(expr);
                if (tree.tokensOnSameLine(tree.firstToken(row_exprs[0]), expr_last_token))
                    continue;
                // Track start of line containing comment.
                if (!tree.tokensOnSameLine(tree.firstToken(row_exprs[this_line_first_expr]), expr_last_token)) {
                    this_line_first_expr = i;
                    this_line_size = rowSize(tree, row_exprs[this_line_first_expr..], rbrace);
                }

                const maybe_comma = expr_last_token + 1;
                if (token_tags[maybe_comma] == .comma) {
                    if (hasSameLineComment(tree, maybe_comma))
                        break :sec_end i - this_line_size + 1;
                }
            }
            break :sec_end row_exprs.len;
        };
        expr_index += section_end;

        const section_exprs = row_exprs[0..section_end];

        var sub_expr_buffer = std.ArrayList(u8).init(gpa);
        defer sub_expr_buffer.deinit();

        const sub_expr_buffer_starts = try gpa.alloc(usize, section_exprs.len + 1);
        defer gpa.free(sub_expr_buffer_starts);

        var sub_render: Render = .{
            .gpa = r.gpa,
            .tree = r.tree,
        };

        // Calculate size of columns in current section
        var column_counter: usize = 0;
        var single_line = true;
        var contains_newline = false;
        for (section_exprs, 0..) |expr, i| {
            const start = sub_expr_buffer.items.len;
            sub_expr_buffer_starts[i] = start;

            if (i + 1 < section_exprs.len) {
                try renderExpression(&sub_render, expr, .none);
                const width = sub_expr_buffer.items.len - start;
                const this_contains_newline = mem.indexOfScalar(u8, sub_expr_buffer.items[start..], '\n') != null;
                contains_newline = contains_newline or this_contains_newline;
                expr_widths[i] = width;
                expr_newlines[i] = this_contains_newline;

                if (!this_contains_newline) {
                    const column = column_counter % row_size;
                    column_widths[column] = @max(column_widths[column], width);

                    const expr_last_token = tree.lastToken(expr) + 1;
                    const next_expr = section_exprs[i + 1];
                    column_counter += 1;
                    if (!tree.tokensOnSameLine(expr_last_token, tree.firstToken(next_expr))) single_line = false;
                } else {
                    single_line = false;
                    column_counter = 0;
                }
            } else {
                try renderExpression(&sub_render, expr, .comma);

                const width = sub_expr_buffer.items.len - start - 2;
                const this_contains_newline = mem.indexOfScalar(u8, sub_expr_buffer.items[start .. sub_expr_buffer.items.len - 1], '\n') != null;
                contains_newline = contains_newline or this_contains_newline;
                expr_widths[i] = width;
                expr_newlines[i] = contains_newline;

                if (!contains_newline) {
                    const column = column_counter % row_size;
                    column_widths[column] = @max(column_widths[column], width);
                }
            }
        }
        sub_expr_buffer_starts[section_exprs.len] = sub_expr_buffer.items.len;

        // Render exprs in current section.
        column_counter = 0;
        for (section_exprs, 0..) |expr, i| {
            const start = sub_expr_buffer_starts[i];
            const end = sub_expr_buffer_starts[i + 1];
            const expr_text = sub_expr_buffer.items[start..end];
            if (!expr_newlines[i]) {
                try ais.writer().writeAll(expr_text);
            } else {
                var by_line = std.mem.splitScalar(u8, expr_text, '\n');
                var last_line_was_empty = false;
                try ais.writer().writeAll(by_line.first());
                while (by_line.next()) |line| {
                    if (std.mem.startsWith(u8, line, "//") and last_line_was_empty) {} else {}
                    last_line_was_empty = (line.len == 0);
                    try ais.writer().writeAll(line);
                }
            }

            if (i + 1 < section_exprs.len) {
                const next_expr = section_exprs[i + 1];
                const comma = tree.lastToken(expr) + 1;

                if (column_counter != row_size - 1) {
                    if (!expr_newlines[i] and !expr_newlines[i + 1]) {
                        // Neither the current or next expression is multiline
                        try renderToken(r, comma, .space); // ,
                        assert(column_widths[column_counter % row_size] >= expr_widths[i]);
                        const padding = column_widths[column_counter % row_size] - expr_widths[i];
                        try ais.writer().writeByteNTimes(' ', padding);

                        column_counter += 1;
                        continue;
                    }
                }

                if (single_line and row_size != 1) {
                    try renderToken(r, comma, .space); // ,
                    continue;
                }

                column_counter = 0;
                try renderToken(r, comma, .newline); // ,
                try renderExtraNewline(r, next_expr);
            }
        }

        if (expr_index == array_init.ast.elements.len)
            break;
    }

    return renderToken(r, rbrace); // rbrace
}

fn renderContainerDecl(
    r: *Render,
    container_decl_node: Ast.Node.Index,
    container_decl: Ast.full.ContainerDecl,
) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);

    if (container_decl.layout_token) |layout_token| {
        try renderToken(r, layout_token, .space);
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
        try renderToken(r, container_decl.ast.main_token, .none); // union
        try renderToken(r, enum_token - 1, .none); // lparen
        try renderToken(r, enum_token, .none); // enum
        if (container_decl.ast.arg != 0) {
            try renderToken(r, enum_token + 1, .none); // lparen
            try renderExpression(r, container_decl.ast.arg, .none);
            const rparen = tree.lastToken(container_decl.ast.arg) + 1;
            try renderToken(r, rparen, .none); // rparen
            try renderToken(r, rparen + 1, .space); // rparen
            lbrace = rparen + 2;
        } else {
            try renderToken(r, enum_token + 1, .space); // rparen
            lbrace = enum_token + 2;
        }
    } else if (container_decl.ast.arg != 0) {
        try renderToken(r, container_decl.ast.main_token, .none); // union
        try renderToken(r, container_decl.ast.main_token + 1, .none); // lparen
        try renderExpression(r, container_decl.ast.arg, .none);
        const rparen = tree.lastToken(container_decl.ast.arg) + 1;
        try renderToken(r, rparen, .space); // rparen
        lbrace = rparen + 1;
    } else {
        try renderToken(r, container_decl.ast.main_token, .space); // union
        lbrace = container_decl.ast.main_token + 1;
    }

    const rbrace = tree.lastToken(container_decl_node);
    if (container_decl.ast.members.len == 0) {
        if (token_tags[lbrace + 1] == .container_doc_comment) {
            try renderToken(r, lbrace, .newline); // lbrace
            try renderContainerDocComments(r, lbrace + 1);
        } else {
            try renderToken(r, lbrace, .none); // lbrace
        }

        return renderToken(r, rbrace); // rbrace
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
        try renderToken(r, lbrace, .space); // lbrace
        for (container_decl.ast.members) |member| {
            try renderMember(r, container, member, .space);
        }
        return renderToken(r, rbrace); // rbrace
    }

    // One member per line.

    try renderToken(r, lbrace, .newline); // lbrace
    if (token_tags[lbrace + 1] == .container_doc_comment) {
        try renderContainerDocComments(r, lbrace + 1);
    }
    for (container_decl.ast.members, 0..) |member, i| {
        if (i != 0) try renderExtraNewline(r, member);
        switch (tree.nodes.items(.tag)[member]) {
            // For container fields, ensure a trailing comma is added if necessary.
            .container_field_init,
            .container_field_align,
            .container_field,
            => {
                try renderMember(r, container, member, .comma);
            },

            else => try renderMember(r, container, member, .newline),
        }
    }

    return renderToken(r, rbrace); // rbrace
}

fn renderAsm(
    r: *Render,
    asm_node: Ast.full.Asm,
) Error!void {
    const tree = r.tree;
    const ais = r.ais;
    const token_tags = tree.tokens.items(.tag);

    try renderToken(r, asm_node.ast.asm_token, .space); // asm

    if (asm_node.volatile_token) |volatile_token| {
        try renderToken(r, volatile_token, .space); // volatile
        try renderToken(r, volatile_token + 1, .none); // lparen
    } else {
        try renderToken(r, asm_node.ast.asm_token + 1, .none); // lparen
    }

    if (asm_node.ast.items.len == 0) {
        try ais.forcePushIndent(.normal);
        if (asm_node.first_clobber) |first_clobber| {
            // asm ("foo" ::: "a", "b")
            // asm ("foo" ::: "a", "b",)
            try renderExpression(r, asm_node.ast.template, .space);
            // Render the three colons.
            try renderToken(r, first_clobber - 3, .none);
            try renderToken(r, first_clobber - 2, .none);
            try renderToken(r, first_clobber - 1, .space);

            var tok_i = first_clobber;
            while (true) : (tok_i += 1) {
                try renderToken(r, tok_i, .none);
                tok_i += 1;
                switch (token_tags[tok_i]) {
                    .r_paren => {
                        return renderToken(r, tok_i);
                    },
                    .comma => {
                        if (token_tags[tok_i + 1] == .r_paren) {
                            return renderToken(r, tok_i + 1);
                        } else {
                            try renderToken(r, tok_i, .space);
                        }
                    },
                    else => unreachable,
                }
            }
        } else {
            // asm ("foo")
            try renderExpression(r, asm_node.ast.template, .none);

            return renderToken(r, asm_node.ast.rparen); // rparen
        }
    }

    try ais.forcePushIndent(.normal);
    try renderExpression(r, asm_node.ast.template, .newline);
    const colon1 = tree.lastToken(asm_node.ast.template) + 1;

    const colon2 = if (asm_node.outputs.len == 0) colon2: {
        try renderToken(r, colon1, .newline); // :
        break :colon2 colon1 + 1;
    } else colon2: {
        try renderToken(r, colon1, .space); // :

        try ais.forcePushIndent(.normal);
        for (asm_node.outputs, 0..) |asm_output, i| {
            if (i + 1 < asm_node.outputs.len) {
                const next_asm_output = asm_node.outputs[i + 1];
                try renderAsmOutput(r, asm_output, .none);

                const comma = tree.firstToken(next_asm_output) - 1;
                try renderToken(r, comma, .newline); // ,
                try renderExtraNewlineToken(r, tree.firstToken(next_asm_output));
            } else if (asm_node.inputs.len == 0 and asm_node.first_clobber == null) {
                try renderAsmOutput(r, asm_output, .comma);

                return renderToken(r, asm_node.ast.rparen); // rparen
            } else {
                try renderAsmOutput(r, asm_output, .comma);
                const comma_or_colon = tree.lastToken(asm_output) + 1;
                break :colon2 switch (token_tags[comma_or_colon]) {
                    .comma => comma_or_colon + 1,
                    else => comma_or_colon,
                };
            }
        } else unreachable;
    };

    const colon3 = if (asm_node.inputs.len == 0) colon3: {
        try renderToken(r, colon2, .newline); // :
        break :colon3 colon2 + 1;
    } else colon3: {
        try renderToken(r, colon2, .space); // :
        try ais.forcePushIndent(.normal);
        for (asm_node.inputs, 0..) |asm_input, i| {
            if (i + 1 < asm_node.inputs.len) {
                const next_asm_input = asm_node.inputs[i + 1];
                try renderAsmInput(r, asm_input, .none);

                const first_token = tree.firstToken(next_asm_input);
                try renderToken(r, first_token - 1, .newline); // ,
                try renderExtraNewlineToken(r, first_token);
            } else if (asm_node.first_clobber == null) {
                try renderAsmInput(r, asm_input, .comma);

                return renderToken(r, asm_node.ast.rparen); // rparen
            } else {
                try renderAsmInput(r, asm_input, .comma);
                const comma_or_colon = tree.lastToken(asm_input) + 1;
                break :colon3 switch (token_tags[comma_or_colon]) {
                    .comma => comma_or_colon + 1,
                    else => comma_or_colon,
                };
            }
        }
        unreachable;
    };

    try renderToken(r, colon3, .space); // :
    const first_clobber = asm_node.first_clobber.?;
    var tok_i = first_clobber;
    while (true) {
        switch (token_tags[tok_i + 1]) {
            .r_paren => {
                try renderToken(r, tok_i, .newline);
                return renderToken(r, tok_i + 1);
            },
            .comma => {
                switch (token_tags[tok_i + 2]) {
                    .r_paren => {
                        try renderToken(r, tok_i, .newline);
                        return renderToken(r, tok_i + 2);
                    },
                    else => {
                        try renderToken(r, tok_i, .none);
                        try renderToken(r, tok_i + 1, .space);
                        tok_i += 2;
                    },
                }
            },
            else => unreachable,
        }
    }
}

fn renderCall(
    r: *Render,
    call: Ast.full.Call,
) Error!void {
    if (call.async_token) |async_token| {
        try renderToken(r, async_token, .space);
    }
    try renderExpression(r, call.ast.fn_expr, .none);
    try renderParamList(r, call.ast.lparen, call.ast.params);
}

fn renderParamList(
    r: *Render,
    lparen: Ast.TokenIndex,
    params: []const Ast.Node.Index,
) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);

    if (params.len == 0) {
        try renderToken(r, lparen, .none);

        return renderToken(r, lparen + 1); // )
    }

    const last_param = params[params.len - 1];
    const after_last_param_tok = tree.lastToken(last_param) + 1;
    if (token_tags[after_last_param_tok] == .comma) {
        try renderToken(r, lparen, .newline); // (
        for (params, 0..) |param_node, i| {
            if (i + 1 < params.len) {
                try renderExpression(r, param_node, .none);

                const comma = tree.lastToken(param_node) + 1;
                try renderToken(r, comma, .newline); // ,

                try renderExtraNewline(r, params[i + 1]);
            } else {
                try renderExpression(r, param_node, .comma);
            }
        }

        return renderToken(r, after_last_param_tok + 1); // )
    }

    try renderToken(r, lparen, .none); // (
    for (params, 0..) |param_node, i| {
        try renderExpression(r, param_node, .none);

        if (i + 1 < params.len) {
            const comma = tree.lastToken(param_node) + 1;
            try renderToken(r, comma);
        }
    }

    return renderToken(r, after_last_param_tok); // )
}

/// Render an expression, and the comma that follows it, if it is present in the source.
/// If a comma is present, and `space` is `Space.comma`, render only a single comma.
fn renderExpressionComma(r: *Render, node: Ast.Node.Index) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const maybe_comma = tree.lastToken(node) + 1;
    if (token_tags[maybe_comma] == .comma) {
        try renderExpression(r, node, .none);
        return renderToken(r, maybe_comma);
    } else {
        return renderExpression(r, node);
    }
}

/// Render a token, and the comma that follows it, if it is present in the source.
/// If a comma is present, and `space` is `Space.comma`, render only a single comma.
fn renderTokenComma(r: *Render, token: Ast.TokenIndex) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const maybe_comma = token + 1;
    if (token_tags[maybe_comma] == .comma) {
        try renderToken(r, token, .none);
        return renderToken(r, maybe_comma);
    } else {
        return renderToken(r, token);
    }
}

/// Render an identifier, and the comma that follows it, if it is present in the source.
/// If a comma is present, and `space` is `Space.comma`, render only a single comma.
fn renderIdentifierComma(r: *Render, token: Ast.TokenIndex, quote: QuoteBehavior) Error!void {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    const maybe_comma = token + 1;
    if (token_tags[maybe_comma] == .comma) {
        try renderIdentifier(r, token, .none, quote);
        return renderToken(r, maybe_comma);
    } else {
        return renderIdentifier(r, token, quote);
    }
}

fn renderToken(r: *Render, writer: anytype, token_index: Ast.TokenIndex) Error!void {
    const tree = r.tree;
    const lexeme = tokenSliceForRender(tree, token_index);
    try writer.writeAll(lexeme);
}

fn renderTokenOverrideSpaceMode(r: *Render, token_index: Ast.TokenIndex) Error!void {
    const tree = r.tree;
    const ais = r.ais;
    const lexeme = tokenSliceForRender(tree, token_index);
    try ais.writer().writeAll(lexeme);
}

const QuoteBehavior = enum {
    preserve_when_shadowing,
    eagerly_unquote,
    eagerly_unquote_except_underscore,
};

fn renderIdentifier(r: *Render, token_index: Ast.TokenIndex, quote: QuoteBehavior) Error![]const u8 {
    const tree = r.tree;
    const token_tags = tree.tokens.items(.tag);
    assert(token_tags[token_index] == .identifier);
    const lexeme = tokenSliceForRender(tree, token_index);

    if (lexeme[0] != '@') {
        return renderToken(r, token_index);
    }

    assert(lexeme.len >= 3);
    assert(lexeme[0] == '@');
    assert(lexeme[1] == '\"');
    assert(lexeme[lexeme.len - 1] == '\"');
    const contents = lexeme[2 .. lexeme.len - 1]; // inside the @"" quotation

    // Empty name can't be unquoted.
    if (contents.len == 0) {
        return renderQuotedIdentifier(r, token_index, false);
    }

    // Special case for _.
    if (std.zig.isUnderscore(contents)) switch (quote) {
        .eagerly_unquote => return renderQuotedIdentifier(r, token_index, true),
        .eagerly_unquote_except_underscore,
        .preserve_when_shadowing,
        => return renderQuotedIdentifier(r, token_index, false),
    };

    // Scan the entire name for characters that would (after un-escaping) be illegal in a symbol,
    // i.e. contents don't match: [A-Za-z_][A-Za-z0-9_]*
    var contents_i: usize = 0;
    while (contents_i < contents.len) {
        switch (contents[contents_i]) {
            '0'...'9' => if (contents_i == 0) return renderQuotedIdentifier(r, token_index, false),
            'A'...'Z', 'a'...'z', '_' => {},
            '\\' => {
                var esc_offset = contents_i;
                const res = std.zig.string_literal.parseEscapeSequence(contents, &esc_offset);
                switch (res) {
                    .success => |char| switch (char) {
                        '0'...'9' => if (contents_i == 0) return renderQuotedIdentifier(r, token_index, false),
                        'A'...'Z', 'a'...'z', '_' => {},
                        else => return renderQuotedIdentifier(r, token_index, false),
                    },
                    .failure => return renderQuotedIdentifier(r, token_index, false),
                }
                contents_i += esc_offset;
                continue;
            },
            else => return renderQuotedIdentifier(r, token_index, false),
        }
        contents_i += 1;
    }

    // Read enough of the name (while un-escaping) to determine if it's a keyword or primitive.
    // If it's too long to fit in this buffer, we know it's neither and quoting is unnecessary.
    // If we read the whole thing, we have to do further checks.
    const longest_keyword_or_primitive_len = comptime blk: {
        var longest = 0;
        for (primitives.names.keys()) |key| {
            if (key.len > longest) longest = key.len;
        }
        for (std.zig.Token.keywords.keys()) |key| {
            if (key.len > longest) longest = key.len;
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
            return renderQuotedIdentifier(r, token_index, false);
        }
        if (primitives.isPrimitive(buf[0..buf_i])) switch (quote) {
            .eagerly_unquote,
            .eagerly_unquote_except_underscore,
            => return renderQuotedIdentifier(r, token_index, true),
            .preserve_when_shadowing => return renderQuotedIdentifier(r, token_index, false),
        };
    }

    try renderQuotedIdentifier(r, token_index, true);
}

// Renders a @"" quoted identifier, normalizing escapes.
// Unnecessary escapes are un-escaped, and \u escapes are normalized to \x when they fit.
// If unquote is true, the @"" is removed and the result is a bare symbol whose validity is asserted.
fn renderQuotedIdentifier(r: *Render, token_index: Ast.TokenIndex, comptime unquote: bool) !void {
    const tree = r.tree;
    const ais = r.ais;
    const token_tags = tree.tokens.items(.tag);
    assert(token_tags[token_index] == .identifier);
    const lexeme = tokenSliceForRender(tree, token_index);
    assert(lexeme.len >= 3 and lexeme[0] == '@');

    if (!unquote) try ais.writer().writeAll("@\"");
    const contents = lexeme[2 .. lexeme.len - 1];
    try renderIdentifierContents(ais.writer(), contents);
    if (!unquote) try ais.writer().writeByte('\"');
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
fn renderComments(r: *Render, start: usize, end: usize) Error!bool {
    const tree = r.tree;
    const ais = r.ais;

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

            } else if (mem.indexOfScalar(u8, tree.source[index..comment_start], '\n') != null) {
                // Respect the newline directly before the comment.
                // Note: This allows an empty line between comments

            } else if (index == start) {
                // Otherwise if the first comment is on the same line as
                // the token before it, prefix it with a single space.
                try ais.writer().writeByte(' ');
            }
        }

        index = 1 + (newline orelse end - 1);

        // Write the comment minus trailing whitespace.
        try ais.writer().print("{s}\n", .{trimmed_comment});
    }

    if (index != start and mem.containsAtLeast(u8, tree.source[index - 1 .. end], 2, "\n")) {
        // Don't leave any whitespace at the end of the file
        if (end != tree.source.len) {}
    }

    return index != start;
}

fn renderExtraNewline(r: *Render, node: Ast.Node.Index) Error!void {
    return renderExtraNewlineToken(r, r.tree.firstToken(node));
}

/// Check if there is an empty line immediately before the given token. If so, render it.
fn renderExtraNewlineToken(r: *Render, token_index: Ast.TokenIndex) Error!void {
    const tree = r.tree;
    const ais = r.ais;
    const token_starts = tree.tokens.items(.start);
    const token_start = token_starts[token_index];
    if (token_start == 0) return;
    const prev_token_end = if (token_index == 0)
        0
    else
        token_starts[token_index - 1] + tokenSliceForRender(tree, token_index - 1).len;

    // If there is a immediately preceding comment or doc_comment,
    // skip it because required extra newline has already been rendered.
    if (mem.indexOf(u8, tree.source[prev_token_end..token_start], "//") != null) return;
    if (token_index > 0 and tree.tokens.items(.tag)[token_index - 1] == .doc_comment) return;

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
fn renderDocComments(r: *Render, end_token: Ast.TokenIndex) Error!?[]const u8 {
    const tree = r.tree;

    // Search backwards for the first doc comment.
    const token_tags = tree.tokens.items(.tag);
    if (end_token == 0) return null;
    var tok = end_token - 1;
    while (token_tags[tok] == .doc_comment) {
        if (tok == 0) break;
        tok -= 1;
    } else {
        tok += 1;
    }
    const first_tok = tok;
    if (first_tok == end_token) return null;

    var doc_comment: std.ArrayList(u8) = .init(r.arena);
    defer doc_comment.deinit();
    while (token_tags[tok] == .doc_comment) : (tok += 1) {
        try renderToken(r, doc_comment.writer(), tok);
        try doc_comment.append('\n');
    }
    return try doc_comment.toOwnedSlice();
}

/// start_token is first container doc comment token.
fn renderContainerDocComments(r: *Render, start_token: Ast.TokenIndex) Error![]const u8 {
    var output: std.ArrayList(u8) = .init(r.arena);
    defer output.deinit();

    const token_tags = r.tree.tokens.items(.tag);
    var tok = start_token;
    while (token_tags[tok] == .container_doc_comment) : (tok += 1) {
        try renderToken(r, output.writer(), tok);
        try output.append('\n');
    }

    return try output.toOwnedSlice();
}

fn discardAllParams(r: *Render, fn_proto_node: Ast.Node.Index) Error!void {
    const tree = &r.tree;
    const ais = r.ais;
    var buf: [1]Ast.Node.Index = undefined;
    const fn_proto = tree.fullFnProto(&buf, fn_proto_node).?;
    const token_tags = tree.tokens.items(.tag);
    var it = fn_proto.iterate(tree);
    while (it.next()) |param| {
        const name_ident = param.name_token.?;
        assert(token_tags[name_ident] == .identifier);
        const w = ais.writer();
        try w.writeAll("_ = ");
        try w.writeAll(tokenSliceForRender(r.tree, name_ident));
        try w.writeAll(";\n");
    }
}

fn tokenSliceForRender(tree: Ast, token_index: Ast.TokenIndex) []const u8 {
    var ret = tree.tokenSlice(token_index);
    switch (tree.tokens.items(.tag)[token_index]) {
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
