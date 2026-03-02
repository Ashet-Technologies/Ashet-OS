const std = @import("std");
const abi_parser = @import("abi-parser");
const doc_comment_parser = abi_parser.doc_comment;
const DocComment = abi_parser.model.DocComment;

// ── Empty / blank ────────────────────────────────────────────────────────────

test "empty input returns empty DocComment" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 0), parsed.comment.sections.len);
}

test "only blank lines returns empty DocComment" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{ "", "", "" });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 0), parsed.comment.sections.len);
}

// ── Paragraphs ───────────────────────────────────────────────────────────────

test "simple paragraph" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" Hello, world!"});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.main, parsed.comment.sections[0].kind);
    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections[0].blocks.len);

    const block = parsed.comment.sections[0].blocks[0];
    try std.testing.expect(block == .paragraph);
    try std.testing.expectEqual(@as(usize, 1), block.paragraph.content.len);
    try std.testing.expect(block.paragraph.content[0] == .text);
    try std.testing.expectEqualStrings("Hello, world!", block.paragraph.content[0].text.value);
}

test "multi-line paragraph joined with space" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " First line",
        " second line",
        " third line",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections[0].blocks.len);

    const block = parsed.comment.sections[0].blocks[0];
    try std.testing.expect(block == .paragraph);
    try std.testing.expectEqual(@as(usize, 1), block.paragraph.content.len);
    try std.testing.expectEqualStrings(
        "First line second line third line",
        block.paragraph.content[0].text.value,
    );
}

test "blank line separates paragraphs" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " First paragraph.",
        "",
        " Second paragraph.",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.comment.sections[0].blocks.len);
    try std.testing.expect(parsed.comment.sections[0].blocks[0] == .paragraph);
    try std.testing.expect(parsed.comment.sections[0].blocks[1] == .paragraph);

    try std.testing.expectEqualStrings(
        "First paragraph.",
        parsed.comment.sections[0].blocks[0].paragraph.content[0].text.value,
    );
    try std.testing.expectEqualStrings(
        "Second paragraph.",
        parsed.comment.sections[0].blocks[1].paragraph.content[0].text.value,
    );
}

// ── Inline elements ──────────────────────────────────────────────────────────

test "inline code span" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" Call `foo()` now."});
    defer parsed.deinit();

    const content = parsed.comment.sections[0].blocks[0].paragraph.content;
    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("Call ", content[0].text.value);
    try std.testing.expect(content[1] == .code);
    try std.testing.expectEqualStrings("foo()", content[1].code.value);
    try std.testing.expect(content[2] == .text);
    try std.testing.expectEqualStrings(" now.", content[2].text.value);
}

test "cross-reference @`fqn`" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" See @`foo.bar.Baz` for details."});
    defer parsed.deinit();

    const content = parsed.comment.sections[0].blocks[0].paragraph.content;
    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("See ", content[0].text.value);
    try std.testing.expect(content[1] == .ref);
    try std.testing.expectEqualStrings("foo.bar.Baz", content[1].ref.fqn);
    try std.testing.expect(content[2] == .text);
    try std.testing.expectEqualStrings(" for details.", content[2].text.value);
}

test "emphasis *text*" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" This is *important* text."});
    defer parsed.deinit();

    const content = parsed.comment.sections[0].blocks[0].paragraph.content;
    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("This is ", content[0].text.value);
    try std.testing.expect(content[1] == .emphasis);
    try std.testing.expectEqual(@as(usize, 1), content[1].emphasis.content.len);
    try std.testing.expectEqualStrings("important", content[1].emphasis.content[0].text.value);
    try std.testing.expect(content[2] == .text);
    try std.testing.expectEqualStrings(" text.", content[2].text.value);
}

test "escape sequences suppress special syntax" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" Escape: \\`not code\\`."});
    defer parsed.deinit();

    const content = parsed.comment.sections[0].blocks[0].paragraph.content;
    // None of the nodes should be a .code span
    for (content) |item| {
        try std.testing.expect(item != .code);
    }
    // First text node is "Escape: "
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("Escape: ", content[0].text.value);
    // Second text node is the escaped backtick character
    try std.testing.expect(content[1] == .text);
    try std.testing.expectEqualStrings("`", content[1].text.value);
}

test "titled link [display](url)" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" See [the docs](https://example.com/docs)."});
    defer parsed.deinit();

    const content = parsed.comment.sections[0].blocks[0].paragraph.content;
    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("See ", content[0].text.value);
    try std.testing.expect(content[1] == .link);
    try std.testing.expectEqualStrings("https://example.com/docs", content[1].link.url);
    try std.testing.expectEqual(@as(usize, 1), content[1].link.content.len);
    try std.testing.expectEqualStrings("the docs", content[1].link.content[0].text.value);
    try std.testing.expect(content[2] == .text);
    try std.testing.expectEqualStrings(".", content[2].text.value);
}

test "autolink <https://...>" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" Visit <https://example.com>."});
    defer parsed.deinit();

    const content = parsed.comment.sections[0].blocks[0].paragraph.content;
    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("Visit ", content[0].text.value);
    try std.testing.expect(content[1] == .link);
    try std.testing.expectEqualStrings("https://example.com", content[1].link.url);
    try std.testing.expectEqual(@as(usize, 1), content[1].link.content.len);
    try std.testing.expectEqualStrings("https://example.com", content[1].link.content[0].text.value);
    try std.testing.expect(content[2] == .text);
    try std.testing.expectEqualStrings(".", content[2].text.value);
}

test "autolink <mailto:...>" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{" Mail <mailto:foo@example.com> us."});
    defer parsed.deinit();

    const content = parsed.comment.sections[0].blocks[0].paragraph.content;
    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[1] == .link);
    try std.testing.expectEqualStrings("mailto:foo@example.com", content[1].link.url);
}

