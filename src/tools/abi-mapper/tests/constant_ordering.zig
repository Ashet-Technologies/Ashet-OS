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

test "constant used as array size after definition succeeds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Constant defined before the struct that uses it.
    const source =
        \\const max_len = 8;
        \\struct Buffer {
        \\    field data: [max_len]u8;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.structs.len);
    // The field's type is an array with size 8
    const fld = doc.structs[0].logic_fields[0];
    const fld_type = doc.get_type(fld.type);
    try std.testing.expect(fld_type.* == .array);
    try std.testing.expectEqual(@as(u32, 8), fld_type.array.size);
}

test "constant used as array size before definition emits error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Struct references constant that isn't declared yet.
    const source =
        \\struct Buffer {
        \\    field data: [max_len]u8;
        \\}
        \\const max_len = 8;
    ;
    const result = parse_and_analyze(allocator, source);
    try std.testing.expectError(error.AnalysisFailed, result);
}
