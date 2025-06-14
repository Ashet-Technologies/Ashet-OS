const std = @import("std");
const args_parser = @import("args");

const syntax = @import("syntax.zig");
const model = @import("model.zig");
const sema = @import("sema.zig");

const CliOptions = struct {
    output: []const u8 = "",
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var args = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer args.deinit();

    if (args.positionals.len != 1) {
        return 1;
    }

    if (args.options.output.len == 1) {
        return 1;
    }

    const input_text = try std.fs.cwd().readFileAlloc(
        allocator,
        args.positionals[0],
        1 << 20,
    );

    var tokenizer: syntax.Tokenizer = .init(input_text, args.positionals[0]);
    var parser: syntax.Parser = .{
        .allocator = allocator,
        .core = .init(&tokenizer),
    };

    const ast_document = parser.accept_document() catch |err| {
        if (parser.bad_token) |bad_token| {
            std.log.err("unexpected token at {}: found {}", .{
                bad_token.location,
                bad_token,
            });
        }
        return err;
    };

    const analyzed_document: model.Document = try sema.analyze(allocator, ast_document);

    var atomic_output = try std.fs.cwd().atomicFile(args.options.output, .{});
    defer atomic_output.deinit();
    {
        var buffered_writer = std.io.bufferedWriter(atomic_output.file.writer());

        try model.to_json_str(analyzed_document, buffered_writer.writer());

        try buffered_writer.flush();
    }

    try atomic_output.finish();

    return 0;
}
