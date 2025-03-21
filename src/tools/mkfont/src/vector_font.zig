const std = @import("std");
const schema = @import("schema.zig");
const turtlefont = @import("turtlefont");

pub fn validate(font: schema.TurtleFontFile) !bool {
    var ok = true;

    for (0x20..0x7F) |codepoint| {
        const ascii: u7 = @intCast(codepoint);
        if (!font.glyphs.contains(ascii)) {
            std.log.warn("Font is missing printable ASCII character '{}' (0x{X:0>2})", .{
                std.zig.fmtEscapes(&.{ascii}),
                ascii,
            });
        }
    }

    for (font.glyphs.keys(), font.glyphs.values()) |codepoint, glyph| {
        _ = turtlefont.FontCompiler.compileGlyphScript(glyph.script, std.io.null_writer) catch |err| {
            ok = false;

            var cpname: [8]u8 = undefined;
            const len = try std.unicode.utf8Encode(codepoint, &cpname);

            std.log.warn("Bad glyph script for codepoint U+{X:0>5} ('{}'): {}", .{
                codepoint,
                std.unicode.fmtUtf8(cpname[0..len]),
                err,
            });
        };
    }

    return ok;
}

pub fn generate(
    allocator: std.mem.Allocator,
    file: std.fs.File,
    root_dir: std.fs.Dir,
    font: *schema.TurtleFontFile,
) !void {
    _ = allocator;
    _ = root_dir;

    // Glyphs must be sorted in the font:
    font.glyphs.sort(struct {
        glyphs: *std.AutoArrayHashMap(u21, schema.TurtleFontFile.Glyph),
        pub fn lessThan(self: @This(), lhs_index: usize, rhs_index: usize) bool {
            return self.glyphs.keys()[lhs_index] < self.glyphs.keys()[rhs_index];
        }
    }{
        .glyphs = &font.glyphs,
    });

    var buffered_writer = std.io.bufferedWriter(file.writer());
    const writer = buffered_writer.writer();

    // Glyphs:
    try writer.writeInt(u32, 0x4c2b8688, .little);
    try writer.writeInt(u32, @intCast(font.glyphs.count()), .little);

    var run_offset: u32 = 0;

    for (font.glyphs.keys(), font.glyphs.values()) |codepoint, glyph| {
        var counter = std.io.countingWriter(std.io.null_writer);
        const meta = turtlefont.FontCompiler.compileGlyphScript(
            glyph.script,
            counter.writer(),
        ) catch @panic("bad validation");

        try writer.writeInt(u32, @as(u32, @bitCast(turtlefont.CodepointAdvancePair{
            .codepoint = codepoint,
            .advance = meta.advance,
        })), .little);
        try writer.writeInt(u32, run_offset, .little);

        run_offset += @as(u32, @intCast(counter.bytes_written));
    }

    for (font.glyphs.values()) |glyph| {
        _ = turtlefont.FontCompiler.compileGlyphScript(
            glyph.script,
            writer,
        ) catch @panic("bad validation");
    }

    try buffered_writer.flush();
}
