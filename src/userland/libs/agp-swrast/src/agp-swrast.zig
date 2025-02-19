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
    backend_type: type,
    framebuffer_type: ?type,
    pixel_layout: PixelLayout,
    blit_buffer_size: comptime_int = 64,
};

pub fn Rasterizer(comptime _options: RasterizerOptions) type {
    const Backend: type = _options.backend_type;

    if (!std.meta.hasMethod(Backend, "create_cursor"))
        @compileError("backend.create_cursor() must be a legal call!");

    if (!std.meta.hasMethod(Backend, "emit_pixels"))
        @compileError("backend.emit_pixels(cursor, color, count) must be a legal call!");

    if (_options.framebuffer_type) |FramebufferType| {
        if (!std.meta.hasMethod(FramebufferType, "create_cursor"))
            @compileError("framebuffer.create_cursor() must be a legal call!");

        if (!std.meta.hasMethod(FramebufferType, "fetch_pixels"))
            @compileError("framebuffer.fetch_pixels(cursor, &pixels) must be a legal call!");

        if (!std.meta.hasMethod(Backend, "copy_pixels"))
            @compileError("backend.copy_pixels(cursor, pixels) must be a legal call!");
    }

    return struct {
        const Rast = @This();

        const FramebufferType = (_options.framebuffer_type orelse @compileError(","));

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
                    try rast.backend.resolve_font(data.font),
                    data.color,
                    data.text,
                ),

                .update_color => |data| rast.update_color(
                    data.index,
                    data.r,
                    data.g,
                    data.b,
                ),

                .blit_framebuffer => |data| if (_options.framebuffer_type) |_| {
                    const fb: FramebufferType = try rast.backend.resolve_framebuffer(data.framebuffer);
                    rast.blit_framebuffer(Point.new(data.x, data.y), fb);
                } else {
                    return error.UnsupportedCommand;
                },

                .blit_partial_framebuffer => |data| if (_options.framebuffer_type) |_| {
                    const fb: FramebufferType = try rast.backend.resolve_framebuffer(data.framebuffer);
                    rast.blit_partial_framebuffer(
                        Rectangle.new(Point.new(data.x, data.y), Size.new(data.width, data.height)),
                        Point.new(data.src_x, data.src_y),
                        fb,
                    );
                } else {
                    return error.UnsupportedCommand;
                },

                .blit_bitmap => |data| rast.blit_bitmap(
                    Point.new(data.x, data.y),
                    data.bitmap,
                ),
                .blit_partial_bitmap => |data| rast.blit_partial_bitmap(
                    Rectangle.new(Point.new(data.x, data.y), Size.new(data.width, data.height)),
                    Point.new(data.src_x, data.src_y),
                    data.bitmap,
                ),
            }
        }
        pub fn update_color(
            rast: Rast,
            index: Color,
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

        pub fn clear(
            rast: Rast,
            color: Color,
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
            color: Color,
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
            color: Color,
        ) void {
            if (from.y == to.y) {
                rast.draw_horizontal_line(from.x, to.x, from.y, color);
            } else if (from.x == to.x) {
                rast.draw_vertical_line(from.x, from.y, to.y, color);
            } else {
                // not an axis aligned line, use bresenham

                // TODO(fqu): Write a much more optimized version of the
                // algorithm using cursor.shift_XXX functions and clip the data
                // to a smaller frame

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
        /// Takes the pixel layout into account to emit optimized code.
        fn draw_horizontal_line(rast: Rast, x0: i16, x1: i16, y: i16, color: Color) void {
            var cursor = rast.get_cursor();
            if (y < rast.clip_rect.y or @as(isize, y) - rast.clip_rect.y >= rast.clip_rect.height)
                return;

            // horizontal
            const start_unclipped = @min(x0, x1); // inclusive
            const end_unclipped = @max(x0, x1); // inclusive

            const start = rast.clamp_coord(start_unclipped, .x_axis);
            const end = rast.clamp_coord(end_unclipped, .x_axis);

            if (end <= start)
                return; // zero length

            const length = (end - start);

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
        fn draw_vertical_line(rast: Rast, x: i16, y0: i16, y1: i16, color: Color) void {
            var cursor = rast.get_cursor();
            if (x < rast.clip_rect.x or @as(isize, x) - rast.clip_rect.x >= rast.clip_rect.width)
                return;

            // horizontal
            const start_unclipped = @min(y0, y1); // inclusive
            const end_unclipped = @max(y0, y1); // inclusive

            const start = rast.clamp_coord(start_unclipped, .y_axis);
            const end = rast.clamp_coord(end_unclipped, .y_axis);

            if (end <= start)
                return; // zero length

            const length = (end - start);

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
            color: Color,
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
        }

        pub fn fill_rect(
            rast: Rast,
            rect: Rectangle,
            color: Color,
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
            font: *const fonts.FontInstance,
            color: Color,
            text: []const u8,
        ) void {
            var sw = rast.screen_writer(start.x, start.y, font, color, null);
            sw.writer().writeAll(text) catch {};
        }

        pub fn blit_bitmap(rast: Rast, point: Point, bitmap: *const Bitmap) void {
            return rast.blit_generic_data(point, Point.zero, null, BitmapWrap{ .bmp = bitmap });
        }

        pub fn blit_framebuffer(rast: Rast, point: Point, framebuffer: FramebufferType) void {
            return rast.blit_generic_data(point, Point.zero, null, framebuffer);
        }

        pub fn blit_partial_bitmap(
            rast: Rast,
            target: Rectangle,
            src_pos: Point,
            bitmap: *const Bitmap,
        ) void {
            return rast.blit_generic_data(target.position(), src_pos, target.size(), BitmapWrap{ .bmp = bitmap });
        }

        pub fn blit_partial_framebuffer(
            rast: Rast,
            target: Rectangle,
            src_pos: Point,
            framebuffer: FramebufferType,
        ) void {
            return rast.blit_generic_data(target.position(), src_pos, target.size(), framebuffer);
        }

        pub fn screen_writer(fb: Rast, x: i16, y: i16, font: *const fonts.FontInstance, color: Color, max_width: ?u15) ScreenWriter {
            const limit: u15 = @intCast(if (max_width) |mw|
                @max(0, x + mw)
            else blk: {
                const cursor = fb.get_cursor();
                break :blk cursor.width;
            });

            return ScreenWriter{
                .fb = fb,
                .dx = x,
                .dy = y,
                .color = color,
                .limit = limit,
                .font = font,
            };
        }

        const BlitDestination = union(enum) {
            point: Point,
            rect: Rectangle,
        };
        fn blit_generic_data(rast: Rast, target_pos: Point, source_pos: Point, optional_size: ?Size, framebuffer: anytype) void {
            if (_options.pixel_layout != PixelLayout.row_major)
                @compileError("unsupported");

            var src_cursor: Cursor = framebuffer.create_cursor();
            var dst_cursor: Cursor = rast.get_cursor();

            if (target_pos.x >= dst_cursor.width)
                return;
            if (target_pos.y >= dst_cursor.height)
                return;

            // Compute the screen-local start:
            const start_x: u16 = @intCast(@max(0, target_pos.x));
            const start_y: u16 = @intCast(@max(0, target_pos.y));
            std.debug.assert(dst_cursor.move(start_x, start_y));

            // Compute the offset to the screen start:
            const dx: u16 = @intCast(source_pos.x + @max(0, -target_pos.x));
            const dy: u16 = @intCast(source_pos.y + @max(0, -target_pos.y));

            // If we would never paint anything from src, discard early:
            if (dx >= src_cursor.width)
                return;
            if (dy >= src_cursor.width)
                return;
            std.debug.assert(src_cursor.move(dx, dy));

            const size = if (optional_size) |size|
                Size.new(
                    @min(src_cursor.width, size.width),
                    @min(src_cursor.height, size.height),
                )
            else
                Size.new(
                    src_cursor.width,
                    src_cursor.height,
                );

            var buffer: [options.blit_buffer_size]Color = undefined;

            logger.debug("blitting {}x{} @ ({},{}) to ({},{})*({},{})", .{
                src_cursor.width, src_cursor.height,
                src_cursor.x,     src_cursor.y,
                dst_cursor.x,     dst_cursor.y,
                dst_cursor.width, dst_cursor.height,
            });
            logger.debug("({},{})x({},{})", .{
                dx,         dy,
                size.width, size.height,
            });

            // @breakpoint();

            var y: u16 = dy;
            copy_row_loop: while (y < size.height) : (y += 1) {
                var src_line_cursor = src_cursor;
                var dst_line_cursor = dst_cursor;

                var x: u16 = dx;
                copy_line_loop: while (x < size.width) {
                    const len: u16 = @min(@as(u16, buffer.len), size.width - x);

                    // logger.info("({},{}): copy {}", .{ x, y, len });

                    framebuffer.fetch_pixels(src_line_cursor, buffer[0..len]);

                    // src must always be big enough, as we're iterating over src:
                    std.debug.assert(src_line_cursor.shift_right(len) == len);

                    // create a copy of our cursor, then advance the other one.
                    // only copy as much as we really need:
                    const target = dst_line_cursor;

                    const row_inc = dst_line_cursor.shift_right(len);
                    rast.blit_pixels(target, buffer[0..row_inc]);
                    // dst may be truncated, then we cancel:
                    if (row_inc < len)
                        break :copy_line_loop;

                    x += len;
                }

                // src must always be big enough, as we're iterating over src:
                std.debug.assert(src_cursor.shift_down(1) == 1);

                // dst may be truncated/out of screen:
                switch (dst_cursor.shift_down(1)) {
                    0 => break :copy_row_loop,
                    1 => {},
                    else => unreachable,
                }
            }
        }

        /// Returns an unset cursor to the backing framebuffer.
        fn get_cursor(rast: Rast) Cursor {
            return rast.backend.create_cursor();
        }

        fn emit(rast: Rast, cursor: Cursor, color: Color, count: u16) void {
            return rast.backend.emit_pixels(cursor, color, count);
        }

        fn blit_pixels(rast: Rast, cursor: Cursor, pixels: []const Color) void {
            return rast.backend.copy_pixels(cursor, pixels);
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
            pub const Writer = std.io.Writer(*ScreenWriter, Error, write);

            const VectorRasterizer = turtlefont.Rasterizer(*ScreenWriter, Color, writeVectorPixel);

            fb: Rast,
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

                        render_loop: while (codepoints.nextCodepoint()) |char| {
                            if (sw.dx >= sw.limit) {
                                break;
                            }
                            const glyph: fonts.BitmapFont.Glyph = bitmap_font.getGlyph(char) orelse fallback_glyph orelse continue;

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
                                            sw.fb.set_pixel(
                                                Point.new(
                                                    sw.dx + glyph.offset_x + gx,
                                                    sw.dy + glyph.offset_y + gy,
                                                ),
                                                sw.color,
                                            );
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

                        const vec_options = vector_font.getTurtleOptions();

                        while (codepoints.nextCodepoint()) |char| {
                            if (sw.dx >= sw.limit) {
                                break;
                            }
                            const glyph: fonts.VectorFont.Glyph = vector_font.getGlyph(char) orelse fallback_glyph orelse continue;

                            const advance = vec_options.scaleX(glyph.advance);

                            if (sw.dx + advance >= 0) {
                                rast.renderGlyph(
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
                sw.fb.set_pixel(Point.new(x, y), color);
            }
        };
    };
}

/// Wrapper around agp.Bitmap that fulfils the requirements
/// of a fetch framebuffer.
///
/// This allows us to use the same source for both data structures.
const BitmapWrap = struct {
    const Cursor = PixelCursor(.row_major);

    bmp: *const Bitmap,

    pub fn create_cursor(wrap: BitmapWrap) Cursor {
        return .{
            .width = wrap.bmp.width,
            .height = wrap.bmp.height,
            .stride = wrap.bmp.stride,
        };
    }

    pub fn fetch_pixels(wrap: BitmapWrap, cursor: Cursor, pixels: []Color) void {
        @memcpy(pixels, wrap.bmp.pixels[cursor.offset..][0..pixels.len]);
    }
};

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

            // logger.debug("move({},{}) @ ({},{})", .{
            //     pc.x,
            //     pc.y,
            //     pc.width,
            //     pc.height,
            // });

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
            // logger.debug("({},{}) < ({}x{})", .{
            //     pc.x,
            //     pc.y,
            //     pc.width,
            //     pc.height,
            // });
            std.debug.assert(pc.x <= pc.width);
            std.debug.assert(pc.y <= pc.height);
            const offset = switch (layout) {
                .row_major => pc.stride * pc.y + pc.x,
                .column_major => pc.stride * pc.x + pc.y,
            };
            std.debug.assert(pc.offset == offset);
        }
    };
}
