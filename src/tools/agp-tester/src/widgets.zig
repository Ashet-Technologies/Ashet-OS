const std = @import("std");
const abi = @import("abi");
const agp = @import("agp");
const agp_swrast = @import("agp-swrast");

const gif = @import("gif.zig");

const Color = agp.Color;
const Rectangle = abi.Rectangle;
const Size = abi.Size;
const Point = abi.Point;

const mono_6_font: agp.Font = embed_font(@embedFile("mono-6.font"), .{});
const mono_8_font: agp.Font = embed_font(@embedFile("mono-8.font"), .{});
const sans_var_font: agp.Font = embed_font(@embedFile("sans.font"), .{ .size = 12 });

const theme_hue: Color.Hue = .purple;
const theme_sat: u2 = 2;
const theme_val: u3 = 4;

const default_theme: Theme = .{
    .border_dark = .from_hsv(theme_hue, theme_sat, theme_val - 1),
    .border_normal = .from_hsv(theme_hue, theme_sat, theme_val),
    .border_bright = .from_hsv(theme_hue, theme_sat, theme_val + 1),

    .panel_background = .blue,
    .widget_background = .from_hsv(theme_hue, theme_sat -| 1, theme_val -| 2),

    .menu_border = .from_hsv(.blue, 2, 2),

    .text_color = .white,

    .window_active = .{
        //
    },
    .window_inactive = undefined,
};

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
    var cmd_buffer: [2048]u8 = undefined;

    const desktop_color: Color = .from_hsv(.green, 1, 2);

    // Collect draw commands:
    var fbs = std.io.fixedBufferStream(&cmd_buffer);
    var draw: Draw = .{
        .enc = agp.encoder(fbs.writer()),
        .theme = default_theme,
    };
    {
        try draw.window(.{
            .bounds = .{
                .x = 50,
                .y = 50,
                .width = 400,
                .height = 250,
            },
            .title = "GUI Demo",
            .icon = icon_7x7,
            .buttons = .{
                .minimize = .visible,
                .maximiize = .visible,
                .close = .visible,
                .resize = .visible,
            },
        });

        try draw.button(.{
            .bounds = .{
                .x = 100,
                .y = 100,
                .width = 50,
                .height = 15,
            },
            .text = "Cancel",
        });

        try draw.button(.{
            .bounds = .{
                .x = 160,
                .y = 100,
                .width = 22,
                .height = 15,
            },
            .text = "Ok",
        });

        try draw.tool_button(.{
            .bounds = .{
                .x = 100,
                .y = 80,
                .width = 12,
                .height = 12,
            },
            .icon = &icon_8x8,
        });

        try draw.hscrollbar(.{
            .bounds = .{
                .x = 100,
                .y = 120,
                .width = 200,
                .height = 11,
            },
            .slider_pos = 0,
            .slider_width = 33,
        });

        try draw.vscrollbar(.{
            .bounds = .{
                .x = 300,
                .y = 50,
                .width = 11,
                .height = 70,
            },
            .slider_pos = 0,
            .slider_height = 33,
        });

        // try enc.draw_line(
        //     100,
        //     60,
        //     200,
        //     60,
        //     .white,
        // );

        // try enc.draw_text(100, 230, mono_6_font, .purple, "Hello, World!");
        // try enc.draw_text(100, 250, sans_var_font, .cyan, "Hello, World!");
    }

    try write_agp(allocator, path, fbs.getWritten(), desktop_color);
}

const Theme = struct {
    border_dark: Color,
    border_normal: Color,
    border_bright: Color,

    panel_background: Color,
    widget_background: Color,
    menu_border: Color, // scrollbar border, window inside border, menus, ...

    text_color: Color,

    window_active: WindowTheme,
    window_inactive: WindowTheme,

    pub const WindowTheme = struct {
        background: Color,

        title_color: Color,
        title_font: agp.Font,

        border_normal: Color,
        border_inner: Color,
        border_dark: Color,
        border_bright: Color,

        title_button_background: Color,
        close_button_background: Color,
    };
};

