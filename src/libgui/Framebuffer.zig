const std = @import("std");
const ashet = @import("ashet");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

const Bitmap = @import("Bitmap.zig");
pub const Font = @import("Font.zig");

const Framebuffer = @This();

width: u16, // width of the image
height: u16, // height of the image
stride: u32, // row length in pixels
pixels: [*]ColorIndex, // height * stride pixels

/// Creates a framebuffer for the given window.
/// Drawing into the framebuffer will draw to the window surface.
pub fn forWindow(window: *const ashet.abi.Window) Framebuffer {
    return Framebuffer{
        .width = window.client_rectangle.width,
        .height = window.client_rectangle.height,
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

const ScreenRect = struct {
    dx: u16,
    dy: u16,
    x: i16,
    y: i16,
    pixels: [*]ColorIndex,
    width: u15,
    height: u15,
};

fn clip(fb: Framebuffer, rect: Rectangle) ScreenRect {
    var width: u16 = rect.width;
    var height: u16 = rect.height;

    width -|= @intCast(u16, std.math.max(0, -rect.x));
    height -|= @intCast(u16, std.math.max(0, -rect.y));

    const x = @intCast(u15, std.math.max(0, rect.x));
    const y = @intCast(u15, std.math.max(0, rect.y));

    if (x + width > fb.width) {
        width = (fb.width - x);
    }
    if (y + height > fb.height) {
        height = (fb.height - y);
    }

    const result = ScreenRect{
        .dx = @intCast(u16, x - rect.x),
        .dy = @intCast(u16, y - rect.y),
        .x = x,
        .y = y,
        .pixels = fb.pixels + @as(usize, y) * fb.stride + @as(usize, x),
        .width = @intCast(u15, width),
        .height = @intCast(u15, height),
    };
    std.log.debug("clip {} to {}", .{ rect, result });
    return result;
}

// draw commands:

pub fn clear(fb: Framebuffer, color: ColorIndex) void {
    var row = fb.pixels;
    var y: usize = 0;
    while (y < fb.height) : (y += 1) {
        std.mem.set(ColorIndex, row[0..fb.width], color);
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
    var dst = fb.clip(rect);

    var top = dst.pixels;
    var bot = dst.pixels + (dst.height - 1) * fb.stride;

    var x: u16 = 0;
    while (x < dst.width) : (x += 1) {
        if (dst.dy == 0) top[0] = color;
        if (dst.y + dst.height == rect.bottom()) bot[0] = color;
        top += 1;
        bot += 1;
    }

    var left = dst.pixels;
    var right = dst.pixels + (dst.width - 1);

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
    fb.pixels[@intCast(usize, y) * fb.stride + @intCast(usize, x)] = color;
}

pub fn drawLine(fb: Framebuffer, from: Point, to: Point, color: ColorIndex) void {
    if (from.y == to.y) {
        if (from.y < 0 or from.y >= fb.height)
            return;
        // horizontal
        const start = @intCast(usize, std.math.max(0, std.math.min(from.x, to.x))); // inclusive
        const end = @intCast(usize, std.math.min(fb.width, std.math.max(from.x, to.x) + 1)); // exlusive
        std.mem.set(ColorIndex, (fb.pixels + @intCast(usize, from.y) * fb.stride)[start..end], color);
    } else if (from.x == to.x) {
        // vertical
        if (from.x < 0 or from.x >= fb.width)
            return;

        const start = @intCast(usize, std.math.max(0, std.math.min(from.y, to.y))); // inclusive
        const end = @intCast(usize, std.math.min(fb.height, std.math.max(from.y, to.y) + 1)); // exlusive

        var row = fb.pixels + @intCast(usize, from.x) + @intCast(usize, start) * fb.stride;
        var y: usize = start;
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

        var x1 = to.x;
        var y1 = to.y;

        // Implementation taken from
        // https://de.wikipedia.org/wiki/Bresenham-Algorithmus#Kompakte_Variante
        // That means that the following code block is licenced under CC-BY-SA
        // which is compatible to the project licence.
        {
            var dx = H.abs(x1 - x0);
            var sx: i2 = if (x0 < x1) 1 else -1;
            var dy = -H.abs(y1 - y0);
            var sy: i2 = if (y0 < y1) 1 else -1;
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
    pub const Error = error{};
    pub const Writer = std.io.Writer(*ScreenWriter, Error, write);

    fb: Framebuffer,
    dx: i16,
    dy: i16,
    color: ColorIndex,
    limit: u15, // only render till this column (exclusive)

    pub fn writer(sw: *ScreenWriter) Writer {
        return Writer{ .context = sw };
    }

    fn write(sw: *ScreenWriter, text: []const u8) Error!usize {
        if (sw.limit == sw.fb.width)
            return text.len;
        const font = &Font.default;

        const gw = font.glyph_size.width;
        const gh = font.glyph_size.height;

        render_loop: for (text) |char| {
            if (sw.dx >= sw.limit) {
                break;
            }
            const glyph = font.getGlyph(char);

            if (sw.dx + gw >= 0) {
                var gx: u15 = 0;
                while (gx < gw) : (gx += 1) {
                    if (sw.dx + gx > sw.limit) {
                        break :render_loop;
                    }

                    var bits = glyph.bits[gx];

                    var gy: u15 = 0;
                    while (gy < gh) : (gy += 1) {
                        if ((bits & (@as(u8, 1) << @truncate(u3, gy))) != 0) {
                            sw.fb.setPixel(sw.dx + gx, sw.dy + gy, sw.color);
                        }
                    }
                }
            }

            sw.dx += gw;
        }

        return text.len;
    }
};

pub fn screenWriter(fb: Framebuffer, x: i16, y: i16, color: ColorIndex, max_width: ?u15) ScreenWriter {
    const limit = @intCast(u15, if (max_width) |mw| @intCast(u15, std.math.max(0, x + mw)) else fb.width);

    return ScreenWriter{ .fb = fb, .dx = x, .dy = y, .color = color, .limit = limit };
}

pub fn drawString(fb: Framebuffer, x: i16, y: i16, text: []const u8, color: ColorIndex, limit: ?u15) void {
    var sw = fb.screenWriter(x, y, color, limit);
    sw.writer().writeAll(text) catch unreachable;
}

pub fn blit(fb: Framebuffer, point: Point, bitmap: Bitmap) void {
    const target = fb.clip(Rectangle{
        .x = point.x,
        .y = point.y,
        .width = bitmap.width,
        .height = bitmap.height,
    });

    var dst = target.pixels;
    var src = bitmap.pixels + target.dy * bitmap.stride;
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
            std.mem.copy(ColorIndex, dst[0..target.width], src[target.dx..target.width]);
            dst += fb.stride;
            src += bitmap.stride;
        }
    }
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
