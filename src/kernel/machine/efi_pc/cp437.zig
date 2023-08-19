const std = @import("std");

/// Code page number
pub const number = 437;

const mapping = [256]u21{
    //0   1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
    0x00, '☺', '☻', '♥', '♦', '♣', '♠', '•', '◘', '○', '◙', '♂', '♀', '♪', '♫', '☼', // 0x0*
    '►', '◄', '↕', '‼', '¶', '§', '▬', '↨', '↑', '↓', '→', '←', '∟', '↔', '▲', '▼', // 0x1*
    ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/', // 0x2*
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', // 0x3*
    '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', // 0x4*
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', // 0x5*
    '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', // 0x6*
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~', '⌂', // 0x7*
    'Ç', 'ü', 'é', 'â', 'ä', 'à', 'å', 'ç', 'ê', 'ë', 'è', 'ï', 'î', 'ì', 'Ä', 'Å', // 0x8*
    'É', 'æ', 'Æ', 'ô', 'ö', 'ò', 'û', 'ù', 'ÿ', 'Ö', 'Ü', '¢', '£', '¥', '₧', 'ƒ', // 0x9*
    'á', 'í', 'ó', 'ú', 'ñ', 'Ñ', 'ª', 'º', '¿', '⌐', '¬', '½', '¼', '¡', '«', '»', // 0xA*
    '░', '▒', '▓', '│', '┤', '╡', '╢', '╖', '╕', '╣', '║', '╗', '╝', '╜', '╛', '┐', // 0xB*
    '└', '┴', '┬', '├', '─', '┼', '╞', '╟', '╚', '╔', '╩', '╦', '╠', '═', '╬', '╧', // 0xC*
    '╨', '╤', '╥', '╙', '╘', '╒', '╓', '╫', '╪', '┘', '┌', '█', '▄', '▌', '▐', '▀', // 0xD*
    'α', 'ß', 'Γ', 'π', 'Σ', 'σ', 'µ', 'τ', 'Φ', 'Θ', 'Ω', 'δ', '∞', 'φ', 'ε', '∩', // 0xE*
    '≡', '±', '≥', '≤', '⌠', '⌡', '÷', '≈', '°', '∙', '·', '√', 'ⁿ', '²', '■', 0xA0, // 0xF*
};

const Range = struct {
    codepage: u8,
    unicode: u21,
    len: u8,
};

const ranges = blk: {
    var list: []const Range = &.{};

    var i = 0;
    while (i < 256) {
        const range_start = mapping[i];

        var cnt = 0;
        const len = while (i + cnt < 256) : (cnt += 1) {
            if (mapping[i + cnt] != range_start + cnt)
                break cnt;
        } else 256 - i;

        if (len > 3) { // minimum threshold to generate a codepoint range
            list = list ++ [_]Range{
                Range{ .codepage = i, .unicode = range_start, .len = len },
            };
        }

        i += len;
    }

    var result: [list.len]Range = undefined;
    std.mem.copyForwards(Range, &result, list);
    break :blk result;
};

pub fn codepageFromUnicode(cp: u21) ?u8 {
    if (comptime ranges.len > 3) {
        inline for (ranges) |range| {
            if (cp >= range.unicode and cp < range.unicode + range.len)
                return @as(u8, @truncate(cp - range.unicode + range.codepage));
        }
    } else {
        inline for (ranges) |range| {
            if (cp >= range.unicode and cp < range.unicode + range.len)
                return @as(u8, @truncate(cp - range.unicode + range.codepage));
        }
    }
    inline for (mapping, 0..) |unicode, codepage| {
        const is_in_range = comptime for (ranges) |range| {
            if (unicode >= range.unicode and unicode < range.unicode + range.len)
                break true;
        } else false;
        if (comptime !is_in_range) {
            if (unicode == cp)
                return codepage;
        }
    }
    return null;
}

test codepageFromUnicode {
    // test the range checks:
    try std.testing.expectEqual(@as(?u8, 'A'), codepageFromUnicode('A'));
    try std.testing.expectEqual(@as(?u8, 'T'), codepageFromUnicode('T'));
    try std.testing.expectEqual(@as(?u8, '9'), codepageFromUnicode('9'));

    // mapped elements:
    try std.testing.expectEqual(@as(?u8, 0xCA), codepageFromUnicode('╩'));
    try std.testing.expectEqual(@as(?u8, 0x13), codepageFromUnicode('‼'));

    // non-mapped element:
    try std.testing.expectEqual(@as(?u8, null), codepageFromUnicode('€'));
}

pub fn unicodeFromCodepage(cp: u8) u21 {
    return mapping[cp];
}

test unicodeFromCodepage {
    // test the range checks:
    try std.testing.expectEqual(@as(u21, 'A'), unicodeFromCodepage('A'));
    try std.testing.expectEqual(@as(u21, 'T'), unicodeFromCodepage('T'));
    try std.testing.expectEqual(@as(u21, '9'), unicodeFromCodepage('9'));

    // mapped elements:
    try std.testing.expectEqual(@as(u21, '╩'), unicodeFromCodepage(0xCA));
    try std.testing.expectEqual(@as(u21, '‼'), unicodeFromCodepage(0x13));
}
