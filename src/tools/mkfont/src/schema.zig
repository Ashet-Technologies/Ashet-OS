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
        .turtle => |vector| .{
            .turtle = .{
                .glyphs = try transform_turtle_glyph_map(result.parsed.arena.allocator(), vector.glyphs),
            },
        },
        .bitmap => |bitmap| .{
            .bitmap = .{
                .line_height = bitmap.line_height,
                .defaults = bitmap.defaults,
                .glyphs = try transform_bitmap_glyph_map(result.parsed.arena.allocator(), bitmap.glyphs),
            },
        },
        .ttf => |ttf| .{ .ttf = ttf },
        .fon => |fon| .{
            .fon = .{
                .file = fon.file,
                .id = fon.id,
                .index = fon.index,
                .encoding = try transform_encoding_map(fon.encoding),
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

    // Just an array of glyphs with TurtleFont code.
    turtle: TurtleFontFile,

    /// A TTF file
    ttf: TtfFontFile,

    /// A FON file
    fon: FonFontFile,
};

pub const TtfFontFile = struct {
    /// Path to the font file.
    file: []const u8,

    /// Index of the font inside the TTF file that shall be converted.
    font_index: u16 = 0,

    /// The line height in pixels for the output font.
    line_height: u8,

    /// A string containing the glyphs to add to the font
    /// in addition to the base ASCII subset.
    glyphs: []const u8,
};

pub const FonFontFile = struct {
    /// Path to the font file.
    file: []const u8,

    id: ?u16,
    index: ?u16,

    encoding: [256]?u21,
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

pub const TurtleFontFile = struct {
    glyphs: std.AutoArrayHashMap(u21, Glyph),

    pub const Glyph = struct {
        script: []const u8,
    };
};

const JsonRootNode = union(enum) {
    bitmap: JsonBitmapFontFile,
    turtle: JsonTurtleFontFile,
    ttf: TtfFontFile,
    fon: JsonFonFontFile,
};

pub const JsonFonFontFile = struct {
    /// Path to the font file.
    file: []const u8,

    id: ?u16 = null,

    index: ?u16 = null,

    encoding: std.json.Value,
};

const JsonBitmapFontFile = struct {
    line_height: u8,
    defaults: BitmapFontFile.Glyph = .{},
    glyphs: std.json.Value,
};

const JsonTurtleFontFile = struct {
    glyphs: std.json.Value,
};

fn transform_encoding_map(raw_map: std.json.Value) ![256]?u21 {
    if (raw_map != .object)
        return error.InvalidGlyphObject;
    const map = &raw_map.object;

    var output: [256]?u21 = @splat(null);

    var iter = map.iterator();
    while (iter.next()) |kv| {
        const key_str = kv.key_ptr.*;
        const json_value = kv.value_ptr.*;

        const index = std.fmt.parseInt(u8, key_str, 0) catch {
            std.log.err("invalid encoding index: '{}'", .{
                std.unicode.fmtUtf8(key_str),
            });
            return error.InvalidKey;
        };

        const codepoint: u21 = switch (json_value) {
            .integer => |int| std.math.cast(u21, int) orelse {
                std.log.err("codepoint out of range: {}", .{
                    int,
                });
                return error.InvalidCodePoint;
            },
            .string => |str| std.fmt.parseInt(u21, str, 0) catch {
                std.log.err("codepoint out of range: '{}'", .{
                    std.unicode.fmtUtf8(str),
                });
                return error.InvalidCodePoint;
            },
            else => {
                std.log.err("invalid codepoint: {s}", .{
                    @tagName(json_value),
                });
                return error.InvalidCodePoint;
            },
        };

        if (!std.unicode.utf8ValidCodepoint(codepoint)) {
            return error.InvalidCodePoint;
        }

        output[index] = codepoint;
    }

    return output;
}

fn transform_bitmap_glyph_map(allocator: std.mem.Allocator, raw_map: std.json.Value) !std.AutoArrayHashMap(u21, BitmapFontFile.Glyph) {
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

fn transform_turtle_glyph_map(allocator: std.mem.Allocator, raw_map: std.json.Value) !std.AutoArrayHashMap(u21, TurtleFontFile.Glyph) {
    if (raw_map != .object)
        return error.InvalidGlyphObject;

    const map = &raw_map.object;

    var output: std.AutoArrayHashMap(u21, TurtleFontFile.Glyph) = .init(allocator);
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

        if (json_value != .string)
            return error.InvalidGlyphSpec;

        const gop = try output.getOrPut(codepoint);
        if (gop.found_existing) {
            std.log.err("duplicate glyph codepoint: '{}' ({})", .{
                std.unicode.fmtUtf8(key_str),
                std.fmt.fmtSliceHexUpper(key_str),
            });
            return error.DuplicateKey;
        }

        gop.value_ptr.* = .{
            .script = json_value.string,
        };
    }

    return output;
}
