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

fn ParseResult(comptime def: []const u8) type {
    const size = parsedSpriteSize(def);
    return [size.height][size.width]?ColorIndex;
}

fn parse(comptime def: []const u8) ParseResult(def) {
    @setEvalBranchQuota(10_000);

    const size = parsedSpriteSize(def);
    var icon: [size.height][size.width]?ColorIndex = [1][size.width]?ColorIndex{
        [1]?ColorIndex{null} ** size.width,
    } ** size.height;

    var it = std.mem.splitScalar(u8, def, '\n');
    var y: usize = 0;
    while (it.next()) |line| : (y += 1) {
        var x: usize = 0;
        while (x < icon[0].len) : (x += 1) {
            icon[y][x] = if (std.fmt.parseInt(u8, line[x .. x + 1], 16)) |index|
                ColorIndex.get(index)
            else |_|
                null;
        }
    }
    return icon;
}

pub const maximize = Bitmap.parse(0,
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

pub const minimize = Bitmap.parse(0,
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

pub const restore = Bitmap.parse(0,
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

pub const restore_from_tray = Bitmap.parse(0,
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

pub const close = Bitmap.parse(0,
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

pub const resize = Bitmap.parse(0,
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

pub const cursor = Bitmap.parse(0,
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
