const std = @import("std");
const agp = @import("agp");
const ashet = @import("ashet-abi");
const agp_swrast = @import("agp-swrast");

const Color = ashet.Color;
const Point = ashet.Point;
const Size = ashet.Size;
const Rectangle = ashet.Rectangle;
const Bitmap = agp.Bitmap;
const Command = agp.Command;
const Font = agp.Font;

// ------------------------------------------------------------------
// Global rasterizer parameters:

/// Maximum size in one dimension:
pub const max_image_size = 2048;

/// Size of a tile in one dimension:
pub const tile_size = 64;

/// Number of tiles in one dimension:
pub const grid_size = @divExact(max_image_size, tile_size);

/// Total number of potential tiles
pub const tile_count = grid_size * grid_size;

/// The maximum number of bytes that can be rendered by a single
/// invocation of the rasterizer.
pub const max_commandbuffer_size = 32768;

// ------------------------------------------------------------------

/// Memory storage for a tile.
/// Organized as an array of pixel rows.
pub const Tile = [tile_size][tile_size]Color; // `[y][x]Color`

/// The tile state is a coarse enumeration of tile properties
/// that allows a quick determination of whether a tile needs
/// rendering or not.
pub const TileState = enum(u2) {
    /// A tile is not rendered in this command chain.
    uncovered = 0b00,

    /// The tile will be rendered but not fully replaced
    /// by the rasterization op.
    updated = 0b10,

    /// The tile will be fully replaced by the rasterizer execution
    /// and doesn't need loading the contents.
    replaced = 0b11,
};

/// The slice of the command sequence that is actually processed by the associated tile.
pub const TileSpan = extern struct {
    /// Index of the first byte of the relevant command sequence.
    first_cmd_offset: u16,

    /// Index of the first byte not in the command sequence anymore (one behind the last byte).
    last_cmd_offset: u16,
};

/// A type that stores a packed representation of `[tile_count]TileState`
pub const TileStateCache = extern struct {
    const items_per_chunk = @bitSizeOf(u32) / @bitSizeOf(TileState);

    pub const init: TileStateCache = .{ .chunks = @splat(0) };

    chunks: [tile_count / items_per_chunk]u32,

    fn set(cache: *TileStateCache, index: usize, value: TileState) void {
        const chunk = &cache.chunks[index / items_per_chunk];
        const shift: u5 = @intCast(2 * (index % items_per_chunk));

        const mask = @as(u32, 0b11) << shift;
        const pattern = @as(u32, @intFromEnum(value)) << shift;

        chunk.* &= ~mask;
        chunk.* |= pattern;
    }

    fn get(cache: *const TileStateCache, index: usize) TileState {
        const chunk = cache.chunks[index / items_per_chunk];
        const shift: u5 = @intCast(2 * (index % items_per_chunk));
        return @enumFromInt((chunk >> shift) & 0b11);
    }
};

// Instance of a single drawable font file.
pub const FontInstance = agp_swrast.fonts.FontInstance;

// Instance of a vector graphics font.
pub const VectorFont = agp_swrast.fonts.VectorFont;

// Instance of a bitmap font.
pub const BitmapFont = agp_swrast.fonts.BitmapFont;

/// A read-only pixel source used for blit operations.
pub const Image = agp_swrast.Image;

