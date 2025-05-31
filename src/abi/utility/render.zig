const std = @import("std");
const abi_schema = @import("abi-schema");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len != 4)
        @panic("<exe> <mode> <input> <output>");

    const json_txt = try std.fs.cwd().readFileAlloc(allocator, argv[1], 1 << 30);

    const schema = try abi_schema.Document.from_json_str(
        allocator,
        json_txt,
    );

    const document = schema.value;

    _ = document;
}
