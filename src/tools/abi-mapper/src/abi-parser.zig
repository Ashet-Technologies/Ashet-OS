const std = @import("std");
const args_parser = @import("args");

pub const syntax = @import("syntax.zig");
pub const model = @import("model.zig");
pub const sema = @import("sema.zig");
pub const doc_comment = @import("doc_comment.zig");

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
            std.log.err("unexpected token at {f}: found {f}", .{
                bad_token.location,
                bad_token,
            });
        }
        if (err == error.UnexpectedToken)
            return 1;
        return err;
    };

    const analyzed_document: model.Document = try sema.analyze(allocator, ast_document);

    var atomic_buffer: [4096]u8 = undefined;
    var atomic_output = try std.fs.cwd().atomicFile(
        args.options.output,
        .{ .write_buffer = &atomic_buffer },
    );
    defer atomic_output.deinit();
    {
        const output_writer = &atomic_output.file_writer.interface;

        try model.to_json_str(analyzed_document, output_writer);

        try output_writer.flush();
    }

    try atomic_output.finish();

    return 0;
}
