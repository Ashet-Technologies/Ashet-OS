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

pub fn parse(comptime base: u8, comptime spec: []const u8) Bitmap {
    const bmp = comptime blk: {
        @setEvalBranchQuota(100_000);

        std.debug.assert(base <= 256 - 16);
        var height = 0;
        var width = 0;

        var used = std.bit_set.IntegerBitSet(16).initFull();

        {
            var it = std.mem.split(u8, spec, "\n");
            while (it.next()) |line| {
                if (line.len > width) width = line.len;
                height += 1;

                for (line) |char, x| {
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
            ColorIndex.get(base + @intCast(u8, first))
        else
            null;

        var buffer = [1][width]ColorIndex{[1]ColorIndex{ColorIndex.get(0)} ** width} ** height;
        {
            var it = std.mem.split(u8, spec, "\n");
            var y = 0;
            while (it.next()) |line| : (y += 1) {
                for (line) |_, x| {
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

        break :blk Bitmap{
            .width = width,
            .height = height,
            .stride = width,
            .pixels = @ptrCast([*]ColorIndex, &buffer),
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

test "bitmap parse with transparency" {
    const icon = Bitmap.parse(0,
        \\123456
    );
    try std.testing.expectEqual(@as(u16, 6), icon.width);
    try std.testing.expectEqual(@as(u16, 1), icon.height);
    try std.testing.expectEqual(@as(u16, 6), icon.stride);
    try std.testing.expectEqual(@as(?ColorIndex, ColorIndex.get(0)), icon.transparent);
}

test "bitmap parse with transparency" {
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
