const std = @import("std");
const ashet = @import("ashet");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

const Bitmap = @This();

width: u15,
height: u15,
stride: u16,
pixels: [*]const ColorIndex,
transparent: ?ColorIndex = null, // if set, this color value is considered transparent and can be skipped

pub const EmbeddedBitmap = struct { bitmap: Bitmap, palette: []const ashet.abi.Color };
pub fn embed(comptime bits: []const u8) EmbeddedBitmap {
    comptime {
        const Header = extern struct {
            magic: u32,
            width: u16,
            height: u16,
            flags: u16,
            palette_size: u8,
            transparency_key: u8,

            pub fn paletteSize(self: @This()) u9 {
                return if (self.palette_size == 0)
                    256
                else
                    self.palette_size;
            }
        };

        const head = @as(Header, @bitCast(bits[0..@sizeOf(Header)].*));
        if (head.magic != 0x48198b74)
            @compileError("Invalid file format. Bitmap.embed expects a Ashet Bitmap!");

        const pixel_count = head.width * head.height;
        const palette_size = head.paletteSize();

        const pixels = @as([pixel_count]ColorIndex, @bitCast(bits[@sizeOf(Header)..][0..pixel_count].*));
        const palette = @as([palette_size]ashet.abi.Color, @bitCast(bits[@sizeOf(Header) + pixel_count ..][0 .. 2 * palette_size].*));

        return EmbeddedBitmap{
            .bitmap = Bitmap{
                .width = head.width,
                .height = head.height,
                .stride = head.width,
                .pixels = &pixels,
                .transparent = if ((head.flags & 1) != 0)
                    ColorIndex.get(head.transparency_key)
                else
                    null,
            },
            .palette = &palette,
        };
    }
}

pub fn parse(comptime base: u8, comptime spec: []const u8) Bitmap {
    const bmp = comptime blk: {
        @setEvalBranchQuota(100_000);

        std.debug.assert(base <= 256 - 16);
        var height = 0;
        var width = 0;

        var used = std.bit_set.IntegerBitSet(16).initFull();

        {
            var it = std.mem.splitScalar(u8, spec, '\n');
            while (it.next()) |line| {
                if (line.len > width) width = line.len;
                height += 1;

                for (line, 0..) |char, x| {
                    if (std.fmt.parseInt(u8, line[x .. x + 1], 16)) |value| {
                        used.unset(value);
                    } else |_| {
                        if (char != '.' and char != ' ')
                            @compileError(std.fmt.comptimePrint("Illegal character in bitmap: {c}", .{char}));
                    }
                }
            }
        }

        const transparent: ?ColorIndex = if (used.findFirstSet()) |first|
            ColorIndex.get(base + @as(u8, @intCast(first)))
        else
            null;

        var buffer = [1][width]ColorIndex{[1]ColorIndex{ColorIndex.get(0)} ** width} ** height;
        {
            var it = std.mem.splitScalar(u8, spec, '\n');
            var y = 0;
            while (it.next()) |line| : (y += 1) {
                for (line, 0..) |_, x| {
                    const value: ?u8 = std.fmt.parseInt(u8, line[x .. x + 1], 16) catch null;

                    buffer[y][x] = if (value) |val|
                        ColorIndex.get(base + val)
                    else if (transparent) |val|
                        val
                    else
                        @compileError("Icon uses all 16 available colors, transparency not supported!");
                }
            }
        }

        const const_buffer = buffer;

        break :blk Bitmap{
            .width = width,
            .height = height,
            .stride = width,
            .pixels = @as([*]const ColorIndex, @ptrCast(&const_buffer)),
            .transparent = transparent,
        };
    };
    return bmp;
}

