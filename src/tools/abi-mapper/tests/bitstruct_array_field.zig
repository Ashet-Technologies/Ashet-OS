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

test "array of 2-bit enum in bitstruct packs correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // 8 × 2-bit MarshalType = 16 bits per field, two fields = 32 bits = u32.
    const source =
        \\enum MarshalType : u2 {
        \\    item none  = 0;
        \\    item small = 1;
        \\    item large = 2;
        \\    item ptr   = 3;
        \\}
        \\bitstruct FunctionSignature : u32 {
        \\    field inputs:  [8]MarshalType;
        \\    field outputs: [8]MarshalType;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.bitstructs.len);
    const bs = doc.bitstructs[0];
    try std.testing.expectEqual(@as(u8, 32), bs.bit_count);
    try std.testing.expectEqual(@as(usize, 2), bs.fields.len);
    // inputs: bit_shift=0, bit_count=16 (8 × 2)
    try std.testing.expectEqual(@as(?u8, 0), bs.fields[0].bit_shift);
    try std.testing.expectEqual(@as(?u8, 16), bs.fields[0].bit_count);
    // outputs: bit_shift=16, bit_count=16
    try std.testing.expectEqual(@as(?u8, 16), bs.fields[1].bit_shift);
    try std.testing.expectEqual(@as(?u8, 16), bs.fields[1].bit_count);
}

test "array of non-packable type in bitstruct emits error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // [4]*u8 contains pointers which have no fixed bit size.
    const source =
        \\bitstruct Bad : u32 {
        \\    field ptrs: [4]*u8;
        \\}
    ;
    const result = parse_and_analyze(allocator, source);
    try std.testing.expectError(error.AnalysisFailed, result);
}
