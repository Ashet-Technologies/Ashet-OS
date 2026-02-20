const std = @import("std");
const schema = @import("schema.zig");

const c = @cImport({
    @cInclude("stb_truetype.h");
});

pub fn validate(font: schema.TtfFontFile) !bool {
    var ok = true;

    if (font.file.len == 0) {
        std.log.warn("Font is missing file path.", .{});
        ok = false;
    }
    if (font.line_height == 0) {
        std.log.warn("Font has zero line height.", .{});
        ok = false;
    }

    return ok;
}

pub fn generate(
    allocator: std.mem.Allocator,
    file_writer: *std.fs.File.Writer,
    root_dir: std.fs.Dir,
    font: *schema.TtfFontFile,
) !void {
    const ttf_data = try root_dir.readFileAlloc(allocator, font.file, 1 * 1024 * 1024);
    defer allocator.free(ttf_data);

    var ttf: c.stbtt_fontinfo = undefined;

    const ttf_offset = c.stbtt_GetFontOffsetForIndex(ttf_data.ptr, font.font_index);
    if (ttf_offset < 0)
        return error.InvalidFontIndex;

    if (c.stbtt_InitFont(&ttf, ttf_data.ptr, ttf_offset) == 0)
        return error.InvalidFontFile;

    const scale: f32 = c.stbtt_ScaleForPixelHeight(&ttf, @floatFromInt(font.line_height));

    var utf8: std.unicode.Utf8View = try .init(font.glyphs);

    var iter = utf8.iterator();
    while (iter.nextCodepoint()) |codepoint| {
        const glyph = c.stbtt_FindGlyphIndex(&ttf, codepoint);
        if (glyph == 0) {
            std.log.err("missing codepoint: U+0x{X:0>4}", .{codepoint});
            return error.MissingCodepoint;
        }
        std.debug.assert(glyph > 0);

        if (c.stbtt_IsGlyphEmpty(&ttf, glyph) != 0) {
            std.log.warn("TODO: empty codepoint: U+0x{X:0>4}", .{codepoint});
            continue;
        }

        var c_width: c_int = 0;
        var c_height: c_int = 0;
        var c_xoff: c_int = 0;
        var c_yoff: c_int = 0;

        const bitmap = c.stbtt_GetGlyphBitmap(&ttf, scale, scale, glyph, &c_width, &c_height, &c_xoff, &c_yoff) orelse return error.OutOfMemory;
        defer c.stbtt_FreeBitmap(bitmap, null);

        const width = std.math.cast(u16, c_width) orelse return error.InvalidSize;
        const height = std.math.cast(u16, c_height) orelse return error.InvalidSize;
        const xoff = std.math.cast(i16, c_xoff) orelse return error.InvalidSize;
        const yoff = std.math.cast(i16, c_yoff) orelse return error.InvalidSize;

        std.log.info("codepoint: U+0x{X:0>4} ({},{})+({},{})", .{
            codepoint,
            xoff,
            yoff,
            width,
            height,
        });

        for (0..height) |y| {
            for (0..width) |x| {
                std.debug.print("{c}", .{
                    " .:ioVM@"[bitmap[y * width + x] >> 5],
                });
            }
            std.debug.print("\n", .{});
        }
    }

    try file_writer.interface.writeAll("hello");

    @panic("not implemented yet");
}
