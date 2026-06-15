/// Ashet OS 256-color palette: comptime lookup table converting the 8-bit
/// "Ashet HSV" color format to RGBA. Ported from the ABI's `to_rgb888()`.
///
/// Bit layout of an 8-bit color byte:
///   [7:6] saturation (u2)
///   [5:3] value      (u3)
///   [2:0] hue        (u3)
///
/// When saturation == 0 the low 6 bits form a grayscale value (64 grays).
/// Otherwise the fields are interpreted as HSV and converted to RGB.

pub const RGBA = [4]u8;

/// Precomputed at comptime: `table[i]` is the RGBA color for palette index `i`.
pub const table: [256]RGBA = blk: {
    var lut: [256]RGBA = undefined;
    for (0..256) |i| {
        lut[i] = ashetToRgba(@intCast(i));
    }
    break :blk lut;
};

fn ashetToRgba(raw: u8) RGBA {
    const hue: u3 = @truncate(raw);
    const value: u3 = @truncate(raw >> 3);
    const saturation: u2 = @truncate(raw >> 6);

    if (saturation == 0) {
        // Grayscale: the low 6 bits form a 6-bit gray value.
        const gray6: u6 = @truncate(raw);
        const gray8 = expandChannel(gray6);
        return .{ gray8, gray8, gray8, 255 };
    }

    const h: f32 = 360.0 * @as(f32, @floatFromInt(hue)) / 8.0;
    const v: f32 = (1.0 + @as(f32, @floatFromInt(value))) / 8.0;
    const s: f32 = @as(f32, @floatFromInt(saturation)) / 3.0;

    const C: f32 = v * s;
    const hp: f32 = h / 60.0;
    const k: f32 = hp - 2.0 * @floor(hp / 2.0);
    const X: f32 = C * (1.0 - @abs(k - 1.0));
    const m: f32 = v - C;

    const i: i32 = @intFromFloat(@floor(hp));
    const rp: f32, const gp: f32, const bp: f32 = switch (i) {
        0 => .{ C, X, 0 },
        1 => .{ X, C, 0 },
        2 => .{ 0, C, X },
        3 => .{ 0, X, C },
        4 => .{ X, 0, C },
        5 => .{ C, 0, X },
        else => unreachable,
    };

    return .{
        @intFromFloat(255.0 * (rp + m)),
        @intFromFloat(255.0 * (gp + m)),
        @intFromFloat(255.0 * (bp + m)),
        255,
    };
}

fn expandChannel(src_value: anytype) u8 {
    const bits = @bitSizeOf(@TypeOf(src_value));
    if (bits > 8) @compileError("src_value must have 8 bits or less");

    comptime var mask: u8 = ((1 << bits) - 1) << (8 - bits);
    var pattern: u8 = @as(u8, src_value) << (8 - bits);
    var result: u8 = 0;
    inline while (mask != 0) {
        result |= pattern;
        mask >>= bits;
        pattern >>= bits;
    }
    return result;
}
