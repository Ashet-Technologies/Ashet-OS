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

test "optional fnptr parameter passes through to native params" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\typedef Callback = fnptr() void;
        \\syscall do_thing {
        \\    in cb: ?Callback;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.syscalls.len);
    const sc = doc.syscalls[0];
    // The optional fnptr should pass through to native_inputs unchanged.
    try std.testing.expectEqual(@as(usize, 1), sc.native_inputs.len);
    try std.testing.expectEqualStrings("cb", sc.native_inputs[0].name);
}

test "optional u32 parameter emits error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\syscall bad_call {
        \\    in x: ?u32;
        \\}
    ;
    const result = parse_and_analyze(allocator, source);
    try std.testing.expectError(error.AnalysisFailed, result);
}
