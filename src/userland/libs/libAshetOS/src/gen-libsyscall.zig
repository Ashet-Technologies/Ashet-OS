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

    var syscall_files: std.ArrayList([]const u8) = .empty;
    defer syscall_files.deinit(allocator);

    for (document.syscalls) |syscall| {
        const filename = try std.fmt.allocPrint(
            allocator,
            "{f}.S",
            .{fmt_fqn(syscall.full_qualified_name, "_")},
        );

        var impl_file = try src_dir.createFile(filename, .{});
        defer impl_file.close();

        var impl_buff: [1024]u8 = undefined;
        var impl_writer = impl_file.writer(&impl_buff);

        try render_syscall_object(
            &impl_writer.interface,
            syscall,
        );
        try impl_writer.interface.flush();

        try syscall_files.append(allocator, filename);
    }

    {
        var file = try output_dir.createFile("assembly-files.rsp", .{});
        defer file.close();

        var file_writer = file.writer(&.{});
        const writer = &file_writer.interface;
        for (syscall_files.items) |filename| {
            try writer.print("{s}/src/{s}\n", .{ output_dir_path, filename });
        }
        try writer.flush();
    }

    return 0;
}

fn render_syscall_object(writer: *std.Io.Writer, syscall: abi_parser.GenericCall) !void {
    try writer.print(
        \\//
        \\// Dynamic Glue Veneer of AshetOS syscall {[name_dot]f}
        \\//
        \\
        \\#define SYSCALL_NAME {[name]f}
        \\#define SYMBOL_NAME ashet_syscalls_{[name]f}
        \\
        \\
    , .{
        .name = fmt_fqn(syscall.full_qualified_name, "_"),
        .name_dot = fmt_fqn(syscall.full_qualified_name, null),
    });

    try writer.writeAll(@embedFile("binding-template.S"));
}

fn fmt_fqn(fqn: []const []const u8, sep: ?[]const u8) FqnFmt {
    return .{
        .fqn = fqn,
        .sep = sep orelse ".",
    };
}

const FqnFmt = struct {
    fqn: []const []const u8,
    sep: []const u8,

    pub fn format(self: FqnFmt, w: *std.Io.Writer) !void {
        for (self.fqn, 0..) |name, i| {
            if (i > 0) {
                try w.writeAll(self.sep);
            }
            try w.writeAll(name);
        }
    }
};
