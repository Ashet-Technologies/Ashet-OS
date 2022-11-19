const std = @import("std");
const ashet = @import("ashet");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

const Bitmap = @import("Bitmap.zig");
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
        .dy = @intCast(u16, x - rect.y),
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

    _ = fb.blit;
}
