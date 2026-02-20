const std = @import("std");
const abi = @import("abi");
const agp = @import("agp");
const agp_swrast = @import("agp-swrast");

const widgets_draw = @import("widgets-draw");

const gif = @import("gif.zig");

const Color = agp.Color;
const Rectangle = abi.Rectangle;
const Size = abi.Size;
const Point = abi.Point;

const theme_hue: Color.Hue = .purple;
const theme_sat: u2 = 2;
const theme_val: u3 = 4;

const default_theme: widgets_draw.Theme = .create_default(.{
    .hue = .purple,
    .saturation = 2,
    .value = 4,
    .border = .yellow,
    .menu_font = mono_6_font,
    .title_font = mono_6_font,
    .widget_font = mono_8_font,
});

const mono_6_font: agp.Font = embed_font(@embedFile("mono-6.font"), .{});
const mono_8_font: agp.Font = embed_font(@embedFile("mono-8.font"), .{});
const sans_var_font: agp.Font = embed_font(@embedFile("sans.font"), .{ .size = 12 });

const icon_7x7: agp.Bitmap = .{
    .has_transparency = true,
    .transparency_key = .magenta,
    .width = 7,
    .height = 7,
    .stride = 7,
    .pixels = blk: {
        const T: Color = .magenta;
        const R: Color = .red;
        const D: Color = .from_gray(0x16);
        const M: Color = .from_gray(0x1B);
        const L: Color = .from_gray(0x2E);
        const B: Color = .from_hsv(.red, 2, 5);
        const bmp: [49]Color align(4) = .{
            T, T, T, T, T, R, R,
            T, T, T, T, L, M, R,
            T, T, T, L, M, D, T,
            T, T, L, M, D, T, T,
            T, T, B, D, T, T, T,
            T, B, T, T, T, T, T,
            B, T, T, T, T, T, T,
        };
        break :blk &bmp;
    },
};

const icon_8x8: agp.Bitmap = .{
    .has_transparency = true,
    .transparency_key = .magenta,
    .width = 8,
    .height = 8,
    .stride = 8,
    .pixels = blk: {
        const T: Color = .magenta;
        const Y: Color = .yellow;
        const W: Color = .white;
        const B: Color = .black;
        const bmp: [64]Color align(4) = .{
            Y, T, Y, T, W, W, W, T,
            T, Y, T, W, W, W, W, T,
            Y, T, Y, W, B, B, W, T,
            T, W, W, W, W, W, W, T,
            T, W, B, B, B, B, W, T,
            T, W, W, W, W, W, W, T,
            T, W, B, B, B, B, W, T,
            T, W, W, W, W, W, W, T,
        };
        break :blk &bmp;
    },
};

pub fn render_demo(
    allocator: std.mem.Allocator,
    path: []const u8,
) !void {
    var cmd_buffer: [4096]u8 = undefined;

    const desktop_color: Color = .from_hsv(.green, 1, 2);

    // Collect draw commands:
    var fbs = std.io.fixedBufferStream(&cmd_buffer);
    var draw: widgets_draw.Draw = .init(
        default_theme,
        agp.encoder(fbs.writer()),
    );

    try render_example(&draw);

    try write_agp(allocator, path, fbs.getWritten(), desktop_color);
}

