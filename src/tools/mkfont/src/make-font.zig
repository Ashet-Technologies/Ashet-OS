const std = @import("std");
const args_parser = @import("args");

const schema = @import("schema.zig");
const bitmap_font = @import("bitmap_font.zig");
const vector_font = @import("vector_font.zig");
const fon_font = @import("fon_font.zig");
const ttf_font = @import("ttf_font.zig");

pub const CliOptions = struct {
    output: []const u8 = "",

    pub const shorthands = .{
        .o = "output",
    };
};

pub fn main(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    const io = init.io;

    var cli = args_parser.parseForCurrentProcess(CliOptions, init, .print) catch return 1;
    defer cli.deinit();

    if (cli.positionals.len != 1) {
        try usage_error("<font definition> must be given!");
    }

    if (cli.options.output.len == 0) {
        try usage_error("--output=<path> must be given!");
    }

    const json_source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        cli.positionals[0],
        allocator,
        .limited(50 * 1024 * 1024),
    );
    defer allocator.free(json_source);

    var document = try schema.load(allocator, json_source);
    defer document.deinit();

    // Validate fonts:
    const font_ok = switch (document.data) {
        .bitmap => |bitmap| try bitmap_font.validate(bitmap),
        .turtle => |vector| try vector_font.validate(vector),
        .ttf => |ttf| try ttf_font.validate(ttf),
        .fon => |fon| try fon_font.validate(fon),
    };

    if (!font_ok) {
        return 1;
    }

    var rel_dir = try std.Io.Dir.cwd().openDir(
        io,
        std.fs.path.dirname(cli.positionals[0]) orelse ".",
        .{},
    );
    defer rel_dir.close(io);

    var output_buff: [1024]u8 = undefined;
    var output_file = try std.Io.Dir.cwd().createFileAtomic(io, cli.options.output, .{ .make_path = true, .replace = true });
    defer output_file.deinit(io);
    var file_writer = output_file.file.writer(io, &output_buff);

    switch (document.data) {
        .bitmap => |*data| try bitmap_font.generate(allocator, io, &file_writer, rel_dir, data),
        .turtle => |*data| try vector_font.generate(allocator, &file_writer, rel_dir, data),
        .ttf => |*data| try ttf_font.generate(allocator, io, &file_writer, rel_dir, data),
        .fon => |*data| try fon_font.generate(allocator, io, &file_writer, rel_dir, data),
    }

    try file_writer.flush();

    try output_file.replace(io);

    return 0;
}

fn usage_error(mistake: []const u8) !noreturn {
    // var stderr = std.fs.File.stderr().writer(&.{});
    std.debug.print("Usage error: {s}\n", .{mistake});
    std.process.exit(1);
}
