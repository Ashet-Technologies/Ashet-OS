//!
//! Implementation of a software rasterizer for row-major framebuffers.
//!
const std = @import("std");
const agp = @import("agp");
const ashet = @import("ashet-abi");
const turtlefont = @import("turtlefont");

pub const fonts = @import("fonts.zig");

const logger = std.log.scoped(.agp_sw_rast);

const Color = agp.Color;
const Point = ashet.Point;
const Size = ashet.Size;
const Rectangle = ashet.Rectangle;

const Font = agp.Font;
const Framebuffer = agp.Framebuffer;
const Bitmap = agp.Bitmap;

/// A read-only pixel source used for blit operations.
pub const Image = struct {
    pixels: [*]const Color,
    width: u16,
    height: u16,
    stride: u32,
    transparency_key: ?Color = null,

    pub fn from_bitmap(bmp: *const Bitmap) Image {
        return .{
            .pixels = bmp.pixels,
            .width = bmp.width,
            .height = bmp.height,
            .stride = @intCast(bmp.stride),
            .transparency_key = if (bmp.has_transparency) bmp.transparency_key else null,
        };
    }

    pub fn row(self: Image, y: u16) [*]const Color {
        return self.pixels + @as(usize, y) * self.stride;
    }

    pub fn slice(self: Image, x: u16, y: u16, len: u16) []const Color {
        const base = @as(usize, y) * self.stride + x;
        return self.pixels[base..][0..len];
    }
};

/// A writable pixel destination for rendering.
pub const RenderTarget = struct {
    pixels: [*]Color,
    width: u16,
    height: u16,
    stride: u32,

    pub fn row(self: RenderTarget, y: u16) [*]Color {
        return self.pixels + @as(usize, y) * self.stride;
    }

    pub fn slice(self: RenderTarget, x: u16, y: u16, len: u16) []Color {
        const base = @as(usize, y) * self.stride + x;
        return self.pixels[base..][0..len];
    }

    pub fn as_image(self: RenderTarget) Image {
        return .{
            .pixels = self.pixels,
            .width = self.width,
            .height = self.height,
            .stride = self.stride,
        };
    }
};

