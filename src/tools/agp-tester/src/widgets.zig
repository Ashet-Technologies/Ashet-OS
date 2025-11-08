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

    .title_font = mono_6_font,

    .window_active = .{
        .background = .from_hsv(theme_hue, 1, 1),
        .border_normal = .from_hsv(.yellow, 2, 8),
        .border_bright = .from_hsv(theme_hue, theme_sat, theme_val -| 2),
        .border_dark = .black,

        .title_bar = .from_hsv(theme_hue, theme_sat, theme_val),
        .title_color = .from_hsv(.yellow, 1, 8),

        .close_button_background = .red,
    },
    .window_inactive = .{
        .background = .from_hsv(theme_hue, 1, 1),
        .border_normal = .from_hsv(.yellow, 2, 5),
        .border_bright = .from_hsv(theme_hue, theme_sat, theme_val -| 2),
        .border_dark = .black,

        .title_bar = .from_hsv(theme_hue, theme_sat -| 1, theme_val -| 1),
        .title_color = .from_gray(0x30),

        .close_button_background = .from_hsv(.red, 2, 5),
    },
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
                .height = 150,
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

        try draw.button(.{
            .bounds = .{
                .x = 155,
                .y = 198,
                .width = 50,
                .height = 15,
            },
            .text = "Cancel",
        });

        try draw.button(.{
            .bounds = .{
                .x = 210,
                .y = 198,
                .width = 22,
                .height = 15,
            },
            .text = "Ok",
        });

        try draw.tool_button(.{
            .bounds = .{
                .x = 103,
                .y = 95,
                .width = 12,
                .height = 12,
            },
            .icon = &icon_8x8,
        });

        try draw.hscrollbar(.{
            .bounds = .{
                .x = 102,
                .y = 217,
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
                .height = 124,
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

    title_font: agp.Font,

    pub const WindowTheme = struct {
        background: Color,

        title_bar: Color,
        title_color: Color,

        border_normal: Color, // window rectangle
        border_dark: Color, // bottom-right border
        border_bright: Color, // top-left border

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
            rect.right(),
            rect.top() +| 1,
            rect.right(),
            rect.bottom(),
            draw.theme.border_dark,
        );
        try draw.enc.draw_line(
            rect.left() +| 1,
            rect.bottom(),
            rect.right(),
            rect.bottom(),
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
            rect.bottom(),
            draw.theme.border_bright,
        );
        try draw.enc.draw_line(
            rect.right(),
            rect.top() +| 1,
            rect.right(),
            rect.bottom(),
            draw.theme.border_dark,
        );
        try draw.enc.draw_line(
            rect.left(),
            rect.bottom(),
            rect.right(),
            rect.bottom(),
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
            rect.bottom(),
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.right() -| 9,
                .y = rect.top() +| 1,
                .width = 9,
                .height = 9,
            },
            .icon = &chevron_right,
        });

        try draw.enc.draw_line(
            rect.right() -| 10,
            rect.top() +| 1,
            rect.right() -| 10,
            rect.bottom(),
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
        while (delta <= opt.slider_width - 5) : (delta += 2) {
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
            rect.right(),
            rect.top() +| 10,
            draw.theme.menu_border,
        );

        try draw.tool_button(.{
            .bounds = .{
                .x = rect.left() +| 1,
                .y = rect.bottom() -| 9,
                .width = 9,
                .height = 9,
            },
            .icon = &chevron_down,
        });

        try draw.enc.draw_line(
            rect.left() +| 1,
            rect.bottom() -| 10,
            rect.right() -| 1,
            rect.bottom() -| 10,
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
        while (delta <= opt.slider_height - 5) : (delta += 2) {
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
        active: bool,
    }) !void {
        const theme = if (opt.active) draw.theme.window_active else draw.theme.window_inactive;
        const rect = opt.bounds.shrink(1);

        try draw.enc.draw_line(
            opt.bounds.left(),
            opt.bounds.top(),
            opt.bounds.right(),
            opt.bounds.top(),
            theme.border_bright,
        );
        try draw.enc.draw_line(
            opt.bounds.left(),
            opt.bounds.top() +| 1,
            opt.bounds.left(),
            opt.bounds.bottom(),
            theme.border_bright,
        );

        try draw.enc.draw_line(
            opt.bounds.left() +| 1,
            opt.bounds.bottom(),
            opt.bounds.right(),
            opt.bounds.bottom(),
            theme.border_dark,
        );
        try draw.enc.draw_line(
            opt.bounds.right(),
            opt.bounds.top() +| 1,
            opt.bounds.right(),
            opt.bounds.bottom() -| 1,
            theme.border_dark,
        );

        try draw.enc.draw_rect(
            rect.left(),
            rect.top(),
            rect.width,
            rect.height,
            theme.border_normal,
        );

        try draw.enc.draw_rect(
            rect.left() +| 1,
            rect.top() +| 1,
            rect.width -| 2,
            rect.height -| 2,
            draw.theme.menu_border,
        );

        try draw.enc.fill_rect(
            rect.left() +| 2,
            rect.top() +| 2,
            rect.width -| 4,
            9,
            theme.title_bar,
        );

        try draw.enc.draw_line(
            rect.left() +| 2,
            rect.top() +| 11,
            rect.right() -| 2,
            rect.top() +| 11,
            draw.theme.menu_border,
        );

        try draw.enc.draw_line(
            rect.left() +| 1,
            rect.top() +| 12,
            rect.right() -| 1,
            rect.top() +| 12,
            theme.border_normal,
        );

        try draw.enc.draw_line(
            rect.left() +| 2,
            rect.top() +| 13,
            rect.right() -| 2,
            rect.top() +| 13,
            draw.theme.menu_border,
        );

        if (opt.icon) |icon| {
            std.debug.assert(icon.height <= 7);
            try draw.enc.blit_bitmap(
                rect.left() +| 3,
                rect.top() +| 3,
                icon,
            );
        }

        if (opt.title.len > 0) {
            try draw.enc.draw_text(
                rect.left() +| 4 +| if (opt.icon) |icon| @as(i16, @intCast(icon.width)) +| 1 else 0,
                rect.top() +| 4,
                draw.theme.title_font,
                theme.title_color,
                opt.title,
            );
        }

        try draw.enc.fill_rect(
            rect.left() +| 2,
            rect.top() +| 14,
            rect.width -| 4,
            rect.height -| 16,
            theme.background,
        );

        var btn_pos: i16 = rect.right() -| 1;
        if (opt.buttons.close != .hidden) {
            btn_pos -= 10;

            try draw.enc.draw_line(
                btn_pos,
                rect.top() +| 2,
                btn_pos,
                rect.top() +| 10,
                draw.theme.menu_border,
            );
            try draw.enc.fill_rect(
                btn_pos +| 1,
                rect.top() +| 2,
                9,
                9,
                theme.close_button_background,
            );
            try draw.enc.blit_bitmap(
                btn_pos +| 3,
                rect.top() +| 4,
                &close_button,
            );
        }

        if (opt.buttons.maximize != .hidden) {
            btn_pos -= 10;

            try draw.enc.draw_line(
                btn_pos,
                rect.top() +| 2,
                btn_pos,
                rect.top() +| 10,
                draw.theme.menu_border,
            );
            try draw.enc.blit_bitmap(
                btn_pos +| 2,
                rect.top() +| 3,
                &maximize_icon,
            );
        }

        if (opt.buttons.minimize != .hidden) {
            btn_pos -= 10;

            try draw.enc.draw_line(
                btn_pos,
                rect.top() +| 2,
                btn_pos,
                rect.top() +| 10,
                draw.theme.menu_border,
            );
            try draw.enc.blit_bitmap(
                btn_pos +| 2,
                rect.top() +| 3,
                &minimize_icon,
            );
        }

        if (btn_pos != rect.right() -| 1) {
            btn_pos -= 1;
            try draw.enc.draw_line(
                btn_pos,
                rect.top() +| 1,
                btn_pos,
                rect.top() +| 11,
                theme.border_normal,
            );
            btn_pos -= 1;
            try draw.enc.draw_line(
                btn_pos,
                rect.top() +| 1,
                btn_pos,
                rect.top() +| 11,
                draw.theme.menu_border,
            );
        }

        if (opt.buttons.resize != .hidden) {
            try draw.enc.draw_line(
                rect.right() -| 11,
                rect.bottom() -| 11,
                rect.right() -| 2,
                rect.bottom() -| 11,
                draw.theme.menu_border,
            );
            try draw.enc.draw_line(
                rect.right() -| 10,
                rect.bottom() -| 10,
                rect.right() -| 1,
                rect.bottom() -| 10,
                theme.border_normal,
            );
            try draw.enc.draw_line(
                rect.right() -| 11,
                rect.bottom() -| 10,
                rect.right() -| 11,
                rect.bottom() -| 2,
                draw.theme.menu_border,
            );
            try draw.enc.draw_line(
                rect.right() -| 10,
                rect.bottom() -| 9,
                rect.right() -| 10,
                rect.bottom() -| 1,
                theme.border_normal,
            );
            try draw.enc.fill_rect(
                rect.right() -| 9,
                rect.bottom() -| 9,
                9,
                9,
                theme.title_bar,
            );
            try draw.enc.blit_bitmap(
                rect.right() - 8,
                rect.bottom() -| 8,
                &resize_icon,
            );
        }
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

    const maximize_icon: agp.Bitmap = genbmp(.white,
        \\xxxxxxx
        \\x     x
        \\xxxxxxx
        \\x     x
        \\x     x
        \\x     x
        \\xxxxxxx
    );

    const minimize_icon: agp.Bitmap = genbmp(.white,
        \\
        \\
        \\
        \\
        \\
        \\
        \\ xxxxx
    );

    const resize_icon: agp.Bitmap = genbmp(.white,
        \\xxx
        \\x x
        \\xxxxxxx
        \\  x   x
        \\  x   x
        \\  x   x
        \\  xxxxx
    );

    const close_button: agp.Bitmap = genbmp(.white,
        \\x   x
        \\ x x
        \\  x
        \\ x x
        \\x   x
    );

    fn genbmp(color: Color, pattern: []const u8) agp.Bitmap {
        var width = 0;
        var height = 1;

        var len = 0;
        for (pattern) |c| {
            if (c == '\n') {
                len = 0;
                height += 1;
            } else {
                len += 1;
                width = @max(width, len);
            }
        }

        const tkey: Color = if (color == Color.magenta) Color.red else Color.magenta;

        var pixels: [width * height]Color = @splat(tkey);
        {
            var x = 0;
            var y = 0;
            for (pattern) |c| {
                if (c == '\n') {
                    x = 0;
                    y += 1;
                } else {
                    if (c != ' ')
                        pixels[y * width + x] = color;
                    x += 1;
                }
            }
        }

        const const_pixels align(4) = pixels;

        return .{
            .has_transparency = true,
            .transparency_key = .magenta,
            .width = width,
            .height = height,
            .stride = width,
            .pixels = &const_pixels,
        };
    }
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