test "bitmap parse" {
    const icon = Bitmap.parse(0,
        \\0123456789ABCDEF
    );
    try std.testing.expectEqual(@as(u16, 16), icon.width);
    try std.testing.expectEqual(@as(u16, 1), icon.height);
    try std.testing.expectEqual(@as(u16, 16), icon.stride);
    try std.testing.expectEqual(@as(?ColorIndex, null), icon.transparent);
    try std.testing.expectEqualSlices(ColorIndex, &.{
        ColorIndex.get(0),  ColorIndex.get(1),  ColorIndex.get(2),  ColorIndex.get(3),
        ColorIndex.get(4),  ColorIndex.get(5),  ColorIndex.get(6),  ColorIndex.get(7),
        ColorIndex.get(8),  ColorIndex.get(9),  ColorIndex.get(10), ColorIndex.get(11),
        ColorIndex.get(12), ColorIndex.get(13), ColorIndex.get(14), ColorIndex.get(15),
    }, icon.pixels[0..icon.width]);
}

test "bitmap parse with offset" {
    const icon = Bitmap.parse(240,
        \\0123456789ABCDEF
    );
    try std.testing.expectEqual(@as(u16, 16), icon.width);
    try std.testing.expectEqual(@as(u16, 1), icon.height);
    try std.testing.expectEqual(@as(u16, 16), icon.stride);
    try std.testing.expectEqual(@as(?ColorIndex, null), icon.transparent);
    try std.testing.expectEqualSlices(ColorIndex, &.{
        ColorIndex.get(240 + 0),  ColorIndex.get(240 + 1),  ColorIndex.get(240 + 2),  ColorIndex.get(240 + 3),
        ColorIndex.get(240 + 4),  ColorIndex.get(240 + 5),  ColorIndex.get(240 + 6),  ColorIndex.get(240 + 7),
        ColorIndex.get(240 + 8),  ColorIndex.get(240 + 9),  ColorIndex.get(240 + 10), ColorIndex.get(240 + 11),
        ColorIndex.get(240 + 12), ColorIndex.get(240 + 13), ColorIndex.get(240 + 14), ColorIndex.get(240 + 15),
    }, icon.pixels[0..icon.width]);
}

test "bitmap parse with transparency 1" {
    const icon = Bitmap.parse(0,
        \\123456
    );
    try std.testing.expectEqual(@as(u16, 6), icon.width);
    try std.testing.expectEqual(@as(u16, 1), icon.height);
    try std.testing.expectEqual(@as(u16, 6), icon.stride);
    try std.testing.expectEqual(@as(?ColorIndex, ColorIndex.get(0)), icon.transparent);
}

test "bitmap parse with transparency 2" {
    const icon = Bitmap.parse(240,
        \\0123456
    );
    try std.testing.expectEqual(@as(u16, 7), icon.width);
    try std.testing.expectEqual(@as(u16, 1), icon.height);
    try std.testing.expectEqual(@as(u16, 7), icon.stride);
    try std.testing.expectEqual(@as(?ColorIndex, ColorIndex.get(247)), icon.transparent);
}

test "bitmap parse rectangular" {
    const icon = Bitmap.parse(0,
        \\0123
        \\4567
        \\89AB
        \\CDEF
    );
    try std.testing.expectEqual(@as(u16, 4), icon.width);
    try std.testing.expectEqual(@as(u16, 4), icon.height);
    try std.testing.expectEqual(@as(u16, 4), icon.stride);
    try std.testing.expectEqual(@as(?ColorIndex, null), icon.transparent);
    try std.testing.expectEqualSlices(ColorIndex, &.{
        ColorIndex.get(0),  ColorIndex.get(1),  ColorIndex.get(2),  ColorIndex.get(3),
        ColorIndex.get(4),  ColorIndex.get(5),  ColorIndex.get(6),  ColorIndex.get(7),
        ColorIndex.get(8),  ColorIndex.get(9),  ColorIndex.get(10), ColorIndex.get(11),
        ColorIndex.get(12), ColorIndex.get(13), ColorIndex.get(14), ColorIndex.get(15),
    }, icon.pixels[0 .. icon.stride * icon.height]);
}
