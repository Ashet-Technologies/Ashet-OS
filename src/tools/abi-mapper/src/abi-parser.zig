const std = @import("std");
const args_parser = @import("args");

pub const syntax = @import("syntax.zig");
pub const model = @import("model.zig");
pub const sema = @import("sema.zig");
pub const doc_comment = @import("doc_comment.zig");

const CliOptions = struct {
    output: []const u8 = "",
    @"id-db": []const u8 = "",
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var args = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer args.deinit();

    if (args.positionals.len != 1) {
        std.debug.print("expects exactly one positional argument, found {}\n", .{args.positionals.len});
        std.debug.print("usage: abi-mapper [--id-db <path>] --output <abi.json> <input.abi>\n", .{});
        return 1;
    }

    if (args.options.output.len == 0) {
        std.debug.print("missing argument: --output <abi.json>\n", .{});
        std.debug.print("usage: abi-mapper [--id-db <path>] --output <abi.json> <input.abi>\n", .{});
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

    // Load UID database if --id-db was specified
    const id_db_path = args.options.@"id-db";
    var uid_database: ?sema.uid_db.UidDatabase = if (id_db_path.len > 0)
        try sema.uid_db.UidDatabase.load(allocator, id_db_path)
    else
        null;
    defer if (uid_database) |*db| db.deinit();

    var analysis_errors: std.ArrayList(sema.AnalysisError) = .empty;
    defer analysis_errors.deinit(allocator);

    const analyzed_document: model.Document = sema.analyze(
        allocator,
        ast_document,
        if (uid_database != null) &uid_database.? else null,
        &analysis_errors,
    ) catch |err| {
        for (analysis_errors.items) |ae| {
            std.log.err("{s}", .{ae.message});
        }
        return err;
    };

    // Save UID database back if it was loaded
    if (uid_database != null and id_db_path.len > 0) {
        try uid_database.?.save(id_db_path);
    }

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
