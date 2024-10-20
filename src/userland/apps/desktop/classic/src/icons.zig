const std = @import("std");
const ashet = @import("ashet");

const ColorIndex = ashet.abi.ColorIndex;
const Size = ashet.abi.Size;

const parse = ashet.graphics.embed_comptime_bitmap;

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
