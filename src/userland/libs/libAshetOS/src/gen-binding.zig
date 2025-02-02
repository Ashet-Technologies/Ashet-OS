const std = @import("std");
const abi_schema = @import("abi-schema");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len != 3) {
        @panic("gen-binding <in json file> <out zig out>");
    }

    const json_txt = try std.fs.cwd().readFileAlloc(allocator, argv[1], 1 << 30);

    const schema = try abi_schema.Document.from_json_str(
        allocator,
        json_txt,
    );

    const document = schema.value;

    var array = std.ArrayList(u8).init(allocator);

    try render_document(array.writer(), document);

    const zig_src_raw = try array.toOwnedSliceSentinel(0);

    const zig_ast = try std.zig.Ast.parse(allocator, zig_src_raw, .zig);
    if (zig_ast.errors.len > 0) {
        for (zig_ast.errors) |err| {
            try zig_ast.renderError(err, std.io.getStdErr().writer());
        }
        return 1;
    }

    const zig_src = try std.zig.Ast.render(zig_ast, allocator);

    {
        var file = try std.fs.cwd().createFile(argv[2], .{});
        defer file.close();

        try file.writeAll(zig_src);
    }

    return 0;
}

fn render_document(writer: std.ArrayList(u8).Writer, document: abi_schema.Document) !void {
    try writer.writeAll(
        \\const std = @import("std");
        \\const builtin = @import("builtin");
        \\
        \\const Arch = enum { thumb, x86, riscv32 };
        \\const target_arch: Arch = @field(Arch, @tagName(builtin.cpu.arch));
        \\
    );
    for (document.syscalls) |syscall| {
        try writer.writeAll("\n");

        const function: *const abi_schema.Function = &syscall.value.Function;

        // try writer.print("export fn {}() callconv(.C) void {{\n", .{
        //     std.zig.fmtId(function.key),
        // });

        try writer.print(
            @embedFile("./binding-template.zig"),
            .{
                .name = function.key,
            },
        );

        // try writer.writeAll("}\n");

        // std.debug.print("{s} {s}\n", .{ syscall.name, function.key });

        try writer.writeAll("\n");
    }
}
