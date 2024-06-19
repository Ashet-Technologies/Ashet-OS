const std = @import("std");
const ashet = @import("ashet");
const turtlefont = @import("turtlefont");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

const fonts = @import("fonts.zig");

const Bitmap = @import("Bitmap.zig");
const Font = fonts.Font;
const BitmapFont = fonts.BitmapFont;
const VectorFont = fonts.VectorFont;

const Framebuffer = @This();

width: u15, // width of the image
height: u15, // height of the image
stride: u32, // row length in pixels
pixels: [*]ColorIndex, // height * stride pixels

/// Creates a framebuffer for the given window.
/// Drawing into the framebuffer will draw to the window surface.
pub fn forWindow(window: *const ashet.abi.Window) Framebuffer {
    return Framebuffer{
        .width = @as(u15, @intCast(window.client_rectangle.width)),
        .height = @as(u15, @intCast(window.client_rectangle.height)),
        .stride = window.stride,
        .pixels = window.pixels,
    };
}

/// Converts the framebuffer into a Bitmap that can be blit into another framebuffer
pub fn toBitmap(fb: Framebuffer) Bitmap {
    return Bitmap{
        .width = fb.width,
        .height = fb.height,
        .stride = fb.stride,
        .pixels = fb.pixels,
    };
}

/// Returns a view into the framebuffer. The returned framebuffer
/// is an alias for the given `rect` inside the bigger framebuffer.
/// This is useful to enable a clip rectangle or a local coordinate system.
pub fn view(fb: Framebuffer, rect: Rectangle) Framebuffer {
    const cliprect = fb.clip(rect);
    return Framebuffer{
        .pixels = cliprect.pixels,
        .width = cliprect.width,
        .height = cliprect.height,
        .stride = fb.stride,
    };
}

const ScreenRect = struct {
    dx: u16,
    dy: u16,
    x: i16,
    y: i16,
    pixels: [*]ColorIndex,
    width: u15,
    height: u15,

    pub const empty = ScreenRect{
        .dx = 0,
        .dy = 0,
        .x = 0,
        .y = 0,
        .pixels = undefined,
        .width = 0,
        .height = 0,
    };
};

/// Computes the actual portion of the given rectangle inside the framebuffer.
pub fn clip(fb: Framebuffer, rect: Rectangle) ScreenRect {
    if (rect.x >= fb.width or rect.y >= fb.height) {
        return ScreenRect.empty;
    }
    if (rect.x + @as(u15, @intCast(rect.width)) < 0 or rect.y + @as(u15, @intCast(rect.height)) < 0) {
        return ScreenRect.empty;
    }

    var width: u16 = rect.width;
    var height: u16 = rect.height;

    width -|= @as(u16, @intCast(@max(0, -rect.x)));
    height -|= @as(u16, @intCast(@max(0, -rect.y)));

    const x = @as(u15, @intCast(@max(0, rect.x)));
    const y = @as(u15, @intCast(@max(0, rect.y)));

    if (x + width > fb.width) {
        width = (fb.width -| x);
    }
    if (y + height > fb.height) {
        height = (fb.height -| y);
    }

    const result = ScreenRect{
        .dx = @as(u16, @intCast(x - rect.x)),
        .dy = @as(u16, @intCast(y - rect.y)),
        .x = x,
        .y = y,
        .pixels = fb.pixels + @as(usize, y) * fb.stride + @as(usize, x),
        .width = @as(u15, @intCast(width)),
        .height = @as(u15, @intCast(height)),
    };
    // std.log.debug("clip {} to {}", .{ rect, result });
    return result;
}

// draw commands:

pub fn clear(fb: Framebuffer, color: ColorIndex) void {
    var row = fb.pixels;
    var y: usize = 0;
    while (y < fb.height) : (y += 1) {
        @memset(row[0..fb.width], color);
        row += fb.stride;
    }
}

pub fn fillRectangle(fb: Framebuffer, rect: Rectangle, color: ColorIndex) void {
    var dst = fb.clip(rect);
    while (dst.height > 0) {
        dst.height -= 1;
        for (dst.pixels[0..dst.width]) |*c| {
            c.* = color;
        }
        dst.pixels += fb.stride;
    }
}

pub fn drawRectangle(fb: Framebuffer, rect: Rectangle, color: ColorIndex) void {
    const dst = fb.clip(rect);

    var top = dst.pixels;
    var bot = dst.pixels + (dst.height -| 1) * fb.stride;

    var x: u16 = 0;
    while (x < dst.width) : (x += 1) {
        if (dst.dy == 0) top[0] = color;
        if (dst.y + dst.height == rect.bottom()) bot[0] = color;
        top += 1;
        bot += 1;
    }

    var left = dst.pixels;
    var right = dst.pixels + (dst.width -| 1);

    var y: u16 = 0;
    while (y < dst.height) : (y += 1) {
        if (dst.dx == 0) left[0] = color;
        if (dst.x + dst.width == rect.right()) right[0] = color;
        left += fb.stride;
        right += fb.stride;
    }
}