pub const Rasterizer = struct {
    target: RenderTarget,
    clip_rect: ClipRect,

    pub fn init(target: RenderTarget) Rasterizer {
        return .{
            .target = target,
            .clip_rect = .{
                .x = 0,
                .y = 0,
                .width = target.width,
                .height = target.height,
            },
        };
    }

    pub const Resolver = struct {
        ctx: *anyopaque,
        resolve_font_fn: *const fn (*anyopaque, Font) ?*const fonts.FontInstance,
        resolve_framebuffer_fn: *const fn (*anyopaque, agp.Framebuffer) ?Image,
    };

    pub fn execute(rast: *Rasterizer, cmd: agp.Command, resolver: Resolver) void {
        switch (cmd) {
            .clear => |data| rast.clear(data.color),
            .set_clip_rect => |data| rast.set_clip_rect(Rectangle.new(
                Point.new(data.x, data.y),
                Size.new(data.width, data.height),
            )),
            .set_pixel => |data| rast.set_pixel(
                Point.new(data.x, data.y),
                data.color,
            ),
            .draw_line => |data| rast.draw_line(
                Point.new(data.x1, data.y1),
                Point.new(data.x2, data.y2),
                data.color,
            ),
            .draw_rect => |data| rast.draw_rect(
                Rectangle.new(
                    Point.new(data.x, data.y),
                    Size.new(data.width, data.height),
                ),
                data.color,
            ),
            .fill_rect => |data| rast.fill_rect(
                Rectangle.new(
                    Point.new(data.x, data.y),
                    Size.new(data.width, data.height),
                ),
                data.color,
            ),
            .draw_text => |data| {
                const font = resolver.resolve_font_fn(resolver.ctx, data.font) orelse return;
                rast.draw_text(
                    Point.new(data.x, data.y),
                    font,
                    data.color,
                    data.text,
                );
            },
            .blit_bitmap => |data| rast.blit_bitmap(
                Point.new(data.x, data.y),
                &data.bitmap,
            ),
            .blit_partial_bitmap => |data| rast.blit_partial_bitmap(
                Rectangle.new(Point.new(data.x, data.y), Size.new(data.width, data.height)),
                Point.new(data.src_x, data.src_y),
                &data.bitmap,
            ),
            .blit_framebuffer => |data| {
                const image = resolver.resolve_framebuffer_fn(resolver.ctx, data.framebuffer) orelse return;
                rast.blit_image(Point.new(data.x, data.y), image);
            },
            .blit_partial_framebuffer => |data| {
                const image = resolver.resolve_framebuffer_fn(resolver.ctx, data.framebuffer) orelse return;
                rast.blit_partial_image(
                    Rectangle.new(
                        Point.new(data.x, data.y),
                        Size.new(data.width, data.height),
                    ),
                    Point.new(data.src_x, data.src_y),
                    image,
                );
            },
        }
    }

    pub fn clear(
        rast: Rasterizer,
        color: Color,
    ) void {
        rast.fill_rect(.{
            .x = @intCast(rast.clip_rect.x),
            .y = @intCast(rast.clip_rect.y),
            .width = rast.clip_rect.width,
            .height = rast.clip_rect.height,
        }, color);
    }

    pub fn set_clip_rect(
        rast: *Rasterizer,
        clip: Rectangle,
    ) void {
        const base = ClipRect{
            .x = 0,
            .y = 0,
            .width = rast.target.width,
            .height = rast.target.height,
        };
        rast.clip_rect = base.intersect(clip);
    }

    pub fn set_pixel(
        rast: Rasterizer,
        pixel: Point,
        color: Color,
    ) void {
        const pos = rast.clip_point(pixel) orelse return;
        rast.target.row(pos.y)[pos.x] = color;
    }

    pub fn draw_line(
        rast: Rasterizer,
        from: Point,
        to: Point,
        color: Color,
    ) void {
        if (from.y == to.y) {
            rast.draw_horizontal_line(from.x, to.x, from.y, color);
        } else if (from.x == to.x) {
            rast.draw_vertical_line(from.x, from.y, to.y, color);
        } else {
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
                    rast.set_pixel(Point.new(x0, y0), color);
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

    /// Optimized version of line drawing for horizontal lines.
    fn draw_horizontal_line(rast: Rasterizer, x0: i16, x1: i16, y: i16, color: Color) void {
        if (y < rast.clip_rect.y or @as(isize, y) - rast.clip_rect.y >= rast.clip_rect.height)
            return;

        const start_unclipped = @min(x0, x1); // inclusive
        const end_unclipped = @max(x0, x1) +| 1; // exclusive

        const start = rast.clamp_coord(start_unclipped, .x_axis);
        const end = rast.clamp_coord(end_unclipped, .x_axis);

        if (end <= start)
            return;

        @memset(rast.target.slice(start, @intCast(y), end - start), color);
    }

    /// Optimized version of line drawing for vertical lines.
    fn draw_vertical_line(rast: Rasterizer, x: i16, y0: i16, y1: i16, color: Color) void {
        if (x < rast.clip_rect.x or @as(isize, x) - rast.clip_rect.x >= rast.clip_rect.width)
            return;

        const start_unclipped = @min(y0, y1); // inclusive
        const end_unclipped = @max(y0, y1) +| 1; // exclusive

        const start = rast.clamp_coord(start_unclipped, .y_axis);
        const end = rast.clamp_coord(end_unclipped, .y_axis);

        if (end <= start)
            return;

        const px: u16 = @intCast(x);
        for (start..end) |y| {
            rast.target.row(@intCast(y))[px] = color;
        }
    }

    pub fn draw_rect(
        rast: Rasterizer,
        rect: Rectangle,
        color: Color,
    ) void {
        const paint_rect = rast.clip_rect.intersect(rect);

        if (paint_rect.width == 0 or paint_rect.height == 0)
            return;

        const right = paint_rect.x + paint_rect.width - 1;
        const bottom = paint_rect.y + paint_rect.height - 1;

        rast.draw_horizontal_line(@intCast(paint_rect.x), @intCast(right), @intCast(paint_rect.y), color);
        if (paint_rect.y != bottom) {
            rast.draw_horizontal_line(@intCast(paint_rect.x), @intCast(right), @intCast(bottom), color);
        }
        if (paint_rect.height > 2) {
            rast.draw_vertical_line(@intCast(paint_rect.x), @intCast(paint_rect.y +| 1), @intCast(bottom -| 1), color);
            if (paint_rect.y != bottom) {
                rast.draw_vertical_line(@intCast(right), @intCast(paint_rect.y +| 1), @intCast(bottom -| 1), color);
            }
        }
    }

    pub fn fill_rect(
        rast: Rasterizer,
        rect: Rectangle,
        color: Color,
    ) void {
        const paint_rect = rast.clip_rect.intersect(rect);
        if (paint_rect.is_empty())
            return;

        for (0..paint_rect.height) |dy| {
            const y: u16 = @intCast(paint_rect.y + dy);
            @memset(rast.target.slice(paint_rect.x, y, paint_rect.width), color);
        }
    }

    pub fn draw_text(
        rast: Rasterizer,
        start: Point,
        font: *const fonts.FontInstance,
        color: Color,
        text: []const u8,
    ) void {
        var sw = rast.screen_writer(start.x, start.y, font, color, null);
        sw.writer().writeAll(text) catch {};
    }

    pub fn blit_bitmap(rast: Rasterizer, point: Point, bitmap: *const Bitmap) void {
        rast.blit_image_region(
            point,
            Point.zero,
            null,
            Image.from_bitmap(bitmap),
        );
    }

    pub fn blit_image(rast: Rasterizer, point: Point, image: Image) void {
        rast.blit_image_region(point, Point.zero, null, image);
    }

    pub fn blit_partial_bitmap(
        rast: Rasterizer,
        target: Rectangle,
        src_pos: Point,
        bitmap: *const Bitmap,
    ) void {
        rast.blit_image_region(
            target.position(),
            src_pos,
            target.size(),
            Image.from_bitmap(bitmap),
        );
    }

    pub fn blit_partial_image(
        rast: Rasterizer,
        target: Rectangle,
        src_pos: Point,
        image: Image,
    ) void {
        rast.blit_image_region(target.position(), src_pos, target.size(), image);
    }

    pub fn screen_writer(rast: Rasterizer, x: i16, y: i16, font: *const fonts.FontInstance, color: Color, max_width: ?u15) ScreenWriter {
        const limit: u15 = @intCast(if (max_width) |mw|
            @max(0, x + mw)
        else
            rast.target.width);

        return ScreenWriter{
            .rast = rast,
            .dx = x,
            .dy = y,
            .color = color,
            .limit = limit,
            .font = font,
        };
    }

    fn blit_image_region(rast: Rasterizer, target_pos: Point, source_pos: Point, optional_size: ?Size, image: Image) void {
        if (target_pos.x >= rast.target.width)
            return;
        if (target_pos.y >= rast.target.height)
            return;

        // Source offset accounting for negative target position:
        const src_x: u16 = @intCast(source_pos.x + @max(0, -target_pos.x));
        const src_y: u16 = @intCast(source_pos.y + @max(0, -target_pos.y));

        if (src_x >= image.width)
            return;
        if (src_y >= image.height)
            return;

        // Destination start (clamped to 0):
        const dst_x: u16 = @intCast(@max(0, target_pos.x));
        const dst_y: u16 = @intCast(@max(0, target_pos.y));

        // Compute the blit region size, clipped to both source and destination:
        const src_avail_w = image.width - src_x;
        const src_avail_h = image.height - src_y;
        const dst_avail_w = rast.clip_rect.x + rast.clip_rect.width -| dst_x;
        const dst_avail_h = rast.clip_rect.y + rast.clip_rect.height -| dst_y;

        const blit_w: u16 = if (optional_size) |s|
            @min(s.width, @min(src_avail_w, dst_avail_w))
        else
            @min(src_avail_w, dst_avail_w);

        const blit_h: u16 = if (optional_size) |s|
            @min(s.height, @min(src_avail_h, dst_avail_h))
        else
            @min(src_avail_h, dst_avail_h);

        if (blit_w == 0 or blit_h == 0)
            return;

        // Also clip against clip_rect left/top:
        const clip_skip_x: u16 = rast.clip_rect.x -| dst_x;
        const clip_skip_y: u16 = rast.clip_rect.y -| dst_y;

        const actual_src_x = src_x + clip_skip_x;
        const actual_dst_x = dst_x + clip_skip_x;
        const actual_src_y = src_y + clip_skip_y;
        const actual_dst_y = dst_y + clip_skip_y;
        const actual_w = blit_w -| clip_skip_x;
        const actual_h = blit_h -| clip_skip_y;

        if (actual_w == 0 or actual_h == 0)
            return;

        logger.debug("blitting {}x{} from ({},{}) to ({},{})", .{
            actual_w,     actual_h,
            actual_src_x, actual_src_y,
            actual_dst_x, actual_dst_y,
        });

        if (image.transparency_key) |key| {
            for (0..actual_h) |dy| {
                const sy: u16 = actual_src_y + @as(u16, @intCast(dy));
                const dy2: u16 = actual_dst_y + @as(u16, @intCast(dy));
                const src_row = image.slice(actual_src_x, sy, actual_w);
                const dst_row = rast.target.slice(actual_dst_x, dy2, actual_w);
                for (0..actual_w) |i| {
                    if (src_row[i] != key) {
                        dst_row[i] = src_row[i];
                    }
                }
            }
        } else {
            for (0..actual_h) |dy| {
                const sy: u16 = actual_src_y + @as(u16, @intCast(dy));
                const dy2: u16 = actual_dst_y + @as(u16, @intCast(dy));
                const src_row = image.slice(actual_src_x, sy, actual_w);
                const dst_row = rast.target.slice(actual_dst_x, dy2, actual_w);
                @memcpy(dst_row, src_row);
            }
        }
    }

    const ClipPoint = struct {
        x: u16,
        y: u16,
    };

    fn clip_point(rast: Rasterizer, point: Point) ?ClipPoint {
        if (point.x < rast.clip_rect.x) return null;
        if (point.y < rast.clip_rect.y) return null;
        if (@as(isize, point.x) - rast.clip_rect.x >= rast.clip_rect.width) return null;
        if (@as(isize, point.y) - rast.clip_rect.y >= rast.clip_rect.height) return null;
        return .{
            .x = @intCast(point.x),
            .y = @intCast(point.y),
        };
    }

    const Axis = enum { x_axis, y_axis };
    fn clamp_coord(rast: Rasterizer, value: i16, comptime axis: Axis) u16 {
        const pos_key = switch (axis) {
            .x_axis => "x",
            .y_axis => "y",
        };
        const size_key = switch (axis) {
            .x_axis => "width",
            .y_axis => "height",
        };

        const base = @field(rast.clip_rect, pos_key);
        const size = @field(rast.clip_rect, size_key);

        if (value < base)
            return base;

        if (value >= base + size)
            return base + size;

        return @intCast(value);
    }

    pub const ClipRect = struct {
        x: u16,
        y: u16,
        width: u16,
        height: u16,

        fn is_empty(clip: ClipRect) bool {
            return (clip.width == 0) or (clip.height == 0);
        }

        fn intersect(clip: ClipRect, rect: Rectangle) ClipRect {
            const x: u16 = @intCast(@max(@as(isize, clip.x), rect.x));
            const y: u16 = @intCast(@max(@as(isize, clip.y), rect.y));
            const dw: usize = @intCast(@max(rect.x - @as(isize, x), 0));
            const dh: usize = @intCast(@max(rect.y - @as(isize, y), 0));
            const mw: usize = clip.width -| x;
            const mh: usize = clip.height -| y;
            return .{
                .x = x,
                .y = y,
                .width = @intCast(@min(mw, rect.width - dw)),
                .height = @intCast(@min(mh, rect.height - dh)),
            };
        }
    };

    pub const ScreenWriter = struct {
        pub const Error = error{InvalidUtf8};
        pub const Writer = std.Io.GenericWriter(*ScreenWriter, Error, write);

        const VectorRasterizer = turtlefont.Rasterizer(*ScreenWriter, Color, writeVectorPixel);

        rast: Rasterizer,
        dx: i16,
        dy: i16,
        color: Color,
        limit: u15, // only render till this column (exclusive)
        font: *const fonts.FontInstance,

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

                    while (codepoints.nextCodepoint()) |char| {
                        if (sw.dx >= sw.limit) {
                            break;
                        }
                        const glyph: fonts.BitmapFont.Glyph = bitmap_font.getGlyph(char) orelse fallback_glyph orelse continue;

                        if (sw.dx + glyph.advance >= 0) {
                            const row_stride = (glyph.width + 7) / 8;

                            const px: i16 = @intCast(sw.dx + glyph.offset_x);
                            const py: i16 = @intCast(sw.dy + glyph.offset_y);

                            var gy: u15 = 0;
                            while (gy < glyph.height) : (gy += 1) {
                                var row_ptr = glyph.bits.ptr + row_stride * gy;

                                {
                                    var gx: u15 = 0;
                                    var mask: u8 = 1;
                                    var bits: u8 = row_ptr[0];
                                    while (gx < glyph.width) : (gx += 1) {
                                        if (sw.dx + gx >= sw.limit) {
                                            break;
                                        }

                                        if ((bits & mask) != 0) {
                                            sw.rast.set_pixel(.new(px + gx, py + gy), sw.color);
                                        }

                                        mask <<= 1;
                                        if (mask == 0) {
                                            row_ptr += 1;
                                            mask = 1;
                                            bits = row_ptr[0];
                                        }
                                    }
                                }
                            }
                        }

                        sw.dx += glyph.advance;
                    }
                },
                .vector => |vector_font| {
                    const fallback_glyph = vector_font.getGlyph('�') orelse vector_font.getGlyph('?');

                    const vrast = VectorRasterizer.init(sw);

                    const vec_options = vector_font.getTurtleOptions();

                    while (codepoints.nextCodepoint()) |char| {
                        if (sw.dx >= sw.limit) {
                            break;
                        }
                        const glyph: fonts.VectorFont.Glyph = vector_font.getGlyph(char) orelse fallback_glyph orelse continue;

                        const advance = vec_options.scaleX(glyph.advance);

                        if (sw.dx + advance >= 0) {
                            vrast.renderGlyph(
                                vec_options,
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

        fn writeVectorPixel(sw: *ScreenWriter, x: i16, y: i16, color: Color) void {
            sw.rast.set_pixel(Point.new(x, y), color);
        }
    };
};
