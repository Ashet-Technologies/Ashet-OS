const std = @import("std");
const abi_parser = @import("abi-parser");

fn parse_and_analyze(allocator: std.mem.Allocator, source: []const u8) !abi_parser.model.Document {
    var tokenizer: abi_parser.syntax.Tokenizer = .init(source, "test");
    var parser: abi_parser.syntax.Parser = .{
        .allocator = allocator,
        .core = .init(&tokenizer),
    };
    const ast = try parser.accept_document();
    var errors: std.ArrayList(abi_parser.sema.AnalysisError) = .empty;
    defer errors.deinit(allocator);
    return abi_parser.sema.analyze(allocator, ast, null, &errors);
}

test "hex digit separators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\enum Foo : u64 {
        \\    item infinity = 0xFFFF_FFFF_FFFF_FFFF;
        \\    item half     = 0x7FFF_FFFF_FFFF_FFFF;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.enums.len);
    try std.testing.expectEqual(@as(usize, 2), doc.enums[0].items.len);
    try std.testing.expectEqual(@as(i65, @bitCast(@as(u65, 0xFFFF_FFFF_FFFF_FFFF))), doc.enums[0].items[0].value);
    try std.testing.expectEqual(@as(i65, 0x7FFF_FFFF_FFFF_FFFF), doc.enums[0].items[1].value);
}

test "decimal digit separators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\enum Counts : u32 {
        \\    item million = 1_000_000;
        \\    item billion = 1_000_000_000;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.enums.len);
    try std.testing.expectEqual(@as(i65, 1_000_000), doc.enums[0].items[0].value);
    try std.testing.expectEqual(@as(i65, 1_000_000_000), doc.enums[0].items[1].value);
}

test "binary digit separators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\enum Bits : u8 {
        \\    item pattern = 0b1111_0000;
        \\    item nibble  = 0b0000_1111;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.enums.len);
    try std.testing.expectEqual(@as(i65, 0b1111_0000), doc.enums[0].items[0].value);
    try std.testing.expectEqual(@as(i65, 0b0000_1111), doc.enums[0].items[1].value);
}
