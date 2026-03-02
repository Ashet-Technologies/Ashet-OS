const std = @import("std");
const abi_parser = @import("abi-parser");
const doc_comment_parser = abi_parser.doc_comment;
const DocComment = abi_parser.model.DocComment;

// Helper: parse raw lines (as produced by the tokenizer after stripping `///`)
// Lines with `/// text` produce `" text"` (one leading space).
// Lines with `///` (empty doc line) produce `""`.
fn parse(arena: std.mem.Allocator, lines: []const []const u8) !DocComment {
    return doc_comment_parser.parse(arena, lines);
}

// ── Empty / blank ────────────────────────────────────────────────────────────

test "empty input returns empty DocComment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{});
    try std.testing.expectEqual(@as(usize, 0), result.sections.len);
}

test "only blank lines returns empty DocComment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{ "", "", "" });
    try std.testing.expectEqual(@as(usize, 0), result.sections.len);
}

// ── Paragraphs ───────────────────────────────────────────────────────────────

test "simple paragraph" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{" Hello, world!"});
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.main, result.sections[0].kind);
    try std.testing.expectEqual(@as(usize, 1), result.sections[0].blocks.len);

    const block = result.sections[0].blocks[0];
    try std.testing.expect(block == .paragraph);
    try std.testing.expectEqual(@as(usize, 1), block.paragraph.content.len);
    try std.testing.expect(block.paragraph.content[0] == .text);
    try std.testing.expectEqualStrings("Hello, world!", block.paragraph.content[0].text.value);
}

test "multi-line paragraph joined with space" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " First line",
        " second line",
        " third line",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(@as(usize, 1), result.sections[0].blocks.len);

    const block = result.sections[0].blocks[0];
    try std.testing.expect(block == .paragraph);
    try std.testing.expectEqual(@as(usize, 1), block.paragraph.content.len);
    try std.testing.expectEqualStrings(
        "First line second line third line",
        block.paragraph.content[0].text.value,
    );
}

test "blank line separates paragraphs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " First paragraph.",
        "",
        " Second paragraph.",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(@as(usize, 2), result.sections[0].blocks.len);
    try std.testing.expect(result.sections[0].blocks[0] == .paragraph);
    try std.testing.expect(result.sections[0].blocks[1] == .paragraph);

    try std.testing.expectEqualStrings(
        "First paragraph.",
        result.sections[0].blocks[0].paragraph.content[0].text.value,
    );
    try std.testing.expectEqualStrings(
        "Second paragraph.",
        result.sections[0].blocks[1].paragraph.content[0].text.value,
    );
}

// ── Inline elements ──────────────────────────────────────────────────────────

test "inline code span" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{" Call `foo()` now."});
    const content = result.sections[0].blocks[0].paragraph.content;

    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("Call ", content[0].text.value);
    try std.testing.expect(content[1] == .code);
    try std.testing.expectEqualStrings("foo()", content[1].code.value);
    try std.testing.expect(content[2] == .text);
    try std.testing.expectEqualStrings(" now.", content[2].text.value);
}

test "cross-reference @`fqn`" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{" See @`foo.bar.Baz` for details."});
    const content = result.sections[0].blocks[0].paragraph.content;

    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[0] == .text);
    try std.testing.expectEqualStrings("See ", content[0].text.value);
    try std.testing.expect(content[1] == .ref);
    try std.testing.expectEqualStrings("foo.bar.Baz", content[1].ref.fqn);
    try std.testing.expect(content[2] == .text);
    try std.testing.expectEqualStrings(" for details.", content[2].text.value);
}

test "emphasis *text*" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{" This is *important* text."});
    const content = result.sections[0].blocks[0].paragraph.content;

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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // \` prevents inline code, \* prevents emphasis
    const result = try parse(arena.allocator(), &.{" Escape: \\`not code\\`."});
    const content = result.sections[0].blocks[0].paragraph.content;

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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{" See [the docs](https://example.com/docs)."});
    const content = result.sections[0].blocks[0].paragraph.content;

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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{" Visit <https://example.com>."});
    const content = result.sections[0].blocks[0].paragraph.content;

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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{" Mail <mailto:foo@example.com> us."});
    const content = result.sections[0].blocks[0].paragraph.content;

    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expect(content[1] == .link);
    try std.testing.expectEqualStrings("mailto:foo@example.com", content[1].link.url);
}

// ── Admonitions ──────────────────────────────────────────────────────────────