fn render_example(draw: *widgets_draw.Draw) !void {
    try draw.window(.{
        .bounds = .{
            .x = 50,
            .y = 20,
            .width = 200,
            .height = 150,
        },
        .title = "Inactive Window",
        .icon = &icon_7x7,
        .active = false,
        .buttons = .{
            .minimize = .hidden,
            .maximize = .hidden,
            .close = .visible,
            .resize = .hidden,
        },
    });

    try draw.window(.{
        .bounds = .{
            .x = 100,
            .y = 80,
            .width = 200,
            .height = 168,
        },
        .title = "GUI Demo",
        .icon = &icon_7x7,
        .active = true,
        .buttons = .{
            .minimize = .visible,
            .maximize = .visible,
            .close = .visible,
            .resize = .visible,
        },
    });

    try draw.hscrollbar(.{
        .bounds = .{
            .x = 102,
            .y = 235,
            .width = 186,
            .height = 11,
        },
        .slider_pos = 0,
        .slider_width = 33,
    });

    try draw.vscrollbar(.{
        .bounds = .{
            .x = 287,
            .y = 94,
            .width = 11,
            .height = 142,
        },
        .slider_pos = 0,
        .slider_height = 33,
    });

    try draw.button(.{
        .bounds = .{
            .x = 155,
            .y = 215,
            .width = 50,
            .height = 15,
        },
        .text = "Cancel",
    });

    try draw.button(.{
        .bounds = .{
            .x = 210,
            .y = 215,
            .width = 22,
            .height = 15,
        },
        .text = "Ok",
    });

    try draw.panel(.{
        .bounds = .{
            .x = 225,
            .y = 110,
            .width = 50,
            .height = 30,
        },
        .style = .sunken,
    });

    try draw.panel(.{
        .bounds = .{
            .x = 225,
            .y = 150,
            .width = 50,
            .height = 30,
        },
        .style = .raised,
    });

    // TODO: Implement proper toolbar drawing
    try draw.tool_button(.{
        .bounds = .{
            .x = 103,
            .y = 95,
            .width = 12,
            .height = 12,
        },
        .icon = &icon_8x8,
    });

    try draw.radiobutton(.{
        .pos = .new(105, 110),
        .text = "Fetch",
        .checked = false,
    });
    try draw.radiobutton(.{
        .pos = .new(105, 121),
        .text = "Unpack",
        .checked = false,
    });
    try draw.radiobutton(.{
        .pos = .new(105, 132),
        .text = "Install",
        .checked = true,
    });

    try draw.hrule(.new(105, 144), 100);

    try draw.checkbox(.{
        .pos = .new(105, 148),
        .text = "Confirm on exit",
        .checked = false,
    });
    try draw.checkbox(.{
        .pos = .new(105, 159),
        .text = "Animations",
        .checked = true,
    });

    try draw.hrule(.new(105, 171), 100);

    try draw.textbox(.{
        .bounds = .{
            .x = 105,
            .y = 176,
            .width = 100,
            .height = 15,
        },
        .text = "Hello!",
    });

    try draw.progressbar(.{
        .bounds = .{
            .x = 105,
            .y = 194,
            .width = 80,
            .height = 15,
        },
        .value = 666,
        .limit = 1337,
        .display = .relative,
    });

    try draw.progressbar(.{
        .bounds = .{
            .x = 188,
            .y = 194,
            .width = 80,
            .height = 15,
        },
        .value = 666,
        .limit = 1337,
        .display = .absolute,
    });
}

pub fn write_agp(
    allocator: std.mem.Allocator,
    path: []const u8,
    cmd_stream: []const u8,
    back_color: Color,
) !void {
    const width = 480;
    const height = 320;

    var pixel_buffer: [width * height]Color = @splat(back_color);

    // Render image:
    {
        const Rasterizer = agp_swrast.Rasterizer(.{
            .backend_type = *Backend,
            .framebuffer_type = null,
            .pixel_layout = .row_major,
        });

        var backend: Backend = .{
            .framebuffer = &pixel_buffer,
            .width = width,
            .height = height,
            .stride = width,
        };
        var rasterizer = Rasterizer.init(&backend);

        var fbs = std.io.fixedBufferStream(cmd_stream);

        var decoder = agp.decoder(allocator, fbs.reader());
        defer decoder.deinit();

        while (try decoder.next()) |cmd| {
            try rasterizer.execute(cmd);
        }
    }

    // Writeout image:
    try gif.write_to_file_path(std.fs.cwd(), path, width, height, &pixel_buffer);
}

const Backend = struct {
    const Cursor = agp_swrast.PixelCursor(.row_major);

    framebuffer: []agp.Color,

    width: usize,
    height: usize,
    stride: usize,

    pub fn create_cursor(back: @This()) Cursor {
        return .{
            .width = @intCast(back.width),
            .height = @intCast(back.height),
            .stride = back.stride,
        };
    }

    pub fn resolve_font(back: @This(), font: agp.Font) error{InvalidFont}!*const agp_swrast.fonts.FontInstance {
        _ = back;
        return @ptrCast(@alignCast(font));
    }

    pub fn copy_pixels(back: @This(), cursor: Cursor, pixels: []const Color) void {
        std.debug.assert(pixels.len > 0);
        std.debug.assert(@as(usize, cursor.x) + pixels.len <= back.width);
        @memcpy(
            back.framebuffer[cursor.offset..][0..pixels.len],
            pixels,
        );
    }

    pub fn emit_pixels(back: *@This(), cursor: Cursor, color: Color, count: u16) void {
        std.debug.assert(count > 0);
        std.debug.assert(@as(usize, cursor.x) + count <= back.width);
        @memset(
            back.framebuffer[cursor.offset..][0..count],
            color,
        );
    }
};

fn embed_font(data: []const u8, hint: agp_swrast.fonts.FontHint) agp.Font {
    @setEvalBranchQuota(10_000);
    return @constCast(@ptrCast(&(agp_swrast.fonts.FontInstance.load(data, hint) catch unreachable)));
}