const Draw = struct {
    enc: agp.Encoder(std.io.FixedBufferStream([]u8).Writer),
    theme: Theme,

    pub fn button(draw: Draw, opt: struct {
        bounds: Rectangle,
        font: agp.Font = mono_8_font,
        text: []const u8 = "",
    }) !void {
        const rect = opt.bounds;
        try draw.enc.draw_line(
            rect.left(),
            rect.top(),
            rect.right() -| 1,
            rect.top(),
            draw.theme.border_bright,
        );
        try draw.enc.draw_line(
            rect.left(),
            rect.top() +| 1,
            rect.left(),
            rect.bottom() -| 1,
            draw.theme.border_bright,
        );
        try draw.enc.draw_rect(
            rect.left() +| 1,
            rect.top() +| 1,
            rect.width -| 2,
            rect.height -| 2,
            draw.theme.border_normal,
        );
        try draw.enc.draw_line(
            rect.right() -| 1,
            rect.top() +| 1,
            rect.right() -| 1,
            rect.bottom() -| 1,
            draw.theme.border_dark,
        );
        try draw.enc.draw_line(
            rect.left() +| 1,
            rect.bottom() -| 1,
            rect.right(),
            rect.bottom() -| 1,
            draw.theme.border_dark,
        );
        try draw.enc.fill_rect(
            rect.left() +| 2,
            rect.top() +| 2,
            rect.width -| 4,
            rect.height -| 4,
            draw.theme.widget_background,
        );
        if (opt.text.len > 0) {
            try draw.enc.draw_text(
                rect.left() +| 5,
                rect.top() +| 4,
                opt.font,
                draw.theme.text_color,
                opt.text,
            );
        }
    }

    pub fn tool_button(draw: Draw, opt: struct {
        bounds: Rectangle,
        icon: ?*const agp.Bitmap,
    }) !void {
        const rect = opt.bounds;
        try draw.enc.draw_line(
            rect.left(),
            rect.top(),
            rect.right(),
            rect.top(),
            draw.theme.border_bright,
        );
        try draw.enc.draw_line(
            rect.left(),
            rect.top() +| 1,
            rect.left(),
            rect.bottom() -| 1,
            draw.theme.border_bright,
        );
        try draw.enc.draw_line(
            rect.right() -| 1,
            rect.top() +| 1,
            rect.right() -| 1,
            rect.bottom() -| 1,
            draw.theme.border_dark,
        );
        try draw.enc.draw_line(
            rect.left(),
            rect.bottom() -| 1,
            rect.right(),
            rect.bottom() -| 1,
            draw.theme.border_dark,
        );
        try draw.enc.fill_rect(
            rect.left() +| 1,
            rect.top() +| 1,
            rect.width -| 2,
            rect.height -| 2,
            draw.theme.border_normal,
        );

        if (opt.icon) |icon| {
            try draw.enc.blit_bitmap(
                rect.left() +| 2,
                rect.top() +| 2,
                icon,
            );
        }
    }

    pub fn hscrollbar(draw: Draw, opt: struct {
        bounds: Rectangle,
        slider_pos: u15,
        slider_width: u15,
    }) !void {
        const rect = opt.bounds;

        try draw.enc.draw_rect(
            rect.left(),
            rect.top(),
            rect.width,
            rect.height,
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.left() +| 1,
                .y = rect.top() +| 1,
                .width = 9,
                .height = 9,
            },
            .icon = &chevron_left,
        });

        try draw.enc.draw_line(
            rect.left() +| 10,
            rect.top() +| 1,
            rect.left() +| 10,
            rect.bottom() -| 1,
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.right() -| 10,
                .y = rect.top() +| 1,
                .width = 9,
                .height = 9,
            },
            .icon = &chevron_right,
        });

        try draw.enc.draw_line(
            rect.right() -| 11,
            rect.top() +| 1,
            rect.right() -| 11,
            rect.bottom() -| 1,
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.left() +| 11 +| opt.slider_pos,
                .y = rect.top() +| 1,
                .width = opt.slider_width,
                .height = 9,
            },
            .icon = null,
        });

        var delta: u15 = 0;
        while (delta < opt.slider_width - 5) : (delta += 2) {
            try draw.enc.draw_line(
                rect.left() +| 13 +| opt.slider_pos + delta,
                rect.top() +| 3,
                rect.left() +| 13 +| opt.slider_pos + delta,
                rect.bottom() -| 3,
                draw.theme.border_dark,
            );
        }
    }

    pub fn vscrollbar(draw: Draw, opt: struct {
        bounds: Rectangle,
        slider_pos: u15,
        slider_height: u15,
    }) !void {
        const rect = opt.bounds;

        try draw.enc.draw_rect(
            rect.left(),
            rect.top(),
            rect.width,
            rect.height,
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.left() +| 1,
                .y = rect.top() +| 1,
                .width = 9,
                .height = 9,
            },
            .icon = &chevron_up,
        });

        try draw.enc.draw_line(
            rect.left() +| 1,
            rect.top() +| 10,
            rect.right() -| 1,
            rect.top() +| 10,
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.left() +| 1,
                .y = rect.bottom() -| 10,
                .width = 9,
                .height = 9,
            },
            .icon = &chevron_down,
        });

        try draw.enc.draw_line(
            rect.left() +| 1,
            rect.bottom() -| 11,
            rect.right() -| 1,
            rect.bottom() -| 11,
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.left() +| 1,
                .y = rect.top() +| 11 +| opt.slider_pos,
                .width = 9,
                .height = opt.slider_height,
            },
            .icon = null,
        });

        var delta: u15 = 0;
        while (delta < opt.slider_height - 5) : (delta += 2) {
            try draw.enc.draw_line(
                rect.left() +| 3,
                rect.top() +| 13 +| opt.slider_pos + delta,
                rect.right() -| 3,
                rect.top() +| 13 +| opt.slider_pos + delta,
                draw.theme.border_dark,
            );
        }
    }

    pub fn window(draw: Draw, opt: struct {
        bounds: Rectangle,
        title: []const u8,
        icon: ?*const agp.Bitmap,
        buttons: ButtonMask = .{},
    }) !void {
        const rect = opt.bounds;
    }

    pub const ButtonState = enum {
        hidden,
        disabled,
        visible,
    };

    pub const ButtonMask = struct {
        close: ButtonState = .visible,
        minimize: ButtonState = .visible,
        maximize: ButtonState = .visible,
        resize: ButtonState = .visible,
    };

    const chevron_right: agp.Bitmap = .{
        .has_transparency = true,
        .transparency_key = .magenta,
        .width = 5,
        .height = 5,
        .stride = 5,
        .pixels = blk: {
            const T: Color = .magenta;
            const W: Color = .white;
            const bmp: [25]Color align(4) = .{
                T, W, T, T, T,
                T, T, W, T, T,
                T, T, T, W, T,
                T, T, W, T, T,
                T, W, T, T, T,
            };
            break :blk &bmp;
        },
    };

    const chevron_left: agp.Bitmap = .{
        .has_transparency = true,
        .transparency_key = .magenta,
        .width = 5,
        .height = 5,
        .stride = 5,
        .pixels = blk: {
            const T: Color = .magenta;
            const W: Color = .white;
            const bmp: [25]Color align(4) = .{
                T, T, T, W, T,
                T, T, W, T, T,
                T, W, T, T, T,
                T, T, W, T, T,
                T, T, T, W, T,
            };
            break :blk &bmp;
        },
    };

    const chevron_up: agp.Bitmap = .{
        .has_transparency = true,
        .transparency_key = .magenta,
        .width = 5,
        .height = 5,
        .stride = 5,
        .pixels = blk: {
            const T: Color = .magenta;
            const W: Color = .white;
            const bmp: [25]Color align(4) = .{
                T, T, T, T, T,
                T, T, W, T, T,
                T, W, T, W, T,
                W, T, T, T, W,
                T, T, T, T, T,
            };
            break :blk &bmp;
        },
    };

    const chevron_down: agp.Bitmap = .{
        .has_transparency = true,
        .transparency_key = .magenta,
        .width = 5,
        .height = 5,
        .stride = 5,
        .pixels = blk: {
            const T: Color = .magenta;
            const W: Color = .white;
            const bmp: [25]Color align(4) = .{
                T, T, T, T, T,
                W, T, T, T, W,
                T, W, T, W, T,
                T, T, W, T, T,
                T, T, T, T, T,
            };
            break :blk &bmp;
        },
    };
};

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