pub fn setPixel(fb: Framebuffer, x: i16, y: i16, color: ColorIndex) void {
    if (x < 0 or x >= fb.width)
        return;
    if (y < 0 or y >= fb.height)
        return;
    fb.pixels[@as(usize, @intCast(y)) * fb.stride + @as(usize, @intCast(x))] = color;
}

pub fn drawLine(fb: Framebuffer, from: Point, to: Point, color: ColorIndex) void {
    if (from.y == to.y) {
        if (from.y < 0 or from.y >= fb.height)
            return;
        // horizontal
        const start = @max(0, @min(from.x, to.x)); // inclusive
        const end = @min(fb.width, @max(from.x, to.x) + 1); // exlusive

        if (end < start)
            return;

        @memset((fb.pixels + @as(usize, @intCast(from.y)) * fb.stride)[@as(usize, @intCast(start))..@as(usize, @intCast(end))], color);
    } else if (from.x == to.x) {
        // vertical
        if (from.x < 0 or from.x >= fb.width)
            return;

        const start = @max(0, @min(from.y, to.y)); // inclusive
        const end = @min(fb.height, @max(from.y, to.y) + 1); // exlusive

        if (end < start)
            return;

        var row = fb.pixels + @as(usize, @intCast(from.x)) + @as(usize, @intCast(start)) * fb.stride;
        var y: usize = @as(usize, @intCast(start));
        while (y < end) : (y += 1) {
            row[0] = color;
            row += fb.stride;
        }
    } else {
        // not an axis aligned line, use bresenham

        const H = struct {
            fn abs(a: i16) i16 {
                return if (a < 0) -a else a;
            }
        };

        var x0 = from.x;
        var y0 = from.y;

        const x1 = to.x;
        const y1 = to.y;

        // Implementation taken from
        // https://de.wikipedia.org/wiki/Bresenham-Algorithmus#Kompakte_Variante
        // That means that the following code block is licenced under CC-BY-SA
        // which is compatible to the project licence.
        {
            const dx = H.abs(x1 - x0);
            const sx: i2 = if (x0 < x1) 1 else -1;
            const dy = -H.abs(y1 - y0);
            const sy: i2 = if (y0 < y1) 1 else -1;
            var err = dx + dy;
            var e2: i16 = undefined;

            while (true) {
                fb.setPixel(x0, y0, color);
                if (x0 == x1 and y0 == y1) break;
                e2 = 2 * err;
                if (e2 > dy) { // e_xy+e_x > 0
                    err += dy;
                    x0 += sx;
                }
                if (e2 < dx) { // e_xy+e_y < 0
                    err += dx;
                    y0 += sy;
                }
            }
        }
        // regular licence continues here
    }
}

