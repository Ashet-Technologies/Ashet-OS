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

test "syscall with zero out params is valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\syscall do_work {
        \\    in x: u32;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.syscalls.len);
    try std.testing.expectEqual(@as(usize, 0), doc.syscalls[0].logic_outputs.len);
}

test "syscall with one out param is valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\syscall get_value {
        \\    out result: u32;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.syscalls.len);
    try std.testing.expectEqual(@as(usize, 1), doc.syscalls[0].logic_outputs.len);
}

test "syscall with two out params emits error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\syscall two_outputs {
        \\    out a: u32;
        \\    out b: u32;
        \\}
    ;
    const result = parse_and_analyze(allocator, source);
    try std.testing.expectError(error.AnalysisFailed, result);
}

test "async_call with multiple out params is valid (not a syscall)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\async_call read_data {
        \\    out bytes_read: u32;
        \\    out eof: bool;
        \\}
    ;
    const doc = try parse_and_analyze(allocator, source);
    try std.testing.expectEqual(@as(usize, 1), doc.async_calls.len);
    try std.testing.expectEqual(@as(usize, 2), doc.async_calls[0].logic_outputs.len);
}
