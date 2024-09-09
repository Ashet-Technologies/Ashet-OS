const std = @import("std");
const agp = @import("agp");
const ashet = @import("ashet-abi");
const turtlefont = @import("turtlefont");

const logger = std.log.scoped(.agp_sw_rast);

const ColorIndex = agp.ColorIndex;
const Point = ashet.Point;
const Size = ashet.Size;
const Rectangle = ashet.Rectangle;

const Font = agp.Font;
const Framebuffer = agp.Framebuffer;
const Bitmap = agp.Bitmap;

pub const PixelLayout = enum {
    /// This pixel layout stores the pixels in a row-major
    /// order.
    ///
    /// This means, the pixels are layed out horizontally
    /// left-to-right in memory.
    row_major,

    /// This pixel layout stores the pixels in a column-major
    /// order.
    ///
    /// This means, the pixels are layed out vertically
    /// top-to-bottom in memory.
    column_major,
};

pub const RasterizerOptions = struct {
    pixel_layout: PixelLayout,
};

pub fn Rasterizer(comptime Backend: type, comptime _options: RasterizerOptions) type {
    if (!std.meta.hasMethod(Backend, "create_cursor"))
        @compileError("backend.create_cursor() must be a legal call!");

    if (!std.meta.hasMethod(Backend, "emit_pixels"))
        @compileError("backend.emit_pixels(cursor, color, count) must be a legal call!");

    return struct {
        const Rast = @This();

        pub const Cursor = PixelCursor(options.pixel_layout);
        pub const options = _options;

        backend: Backend,
        clip_rect: ClipRect,

        pub fn init(backend: Backend) Rast {
            const cursor: Cursor = backend.create_cursor();
            return .{
                .backend = backend,
                .clip_rect = .{
                    .x = 0,
                    .y = 0,
                    .width = cursor.width,
                    .height = cursor.height,
                },
            };
        }

        pub fn execute(rast: *Rast, cmd: agp.Command) void {
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
                .draw_text => |data| rast.draw_text(
                    Point.new(data.x, data.y),
                    data.font,
                    data.color,
                    data.text,
                ),
                .blit_bitmap => |data| rast.blit_bitmap(
                    Point.new(data.x, data.y),
                    data.bitmap,
                ),
                .blit_framebuffer => |data| rast.blit_framebuffer(
                    Point.new(data.x, data.y),
                    data.framebuffer,
                ),
                .update_color => |data| rast.update_color(
                    data.index,
                    data.r,
                    data.g,
                    data.b,
                ),
                .blit_partial_bitmap => |data| rast.blit_partial_bitmap(
                    Rectangle.new(Point.new(data.x, data.y), Size.new(data.width, data.height)),
                    Point.new(data.src_x, data.src_y),
                    data.bitmap,
                ),
                .blit_partial_framebuffer => |data| rast.blit_partial_framebuffer(
                    Rectangle.new(Point.new(data.x, data.y), Size.new(data.width, data.height)),
                    Point.new(data.src_x, data.src_y),
                    data.framebuffer,
                ),
            }
        }

        pub fn clear(
            rast: Rast,
            color: ColorIndex,
        ) void {
            var cursor = rast.get_cursor();
            std.debug.assert(cursor.move(0, 0));
            switch (options.pixel_layout) {
                .row_major => {
                    rast.emit(cursor, color, cursor.width);
                    for (1..cursor.height) |_| {
                        std.debug.assert(cursor.shift_down(1) == 1);
                        rast.emit(cursor, color, cursor.width);
                    }
                },
                .column_major => {
                    rast.emit(cursor, color, cursor.height);
                    for (1..cursor.width) |_| {
                        std.debug.assert(cursor.shift_right(1) == 1);
                        rast.emit(cursor, color, cursor.height);
                    }
                },
            }
        }

        pub fn set_clip_rect(
            rast: *Rast,
            clip: Rectangle,
        ) void {
            const cursor = rast.get_cursor();
            const base = ClipRect{
                .x = 0,
                .y = 0,
                .width = cursor.width,
                .height = cursor.height,
            };
            rast.clip_rect = base.intersect(clip);
        }

        pub fn set_pixel(
            rast: Rast,
            pixel: Point,
            color: ColorIndex,
        ) void {
            const pos = rast.clip_point(pixel) orelse return;
            var cursor = rast.get_cursor();
            std.debug.assert(cursor.move(pos.x, pos.y));
            rast.emit(cursor, color, 1);
        }

        pub fn draw_line(
            rast: Rast,
            from: Point,
            to: Point,
            color: ColorIndex,
        ) void {
            if (from.y == to.y) {
                rast.draw_horizontal_line(from.x, to.x, from.y, color);
            } else if (from.x == to.x) {
                rast.draw_vertical_line(from.x, from.y, to.y, color);
            } else {
                logger.info("Rasterizer.draw_line()", .{});
                // not an axis aligned line, use bresenham

                // const H = struct {
                //     fn abs(a: i16) i16 {
                //         return if (a < 0) -a else a;
                //     }
                // };

                // var x0 = from.x;
                // var y0 = from.y;

                // const x1 = to.x;
                // const y1 = to.y;

                // // Implementation taken from
                // // https://de.wikipedia.org/wiki/Bresenham-Algorithmus#Kompakte_Variante
                // // That means that the following code block is licenced under CC-BY-SA
                // // which is compatible to the project licence.
                // {
                //     const dx = H.abs(x1 - x0);
                //     const sx: i2 = if (x0 < x1) 1 else -1;
                //     const dy = -H.abs(y1 - y0);
                //     const sy: i2 = if (y0 < y1) 1 else -1;
                //     var err = dx + dy;
                //     var e2: i16 = undefined;

                //     while (true) {
                //         fb.setPixel(x0, y0, color);
                //         if (x0 == x1 and y0 == y1) break;
                //         e2 = 2 * err;
                //         if (e2 > dy) { // e_xy+e_x > 0
                //             err += dy;
                //             x0 += sx;
                //         }
                //         if (e2 < dx) { // e_xy+e_y < 0
                //             err += dx;
                //             y0 += sy;
                //         }
                //     }
                // }
                // // regular licence continues here
            }
        }

        /// Optimized version of line drawing for horizontal lines.
        /// Takes the pixel layout into account to emit optimized code.
        fn draw_horizontal_line(rast: Rast, x0: i16, x1: i16, y: i16, color: ColorIndex) void {
            var cursor = rast.get_cursor();
            if (y < rast.clip_rect.y or @as(isize, y) - rast.clip_rect.y >= rast.clip_rect.height)
                return;

            // horizontal
            const start_unclipped = @min(x0, x1); // inclusive
            const end_unclipped = @max(x0, x1); // inclusive

            const start = rast.clamp_coord(start_unclipped, .x_axis);
            const end = rast.clamp_coord(end_unclipped, .x_axis);

            if (end < start)
                return; // zero length

            const length = (end - start) + 1;

            std.debug.assert(cursor.move(start, @intCast(y)));

            switch (options.pixel_layout) {
                .row_major => {
                    rast.emit(cursor, color, length);
                },
                .column_major => {
                    rast.emit(cursor, color, 1);
                    for (1..length) |_| {
                        std.debug.assert(cursor.shift_down(1) == 1);
                        rast.emit(cursor, color, 1);
                    }
                },
            }
        }

        /// Optimized version of line drawing for vertical lines.
        /// Takes the pixel layout into account to emit optimized code.
        fn draw_vertical_line(rast: Rast, x: i16, y0: i16, y1: i16, color: ColorIndex) void {
            var cursor = rast.get_cursor();
            if (x < rast.clip_rect.x or @as(isize, x) - rast.clip_rect.x >= rast.clip_rect.width)
                return;

            // horizontal
            const start_unclipped = @min(y0, y1); // inclusive
            const end_unclipped = @max(y0, y1); // inclusive

            const start = rast.clamp_coord(start_unclipped, .y_axis);
            const end = rast.clamp_coord(end_unclipped, .y_axis);

            if (end < start)
                return; // zero length

            const length = (end - start) + 1;

            std.debug.assert(cursor.move(@intCast(x), start));

            switch (options.pixel_layout) {
                .row_major => {
                    rast.emit(cursor, color, 1);
                    for (1..length) |_| {
                        std.debug.assert(cursor.shift_down(1) == 1);
                        rast.emit(cursor, color, 1);
                    }
                },
                .column_major => {
                    rast.emit(cursor, color, length);
                },
            }
        }

        pub fn draw_rect(
            rast: Rast,
            rect: Rectangle,
            color: ColorIndex,
        ) void {
            const paint_rect = rast.clip_rect.intersect(rect);

            if (paint_rect.width == 0 or paint_rect.height == 0)
                // TODO: Is "height=0" still a horizontal line?
                return;

            const right = paint_rect.x + paint_rect.width - 1;
            const bottom = paint_rect.y + paint_rect.height - 1;

            var cursor = rast.get_cursor();
            switch (options.pixel_layout) {
                .row_major => {
                    // top line:
                    if (paint_rect.y == rect.y) {
                        std.debug.assert(cursor.move(paint_rect.x, paint_rect.y));
                        rast.emit(cursor, color, paint_rect.width);
                    }

                    // bottom line:
                    if (rect.height > 1 and bottom == rect.bottom() - 1) {
                        std.debug.assert(cursor.move(paint_rect.x, bottom));
                        rast.emit(cursor, color, paint_rect.width);
                    }

                    // left line:
                    if (rect.height > 2 and paint_rect.x == rect.x) {
                        std.debug.assert(cursor.move(paint_rect.x, paint_rect.y + 1));
                        rast.emit(cursor, color, 1);
                        for (1..rect.height - 2) |_| {
                            std.debug.assert(cursor.shift_down(1) == 1);
                            rast.emit(cursor, color, 1);
                        }
                    }

                    // right line:
                    if (rect.height > 2 and right == rect.right() - 1) {
                        std.debug.assert(cursor.move(right, paint_rect.y + 1));
                        rast.emit(cursor, color, 1);
                        for (1..rect.height - 2) |_| {
                            std.debug.assert(cursor.shift_down(1) == 1);
                            rast.emit(cursor, color, 1);
                        }
                    }
                },
                .column_major => @compileError("not implemented yet!"),
            }

            //     const dst = fb.clip(rect);

            //     var top = dst.pixels;
            //     var bot = dst.pixels + (dst.height -| 1) * fb.stride;

            //     var x: u16 = 0;
            //     while (x < dst.width) : (x += 1) {
            //         if (dst.dy == 0) top[0] = color;
            //         if (dst.y + dst.height == rect.bottom()) bot[0] = color;
            //         top += 1;
            //         bot += 1;
            //     }

            //     var left = dst.pixels;
            //     var right = dst.pixels + (dst.width -| 1);

            //     var y: u16 = 0;
            //     while (y < dst.height) : (y += 1) {
            //         if (dst.dx == 0) left[0] = color;
            //         if (dst.x + dst.width == rect.right()) right[0] = color;
            //         left += fb.stride;
            //         right += fb.stride;
            //     }
        }

        pub fn fill_rect(
            rast: Rast,
            rect: Rectangle,
            color: ColorIndex,
        ) void {
            const paint_rect = rast.clip_rect.intersect(rect);
            if (paint_rect.is_empty())
                return;

            var cursor = rast.get_cursor();
            std.debug.assert(cursor.move(paint_rect.x, paint_rect.y));
            switch (options.pixel_layout) {
                .row_major => {
                    rast.emit(cursor, color, paint_rect.width);
                    for (1..paint_rect.height) |_| {
                        std.debug.assert(cursor.shift_down(1) == 1);
                        rast.emit(cursor, color, paint_rect.width);
                    }
                },

                .column_major => {
                    rast.emit(cursor, color, paint_rect.height);
                    for (1..paint_rect.width) |_| {
                        std.debug.assert(cursor.shift_right(1) == 1);
                        rast.emit(cursor, color, paint_rect.height);
                    }
                },
            }
        }

        pub fn draw_text(
            rast: Rast,
            start: Point,
            font: Font,
            color: ColorIndex,
            text: []const u8,
        ) void {
            _ = rast;
            _ = start;
            _ = font;
            _ = color;
            _ = text;

            // var sw = rast.screenWriter(x, y, font, color, limit);
            // sw.writer().writeAll(text) catch {};

            logger.info("Rasterizer.draw_text()", .{});
        }

        pub fn blit_bitmap(
            rast: Rast,
            point: Point,
            bitmap: Bitmap,
        ) void {
            _ = rast;
            _ = point;
            _ = bitmap;
            logger.info("Rasterizer.blit_bitmap()", .{});
        }

        pub fn blit_framebuffer(
            rast: Rast,
            point: Point,
            framebuffer: Framebuffer,
        ) void {
            _ = rast;
            _ = point;
            _ = framebuffer;
            logger.info("Rasterizer.blit_framebuffer()", .{});
        }

        pub fn update_color(
            rast: Rast,
            index: ColorIndex,
            r: u8,
            g: u8,
            b: u8,
        ) void {
            _ = rast;
            _ = index;
            _ = r;
            _ = g;
            _ = b;
            logger.info("Rasterizer.update_color()", .{});
        }

        pub fn blit_partial_bitmap(
            rast: Rast,
            target: Rectangle,
            src_pos: Point,
            bitmap: Bitmap,
        ) void {
            _ = rast;
            _ = target;
            _ = src_pos;
            _ = bitmap;
            logger.info("Rasterizer.blit_bitmap()", .{});
        }

        pub fn blit_partial_framebuffer(
            rast: Rast,
            target: Rectangle,
            src_pos: Point,
            framebuffer: Framebuffer,
        ) void {
            _ = rast;
            _ = target;
            _ = src_pos;
            _ = framebuffer;
            logger.info("Rasterizer.blit_framebuffer()", .{});
        }

        // pub const ScreenWriter = struct {
        //     pub const Error = error{InvalidUtf8};
        //     pub const Writer = std.io.Writer(*ScreenWriter, Error, write);

        //     const VectorRasterizer = turtlefont.Rasterizer(*ScreenWriter, ColorIndex, writeVectorPixel);

        //     fb: Rast,
        //     dx: i16,
        //     dy: i16,
        //     color: ColorIndex,
        //     limit: u15, // only render till this column (exclusive)
        //     font: *const Font,

        //     pub fn writer(sw: *ScreenWriter) Writer {
        //         return Writer{ .context = sw };
        //     }

        //     fn write(sw: *ScreenWriter, text: []const u8) Error!usize {
        //         if (sw.dx >= sw.limit)
        //             return text.len;

        //         var utf8_view = try std.unicode.Utf8View.init(text);
        //         var codepoints = utf8_view.iterator();

        //         switch (sw.font.*) {
        //             .bitmap => |bitmap_font| {
        //                 const fallback_glyph = bitmap_font.getGlyph('�') orelse bitmap_font.getGlyph('?');

        //                 render_loop: while (codepoints.nextCodepoint()) |char| {
        //                     if (sw.dx >= sw.limit) {
        //                         break;
        //                     }
        //                     const glyph: BitmapFont.Glyph = bitmap_font.getGlyph(char) orelse fallback_glyph orelse continue;

        //                     if (sw.dx + glyph.advance >= 0) {
        //                         var data_ptr = glyph.bits.ptr;

        //                         var gx: u15 = 0;
        //                         while (gx < glyph.width) : (gx += 1) {
        //                             if (sw.dx + gx > sw.limit) {
        //                                 break :render_loop;
        //                             }

        //                             var bits: u8 = undefined;

        //                             var gy: u15 = 0;
        //                             while (gy < glyph.height) : (gy += 1) {
        //                                 if ((gy % 8) == 0) {
        //                                     bits = data_ptr[0];
        //                                     data_ptr += 1;
        //                                 }

        //                                 if ((bits & (@as(u8, 1) << @as(u3, @truncate(gy)))) != 0) {
        //                                     sw.fb.setPixel(sw.dx + glyph.offset_x + gx, sw.dy + glyph.offset_y + gy, sw.color);
        //                                 }
        //                             }
        //                         }
        //                     }

        //                     sw.dx += glyph.advance;
        //                 }
        //             },
        //             .vector => |vector_font| {
        //                 const fallback_glyph = vector_font.getGlyph('�') orelse vector_font.getGlyph('?');

        //                 const rast = VectorRasterizer.init(sw);

        //                 const options = vector_font.getTurtleOptions();

        //                 while (codepoints.nextCodepoint()) |char| {
        //                     if (sw.dx >= sw.limit) {
        //                         break;
        //                     }
        //                     const glyph: VectorFont.Glyph = vector_font.getGlyph(char) orelse fallback_glyph orelse continue;

        //                     const advance = options.scaleX(glyph.advance);

        //                     if (sw.dx + advance >= 0) {
        //                         rast.renderGlyph(
        //                             options,
        //                             sw.dx,
        //                             sw.dy + vector_font.size,
        //                             sw.color,
        //                             vector_font.turtle_font.getCode(glyph),
        //                         );
        //                     }

        //                     sw.dx += advance;
        //                     sw.dx += @intFromBool(vector_font.bold);
        //                 }
        //             },
        //         }

        //         return text.len;
        //     }

        //     fn writeVectorPixel(sw: *ScreenWriter, x: i16, y: i16, color: ColorIndex) void {
        //         sw.fb.setPixel(x, y, color);
        //     }
        // };

        // pub fn screen_writer(fb: Rast, x: i16, y: i16, font: *const Font, color: ColorIndex, max_width: ?u15) ScreenWriter {
        //     const limit = @as(u15, @intCast(if (max_width) |mw|
        //         @as(u15, @intCast(@max(0, x + mw)))
        //     else
        //         fb.width));

        //     return ScreenWriter{
        //         .fb = fb,
        //         .dx = x,
        //         .dy = y,
        //         .color = color,
        //         .limit = limit,
        //         .font = font,
        //     };
        // }

        // pub fn blit(fb: Rast, point: Point, bitmap: Bitmap) void {
        //     const target = fb.clip(Rectangle{
        //         .x = point.x,
        //         .y = point.y,
        //         .width = bitmap.width,
        //         .height = bitmap.height,
        //     });

        //     var dst = target.pixels;
        //     var src = bitmap.pixels + target.dy * @as(usize, bitmap.stride);
        //     if (bitmap.transparent) |transparent| {
        //         var y: usize = 0;
        //         while (y < target.height) : (y += 1) {
        //             var x: usize = 0;
        //             while (x < target.width) : (x += 1) {
        //                 const pixel = src[target.dx + x];
        //                 if (pixel != transparent) {
        //                     dst[x] = pixel;
        //                 }
        //             }
        //             dst += fb.stride;
        //             src += bitmap.stride;
        //         }
        //     } else {
        //         // use optimized memcpy route when we don't have to consider transparency
        //         var y: usize = 0;
        //         while (y < target.height) : (y += 1) {
        //             std.mem.copyForwards(ColorIndex, dst[0..target.width], src[target.dx..bitmap.width]);
        //             dst += fb.stride;
        //             src += bitmap.stride;
        //         }
        //     }
        // }

        /// Returns an unset cursor to the backing framebuffer.
        fn get_cursor(rast: Rast) Cursor {
            return rast.backend.create_cursor();
        }

        fn emit(rast: Rast, cursor: Cursor, color: ColorIndex, count: u16) void {
            return rast.backend.emit_pixels(cursor, color, count);
        }

        fn clamp(value: anytype, min: anytype, max: anytype) @TypeOf(value, min, max) {
            if (value < min) return min;
            if (value > max) return max;
            return value;
        }

        const ClipPoint = struct {
            x: u16,
            y: u16,
        };

        fn clip_point(rast: Rast, point: Point) ?ClipPoint {
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
        fn clamp_coord(rast: Rast, value: i16, comptime axis: Axis) u16 {
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

        const ClipRect = struct {
            x: u16,
            y: u16,
            width: u16,
            height: u16,

            fn is_empty(clip: ClipRect) bool {
                return (clip.width == 0) or (clip.height == 0);
            }

            fn intersect(clip: ClipRect, rect: Rectangle) ClipRect {
                // std.debug.print("clip('({},{})+({}×{})', '({},{})+({}×{})')\n", .{
                //     clip.x, clip.y, clip.width, clip.height,
                //     rect.x, rect.y, rect.width, rect.height,
                // });
                const x: u16 = @intCast(@max(@as(isize, clip.x), rect.x));
                const y: u16 = @intCast(@max(@as(isize, clip.y), rect.y));
                const dw: usize = @intCast(@max(rect.x - @as(isize, x), 0));
                const dh: usize = @intCast(@max(rect.y - @as(isize, y), 0));
                const mw: usize = clip.width - x;
                const mh: usize = clip.height - y;
                return .{
                    .x = x,
                    .y = y,
                    .width = @intCast(@min(mw, rect.width - dw)),
                    .height = @intCast(@min(mh, rect.height - dh)),
                };
            }
        };
    };
}

/// A structure that allows incremental modifications to a framebuffer layout
/// with configurable pixel layout.
///
/// The structure performs bounds checking and keeps the data inside the bounds.
///
/// It initializes to an undefined position and must explicitly be initialized
/// after construction with a call to `.move()` to set the initial position.
pub fn PixelCursor(comptime _layout: PixelLayout) type {
    return struct {
        const Cursor = @This();

        pub const layout = _layout;

        // constraints:

        /// Horizontal height of the target in pixels.
        width: u16,

        /// Vertical size of the target in pixels.
        height: u16,

        /// Distance between two scanlines in abstract "units".
        stride: usize,

        // position:

        /// The current offset into the framebuffer in "units".
        offset: usize = undefined,

        /// Distance to the left edge of the target.
        x: u16 = undefined,

        /// Distance to the top edge of the target.
        y: u16 = undefined,

        /// Moves the cursor to (x, y) and returns `true` if inside bounds.
        pub fn move(pc: *Cursor, x: usize, y: usize) bool {
            defer pc.check_consistency();

            if (x >= pc.width or y >= pc.height)
                return false;
            pc.x = @intCast(x);
            pc.y = @intCast(y);
            switch (layout) {
                .row_major => pc.offset = pc.stride * y + x,
                .column_major => pc.offset = pc.stride * x + y,
            }
            return true;
        }

        /// Moves the cursor `count` elements to the left and returns the number of
        /// actual pixels moved.
        pub fn shift_left(pc: *Cursor, count: u16) u16 {
            defer pc.check_consistency();

            const delta = @min(pc.x, count);
            pc.x -= delta;
            switch (layout) {
                .row_major => pc.offset -= delta,
                .column_major => pc.offset -= pc.stride * delta,
            }
            return delta;
        }

        /// Moves the cursor `count` elements to the right and returns the number of
        /// actual pixels moved.
        pub fn shift_right(pc: *Cursor, count: u16) u16 {
            defer pc.check_consistency();

            const delta = @min(pc.width - pc.x, count);
            pc.x += delta;
            switch (layout) {
                .row_major => pc.offset += delta,
                .column_major => pc.offset += pc.stride * delta,
            }
            return delta;
        }

        /// Moves the cursor `count` elements upwards and returns the number of
        /// actual pixels moved.
        pub fn shift_up(pc: *Cursor, count: u16) u16 {
            defer pc.check_consistency();

            const delta = @min(pc.y, count);
            switch (layout) {
                .row_major => pc.offset -= pc.stride * delta,
                .column_major => pc.offset -= delta,
            }
            pc.y -= delta;
            return delta;
        }

        /// Moves the cursor `count` elements downwards and returns the number of
        /// actual pixels moved.
        pub fn shift_down(pc: *Cursor, count: u16) u16 {
            defer pc.check_consistency();

            const delta = @min(pc.height - pc.y, count);
            switch (layout) {
                .row_major => pc.offset += pc.stride * delta,
                .column_major => pc.offset += delta,
            }
            pc.y += delta;
            return delta;
        }

        /// Performs a Debug-only consistency check which
        inline fn check_consistency(pc: Cursor) void {
            std.debug.assert(pc.x < pc.width);
            std.debug.assert(pc.y < pc.height);
            const offset = switch (layout) {
                .row_major => pc.stride * pc.y + pc.x,
                .column_major => pc.stride * pc.x + pc.y,
            };
            std.debug.assert(pc.offset == offset);
        }
    };
}
