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

fn find_fnptr(doc: abi_parser.model.Document) ?abi_parser.model.FunctionPointer {
    for (doc.types) |t| {
        switch (t) {
            .fnptr => |fp| return fp,
            else => {},
        }
    }
    return null;
}

test "named parameters in fnptr are stored" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\typedef Handler = fnptr(context: *u8, value: u32) void;
    ;
    const doc = try parse_and_analyze(allocator, source);
    const fp = find_fnptr(doc) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), fp.parameters.len);
    try std.testing.expectEqualStrings("context", fp.parameters[0].name.?);
    try std.testing.expectEqualStrings("value", fp.parameters[1].name.?);
}

test "unnamed parameters in fnptr store null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\typedef Callback = fnptr(*u8, u32) void;
    ;
    const doc = try parse_and_analyze(allocator, source);
    const fp = find_fnptr(doc) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), fp.parameters.len);
    try std.testing.expectEqual(@as(?[]const u8, null), fp.parameters[0].name);
    try std.testing.expectEqual(@as(?[]const u8, null), fp.parameters[1].name);
}

test "mixed named and unnamed parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\typedef Mixed = fnptr(ctx: *u8, u32) void;
    ;
    const doc = try parse_and_analyze(allocator, source);
    const fp = find_fnptr(doc) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), fp.parameters.len);
    try std.testing.expectEqualStrings("ctx", fp.parameters[0].name.?);
    try std.testing.expectEqual(@as(?[]const u8, null), fp.parameters[1].name);
}

test "fnptr with no parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source =
        \\typedef Thunk = fnptr() void;
    ;
    const doc = try parse_and_analyze(allocator, source);
    const fp = find_fnptr(doc) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 0), fp.parameters.len);
}
