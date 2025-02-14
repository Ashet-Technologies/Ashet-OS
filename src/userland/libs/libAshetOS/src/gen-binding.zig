const std = @import("std");
const abi_schema = @import("abi-schema");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len != 4) {
        @panic("gen-binding <in json file> <abi path> <out zig out>");
    }

    const abs_abi_dir_path = argv[2];
    std.debug.assert(std.fs.path.isAbsolute(abs_abi_dir_path));

    const output_dir_path = argv[3];

    var output_dir = try std.fs.cwd().openDir(output_dir_path, .{});
    defer output_dir.close();

    var src_dir = try output_dir.makeOpenPath("src", .{});
    defer src_dir.close();

    const json_txt = try std.fs.cwd().readFileAlloc(allocator, argv[1], 1 << 30);

    const schema = try abi_schema.Document.from_json_str(
        allocator,
        json_txt,
    );

    const document = schema.value;

    var syscall_files = std.ArrayList([]const u8).init(allocator);

    for (document.syscalls) |syscall| {
        const filename = try std.fmt.allocPrint(allocator, "{s}.S", .{syscall.value.Function.key});

        var impl_file = try src_dir.createFile(filename, .{});
        defer impl_file.close();

        try render_syscall_object(
            impl_file.writer(),
            syscall,
        );

        try syscall_files.append(filename);
    }

    {
        const abi_relative_path = try std.fs.path.relative(allocator, output_dir_path, abs_abi_dir_path);

        var file = try output_dir.createFile("build.zig.zon", .{});
        defer file.close();

        const writer = file.writer();

        try writer.print(
            \\.{{
            \\  .version = "1.0.0",
            \\  .name = "libAshetOS.generated",
            \\  .dependencies = .{{
            \\      .abi = .{{
            \\          .path = "{}",
            \\      }}
            \\  }},
            \\  .paths = .{{"."}},
            \\}}
            \\
        , .{
            std.zig.fmtEscapes(abi_relative_path),
        });
    }

    {
        var file = try output_dir.createFile("build.zig", .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll(
            \\const std = @import("std");
            \\const ashet_abi = @import("abi");
            \\
            \\pub fn build(b: *std.Build) void {
            \\    const ashet_target = b.option(ashet_abi.Platform, "target", "Which platform to build").?;
            \\
            \\    const zig_target: std.Build.ResolvedTarget = ashet_target.resolve_target(b);
            \\
            \\    const libsyscall = b.addStaticLibrary(.{
            \\        .name = "AshetOS",
            \\        .target = zig_target,
            \\        .optimize = .ReleaseSmall,
            \\        .root_source_file = null,
            \\        .pic = true,
            \\    });
            \\    libsyscall.pie = true;
            \\
            \\    switch(ashet_target) {
            \\        .arm => libsyscall.root_module.addCMacro("PLATFORM_THUMB", "1"),
            \\        .rv32 => libsyscall.root_module.addCMacro("PLATFORM_RISCV32", "1"),
            \\        .x86 => libsyscall.root_module.addCMacro("PLATFORM_X86", "1"),
            \\    }
            \\
            \\
        );

        for (syscall_files.items) |filename| {
            try writer.print(
                \\    libsyscall.root_module.addAssemblyFile(b.path("src/{s}"));
                \\
            , .{filename});
        }

        try writer.writeAll(
            \\    b.installArtifact(libsyscall);
            \\}
            \\
        );
    }

    return 0;
}

fn render_syscall_object(writer: std.fs.File.Writer, syscall: abi_schema.Declaration) !void {
    const function: *const abi_schema.Function = &syscall.value.Function;
    try writer.print(
        \\//
        \\// Dynamic Glue Veneer of AshetOS syscall {[name]s}
        \\//
        \\
        \\#define SYSCALL_NAME {[name]s}
        \\#define SYMBOL_NAME ashet_{[name]s}
        \\
        \\
    , .{ .name = function.key });

    try writer.writeAll(@embedFile("binding-template.S"));
}

// fn render_document(writer: std.ArrayList(u8).Writer, document: abi_schema.Document) !void {
//     try writer.writeAll(
//         \\const std = @import("std");
//         \\const builtin = @import("builtin");
//         \\
//         \\const Arch = enum { thumb, x86, riscv32 };
//         \\const target_arch: Arch = @field(Arch, @tagName(builtin.cpu.arch));
//         \\
//     );
//     for (document.syscalls) |syscall| {
//         try writer.writeAll("\n");

//         // try writer.print("export fn {}() callconv(.C) void {{\n", .{
//         //     std.zig.fmtId(function.key),
//         // });

//         try writer.print(
//             @embedFile("./binding-template.zig"),
//             .{
//                 .name = function.key,
//             },
//         );

//         // try writer.writeAll("}\n");

//         // std.debug.print("{s} {s}\n", .{ syscall.name, function.key });

//         try writer.writeAll("\n");
//     }
// }
