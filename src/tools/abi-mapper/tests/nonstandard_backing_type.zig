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

test "enum with u2 backing type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\enum FileType : u2 {
        \\    item unknown = 0;
        \\    item file    = 1;
        \\    item dir     = 2;
        \\    item symlink = 3;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.enums.len);
    const e = doc.enums[0];
    // bit_count must reflect the declared u2 width
    try std.testing.expectEqual(@as(u8, 2), e.bit_count);
    // backing_type must be rounded up to the next standard type (u8)
    try std.testing.expectEqual(abi_parser.model.StandardType.u8, e.backing_type);
    try std.testing.expectEqual(@as(usize, 4), e.items.len);
}

test "enum with u10 backing type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\enum Wide : u10 {
        \\    item a = 0;
        \\    item b = 1023;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.enums.len);
    const e = doc.enums[0];
    try std.testing.expectEqual(@as(u8, 10), e.bit_count);
    try std.testing.expectEqual(abi_parser.model.StandardType.u16, e.backing_type);
}

test "enum with non-integer backing type emits error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\struct BadType { field x: u8; }
        \\enum Bad : BadType {
        \\    item a = 0;
        \\}
    ;
    const result = parse_and_analyze(allocator, source);
    try std.testing.expectError(error.AnalysisFailed, result);
}

test "bitstruct with u2 enum field packs correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // FileType : u2 → bit_count = 2; bitstruct uses 2+2 = 4 bits, fits in u8.
    const source =
        \\enum FileType : u2 {
        \\    item unknown = 0;
        \\    item file    = 1;
        \\}
        \\bitstruct Pair : u8 {
        \\    field a: FileType;
        \\    field b: FileType;
        \\    reserve u4 = 0;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.bitstructs.len);
    const bs = doc.bitstructs[0];
    // Two 2-bit fields + 4-bit reserve = 8 bits total
    try std.testing.expectEqual(@as(u8, 8), bs.bit_count);
    try std.testing.expectEqual(@as(usize, 3), bs.fields.len);
    // First field: bit_shift=0, bit_count=2
    try std.testing.expectEqual(@as(?u8, 0), bs.fields[0].bit_shift);
    try std.testing.expectEqual(@as(?u8, 2), bs.fields[0].bit_count);
    // Second field: bit_shift=2, bit_count=2
    try std.testing.expectEqual(@as(?u8, 2), bs.fields[1].bit_shift);
    try std.testing.expectEqual(@as(?u8, 2), bs.fields[1].bit_count);
}
