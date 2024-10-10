const std = @import("std");
const ashet = @import("ashet");

const ColorIndex = ashet.abi.ColorIndex;
const Size = ashet.abi.Size;

pub const maximize = parse(0,
    \\.........
    \\.FFFFFFF.
    \\.F.....F.
    \\.FFFFFFF.
    \\.F.....F.
    \\.F.....F.
    \\.F.....F.
    \\.FFFFFFF.
    \\.........
);

pub const minimize = parse(0,
    \\.........
    \\.........
    \\.........
    \\.........
    \\.........
    \\.........
    \\.........
    \\..FFFFF..
    \\.........
);

pub const restore = parse(0,
    \\.........
    \\...FFFFF.
    \\...F...F.
    \\.FFFFF.F.
    \\.FFFFF.F.
    \\.F...FFF.
    \\.F...F...
    \\.FFFFF...
    \\.........
);

pub const restore_from_tray = parse(0,
    \\.........
    \\..FFFFF..
    \\.........
    \\.........
    \\.........
    \\.........
    \\.........
    \\.........
    \\.........
);

pub const close = parse(0,
    \\444444444
    \\444444444
    \\44F444F44
    \\444F4F444
    \\4444F4444
    \\444F4F444
    \\44F444F44
    \\444444444
    \\444444444
);

pub const resize = parse(0,
    \\.........
    \\.FFF.....
    \\.F.F.....
    \\.FFFFFFF.
    \\...F...F.
    \\...F...F.
    \\...F...F.
    \\...FFFFF.
    \\.........
);

pub const cursor = parse(0,
    \\BBB..........
    \\9FFBB........
    \\9FFFFBB......
    \\.9FFFFFBB....
    \\.9FFFFFFFBB..
    \\..9FFFFFFFFB.
    \\..9FFFFFFFB..
    \\...9FFFFFB...
    \\...9FFFFFB...
    \\....9FF99FB..
    \\....9F9..9FB.
    \\.....9....9FB
    \\...........9.
);

fn parse(comptime base: comptime_int, comptime def: []const u8) *const ashet.graphics.Bitmap {
    @setEvalBranchQuota(10_000);

    const size = parsedSpriteSize(def);
    var icon: [size.height][size.width]?ColorIndex = [1][size.width]?ColorIndex{
        [1]?ColorIndex{null} ** size.width,
    } ** size.height;

    var needs_transparency = false;
    var can_use_0xFF = true;
    var can_use_0x00 = true;

    var it = std.mem.splitScalar(u8, def, '\n');
    var y: usize = 0;
    while (it.next()) |line| : (y += 1) {
        var x: usize = 0;
        while (x < icon[0].len) : (x += 1) {
            icon[y][x] = if (std.fmt.parseInt(u8, line[x .. x + 1], 16)) |index|
                ColorIndex.get(base + index)
            else |_|
                null;
            if (icon[y][x] == null)
                needs_transparency = true;
            if (icon[y][x] == ColorIndex.get(0x00))
                can_use_0x00 = false;
            if (icon[y][x] == ColorIndex.get(0xFF))
                can_use_0xFF = false;
        }
    }

    const transparency_key: ColorIndex = if (needs_transparency)
        if (can_use_0x00)
            ColorIndex.get(0x00)
        else if (can_use_0xFF)
            ColorIndex.get(0xFF)
        else
            @compileError("Can't declare an icon that uses both 0xFF and 0x00!")
    else
        undefined;

    var output_bits: [size.height * size.width]ColorIndex = undefined;
    var index: usize = 0;
    for (icon) |row| {
        for (row) |pixel| {
            output_bits[index] = pixel orelse transparency_key;
            index += 1;
        }
    }

    const const_output_bits = output_bits;

    return comptime &ashet.graphics.Bitmap{
        .pixels = &const_output_bits,
        .width = size.width,
        .height = size.height,
        .stride = size.width,
        .transparency_key = if (needs_transparency)
            transparency_key
        else
            null,
    };
}

fn parsedSpriteSize(comptime def: []const u8) Size {
    var it = std.mem.splitScalar(u8, def, '\n');
    const first = it.next().?;
    const width = first.len;
    var height = 1;
    while (it.next()) |line| {
        std.debug.assert(line.len == width);
        height += 1;
    }
    return .{ .width = width, .height = height };
}
