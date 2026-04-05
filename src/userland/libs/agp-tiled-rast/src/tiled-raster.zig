const std = @import("std");
const agp = @import("agp");
const ashet = @import("ashet-abi");

const Color = ashet.Color;
const Point = ashet.Point;
const Size = ashet.Size;
const Rectangle = ashet.Rectangle;
const Bitmap = agp.Bitmap;
const Command = agp.Command;

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

/// Tiled rasterizer storing the full state of the rasterization progress.
pub const Rasterizer = struct {
    tile_states: TileStateCache = .init,

    tile_spans: [grid_size][grid_size]TileSpan = undefined, // [y][x]TileSpan

    cmd_sequence: [max_commandbuffer_size]u8 = @splat(0),
    cmd_sequence_len: usize = 0,

    current_tile: Tile = undefined,

    target: RenderTarget = undefined,

    pub const ExecuteError = error{ ImageTooLarge, StreamTooLong, InvalidStream };

    /// Executes the given command sequence.
    ///
    /// In case of an error, the execution might have performed a partial rendering already.
    pub fn execute(rast: *Rasterizer, target: RenderTarget, sequence: []const u8) ExecuteError!void {
        std.debug.assert(std.mem.isAligned(target.stride, tile_size));
        std.debug.assert(target.width <= target.stride);

        if (target.width >= max_image_size or target.height >= max_image_size)
            return error.ImageTooLarge;

        if (sequence.len > max_commandbuffer_size)
            return error.StreamTooLong;

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
        };
    }

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

        var start_of_cmd: u16 = 0;
        while (try decoder.next()) |cmd| {
            const end_of_cmd: u16 = @intCast(decoder.cursor);
            defer start_of_cmd = end_of_cmd;

            const cmd_area = cmd.get_area_of_effect();

            const potential_tile_area: TileArea = .from_rectangle(
                // Overlap effect area and image area so we don't activate tiles
                // outside the actual image:
                cmd_area.overlappedRegion(output_rect),
            );

            for (potential_tile_area.top..potential_tile_area.bottom) |tile_y| {
                std.debug.assert(tile_y < tile_height); // assert we're in bounds

                for (potential_tile_area.left..potential_tile_area.right) |tile_x| {
                    std.debug.assert(tile_x < tile_width); // assert we're in bounds

                    const index = tile_y * grid_size + tile_x;

                    const tile_rect = get_tile_rect(tile_x, tile_y);

                    const state = cmd_touches_rectangle(&cmd, tile_rect);
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
                }
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

test "Rasterizer smoke" {
    var rast: Rasterizer = .{};

    var buffer: [140 * 192]Color align(64) = @splat(.black);

    const target: RenderTarget = .{
        .width = 150,
        .height = 140,
        .stride = 192,
        .pixels = &buffer,
    };

    try rast.execute(target, "");
}