pub const ScreenWriter = struct {
    pub const Error = error{InvalidUtf8};
    pub const Writer = std.io.Writer(*ScreenWriter, Error, write);

    const VectorRasterizer = turtlefont.Rasterizer(*ScreenWriter, ColorIndex, writeVectorPixel);

    fb: Framebuffer,
    dx: i16,
    dy: i16,
    color: ColorIndex,
    limit: u15, // only render till this column (exclusive)
    font: *const Font,

    pub fn writer(sw: *ScreenWriter) Writer {
        return Writer{ .context = sw };
    }

    fn write(sw: *ScreenWriter, text: []const u8) Error!usize {
        if (sw.dx >= sw.limit)
            return text.len;

        var utf8_view = try std.unicode.Utf8View.init(text);
        var codepoints = utf8_view.iterator();

        switch (sw.font.*) {
            .bitmap => |bitmap_font| {
                const fallback_glyph = bitmap_font.getGlyph('�') orelse bitmap_font.getGlyph('?');

                render_loop: while (codepoints.nextCodepoint()) |char| {
                    if (sw.dx >= sw.limit) {
                        break;
                    }
                    const glyph: BitmapFont.Glyph = bitmap_font.getGlyph(char) orelse fallback_glyph orelse continue;

                    if (sw.dx + glyph.advance >= 0) {
                        var data_ptr = glyph.bits.ptr;

                        var gx: u15 = 0;
                        while (gx < glyph.width) : (gx += 1) {
                            if (sw.dx + gx > sw.limit) {
                                break :render_loop;
                            }

                            var bits: u8 = undefined;

                            var gy: u15 = 0;
                            while (gy < glyph.height) : (gy += 1) {
                                if ((gy % 8) == 0) {
                                    bits = data_ptr[0];
                                    data_ptr += 1;
                                }

                                if ((bits & (@as(u8, 1) << @as(u3, @truncate(gy)))) != 0) {
                                    sw.fb.setPixel(sw.dx + glyph.offset_x + gx, sw.dy + glyph.offset_y + gy, sw.color);
                                }
                            }
                        }
                    }

                    sw.dx += glyph.advance;
                }
            },
            .vector => |vector_font| {
                const fallback_glyph = vector_font.getGlyph('�') orelse vector_font.getGlyph('?');

                const rast = VectorRasterizer.init(sw);

                const options = vector_font.getTurtleOptions();

                while (codepoints.nextCodepoint()) |char| {
                    if (sw.dx >= sw.limit) {
                        break;
                    }
                    const glyph: VectorFont.Glyph = vector_font.getGlyph(char) orelse fallback_glyph orelse continue;

                    const advance = options.scaleX(glyph.advance);

                    if (sw.dx + advance >= 0) {
                        rast.renderGlyph(
                            options,
                            sw.dx,
                            sw.dy + vector_font.size,
                            sw.color,
                            vector_font.turtle_font.getCode(glyph),
                        );
                    }

                    sw.dx += advance;
                    sw.dx += @intFromBool(vector_font.bold);
                }
            },
        }

        return text.len;
    }

    fn writeVectorPixel(sw: *ScreenWriter, x: i16, y: i16, color: ColorIndex) void {
        sw.fb.setPixel(x, y, color);
    }
};

pub fn screenWriter(fb: Framebuffer, x: i16, y: i16, font: *const Font, color: ColorIndex, max_width: ?u15) ScreenWriter {
    const limit = @as(u15, @intCast(if (max_width) |mw|
        @as(u15, @intCast(@max(0, x + mw)))
    else
        fb.width));

    return ScreenWriter{
        .fb = fb,
        .dx = x,
        .dy = y,
        .color = color,
        .limit = limit,
        .font = font,
    };
}

pub fn drawString(fb: Framebuffer, x: i16, y: i16, text: []const u8, font: *const Font, color: ColorIndex, limit: ?u15) void {
    var sw = fb.screenWriter(x, y, font, color, limit);
    sw.writer().writeAll(text) catch {};
}

pub fn blit(fb: Framebuffer, point: Point, bitmap: Bitmap) void {
    const target = fb.clip(Rectangle{
        .x = point.x,
        .y = point.y,
        .width = bitmap.width,
        .height = bitmap.height,
    });

    var dst = target.pixels;
    var src = bitmap.pixels + target.dy * @as(usize, bitmap.stride);
    if (bitmap.transparent) |transparent| {
        var y: usize = 0;
        while (y < target.height) : (y += 1) {
            var x: usize = 0;
            while (x < target.width) : (x += 1) {
                const pixel = src[target.dx + x];
                if (pixel != transparent) {
                    dst[x] = pixel;
                }
            }
            dst += fb.stride;
            src += bitmap.stride;
        }
    } else {
        // use optimized memcpy route when we don't have to consider transparency
        var y: usize = 0;
        while (y < target.height) : (y += 1) {
            std.mem.copyForwards(ColorIndex, dst[0..target.width], src[target.dx..bitmap.width]);
            dst += fb.stride;
            src += bitmap.stride;
        }
    }
}

pub fn horizontalLine(fb: Framebuffer, x: i16, y: i16, w: u16, color: ColorIndex) void {
    var i: u15 = 0;
    while (i < w) : (i += 1) {
        fb.setPixel(x + i, y, color);
    }
}

pub fn verticalLine(fb: Framebuffer, x: i16, y: i16, h: u16, color: ColorIndex) void {
    var i: u15 = 0;
    while (i < h) : (i += 1) {
        fb.setPixel(x, y + i, color);
    }
}

pub fn size(fb: Framebuffer) Size {
    return Size.new(fb.width, fb.height);
}

test "framebuffer basic draw" {
    var target: [8][8]ColorIndex = [1][8]ColorIndex{[1]ColorIndex{ColorIndex.get(0)} ** 8} ** 8;
    var fb = Framebuffer{
        .pixels = &target[0],
        .stride = 8,
        .width = 8,
        .height = 8,
    };

    fb.fillRectangle(Rectangle{ .x = 2, .y = 2, .width = 3, .height = 4 }, ColorIndex.get(1));
    fb.drawRectangle(Rectangle{ .x = 2, .y = 2, .width = 3, .height = 4 }, ColorIndex.get(1));
}