test "NOTE admonition starts new section" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " Main text.",
        "",
        " NOTE: This is a note.",
    });
    try std.testing.expectEqual(@as(usize, 2), result.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.main, result.sections[0].kind);
    try std.testing.expectEqual(DocComment.Section.Kind.note, result.sections[1].kind);

    const note_content = result.sections[1].blocks[0].paragraph.content;
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
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();

        var buf: [64]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, " {s}: test text", .{c.tag});
        const result = try parse(arena.allocator(), &.{line});

        try std.testing.expectEqual(@as(usize, 1), result.sections.len);
        try std.testing.expectEqual(c.kind, result.sections[0].kind);
    }
}

test "admonition with empty body starts section" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " NOTE:",
        " Text on the next line.",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.note, result.sections[0].kind);
    try std.testing.expectEqual(@as(usize, 1), result.sections[0].blocks.len);
    try std.testing.expectEqualStrings(
        "Text on the next line.",
        result.sections[0].blocks[0].paragraph.content[0].text.value,
    );
}

test "multiple admonition sections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " Main description.",
        "",
        " NOTE: Important note.",
        "",
        " WARNING: Be careful.",
    });
    try std.testing.expectEqual(@as(usize, 3), result.sections.len);
    try std.testing.expectEqual(DocComment.Section.Kind.main, result.sections[0].kind);
    try std.testing.expectEqual(DocComment.Section.Kind.note, result.sections[1].kind);
    try std.testing.expectEqual(DocComment.Section.Kind.warning, result.sections[2].kind);
}

// ── Lists ────────────────────────────────────────────────────────────────────

test "unordered list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " - First item",
        " - Second item",
        " - Third item",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(@as(usize, 1), result.sections[0].blocks.len);

    const block = result.sections[0].blocks[0];
    try std.testing.expect(block == .unordered_list);
    try std.testing.expectEqual(@as(usize, 3), block.unordered_list.items.len);
    try std.testing.expectEqualStrings("First item", block.unordered_list.items[0][0].text.value);
    try std.testing.expectEqualStrings("Second item", block.unordered_list.items[1][0].text.value);
    try std.testing.expectEqualStrings("Third item", block.unordered_list.items[2][0].text.value);
}

test "ordered list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " 1. First",
        " 2. Second",
        " 3. Third",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(@as(usize, 1), result.sections[0].blocks.len);

    const block = result.sections[0].blocks[0];
    try std.testing.expect(block == .ordered_list);
    try std.testing.expectEqual(@as(usize, 3), block.ordered_list.items.len);
    try std.testing.expectEqualStrings("First", block.ordered_list.items[0][0].text.value);
    try std.testing.expectEqualStrings("Second", block.ordered_list.items[1][0].text.value);
    try std.testing.expectEqualStrings("Third", block.ordered_list.items[2][0].text.value);
}

test "list item continuation line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " - First item",
        "   continues here",
        " - Second item",
    });
    const block = result.sections[0].blocks[0];
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " - Item one",
        " - Item two",
        "",
        " Trailing paragraph.",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(@as(usize, 2), result.sections[0].blocks.len);
    try std.testing.expect(result.sections[0].blocks[0] == .unordered_list);
    try std.testing.expect(result.sections[0].blocks[1] == .paragraph);
}

// ── Code fences ──────────────────────────────────────────────────────────────

test "code fence without syntax hint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " ```",
        " some code",
        " more code",
        " ```",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(@as(usize, 1), result.sections[0].blocks.len);

    const block = result.sections[0].blocks[0];
    try std.testing.expect(block == .code_block);
    try std.testing.expectEqual(@as(?[]const u8, null), block.code_block.syntax);
    try std.testing.expectEqualStrings("some code\nmore code", block.code_block.content);
}

test "code fence with syntax hint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " ```zig",
        " const x = 42;",
        " ```",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);

    const block = result.sections[0].blocks[0];
    try std.testing.expect(block == .code_block);
    try std.testing.expect(block.code_block.syntax != null);
    try std.testing.expectEqualStrings("zig", block.code_block.syntax.?);
    try std.testing.expectEqualStrings("const x = 42;", block.code_block.content);
}

test "code fence preceded and followed by text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const result = try parse(arena.allocator(), &.{
        " Before.",
        "",
        " ```",
        " code here",
        " ```",
        "",
        " After.",
    });
    try std.testing.expectEqual(@as(usize, 1), result.sections.len);
    try std.testing.expectEqual(@as(usize, 3), result.sections[0].blocks.len);
    try std.testing.expect(result.sections[0].blocks[0] == .paragraph);
    try std.testing.expect(result.sections[0].blocks[1] == .code_block);
    try std.testing.expect(result.sections[0].blocks[2] == .paragraph);
}
