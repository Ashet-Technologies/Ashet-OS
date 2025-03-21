const std = @import("std");

const parse_options: std.json.ParseOptions = .{
    .allocate = .alloc_always,
    .ignore_unknown_fields = false,
};

pub fn load(allocator: std.mem.Allocator, text: []const u8) !Document {
    var result: Document = .{
        .parsed = try std.json.parseFromSlice(
            JsonRootNode,
            allocator,
            text,
            parse_options,
        ),
        .data = undefined,
    };
    errdefer result.parsed.deinit();

    result.data = switch (result.parsed.value) {
        .turtle => |value| .{ .turtle = value },
        .bitmap => |bitmap| .{
            .bitmap = .{
                .line_height = bitmap.line_height,
                .defaults = bitmap.defaults,
                .glyphs = try transform_glyph_map(result.parsed.arena.allocator(), bitmap.glyphs),
            },
        },
    };

    return result;
}

pub const Document = struct {
    parsed: std.json.Parsed(JsonRootNode),

    data: Body,

    pub fn deinit(doc: *Document) void {
        doc.parsed.deinit();
        doc.* = undefined;
    }
};

pub const Body = union(enum) {

    // Contains a bitmap font composed of one or more image files
    bitmap: BitmapFontFile,

    // Just a file path, turtle fonts are self-contained
    turtle: []const u8,
};

pub const BitmapFontFile = struct {
    line_height: u8,
    defaults: Glyph = .{},
    glyphs: std.AutoArrayHashMap(u21, Glyph),

    pub const Glyph = struct {
        image_file: ?[]const u8 = null,
        advance: ?u8 = null,
        atlas: ?Atlas = null,
        index: ?usize = null,
        select_pixels: ?SelectPixel = null,
    };

    pub const Atlas = struct {
        margin: u16,
        offset_x: u16,
        offset_y: u16,
        cell_width: u16,
        cell_height: u16,
        cell_padding: u16,
        row_length: u16,
    };

    pub const SelectPixel = enum {
        @"opaque",
        white,
        black,
    };
};

const JsonRootNode = union(enum) {
    // Contains a bitmap font composed of one or more image files
    bitmap: JsonBitmapFontFile,

    // Just a file path, turtle fonts are self-contained
    turtle: []const u8,
};

const JsonBitmapFontFile = struct {
    line_height: u8,
    defaults: BitmapFontFile.Glyph = .{},
    glyphs: std.json.Value,
};

fn transform_glyph_map(allocator: std.mem.Allocator, raw_map: std.json.Value) !std.AutoArrayHashMap(u21, BitmapFontFile.Glyph) {
    if (raw_map != .object)
        return error.InvalidGlyphObject;

    const map = &raw_map.object;

    var output: std.AutoArrayHashMap(u21, BitmapFontFile.Glyph) = .init(allocator);
    errdefer output.deinit();

    var iter = map.iterator();
    while (iter.next()) |kv| {
        const key_str = kv.key_ptr.*;
        const json_value = kv.value_ptr.*;

        if ((std.unicode.utf8CountCodepoints(key_str) catch 0) != 1) {
            std.log.err("invalid glyph codepoint: '{}' ({})", .{
                std.unicode.fmtUtf8(key_str),
                std.fmt.fmtSliceHexUpper(key_str),
            });
            return error.InvalidKey;
        }

        const codepoint: u21 = try std.unicode.utf8Decode(key_str);
        if (!std.unicode.utf8ValidCodepoint(codepoint)) {
            return error.InvalidCodePoint;
        }

        const glyph = try std.json.parseFromValueLeaky(
            BitmapFontFile.Glyph,
            allocator,
            json_value,
            parse_options,
        );

        const gop = try output.getOrPut(codepoint);
        if (gop.found_existing) {
            std.log.err("duplicate glyph codepoint: '{}' ({})", .{
                std.unicode.fmtUtf8(key_str),
                std.fmt.fmtSliceHexUpper(key_str),
            });
            return error.DuplicateKey;
        }
        gop.value_ptr.* = glyph;
    }

    return output;
}