/// A writable pixel destination for rendering.
///
/// Requires a stride that is a multiple of `tile_size` and it's memory must be
/// aligned to `tile_size`.
///
/// This way each scanline is well aligned in memory.
pub const RenderTarget = struct {
    pixels: [*]align(tile_size) Color,
    width: u16,
    height: u16,
    stride: u32, // must be a multiple of `tile_size`!

    pub fn row(self: RenderTarget, y: u16) [*]align(tile_size) Color {
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

/// The resolver provides an abstraction over different host systems that
/// have different implementations for framebuffer objects and font instancing.
pub const Resolver = struct {
    pub const VTable = struct {
        resolve_font_fn: *const fn (*anyopaque, Font) ?*const FontInstance,
        resolve_framebuffer_fn: *const fn (*anyopaque, agp.Framebuffer) ?Image,
    };

    ctx: *anyopaque,
    vtable: *const VTable,

    /// Resolves a font handle into a font instance.
    pub fn resolve_font(resolver: Resolver, handle: Font) ?*const FontInstance {
        return resolver.vtable.resolve_font_fn(resolver.ctx, handle);
    }

    /// Resolves a framebuffer into an image.
    ///
    /// TODO: Change Image to RenderTarget or another type that gives us the sweet
    ///       64 byte alignment guarantee for super fast fused-store blitting.
    pub fn resolve_framebuffer(resolver: Resolver, handle: agp.Framebuffer) ?Image {
        return resolver.vtable.resolve_framebuffer_fn(resolver.ctx, handle);
    }
};

/// Tiled rasterizer storing the full state of the rasterization progress.
pub const Rasterizer = struct {
    tile_states: TileStateCache = .init,

    tile_spans: [grid_size][grid_size]TileSpan = undefined, // [y][x]TileSpan

    cmd_sequence: [max_commandbuffer_size]u8 = @splat(0),
    cmd_sequence_len: usize = 0,

    current_tile: Tile align(64) = undefined,

    target: RenderTarget = undefined,

    tile_width: usize = 0,
    tile_height: usize = 0,

    screen_rect: Rectangle = undefined,

    resolver: Resolver = undefined,

    pub const ExecuteError = error{
        ImageTooLarge,
        StreamTooLong,
        InvalidStream,
        UnknownFramebuffer,
        UnknownFont,
    };

    /// Executes the given command sequence.
    ///
    /// In case of an error, the execution might have performed a partial rendering already.
    pub fn execute(rast: *Rasterizer, target: RenderTarget, resolver: Resolver, sequence: []const u8) ExecuteError!void {
        std.debug.assert(std.mem.isAligned(target.stride, tile_size));
        std.debug.assert(target.width <= target.stride);

        if (target.width >= max_image_size or target.height >= max_image_size)
            return error.ImageTooLarge;

        if (sequence.len > max_commandbuffer_size)
            return error.StreamTooLong;

        rast.resolver = resolver;

        // Copy the command sequence into our own buffers so we both
        // own it, and can guarantee it's stored in a fast RAM area.
        @memcpy(rast.cmd_sequence[0..sequence.len], sequence);
        rast.cmd_sequence_len = sequence.len;

        // We only initialize the tile states to uncovered,
        // but we don't initialize `tile_spans` or `tiles`
        // as we're only ever going to read the visited tiles
        rast.tile_states = .init;

        // `sweep_and_mark` also needs to know the size of the file render:
        rast.target = target;

        // Initialize all tile states. This decodes the stream
        // the first time, so it can potentially fail, and we
        // check the stream validity with it:
        rast.sweep_and_mark() catch |err| switch (err) {
            error.EndOfStream, error.InvalidCommand => return error.InvalidStream,
            error.UnknownFramebuffer => return error.UnknownFramebuffer,
            error.UnknownFont => return error.UnknownFont,
        };

        rast.render_all_tiles();
    }

    /// Goes through all tiles and record which commands need to be considered for the
    /// tile and what tiles are actually touched by the code.
    fn sweep_and_mark(rast: *Rasterizer) !void {
        var decoder: agp.BufferDecoder = .init(rast.cmd_sequence[0..rast.cmd_sequence_len]);

        const output_rect: Rectangle = .{
            .x = 0,
            .y = 0,
            .width = @min(rast.target.width, max_image_size),
            .height = @min(rast.target.height, max_image_size),
        };

        const tile_width = @divFloor(output_rect.width + tile_size - 1, tile_size);
        const tile_height = @divFloor(output_rect.height + tile_size - 1, tile_size);

        std.debug.assert(tile_width <= grid_size); // assert we're in bounds
        std.debug.assert(tile_height <= grid_size); // assert we're in bounds

        rast.tile_width = tile_width;
        rast.tile_height = tile_height;

        std.log.info("render image into {f}", .{output_rect});

        var start_of_cmd: u16 = 0;
        while (try decoder.next()) |cmd| {
            const end_of_cmd: u16 = @intCast(decoder.cursor);
            defer start_of_cmd = end_of_cmd;

            switch (cmd) {
                .blit_framebuffer => |blit| {
                    const fb = rast.resolver.resolve_framebuffer(blit.framebuffer);
                    if (fb == null)
                        return error.UnknownFramebuffer;
                },

                .blit_partial_framebuffer => |blit| {
                    const fb = rast.resolver.resolve_framebuffer(blit.framebuffer);
                    if (fb == null)
                        return error.UnknownFramebuffer;
                },

                .draw_text => |draw| {
                    const font = rast.resolver.resolve_font(draw.font);
                    if (font == null)
                        return error.UnknownFont;
                },

                else => {},
            }

            const cmd_area = rast.cmd_area_of_effect(&cmd);

            const potential_tile_area: TileArea = .from_rectangle(
                // Overlap effect area and image area so we don't activate tiles
                // outside the actual image:
                cmd_area.overlappedRegion(output_rect),
            );

            std.log.info("test cmd {t}: {f}, {}", .{
                cmd,
                cmd_area,
                potential_tile_area,
            });

            for (potential_tile_area.top..potential_tile_area.bottom) |tile_y| {
                std.debug.assert(tile_y < tile_height); // assert we're in bounds

                for (potential_tile_area.left..potential_tile_area.right) |tile_x| {
                    std.debug.assert(tile_x < tile_width); // assert we're in bounds

                    const index = tile_y * grid_size + tile_x;

                    const tile_rect = get_tile_rect(tile_x, tile_y);

                    const state = cmd_touches_rectangle(&cmd, tile_rect);
                    std.log.info("assign cmd {t} to {}/{}: {t}", .{ cmd, tile_x, tile_y, state });
                    if (state == .uncovered) {
                        // Ignore all tiles that aren't touched inside the bounding box.
                        continue;
                    }

                    const span = &rast.tile_spans[tile_y][tile_x];

                    const current_state = rast.tile_states.get(index);
                    if (current_state == .uncovered) {
                        // We're seeing this tile for the first time, let's initialize the
                        // command id and setup:
                        span.* = .{
                            .first_cmd_offset = start_of_cmd,
                            .last_cmd_offset = end_of_cmd,
                        };
                    }

                    if (state == .replaced) {
                        // If the tile is fully replaced by this command, we can
                        // skip all potential previous commands:
                        span.first_cmd_offset = start_of_cmd;
                    }

                    // Store the end of the command sequence that affect this tile:
                    span.last_cmd_offset = end_of_cmd;

                    rast.tile_states.set(index, state);
                }
            }
        }

        rast.screen_rect = output_rect;
    }

    fn cmd_area_of_effect(rast: *Rasterizer, cmd: *const Command) Rectangle {
        return switch (cmd.*) {
            .draw_text => |draw| blk: {
                // TODO: Implement correct text layouting engine:

                const font = rast.resolver.resolve_font(draw.font) orelse unreachable;
                const line_height: u16 = font.line_height();
                const width: u16 = font.measure_width(draw.text);

                break :blk .{
                    .x = draw.x,
                    .y = draw.y - @as(i16, @intCast(line_height)),
                    .width = width,
                    .height = line_height * 2,
                };
            },
            .blit_framebuffer => |blit| blk: {
                const image = rast.resolver.resolve_framebuffer(blit.framebuffer) orelse unreachable;
                break :blk .{
                    .x = blit.x,
                    .y = blit.y,
                    .width = image.width,
                    .height = image.height,
                };
            },
            inline else => |item| item.get_area_of_effect(),
        };
    }

    fn render_all_tiles(rast: *Rasterizer) void {
        var target_rect: Rectangle = .{
            .x = 0,
            .y = 0,
            .width = undefined,
            .height = undefined,
        };

        var row_index: usize = 0;
        for (rast.tile_spans[0..rast.tile_height], 0..) |*row_of_tile_spans, tile_y| {
            target_rect.height = get_tile_extend((tile_y == rast.tile_height - 1), rast.target.height);

            for (row_of_tile_spans[0..rast.tile_width], 0..) |*tile_span, tile_x| {
                const state = rast.tile_states.get(row_index + tile_x);
                switch (state) {
                    .uncovered => continue,

                    .updated => rast.fetch_tile_data(tile_x, tile_y),

                    // We just keep whatever was in the tile because we're
                    // going to overwrite it in any case
                    .replaced => {
                        var rng = std.Random.DefaultPrng.init(0);
                        rng.fill(std.mem.asBytes(&rast.current_tile));
                    },
                }

                target_rect.width = get_tile_extend((tile_x == rast.tile_width - 1), rast.target.width);

                var decoder: agp.BufferDecoder = .init(
                    rast.cmd_sequence[tile_span.first_cmd_offset..tile_span.last_cmd_offset],
                );

                const base = target_rect.position();

                std.log.info("render to {f}", .{target_rect});

                var clipped_rect = target_rect;
                while (decoder.next() catch unreachable) |cmd| {
                    switch (cmd) {
                        .set_clip_rect => |clip_rect_cmd| {
                            clipped_rect = target_rect.overlappedRegion(.{
                                .x = clip_rect_cmd.x,
                                .y = clip_rect_cmd.y,
                                .width = clip_rect_cmd.width,
                                .height = clip_rect_cmd.height,
                            });
                            std.debug.assert(clipped_rect.x >= target_rect.x);
                            std.debug.assert(clipped_rect.y >= target_rect.y);
                            std.debug.assert(clipped_rect.width <= tile_size);
                            std.debug.assert(clipped_rect.height <= tile_size);
                            std.log.info("updated clip to {f} by {}", .{ clipped_rect, clip_rect_cmd });
                        },

                        // That will dispatch each command to the "exec_*" command and call the function:
                        inline else => |item, tag| {
                            // Early clipping is easy:
                            if (clipped_rect.width == 0 or clipped_rect.height == 0)
                                continue;

                            @field(Rasterizer, "exec_" ++ @tagName(tag))(rast, item, base, clipped_rect);
                        },
                    }
                }

                // Write the data back to the target buffer:
                rast.flush_tile_data(tile_x, tile_y);

                target_rect.x += tile_size;
            }

            target_rect.x = 0;
            target_rect.y += tile_size;

            row_index += grid_size;
        }
    }

    fn fetch_tile_data(rast: *Rasterizer, tile_x: usize, tile_y: usize) void {
        std.debug.assert(std.mem.isAligned(rast.target.stride, tile_size));

        const height = get_tile_extend((tile_y == rast.tile_height - 1), rast.target.height);

        var src_scanline: [*]align(tile_size) const Color = @alignCast(rast.target.pixels + tile_y * tile_size * rast.target.stride);
        for (rast.current_tile[0..height]) |*dst_row| {
            @memcpy(dst_row, src_scanline[tile_size * tile_x ..][0..tile_size]);
            src_scanline = @alignCast(src_scanline + rast.target.stride);
        }
    }

    fn flush_tile_data(rast: *Rasterizer, tile_x: usize, tile_y: usize) void {
        std.debug.assert(std.mem.isAligned(rast.target.stride, tile_size));

        const height = get_tile_extend((tile_y == rast.tile_height - 1), rast.target.height);

        var dst_scanline: [*]align(tile_size) Color = @alignCast(rast.target.pixels + tile_y * tile_size * rast.target.stride);
        for (rast.current_tile[0..height]) |*src_row| {
            @memcpy(dst_scanline[tile_size * tile_x ..][0..tile_size], src_row);
            dst_scanline = @alignCast(dst_scanline + rast.target.stride);
        }
    }

    fn exec_clear(rast: *Rasterizer, cmd: agp.Command.Clear, base: Point, target_rect: Rectangle) void {
        std.log.info("clear({f}, {})", .{ target_rect, cmd });
        rast.exec_fill_rect(.{
            .color = cmd.color,
            .x = rast.screen_rect.x,
            .y = rast.screen_rect.y,
            .width = rast.screen_rect.width,
            .height = rast.screen_rect.height,
        }, base, target_rect);
    }

    fn exec_set_pixel(rast: *Rasterizer, cmd: agp.Command.SetPixel, base: Point, target_rect: Rectangle) void {
        if (target_rect.contains(.new(cmd.x, cmd.y))) {
            rast.current_tile[@intCast(cmd.y - base.y)][@intCast(cmd.x - base.x)] = cmd.color;
        }
    }

    fn exec_draw_line(rast: *Rasterizer, cmd: agp.Command.DrawLine, base: Point, target_rect: Rectangle) void {
        if (cmd.x1 == cmd.x2) {
            // vertical line
            if (!in_between(cmd.x1, target_rect.left(), target_rect.right()))
                return;

            const start: usize = @intCast(@max(target_rect.top(), @min(cmd.y1, cmd.y2)) - base.y);
            const end: usize = @intCast(@min(target_rect.bottom(), @max(cmd.y1, cmd.y2)) - base.y + 1);

            if (start < end) {
                for (rast.current_tile[start..end]) |*row| {
                    row[@intCast(cmd.x1 - base.x)] = cmd.color;
                }
            }
        } else if (cmd.y1 == cmd.y2) {
            // horizontal line
            if (!in_between(cmd.y1, target_rect.top(), target_rect.bottom()))
                return;

            const start: usize = @intCast(@max(target_rect.left(), @min(cmd.x1, cmd.x2)) - base.x);
            const end: usize = @intCast(@min(target_rect.right(), @max(cmd.x1, cmd.x2)) - base.x + 1);

            if (start < end) {
                @memset(rast.current_tile[@intCast(cmd.y1 - base.y)][start..end], cmd.color);
            }
        } else {
            const min_x = @min(cmd.x1, cmd.x2);
            const max_x = @max(cmd.x1, cmd.x2);
            const min_y = @min(cmd.y1, cmd.y2);
            const max_y = @max(cmd.y1, cmd.y2);

            if (max_x < target_rect.left() or min_x > target_rect.right())
                return;
            if (max_y < target_rect.top() or min_y > target_rect.bottom())
                return;

            var x0: i32 = cmd.x1;
            var y0: i32 = cmd.y1;
            const x1: i32 = cmd.x2;
            const y1: i32 = cmd.y2;

            const dx: i32 = @intCast(@abs(x1 - x0));
            const sx: i2 = if (x0 < x1) 1 else -1;
            const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
            const sy: i2 = if (y0 < y1) 1 else -1;
            var err: i32 = dx + dy;

            while (true) {
                if (in_between(x0, target_rect.left(), target_rect.right()) and
                    in_between(y0, target_rect.top(), target_rect.bottom()))
                {
                    rast.current_tile[@intCast(y0 - base.y)][@intCast(x0 - base.x)] = cmd.color;
                }

                if (x0 == x1 and y0 == y1)
                    break;

                const e2 = 2 * err;
                if (e2 > dy) {
                    err += dy;
                    x0 += sx;
                }
                if (e2 < dx) {
                    err += dx;
                    y0 += sy;
                }
            }
        }
    }

    fn in_between(value: anytype, min: anytype, max: anytype) bool {
        if (value < min)
            return false;
        if (value > max)
            return false;
        return true;
    }

    fn exec_draw_rect(rast: *Rasterizer, cmd: agp.Command.DrawRect, base: Point, target_rect: Rectangle) void {
        {
            if (in_between(cmd.y, target_rect.top(), target_rect.bottom())) {
                const left = @max(target_rect.left(), cmd.x) - base.x;
                const right = @min(target_rect.right() +| 1, cmd.x + @as(i32, cmd.width)) - base.x;

                if (left < right) {
                    @memset(rast.current_tile[@intCast(cmd.y - base.y)][@intCast(left)..@intCast(right)], cmd.color);
                }
            }
        }
        if (cmd.height > 1) {
            const bottom = @as(i32, cmd.y) + cmd.height - 1;
            if (in_between(bottom, target_rect.top(), target_rect.bottom())) {
                const left = @max(target_rect.left(), cmd.x) - base.x;
                const right = @min(target_rect.right() +| 1, cmd.x + @as(i32, cmd.width)) - base.x;

                if (left < right) {
                    @memset(rast.current_tile[@intCast(bottom - base.y)][@intCast(left)..@intCast(right)], cmd.color);
                }
            }
        }
        {
            if (in_between(cmd.x, target_rect.left(), target_rect.right())) {
                const top = @max(target_rect.top(), cmd.y) - base.y;
                const bottom = @min(target_rect.bottom() +| 1, cmd.y + @as(i32, cmd.height)) - base.y;

                if (top < bottom) {
                    for (@intCast(top)..@intCast(bottom)) |y| {
                        rast.current_tile[y][@intCast(cmd.x - base.x)] = cmd.color;
                    }
                }
            }
        }
        if (cmd.width > 1) {
            const right = @as(i32, cmd.x) + cmd.width - 1;
            if (in_between(right, target_rect.left(), target_rect.right())) {
                const top = @max(target_rect.top(), cmd.y) - base.y;
                const bottom = @min(target_rect.bottom() +| 1, cmd.y + @as(i32, cmd.height)) - base.y;

                if (top < bottom) {
                    for (@intCast(top)..@intCast(bottom)) |y| {
                        rast.current_tile[y][@intCast(right - base.x)] = cmd.color;
                    }
                }
            }
        }
    }

    fn exec_fill_rect(rast: *Rasterizer, cmd: agp.Command.FillRect, base: Point, target_rect: Rectangle) void {
        std.debug.assert(rast.screen_rect.containsRectangle(target_rect));

        const source: Rectangle = .{
            .x = cmd.x,
            .y = cmd.y,
            .width = cmd.width,
            .height = cmd.height,
        };

        const clipped = source.overlappedRegion(target_rect);
        if (clipped.empty())
            return;

        std.log.info("{f} {f} {f}", .{
            rast.screen_rect,
            target_rect,
            clipped,
        });
        std.debug.assert(rast.screen_rect.containsRectangle(clipped));
        std.debug.assert(target_rect.containsRectangle(clipped));

        std.debug.assert(clipped.x >= base.x);
        std.debug.assert(clipped.y >= base.y);
        std.debug.assert(clipped.width <= tile_size);
        std.debug.assert(clipped.height <= tile_size);

        std.debug.assert(clipped.x >= target_rect.x);
        std.debug.assert(clipped.y >= target_rect.y);
        std.debug.assert(clipped.width <= target_rect.width);
        std.debug.assert(clipped.height <= target_rect.height);

        for (rast.current_tile[@intCast(clipped.y - base.y)..][0..clipped.height]) |*dst_row| {
            @memset(dst_row[@intCast(clipped.x - base.x)..][0..clipped.width], cmd.color);
        }
    }

    fn exec_draw_text(rast: *Rasterizer, cmd: agp.Command.DrawText, base: Point, target_rect: Rectangle) void {
        _ = rast;
        _ = cmd;
        _ = target_rect;
        _ = base;
    }

    fn exec_blit_bitmap(rast: *Rasterizer, cmd: agp.Command.BlitBitmap, base: Point, target_rect: Rectangle) void {
        rast.exec_blit_partial_bitmap(.{
            .x = cmd.x,
            .y = cmd.y,
            .src_x = 0,
            .src_y = 0,
            .width = cmd.bitmap.width,
            .height = cmd.bitmap.height,
            .bitmap = cmd.bitmap,
        }, base, target_rect);
    }

    fn exec_blit_framebuffer(rast: *Rasterizer, cmd: agp.Command.BlitFramebuffer, base: Point, target_rect: Rectangle) void {
        // Get the framebuffer handle. We resolved that already earlier, so we know it exists:
        const image = rast.resolver.resolve_framebuffer(cmd.framebuffer) orelse unreachable;

        rast.exec_blit_partial_image(base, target_rect, .{
            .x = cmd.x,
            .y = cmd.y,
            .src_x = 0,
            .src_y = 0,
            .width = image.width,
            .height = image.height,
            .image = image,
        });
    }

    fn exec_blit_partial_bitmap(rast: *Rasterizer, cmd: agp.Command.BlitPartialBitmap, base: Point, target_rect: Rectangle) void {
        rast.exec_blit_partial_image(base, target_rect, .{
            .x = cmd.x,
            .y = cmd.y,
            .src_x = cmd.src_x,
            .src_y = cmd.src_y,
            .width = cmd.width,
            .height = cmd.height,
            .image = Image.from_bitmap(&cmd.bitmap),
        });
    }

    fn exec_blit_partial_framebuffer(rast: *Rasterizer, cmd: agp.Command.BlitPartialFramebuffer, base: Point, target_rect: Rectangle) void {

        // Get the framebuffer handle. We resolved that already earlier, so we know it exists:
        const image = rast.resolver.resolve_framebuffer(cmd.framebuffer) orelse unreachable;

        rast.exec_blit_partial_image(base, target_rect, .{
            .x = cmd.x,
            .y = cmd.y,
            .src_x = cmd.src_x,
            .src_y = cmd.src_y,
            .width = cmd.width,
            .height = cmd.height,
            .image = image,
        });
    }

    fn exec_blit_partial_image(rast: *Rasterizer, base: Point, clip_rect: Rectangle, cmd: struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        src_x: i16,
        src_y: i16,
        image: Image,
    }) void {
        std.debug.assert(rast.screen_rect.containsRectangle(clip_rect));

        const image: *const Image = &cmd.image;
        const target_pos: Point = .new(cmd.x, cmd.y);
        const source_pos: Point = .new(cmd.src_x, cmd.src_y);
        const size: Size = .new(cmd.width, cmd.height);

        const clip_rect_x: u16 = @intCast(clip_rect.x);
        const clip_rect_y: u16 = @intCast(clip_rect.y);

        if (target_pos.x >= rast.target.width)
            return;
        if (target_pos.y >= rast.target.height)
            return;

        const target_skip_x: u16 = @intCast(@max(0, -target_pos.x));
        const target_skip_y: u16 = @intCast(@max(0, -target_pos.y));

        // Source offset accounting for negative target position:
        const src_x: u16 = @intCast(source_pos.x + @as(i16, @intCast(target_skip_x)));
        const src_y: u16 = @intCast(source_pos.y + @as(i16, @intCast(target_skip_y)));

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
        const dst_avail_w = clip_rect_x + clip_rect.width -| dst_x;
        const dst_avail_h = clip_rect_y + clip_rect.height -| dst_y;

        const blit_w: u16 = @min(size.width -| target_skip_x, @min(src_avail_w, dst_avail_w));
        const blit_h: u16 = @min(size.height -| target_skip_y, @min(src_avail_h, dst_avail_h));

        if (blit_w == 0 or blit_h == 0)
            return;

        // Also clip against clip_rect left/top:
        const clip_skip_x: u16 = clip_rect_x -| dst_x;
        const clip_skip_y: u16 = clip_rect_y -| dst_y;

        const actual_src_x = src_x + clip_skip_x;
        const actual_dst_x = dst_x + clip_skip_x - @as(usize, @intCast(base.x));
        const actual_src_y = src_y + clip_skip_y;
        const actual_dst_y = dst_y + clip_skip_y - @as(usize, @intCast(base.y));
        const actual_w = blit_w -| clip_skip_x;
        const actual_h = blit_h -| clip_skip_y;

        if (actual_w == 0 or actual_h == 0)
            return;

        std.debug.assert(actual_w <= clip_rect.width);
        std.debug.assert(actual_h <= clip_rect.height);

        if (image.transparency_key) |key| {
            for (rast.current_tile[actual_dst_y..][0..actual_h], 0..) |*dst_row, dy| {
                const sy: u16 = actual_src_y + @as(u16, @intCast(dy));
                const src_row = image.slice(actual_src_x, sy, actual_w);
                for (dst_row[actual_dst_x..][0..actual_w], src_row) |*dst, src| {
                    if (src != key) {
                        dst.* = src;
                    }
                }
            }
        } else {
            for (rast.current_tile[actual_dst_y..][0..actual_h], 0..) |*dst_row, dy| {
                const sy: u16 = actual_src_y + @as(u16, @intCast(dy));
                const src_row = image.slice(actual_src_x, sy, actual_w);
                @memcpy(dst_row[actual_dst_x..][0..actual_w], src_row);
            }
        }
    }
};

/// Returns if the rectangle will actually be processed by `cmd`.
fn cmd_touches_rectangle(cmd: *const Command, rect: Rectangle) TileState {
    _ = cmd;
    _ = rect;
    return .updated;
}

/// Gets the rectangle pixel area for a given tile index.
fn get_tile_rect(x: usize, y: usize) Rectangle {
    std.debug.assert(x < tile_count);
    std.debug.assert(y < tile_count);
    return .{
        .x = @intCast(x * tile_size),
        .y = @intCast(y * tile_size),
        .width = tile_size,
        .height = tile_size,
    };
}

const TileArea = struct {
    left: usize, // inclusive
    right: usize, // inclusive
    top: usize, // exclude
    bottom: usize, // exclude

    fn from_rectangle(rect: Rectangle) TileArea {
        if (rect.width == 0 or rect.height == 0) {
            return .{
                .left = 0,
                .right = 0,
                .top = 0,
                .bottom = 0,
            };
        }

        const left = @max(rect.x, 0);
        const top = @max(rect.y, 0);

        const right: usize = @intCast(@max(0, @min(rect.x + @as(i32, rect.width) - 1, max_image_size - 1)));
        const bottom: usize = @intCast(@max(0, @min(rect.y + @as(i32, rect.height) - 1, max_image_size - 1)));

        const area: TileArea = .{
            .left = @divFloor(left, tile_size), // flooring division to get left-most tile
            .top = @divFloor(top, tile_size), // flooring division to get top-most tile
            .right = @divFloor(right, tile_size) + 1, // ceiling division to get right-most tile
            .bottom = @divFloor(bottom, tile_size) + 1, // ceiling division to get bottom-most tile
        };
        std.debug.assert(area.left < grid_size);
        std.debug.assert(area.top < grid_size);
        std.debug.assert(area.right <= grid_size);
        std.debug.assert(area.bottom <= grid_size);
        return area;
    }
};

fn get_tile_extend(last: bool, dimension: u16) u16 {
    if (!last)
        return tile_size;
    const size = dimension & (tile_size - 1);
    if (size == 0)
        return tile_size;
    return size;
}

// Assert invariants:

inline fn assert_max_size(comptime T: type, size_limit: comptime_int) void {
    if (@sizeOf(T) <= size_limit)
        return;
    @compileError(std.fmt.comptimePrint("{} is {} bytes large and exceeds the limit of {} bytes", .{
        T,
        @sizeOf(T),
        size_limit,
    }));
}
inline fn assert_exact_size(comptime T: type, size_limit: comptime_int) void {
    if (@sizeOf(T) == size_limit)
        return;
    @compileError(std.fmt.comptimePrint("Expected {} to be {} bytes large, but it actually is {} bytes", .{
        T,
        size_limit,
        @sizeOf(T),
    }));
}

comptime {
    // We only want to store 2 bit per tile in any case:
    assert_exact_size(TileStateCache, tile_count / 4);

    if (max_commandbuffer_size >= std.math.maxInt(u16))
        @compileError("The maximum command buffer length is 65536");

    assert_max_size(Rasterizer, 128 * 1024);
    assert_exact_size([grid_size][grid_size]TileSpan, 4096);
    assert_exact_size(Tile, 4096);

    std.debug.assert(std.math.isPowerOfTwo(max_image_size));
    std.debug.assert(std.math.isPowerOfTwo(grid_size));
    std.debug.assert(std.math.isPowerOfTwo(tile_size));
}

test TileStateCache {
    var cache: TileStateCache = .init;

    for (0..tile_count) |i| {
        try std.testing.expectEqual(TileState.uncovered, cache.get(i));
    }

    var rng: std.Random.DefaultPrng = .init(std.testing.random_seed);

    var mirror: [tile_count]TileState = @splat(.uncovered);

    for (0..1000) |_| {
        const i: usize = rng.random().intRangeLessThan(usize, 0, tile_count);

        const next = rng.random().enumValue(TileState);

        try std.testing.expectEqual(mirror[i], cache.get(i));

        cache.set(i, next);
        mirror[i] = next;

        for (0..tile_count) |j| {
            try std.testing.expectEqual(mirror[j], cache.get(j));
        }
    }
}

const TestResolver = struct {
    const vtable: Resolver.VTable = .{
        .resolve_font_fn = resolveFont,
        .resolve_framebuffer_fn = resolveFramebuffer,
    };

    fn resolver() Resolver {
        return .{
            .ctx = @ptrFromInt(1),
            .vtable = &vtable,
        };
    }

    fn resolveFont(_: *anyopaque, _: Font) ?*const FontInstance {
        return null;
    }

    fn resolveFramebuffer(_: *anyopaque, _: agp.Framebuffer) ?Image {
        return null;
    }
};

test "Rasterizer smoke" {
    var rast: Rasterizer = .{};

    var buffer: [140 * 192]Color align(64) = @splat(.black);

    const target: RenderTarget = .{
        .width = 150,
        .height = 140,
        .stride = 192,
        .pixels = &buffer,
    };

    try rast.execute(target, TestResolver.resolver(), "");
}

test "Rectangle.overlappedRegion" {
    try std.testing.expectEqualDeep(
        Rectangle{
            .x = 6,
            .y = 4,
            .width = 4,
            .height = 4,
        },
        (Rectangle{
            .x = 2,
            .y = 2,
            .width = 8,
            .height = 6,
        }).overlappedRegion(.{
            .x = 6,
            .y = 4,
            .width = 8,
            .height = 8,
        }),
    );

    try std.testing.expectEqualDeep(
        Rectangle{
            .x = 5,
            .y = 6,
            .width = 2,
            .height = 3,
        },
        (Rectangle{
            .x = 0,
            .y = 0,
            .width = 16,
            .height = 16,
        }).overlappedRegion(.{
            .x = 5,
            .y = 6,
            .width = 2,
            .height = 3,
        }),
    );

    try std.testing.expectEqualDeep(
        Rectangle{
            .x = 20,
            .y = 10,
            .width = 0,
            .height = 0,
        },
        (Rectangle{
            .x = 0,
            .y = 0,
            .width = 8,
            .height = 8,
        }).overlappedRegion(.{
            .x = 20,
            .y = 10,
            .width = 4,
            .height = 4,
        }),
    );
}

test "Rasterizer renders clipped diagonal lines across tiles" {
    var rast: Rasterizer = .{};

    var buffer: [96 * 128]Color align(64) = @splat(.black);

    const target: RenderTarget = .{
        .width = 96,
        .height = 96,
        .stride = 128,
        .pixels = &buffer,
    };

    var stream: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer stream.deinit();
    const enc = agp.encoder(&stream.writer);
    try enc.draw_line(-5, 70, 70, -5, .yellow);
    try rast.execute(target, TestResolver.resolver(), stream.written());

    try std.testing.expectEqual(Color.yellow, buffer[0 * target.stride + 65]);
    try std.testing.expectEqual(Color.yellow, buffer[1 * target.stride + 64]);
    try std.testing.expectEqual(Color.yellow, buffer[63 * target.stride + 2]);
    try std.testing.expectEqual(Color.yellow, buffer[64 * target.stride + 1]);
    try std.testing.expectEqual(Color.yellow, buffer[65 * target.stride + 0]);

    try std.testing.expectEqual(Color.black, buffer[0 * target.stride + 64]);
    try std.testing.expectEqual(Color.black, buffer[64 * target.stride + 0]);
    try std.testing.expectEqual(Color.black, buffer[66 * target.stride + 0]);
}
