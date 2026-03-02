const std = @import("std");
const model = @import("model.zig");

const DocComment = model.DocComment;

/// Parses raw doc comment lines (after `///` prefix stripping) into a structured DocComment.
/// Each raw line should be `token.text[3..]` where token.text starts with `///`.
pub fn parse(allocator: std.mem.Allocator, raw_lines: []const []const u8) !DocComment {
    if (raw_lines.len == 0) return .empty;

    var ctx: ParseContext = .{ .allocator = allocator };
    return ctx.parse_doc(raw_lines);
}

const AccKind = enum { none, paragraph, unordered_list, ordered_list };

const ParseContext = struct {
    allocator: std.mem.Allocator,

    fn parse_doc(ctx: *ParseContext, raw_lines: []const []const u8) !DocComment {
        const a = ctx.allocator;

        // Normalize lines: strip one optional leading space (the /// separator), right-trim.
        var norm_lines: std.ArrayList([]const u8) = .empty;
        defer norm_lines.deinit(a);

        for (raw_lines) |raw| {
            const stripped = if (raw.len > 0 and raw[0] == ' ') raw[1..] else raw;
            try norm_lines.append(a, std.mem.trimRight(u8, stripped, " \t"));
        }
        const lines = norm_lines.items;

        var sections: std.ArrayList(DocComment.Section) = .empty;
        defer sections.deinit(a);

        var current_kind: DocComment.Section.Kind = .main;
        var blocks: std.ArrayList(DocComment.Block) = .empty;
        defer blocks.deinit(a);

        // Current paragraph lines accumulator
        var para_lines: std.ArrayList([]const u8) = .empty;
        defer para_lines.deinit(a);

        // Current list items (each item is a list of lines)
        var list_items: std.ArrayList(std.ArrayList([]const u8)) = .empty;
        defer {
            for (list_items.items) |*item| item.deinit(a);
            list_items.deinit(a);
        }

        var acc_kind: AccKind = .none;

        // Code fence state
        var in_fence = false;
        var fence_syntax: ?[]const u8 = null;
        var fence_lines: std.ArrayList([]const u8) = .empty;
        defer fence_lines.deinit(a);

        for (lines) |line| {
            if (in_fence) {
                if (std.mem.eql(u8, line, "```")) {
                    const content = try std.mem.join(a, "\n", fence_lines.items);
                    try blocks.append(a, .{ .code_block = .{ .syntax = fence_syntax, .content = content } });
                    in_fence = false;
                    fence_syntax = null;
                    fence_lines.clearRetainingCapacity();
                } else {
                    try fence_lines.append(a, line);
                }
                continue;
            }

            // Code fence start
            if (std.mem.startsWith(u8, line, "```")) {
                try ctx.flush_acc(a, &blocks, &acc_kind, &para_lines, &list_items);
                const syn = std.mem.trim(u8, line[3..], " ");
                fence_syntax = if (syn.len > 0) try a.dupe(u8, syn) else null;
                in_fence = true;
                continue;
            }

            // Blank line: flush current block
            if (line.len == 0) {
                try ctx.flush_acc(a, &blocks, &acc_kind, &para_lines, &list_items);
                continue;
            }

            // Admonition tag: NOTE:, WARNING:, LORE:, EXAMPLE:, DEPRECATED:, DECISION:
            if (parse_admonition(line)) |adm| {
                try ctx.flush_acc(a, &blocks, &acc_kind, &para_lines, &list_items);
                // Emit current section if it has content
                if (blocks.items.len > 0) {
                    try sections.append(a, .{ .kind = current_kind, .blocks = try blocks.toOwnedSlice(a) });
                }
                current_kind = adm.kind;
                acc_kind = .paragraph;
                if (adm.text.len > 0) {
                    try para_lines.append(a, adm.text);
                }
                continue;
            }

            // Unordered list item: starts with "- "
            if (std.mem.startsWith(u8, line, "- ")) {
                if (acc_kind != .unordered_list) {
                    try ctx.flush_acc(a, &blocks, &acc_kind, &para_lines, &list_items);
                    acc_kind = .unordered_list;
                }
                var new_item: std.ArrayList([]const u8) = .empty;
                try new_item.append(a, line[2..]);
                try list_items.append(a, new_item);
                continue;
            }

            // Ordered list item: starts with "N. "
            if (parse_ordered_item(line)) |text| {
                if (acc_kind != .ordered_list) {
                    try ctx.flush_acc(a, &blocks, &acc_kind, &para_lines, &list_items);
                    acc_kind = .ordered_list;
                }
                var new_item: std.ArrayList([]const u8) = .empty;
                try new_item.append(a, text);
                try list_items.append(a, new_item);
                continue;
            }

            // Continuation of current list item (indented by 2+ spaces)
            if ((acc_kind == .unordered_list or acc_kind == .ordered_list) and
                list_items.items.len > 0 and
                std.mem.startsWith(u8, line, "  "))
            {
                const cont = std.mem.trimLeft(u8, line, " ");
                try list_items.items[list_items.items.len - 1].append(a, cont);
                continue;
            }

            // Paragraph (default): accumulate lines, trimming leading whitespace
            // so that admonition continuation indentation is normalized.
            if (acc_kind != .paragraph) {
                try ctx.flush_acc(a, &blocks, &acc_kind, &para_lines, &list_items);
                acc_kind = .paragraph;
            }
            try para_lines.append(a, std.mem.trimLeft(u8, line, " \t"));
        }

        // Flush whatever remains
        try ctx.flush_acc(a, &blocks, &acc_kind, &para_lines, &list_items);

        // Emit the final section
        if (blocks.items.len > 0) {
            try sections.append(a, .{ .kind = current_kind, .blocks = try blocks.toOwnedSlice(a) });
        }

        if (sections.items.len == 0) return .empty;

        return .{ .sections = try sections.toOwnedSlice(a) };
    }

    fn flush_acc(
        ctx: *ParseContext,
        a: std.mem.Allocator,
        blocks: *std.ArrayList(DocComment.Block),
        acc_kind: *AccKind,
        para_lines: *std.ArrayList([]const u8),
        list_items: *std.ArrayList(std.ArrayList([]const u8)),
    ) !void {
        switch (acc_kind.*) {
            .none => {},
            .paragraph => {
                if (para_lines.items.len > 0) {
                    const text = try std.mem.join(a, " ", para_lines.items);
                    const content = try ctx.parse_inline(text);
                    try blocks.append(a, .{ .paragraph = .{ .content = content } });
                    para_lines.clearRetainingCapacity();
                }
            },
            .unordered_list, .ordered_list => {
                const items = try a.alloc([]const DocComment.Inline, list_items.items.len);
                for (list_items.items, 0..) |item_lines, j| {
                    const text = try std.mem.join(a, " ", item_lines.items);
                    items[j] = try ctx.parse_inline(text);
                }
                for (list_items.items) |*item| item.deinit(a);
                list_items.clearRetainingCapacity();
                if (acc_kind.* == .unordered_list) {
                    try blocks.append(a, .{ .unordered_list = .{ .items = items } });
                } else {
                    try blocks.append(a, .{ .ordered_list = .{ .items = items } });
                }
            },
        }
        acc_kind.* = .none;
    }

    fn parse_inline(ctx: *ParseContext, text: []const u8) ![]const DocComment.Inline {
        const a = ctx.allocator;
        var result: std.ArrayList(DocComment.Inline) = .empty;
        defer result.deinit(a);

        var text_start: usize = 0;
        var i: usize = 0;

        while (i < text.len) {
            const c = text[i];

            // Escape sequence: \` \* \[ \< \@ \\
            if (c == '\\' and i + 1 < text.len) {
                const next = text[i + 1];
                const escapable = switch (next) {
                    '`', '*', '[', '<', '@', '\\' => true,
                    else => false,
                };
                if (escapable) {
                    if (i > text_start) {
                        try result.append(a, .{ .text = .{ .value = text[text_start..i] } });
                    }
                    try result.append(a, .{ .text = .{ .value = text[i + 1 .. i + 2] } });
                    i += 2;
                    text_start = i;
                    continue;
                }
            }

            // Cross-reference: @`fqn`
            if (c == '@' and i + 1 < text.len and text[i + 1] == '`') {
                if (i > text_start) {
                    try result.append(a, .{ .text = .{ .value = text[text_start..i] } });
                }
                const ref_start = i + 2;
                if (std.mem.indexOfScalar(u8, text[ref_start..], '`')) |rel_end| {
                    const fqn = text[ref_start .. ref_start + rel_end];
                    try result.append(a, .{ .ref = .{ .fqn = fqn } });
                    i = ref_start + rel_end + 1;
                    text_start = i;
                } else {
                    // Unmatched backtick — treat as literal text
                    i += 1;
                }
                continue;
            }

            // Inline code: `text`
            if (c == '`') {
                if (i > text_start) {
                    try result.append(a, .{ .text = .{ .value = text[text_start..i] } });
                }
                const code_start = i + 1;
                if (std.mem.indexOfScalar(u8, text[code_start..], '`')) |rel_end| {
                    const code_val = text[code_start .. code_start + rel_end];
                    try result.append(a, .{ .code = .{ .value = code_val } });
                    i = code_start + rel_end + 1;
                    text_start = i;
                } else {
                    i += 1;
                }
                continue;
            }

            // Emphasis: *content*
            // Opening * must be preceded by whitespace or start-of-text.
            if (c == '*') {
                const at_word_start = (i == 0 or text[i - 1] == ' ' or text[i - 1] == '\t');
                if (at_word_start and i + 1 < text.len) {
                    const em_start = i + 1;
                    var j = em_start;
                    var found_close: ?usize = null;
                    while (j < text.len) : (j += 1) {
                        if (text[j] == '*') {
                            // Closing * must be followed by whitespace, non-alphanumeric, or end-of-text
                            const after_close = j + 1;
                            const valid_close = (after_close >= text.len or
                                !std.ascii.isAlphanumeric(text[after_close]));
                            if (valid_close and j > em_start) {
                                found_close = j;
                                break;
                            }
                        }
                    }
                    if (found_close) |close_pos| {
                        if (i > text_start) {
                            try result.append(a, .{ .text = .{ .value = text[text_start..i] } });
                        }
                        const inner = text[em_start..close_pos];
                        const inner_content = try ctx.parse_inline(inner);
                        try result.append(a, .{ .emphasis = .{ .content = inner_content } });
                        i = close_pos + 1;
                        text_start = i;
                        continue;
                    }
                }
            }

            // Titled link: [display](url)
            if (c == '[') {
                if (std.mem.indexOfScalarPos(u8, text, i + 1, ']')) |close_bracket| {
                    if (close_bracket + 1 < text.len and text[close_bracket + 1] == '(') {
                        if (std.mem.indexOfScalarPos(u8, text, close_bracket + 2, ')')) |close_paren| {
                            if (i > text_start) {
                                try result.append(a, .{ .text = .{ .value = text[text_start..i] } });
                            }
                            const display = text[i + 1 .. close_bracket];
                            const url = text[close_bracket + 2 .. close_paren];
                            const content = try ctx.parse_inline(display);
                            try result.append(a, .{ .link = .{ .url = url, .content = content } });
                            i = close_paren + 1;
                            text_start = i;
                            continue;
                        }
                    }
                }
            }

            // Autolink: <http://...> <https://...> <mailto:...>
            if (c == '<') {
                const url_schemes = [_][]const u8{ "http://", "https://", "mailto:" };
                var matched_scheme = false;
                for (url_schemes) |scheme| {
                    if (i + 1 + scheme.len <= text.len and
                        std.mem.eql(u8, text[i + 1 .. i + 1 + scheme.len], scheme))
                    {
                        matched_scheme = true;
                        break;
                    }
                }
                if (matched_scheme) {
                    if (std.mem.indexOfScalarPos(u8, text, i + 1, '>')) |close_angle| {
                        if (i > text_start) {
                            try result.append(a, .{ .text = .{ .value = text[text_start..i] } });
                        }
                        const url = text[i + 1 .. close_angle];
                        const content = try a.alloc(DocComment.Inline, 1);
                        content[0] = .{ .text = .{ .value = url } };
                        try result.append(a, .{ .link = .{ .url = url, .content = content } });
                        i = close_angle + 1;
                        text_start = i;
                        continue;
                    }
                }
            }

            i += 1;
        }

        // Flush remaining literal text
        if (text_start < text.len) {
            try result.append(a, .{ .text = .{ .value = text[text_start..] } });
        }

        return result.toOwnedSlice(a);
    }
};

