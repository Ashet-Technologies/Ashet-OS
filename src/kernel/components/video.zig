const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../main.zig");

pub const Color = ashet.abi.Color;
pub const ColorIndex = ashet.abi.ColorIndex;

pub const Resolution = ashet.abi.Size;

/// If true, the kernel will automatically flush the screen in a background process.
pub var auto_flush: bool = true;

/// The raw exposed video memory. Writing to this will change the content
/// on the screen.
/// Memory is interpreted with the current video mode to produce an image.
pub fn getVideoMemory() []align(ashet.memory.page_size) ColorIndex {
    return video_driver.getVideoMemory();
}

/// The currently used palette. Modifying values here changes the appearance of
/// the displayed picture.
pub fn getPaletteMemory() *[256]Color {
    return video_driver.getPaletteMemory();
}

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
    ///
    /// INFO: This is loaded from `src/kernel/data/palette.gpl`.
    pub const palette: [256]Color = system_palette_info.palette;

    /// The standard palette exports some named colors.
    /// Those colors can be accessed via `known_colors.<name>`.
    ///
    /// INFO: This is loaded from `src/kernel/data/palette.gpl`.
    pub const known_colors: system_palette_info.KnownColors = .{};

    /// The splash screen that should be shown until the operating system
    /// has fully bootet. This has to be displayed in 256x128 8bpp video mode.
    pub const splash_screen: [32768]ColorIndex = @as([32768]ColorIndex, @bitCast(@as([32768]u8, @embedFile("../data/splash.raw").*)));

    /// The default border color.
    /// Must match the splash screen, otherwise it looks kinda weird.
    pub const border: ColorIndex = splash_screen[0]; // we just use the top-left pixel of the splash. smort!
};

const system_palette_info = blk: {
    @setEvalBranchQuota(100_000);

    var colors: [256]Color = undefined;

    const gpl_palette = @embedFile("../data/palette.gpl");

    var literator = std.mem.tokenizeAny(u8, gpl_palette, "\r\n");

    if (!std.mem.eql(u8, literator.next() orelse @compileError("Not a GIMP palette file!"), "GIMP Palette"))
        @compileError("Not a GIMP palette file!");

    var fields: []const std.builtin.Type.StructField = &.{};

    var index: usize = 0;
    while (literator.next()) |line| {
        if (index >= colors.len)
            @compileError(std.fmt.comptimePrint("palette.gpl contains more than {} colors!", .{colors.len}));

        const trimmed = std.mem.trim(u8, line, " \t"); // remove leading/trailing whitespace

        if (std.mem.startsWith(u8, trimmed, "#"))
            continue;

        var tups = std.mem.tokenizeAny(u8, trimmed, "\t ");

        const r = std.fmt.parseInt(u8, tups.next().?, 10) catch @compileError("failed to parse color tuple");
        const g = std.fmt.parseInt(u8, tups.next().?, 10) catch @compileError("failed to parse color tuple");
        const b = std.fmt.parseInt(u8, tups.next().?, 10) catch @compileError("failed to parse color tuple");

        _ = tups.next(); // ignore RRGGBB

        if (tups.next()) |name| {
            // color name

            var name_: [name.len:0]u8 = undefined;
            @memcpy(&name_, name);

            const new_field: std.builtin.Type.StructField = .{
                .name = &name_,
                .type = ashet.abi.ColorIndex,
                .default_value = &ashet.abi.ColorIndex.get(@as(u8, @intCast(index))),
                .is_comptime = true,
                .alignment = 1,
            };

            fields = fields ++ &[1]std.builtin.Type.StructField{new_field};
        }

        colors[index] = Color.fromRgb888(r, g, b);
        index += 1;
    }
    while (index < colors.len) : (index += 1) {
        colors[index] = Color.fromRgb888(0xFF, 0x00, 0xFF);
    }

    break :blk .{
        .palette = colors,
        .KnownColors = @Type(.{
            .Struct = .{
                .layout = .auto,
                .backing_integer = null,
                .fields = fields,
                .decls = &.{},
                .is_tuple = false,
            },
        }),
    };
};

var video_driver: *ashet.drivers.VideoDevice = undefined;

pub fn initialize() void {
    video_driver = ashet.drivers.first(.video) orelse @panic("no video device found!");
}

/// Sets the border color of the screen. This color fills all unreachable pixels.
/// *C64 feeling intensifies.*
pub fn setBorder(b: ColorIndex) void {
    video_driver.setBorder(b);
}

/// Potentially synchronizes the video storage with the screen.
/// Without calling this, the screen might not be refreshed at all.
pub fn flush() void {
    video_driver.flush();
}

/// Returns the current screen resolution
pub fn getResolution() Resolution {
    return video_driver.getResolution();
}

pub fn getMaxResolution() Resolution {
    return video_driver.getMaxResolution();
}

pub fn getBorder() ColorIndex {
    return video_driver.getBorder();
}

/// Sets the screen resolution of the video mode.
/// This will make it simpler to create smaller applications that are
/// centered on the screen by reducing the logical resolution of the screen.
/// This only applies to graphics mode.
pub fn setResolution(width: u15, height: u15) void {
    std.debug.assert(width > 0 and height > 0);
    video_driver.setResolution(width, height);
}

// Render text mode:
// {
//     @memset( gpu.fb_mem, pal(border_color));

//     const font = ashet.video.defaults.font;

//     const w = 64;
//     const h = 32;

//     const gw = 6;
//     const gh = 8;

//     const dx = (gpu.fb_width - gw * w) / 2;
//     const dy = (gpu.fb_height - gh * h) / 2;

//     var i: usize = 0;
//     while (i < w * h) : (i += 1) {
//         const cx = i % w;
//         const cy = i / w;

//         const char = video.memory[2 * i + 0];
//         const attr = ashet.abi.CharAttributes.fromByte(video.memory[2 * i + 1]);

//         const glyph = font[char];

//         var x: usize = 0;
//         while (x < gw) : (x += 1) {
//             var bits = glyph[x];

//             comptime var y: usize = 0;
//             inline while (y < gh) : (y += 1) {
//                 const index = if ((bits & (1 << y)) != 0)
//                     attr.fg
//                 else
//                     attr.bg;
//                 gpu.fb_mem[gpu.fb_width * (dy + gh * cy + y) + (dx + gw * cx + x)] = pal(index);
//             }
//         }
//     }
// }
