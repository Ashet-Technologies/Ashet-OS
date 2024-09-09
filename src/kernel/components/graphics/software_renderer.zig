const std = @import("std");
const ashet = @import("ashet");
const turtlefont = @import("turtlefont");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

const fonts = @import("fonts.zig");
const bitmaps = @import("bitmaps.zig");

const Bitmap = bitmaps.Bitmap;
const Font = fonts.Font;
const BitmapFont = fonts.BitmapFont;
const VectorFont = fonts.VectorFont;

pub const Framebuffer = struct {
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


    pub fn size(fb: Framebuffer) Size {
        return Size.new(fb.width, fb.height);
    }
};

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
