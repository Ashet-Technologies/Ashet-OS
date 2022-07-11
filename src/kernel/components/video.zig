const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");

pub const max_res_x = 400;
pub const max_res_y = 300;

/// The raw exposed video memory. Writing to this will change the content
/// on the screen.
/// Memory is interpreted with the current video mode to produce an image.
pub const memory: []align(ashet.memory.page_size) u8 = hal.video.memory;
comptime {
    // Make sure we have at least the guaranteed amount of RAM
    // to store the largest possible image.
    std.debug.assert(memory.len >= 32768);
}

/// The currently used palette. Modifying values here changes the appearance of
/// the displayed picture.
pub const palette: *[256]u16 = hal.video.palette;

pub const Mode = ashet.abi.VideoMode;

pub const Color = ashet.abi.Color;

/// Contains initialization defaults for the system
pub const defaults = struct {
    pub const font: [256][6]u8 = blk: {
        @setEvalBranchQuota(100_000);

        var data: [256][6]u8 = undefined;

        const src_w = 7;
        const src_h = 9;

        const src_dx = 1;
        const src_dy = 1;

        const dst_w = 6;
        const dst_h = 8;

        const source_pixels = @embedFile("../data/font.raw");
        if (source_pixels.len != src_w * src_h * 256)
            @compileError(std.fmt.comptimePrint("Font file must be 16 by 16 characters of size {}x{}", .{ src_w, src_h }));

        if (dst_h > 8)
            @compileError("dst_h must be less than 9!");

        var c = 0;
        while (c < 256) : (c += 1) {
            const cx = c % 16;
            const cy = c / 16;

            var x = 0;
            while (x < dst_w) : (x += 1) {
                var bits = 0;

                var y = 0;
                while (y < dst_h) : (y += 1) {
                    const src_x = src_dx + src_w * cx + x;
                    const src_y = src_dy + src_h * cy + y;

                    const src_i = 16 * src_w * src_y + src_x;

                    const pix = source_pixels[src_i];

                    if (pix != 0) {
                        bits |= (1 << y);
                    }
                }

                data[c][x] = bits;
            }
        }

        break :blk data;
    };

    /// The standard Ashet OS palette.
    /// This is loaded from `src/kernel/data/palette.gpl`.
    pub const palette: [256]u16 = blk: {
        @setEvalBranchQuota(10_000);

        var colors: [256]Color = undefined;

        const gpl_palette = @embedFile("../data/palette.gpl");

        var literator = std.mem.tokenize(u8, gpl_palette, "\r\n");

        if (!std.mem.eql(u8, literator.next() orelse @compileError("Not a GIMP palette file!"), "GIMP Palette"))
            @compileError("Not a GIMP palette file!");

        var index: usize = 0;
        while (literator.next()) |line| {
            if (index >= colors.len)
                @compileError(std.fmt.comptimePrint("palette.gpl contains more than {} colors!", .{colors.len}));

            var trimmed = std.mem.trim(u8, line, " \t"); // remove leading/trailing whitespace
            if (std.mem.indexOfScalar(u8, trimmed, '\t')) |tab_index| { // remove the color name
                trimmed = std.mem.trim(u8, trimmed[0..tab_index], " ");
            }

            if (std.mem.startsWith(u8, trimmed, "#"))
                continue;

            var tups = std.mem.tokenize(u8, trimmed, " ");

            const r = std.fmt.parseInt(u8, tups.next().?, 10) catch unreachable;
            const g = std.fmt.parseInt(u8, tups.next().?, 10) catch unreachable;
            const b = std.fmt.parseInt(u8, tups.next().?, 10) catch unreachable;

            colors[index] = Color.fromRgb888(r, g, b);
            index += 1;
        }

        break :blk @bitCast([256]u16, colors);
    };

    /// The splash screen that should be shown until the operating system
    /// has fully bootet. This has to be displayed in 256x128 8bpp video mode.
    pub const splash_screen: [32768]u8 = @embedFile("../data/splash.raw").*;

    /// The default border color.
    /// Must match the splash screen, otherwise it looks kinda weird.
    pub const border: u8 = splash_screen[0]; // we just use the top-left pixel of the splash. smort!
};

/// If this is `true`, the kernel will repeatedly call `flush()` to
/// ensure the display is up-to-date.
pub const is_flush_required = @hasDecl(hal.video, "flush");

/// Changes the current video mode.
pub fn setMode(mode: Mode) void {
    hal.video.setMode(mode);
}

/// Sets the border color of the screen. This color fills all unreachable pixels.
/// *C64 feeling intensifies.*
pub fn setBorder(b: u8) void {
    hal.video.setBorder(b);
}

/// Potentially synchronizes the video storage with the screen.
/// Without calling this
pub fn flush() void {
    hal.video.flush();
}

/// Sets the screen resolution of the video mode.
/// This will make it simpler to create smaller applications that are
/// centered on the screen by reducing the logical resolution of the screen.
/// This only applies to graphics mode.
pub fn setResolution(width: u16, height: u16) void {
    std.debug.assert(width > 0 and height > 0);
    std.debug.assert(width <= 400 and height <= 300);
    hal.video.setResolution(width, height);
}

/// Computes the character attributes and selects both foreground and background color.
pub fn charAttributes(foreground: u4, background: u4) u8 {
    return (CharAttributes{ .fg = foreground, .bg = background }).toByte();
}

pub const CharAttributes = packed struct {
    bg: u4, // lo nibble
    fg: u4, // hi nibble

    pub fn fromByte(val: u8) CharAttributes {
        return @bitCast(CharAttributes, val);
    }

    pub fn toByte(attr: CharAttributes) u8 {
        return @bitCast(u8, attr);
    }
};