// ── Admonitions ──────────────────────────────────────────────────────────────

test "NOTE admonition starts new section" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " Main text.",
        "",
        " NOTE: This is a note.",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.comment.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.main, parsed.comment.sections[0].kind);
    try std.testing.expectEqual(DocComment.Section.Kind.note, parsed.comment.sections[1].kind);

    const note_content = parsed.comment.sections[1].blocks[0].paragraph.content;
    try std.testing.expectEqualStrings("This is a note.", note_content[0].text.value);
}

test "all admonition kinds are recognized" {
    const Case = struct { tag: []const u8, kind: DocComment.Section.Kind };
    const cases = [_]Case{
        .{ .tag = "NOTE", .kind = .note },
        .{ .tag = "WARNING", .kind = .warning },
        .{ .tag = "LORE", .kind = .lore },
        .{ .tag = "EXAMPLE", .kind = .example },
        .{ .tag = "DEPRECATED", .kind = .deprecated },
        .{ .tag = "DECISION", .kind = .decision },
    };

    for (cases) |c| {
        var buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, " {s}: test text", .{c.tag});

        var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{line});
        defer parsed.deinit();

        try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections.len);
        try std.testing.expectEqual(c.kind, parsed.comment.sections[0].kind);
    }
}

test "admonition with empty body starts section" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " NOTE:",
        " Text on the next line.",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.note, parsed.comment.sections[0].kind);
    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections[0].blocks.len);
    try std.testing.expectEqualStrings(
        "Text on the next line.",
        parsed.comment.sections[0].blocks[0].paragraph.content[0].text.value,
    );
}

test "multiple admonition sections" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " Main description.",
        "",
        " NOTE: Important note.",
        "",
        " WARNING: Be careful.",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.comment.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.main, parsed.comment.sections[0].kind);
    try std.testing.expectEqual(DocComment.Section.Kind.note, parsed.comment.sections[1].kind);
    try std.testing.expectEqual(DocComment.Section.Kind.warning, parsed.comment.sections[2].kind);
}

// ── Lists ────────────────────────────────────────────────────────────────────

test "unordered list" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " - First item",
        " - Second item",
        " - Third item",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections[0].blocks.len);

    const block = parsed.comment.sections[0].blocks[0];
    try std.testing.expect(block == .unordered_list);
    try std.testing.expectEqual(@as(usize, 3), block.unordered_list.items.len);
    try std.testing.expectEqualStrings("First item", block.unordered_list.items[0][0].text.value);
    try std.testing.expectEqualStrings("Second item", block.unordered_list.items[1][0].text.value);
    try std.testing.expectEqualStrings("Third item", block.unordered_list.items[2][0].text.value);
}

test "ordered list" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " 1. First",
        " 2. Second",
        " 3. Third",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections[0].blocks.len);

    const block = parsed.comment.sections[0].blocks[0];
    try std.testing.expect(block == .ordered_list);
    try std.testing.expectEqual(@as(usize, 3), block.ordered_list.items.len);
    try std.testing.expectEqualStrings("First", block.ordered_list.items[0][0].text.value);
    try std.testing.expectEqualStrings("Second", block.ordered_list.items[1][0].text.value);
    try std.testing.expectEqualStrings("Third", block.ordered_list.items[2][0].text.value);
}

test "list item continuation line" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " - First item",
        "   continues here",
        " - Second item",
    });
    defer parsed.deinit();

    const block = parsed.comment.sections[0].blocks[0];
    try std.testing.expect(block == .unordered_list);
    try std.testing.expectEqual(@as(usize, 2), block.unordered_list.items.len);
    // The two continuation lines are joined with a space
    try std.testing.expectEqualStrings(
        "First item continues here",
        block.unordered_list.items[0][0].text.value,
    );
    try std.testing.expectEqualStrings("Second item", block.unordered_list.items[1][0].text.value);
}

test "paragraph after list" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " - Item one",
        " - Item two",
        "",
        " Trailing paragraph.",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.comment.sections[0].blocks.len);
    try std.testing.expect(parsed.comment.sections[0].blocks[0] == .unordered_list);
    try std.testing.expect(parsed.comment.sections[0].blocks[1] == .paragraph);
}

// ── Code fences ──────────────────────────────────────────────────────────────

test "code fence without syntax hint" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " ```",
        " some code",
        " more code",
        " ```",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.comment.sections[0].blocks.len);

    const block = parsed.comment.sections[0].blocks[0];
    try std.testing.expect(block == .code_block);
    try std.testing.expectEqual(@as(?[]const u8, null), block.code_block.syntax);
    try std.testing.expectEqualStrings("some code\nmore code", block.code_block.content);
}

test "code fence with syntax hint" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " ```zig",
        " const x = 42;",
        " ```",
    });
    defer parsed.deinit();

    const block = parsed.comment.sections[0].blocks[0];
    try std.testing.expect(block == .code_block);
    try std.testing.expect(block.code_block.syntax != null);
    try std.testing.expectEqualStrings("zig", block.code_block.syntax.?);
    try std.testing.expectEqualStrings("const x = 42;", block.code_block.content);
}

test "code fence preceded and followed by text" {
    var parsed = try doc_comment_parser.parse(std.testing.allocator, &.{
        " Before.",
        "",
        " ```",
        " code here",
        " ```",
        "",
        " After.",
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.comment.sections[0].blocks.len);
    try std.testing.expect(parsed.comment.sections[0].blocks[0] == .paragraph);
    try std.testing.expect(parsed.comment.sections[0].blocks[1] == .code_block);
    try std.testing.expect(parsed.comment.sections[0].blocks[2] == .paragraph);
}