const AdmonitionResult = struct {
    kind: DocComment.Section.Kind,
    text: []const u8,
};

fn parse_admonition(line: []const u8) ?AdmonitionResult {
    const Tag = struct { tag: []const u8, kind: DocComment.Section.Kind };
    const tags = [_]Tag{
        .{ .tag = "NOTE", .kind = .note },
        .{ .tag = "WARNING", .kind = .warning },
        .{ .tag = "LORE", .kind = .lore },
        .{ .tag = "EXAMPLE", .kind = .example },
        .{ .tag = "DEPRECATED", .kind = .deprecated },
        .{ .tag = "DECISION", .kind = .decision },
    };

    for (tags) |entry| {
        if (std.mem.startsWith(u8, line, entry.tag)) {
            const rest = line[entry.tag.len..];
            if (std.mem.startsWith(u8, rest, ": ")) {
                return .{ .kind = entry.kind, .text = rest[2..] };
            } else if (std.mem.eql(u8, rest, ":")) {
                return .{ .kind = entry.kind, .text = "" };
            }
        }
    }
    return null;
}

fn parse_ordered_item(line: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {}
    if (i == 0 or i >= line.len) return null;
    if (line[i] != '.') return null;
    if (i + 1 >= line.len or line[i + 1] != ' ') return null;
    return line[i + 2 ..];
}
