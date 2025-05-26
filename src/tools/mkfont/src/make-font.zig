const std = @import("std");
const args_parser = @import("args");

const schema = @import("schema.zig");
const bitmap_font = @import("bitmap_font.zig");
const vector_font = @import("vector_font.zig");

pub const CliOptions = struct {
    output: []const u8 = "",

    pub const shorthands = .{
        .o = "output",
    };
};

pub fn main() !u8 {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;

    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var cli = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli.deinit();

    if (cli.positionals.len != 1) {
        try usage_error("<font definition> must be given!");
    }

    if (cli.options.output.len == 0) {
        try usage_error("--output=<path> must be given!");
    }

    const json_source = try std.fs.cwd().readFileAlloc(allocator, cli.positionals[0], 50 * 1024 * 1024);
    defer allocator.free(json_source);

    var document = try schema.load(allocator, json_source);
    defer document.deinit();

    // Validate fonts:
    const font_ok = switch (document.data) {
        .bitmap => |bitmap| try bitmap_font.validate(bitmap),
        .turtle => |vector| try vector_font.validate(vector),
    };

    if (!font_ok) {
        return 1;
    }

    var rel_dir = try std.fs.cwd().openDir(
        std.fs.path.dirname(cli.positionals[0]) orelse ".",
        .{},
    );
    defer rel_dir.close();

    var output_file = try std.fs.cwd().atomicFile(cli.options.output, .{});
    defer output_file.deinit();

    switch (document.data) {
        .bitmap => |*bitmap| try bitmap_font.generate(allocator, output_file.file, rel_dir, bitmap),
        .turtle => |*vector| try vector_font.generate(allocator, output_file.file, rel_dir, vector),
    }

    try output_file.finish();

    return 0;
}

fn usage_error(mistake: []const u8) !noreturn {
    const stderr = std.io.getStdErr().writer();
    try stderr.print("Usage error: {s}\n", .{mistake});
    std.process.exit(1);
}
