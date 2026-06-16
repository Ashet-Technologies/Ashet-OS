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

test "struct with undefined field type emits error without crashing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // References a type that does not exist — should produce an error, not a panic.
    const source =
        \\struct Broken {
        \\    field x: NonExistentType;
        \\    field y: u32;
        \\}
    ;
    const result = parse_and_analyze(allocator, source);
    try std.testing.expectError(error.AnalysisFailed, result);
}
