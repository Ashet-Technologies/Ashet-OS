const std = @import("std");
const abi_parser = @import("abi-parser").model;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len != 4) {
        @panic("gen-libsyscall <in json file> <abi path> <out zig out>");
    }

    const abs_abi_dir_path = argv[2];
    std.debug.assert(std.fs.path.isAbsolute(abs_abi_dir_path));

    const output_dir_path = argv[3];

    var output_dir = try std.fs.cwd().openDir(output_dir_path, .{});
    defer output_dir.close();

    var src_dir = try output_dir.makeOpenPath("src", .{});
    defer src_dir.close();

    const json_txt = try std.fs.cwd().readFileAlloc(allocator, argv[1], 1 << 30);

    const schema = try abi_parser.from_json_str(allocator, json_txt);

    const document = schema.value;

    var syscall_files = std.ArrayList([]const u8).init(allocator);

    for (document.syscalls) |syscall| {
        const filename = try std.fmt.allocPrint(allocator, "{_}.S", .{fmt_fqn(syscall.full_qualified_name)});

        var impl_file = try src_dir.createFile(filename, .{});
        defer impl_file.close();

        try render_syscall_object(
            impl_file.writer(),
            syscall,
        );

        try syscall_files.append(filename);
    }

    {
        var file = try output_dir.createFile("assembly-files.rsp", .{});
        defer file.close();

        const writer = file.writer();
        for (syscall_files.items) |filename| {
            try writer.print("{s}/src/{s}\n", .{ output_dir_path, filename });
        }
    }

    return 0;
}

fn render_syscall_object(writer: std.fs.File.Writer, syscall: abi_parser.GenericCall) !void {
    try writer.print(
        \\//
        \\// Dynamic Glue Veneer of AshetOS syscall {[name]}
        \\//
        \\
        \\#define SYSCALL_NAME {[name]_}
        \\#define SYMBOL_NAME ashet_syscalls_{[name]_}
        \\
        \\
    , .{ .name = fmt_fqn(syscall.full_qualified_name) });

    try writer.writeAll(@embedFile("binding-template.S"));
}

fn fmt_fqn(fqn: []const []const u8) std.fmt.Formatter(format_fqn) {
    return .{ .data = fqn };
}

fn format_fqn(fqn: []const []const u8, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    for (fqn, 0..) |name, i| {
        if (i > 0) {
            try writer.writeAll(if (fmt.len > 0) fmt else ".");
        }
        try writer.writeAll(name);
    }
}
