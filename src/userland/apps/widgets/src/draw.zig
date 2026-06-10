const std = @import("std");
const ashet = @import("ashet");
const abi = ashet.abi;
const agp = ashet.graphics.agp;
const agp_swrast = @import("agp-swrast");

const Color = agp.Color;
const Rectangle = abi.Rectangle;
const Size = abi.Size;
const Point = abi.Point;

pub const Theme = struct {
    border_dark: Color,
    border_normal: Color,
    border_bright: Color,

    panel_background: Color,
    widget_background: Color,
    menu_border: Color, // scrollbar border, window inside border, menus, ...

    text_color: Color,

    window_active: WindowTheme,
    window_inactive: WindowTheme,

    title_font: ashet.graphics.Font,
    menu_font: ashet.graphics.Font,
    widget_font: ashet.graphics.Font,
    item_font: ashet.graphics.Font,

    pub const WindowTheme = struct {
        background: Color,

        title_bar: Color,
        title_color: Color,

        border_normal: Color, // window rectangle
        border_dark: Color, // bottom-right border
        border_bright: Color, // top-left border

        close_button_background: Color,
    };

    pub fn create_default(opt: struct {
        hue: Color.Hue,
        saturation: u2,
        value: u4,
        border: Color.Hue,
        title_font: agp.Font,
        menu_font: agp.Font,
        item_font: agp.Font,
        widget_font: agp.Font,
        text_color: agp.Color = .white,
    }) Theme {
        const theme_hue = opt.hue;
        const theme_sat = opt.saturation;
        const theme_val = opt.value;
        return .{
            .border_dark = .from_hsv(theme_hue, theme_sat, theme_val -| 1),
            .border_normal = .from_hsv(theme_hue, theme_sat, theme_val),
            .border_bright = .from_hsv(theme_hue, theme_sat, theme_val +| 1),

            .panel_background = .blue,
            .widget_background = .from_hsv(theme_hue, theme_sat -| 1, theme_val -| 2),

            .menu_border = .from_hsv(.blue, 2, 2),

            .text_color = opt.text_color,

            .title_font = opt.title_font,
            .widget_font = opt.widget_font,
            .menu_font = opt.menu_font,
            .item_font = opt.item_font,

            .window_active = .{
                .background = .from_hsv(theme_hue, 1, 1),
                .border_normal = .from_hsv(opt.border, 2, 8),
                .border_bright = .from_hsv(theme_hue, theme_sat, theme_val -| 2),
                .border_dark = .black,

                .title_bar = .from_hsv(theme_hue, theme_sat, theme_val),
                .title_color = .from_hsv(opt.border, 1, 8),

                .close_button_background = .red,
            },
            .window_inactive = .{
                .background = .from_hsv(theme_hue, 1, 1),
                .border_normal = .from_hsv(opt.border, 2, 5),
                .border_bright = .from_hsv(theme_hue, theme_sat, theme_val -| 2),
                .border_dark = .black,

                .title_bar = .from_hsv(theme_hue, theme_sat -| 1, theme_val -| 1),
                .title_color = .from_gray(0x30),

                .close_button_background = .from_hsv(.red, 2, 5),
            },
        };
    }
};

pub const Draw = struct {
    enc: agp.Encoder,
    theme: Theme,
    icons: IconStack,

    pub fn init(
        theme: Theme,
        enc: agp.Encoder,
    ) Draw {
        return .{
            .enc = enc,
            .theme = theme,
            .icons = .init(.{
                .B = theme.border_bright,
                .N = theme.border_normal,
                .D = theme.border_dark,
                ._ = theme.widget_background,
                .I = theme.text_color,
            }),
        };
    }

    fn rstrip(text: []const u8) []const u8 {
        return std.mem.trimRight(u8, text, " \r\n\t");
    }

    pub fn radiobutton(draw: *const Draw, opt: struct {
        pos: Point,
        font: ?agp.Font = null,
        text: []const u8 = "",
        checked: bool,
    }) !void {
        const icon = if (opt.checked)
            draw.icons.get(.checked_radio_icon)
        else
            draw.icons.get(.unchecked_radio_icon);

        try draw.enc.blit_bitmap(
            opt.pos.x,
            opt.pos.y,
            &icon,
        );

        const text = rstrip(opt.text);
        if (text.len > 0) {
            try draw.enc.draw_text(
                opt.pos.x +| @as(i16, @intCast(icon.width)) +| 3,
                opt.pos.y + 1,
                opt.font orelse draw.theme.widget_font,
                draw.theme.text_color,
                text,
            );
        }
    }

    pub fn checkbox(draw: *const Draw, opt: struct {
        pos: Point,
        font: ?agp.Font = null,
        text: []const u8 = "",
        checked: bool,
    }) !void {
        const icon = if (opt.checked)
            draw.icons.get(.checked_box_icon)
        else
            draw.icons.get(.unchecked_box_icon);

        try draw.enc.blit_bitmap(
            opt.pos.x,
            opt.pos.y,
            &icon,
        );

        const text = rstrip(opt.text);
        if (text.len > 0) {
            try draw.enc.draw_text(
                opt.pos.x +| @as(i16, @intCast(icon.width)) +| 3,
                opt.pos.y + 1,
                opt.font orelse draw.theme.widget_font,
                draw.theme.text_color,
                text,
            );
        }
    }

    /// The hrule extends ±1 from pos on Y
    pub fn hrule(draw: *const Draw, pos: Point, width: u16) !void {
        const x1 = pos.x;
        const x2: i16 = pos.x +| @as(i16, @intCast(width));

        try draw.enc.draw_line(x1, pos.y -| 1, x2, pos.y -| 1, draw.theme.border_bright);
        try draw.enc.set_pixel(x1, pos.y, draw.theme.border_bright);
        try draw.enc.draw_line(x1 +| 1, pos.y, x2 -| 1, pos.y, draw.theme.border_normal);
        try draw.enc.set_pixel(x2, pos.y, draw.theme.border_dark);
        try draw.enc.draw_line(x1, pos.y +| 1, x2, pos.y +| 1, draw.theme.border_dark);
    }

    pub const PanelStyle = enum { sunken, raised };
    pub fn panel(draw: *const Draw, opt: struct {
        bounds: Rectangle,
        style: PanelStyle,
    }) !void {
        const rect = opt.bounds;
        switch (opt.style) {
            .raised => {
                try draw.enc.draw_line(
                    rect.left(),
                    rect.top(),
                    rect.right(),
                    rect.top(),
                    draw.theme.border_bright,
                );

                try draw.enc.draw_line(
                    rect.left(),
                    rect.top(),
                    rect.left(),
                    rect.bottom() -| 1,
                    draw.theme.border_bright,
                );

                try draw.enc.draw_line(
                    rect.left(),
                    rect.bottom(),
                    rect.right(),
                    rect.bottom(),
                    draw.theme.border_dark,
                );

                try draw.enc.draw_line(
                    rect.right(),
                    rect.top() +| 1,
                    rect.right(),
                    rect.bottom() -| 1,
                    draw.theme.border_dark,
                );

                try draw.enc.draw_rect(
                    rect.x +| 1,
                    rect.y +| 1,
                    rect.width -| 2,
                    rect.height -| 2,
                    draw.theme.border_normal,
                );
            },

            .sunken => {
                try draw.enc.draw_rect(
                    rect.x,
                    rect.y,
                    rect.width,
                    rect.height,
                    draw.theme.border_normal,
                );

                try draw.enc.draw_line(
                    rect.left() +| 1,
                    rect.top() +| 1,
                    rect.right() -| 2,
                    rect.top() +| 1,
                    draw.theme.border_dark,
                );
                try draw.enc.draw_line(
                    rect.left() +| 1,
                    rect.top() +| 2,
                    rect.left() +| 1,
                    rect.bottom() -| 2,
                    draw.theme.border_dark,
                );

                try draw.enc.draw_line(
                    rect.right() -| 1,
                    rect.top() +| 1,
                    rect.right() -| 1,
                    rect.bottom() -| 2,
                    draw.theme.border_bright,
                );

                try draw.enc.draw_line(
                    rect.left() +| 1,
                    rect.bottom() -| 1,
                    rect.right() -| 1,
                    rect.bottom() -| 1,
                    draw.theme.border_bright,
                );
            },
        }
    }

    pub fn textbox(draw: *const Draw, opt: struct {
        bounds: Rectangle,
        font: ?agp.Font = null,
        text: []const u8,
    }) !void {
        try draw.panel(.{
            .bounds = opt.bounds,
            .style = .sunken,
        });

        try draw.enc.fill_rect(
            opt.bounds.left() +| 2,
            opt.bounds.top() +| 2,
            opt.bounds.width -| 4,
            opt.bounds.height -| 4,
            draw.theme.widget_background,
        );

        const text = rstrip(opt.text);
        if (text.len > 0) {
            try draw.enc.draw_text(
                opt.bounds.left() +| 4,
                opt.bounds.top() +| 4,
                opt.font orelse draw.theme.widget_font,
                draw.theme.text_color,
                text,
            );
        }
    }

    pub const ProgressDisplay = enum {
        none,
        relative,
        absolute,
    };

    pub fn progressbar(draw: *const Draw, opt: struct {
        bounds: Rectangle,

        value: u32,
        limit: u32,

        font: ?agp.Font = null,
        display: ProgressDisplay,
    }) !void {
        const rect = opt.bounds;

        try draw.panel(.{
            .bounds = rect,
            .style = .sunken,
        });

        try draw.enc.fill_rect(
            rect.left() +| 2,
            rect.top() +| 2,
            rect.width -| 4,
            rect.height -| 4,
            draw.theme.widget_background,
        );

        const bar_width = (rect.width -| 6);
        const fill_level: u16 = if (opt.limit != 0)
            @intCast(((bar_width *| opt.value +| opt.limit / 2) / opt.limit))
        else
            bar_width;

        if (fill_level > 0) {
            try draw.enc.fill_rect(
                opt.bounds.left() +| 3,
                opt.bounds.top() +| 3,
                fill_level,
                opt.bounds.height -| 6,
                draw.theme.border_normal,
            );
        }

        // buffer has enough space to fill "{maxInt(u32)}/{maxInt(u32)}"
        var buffer: [21]u8 = undefined;
        const text = switch (opt.display) {
            .none => return,

            .relative => if (opt.limit > 0)
                std.fmt.bufPrint(&buffer, "{}%", .{
                    (100 *| opt.value +| opt.limit / 2) / opt.limit,
                }) catch unreachable
            else
                "~",

            .absolute => std.fmt.bufPrint(&buffer, "{}/{}", .{
                opt.value,
                opt.limit,
            }) catch unreachable,
        };
        std.debug.assert(text.len > 0);

        try draw.enc.draw_text(
            rect.left() +| @as(i16, @intCast((rect.width - 6 * text.len) / 2)),
            rect.top() +| 4,
            opt.font orelse draw.theme.widget_font,
            draw.theme.text_color,
            text,
        );
    }

    pub fn button(draw: *const Draw, opt: struct {
        bounds: Rectangle,
        font: ?agp.Font = null,
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

        const text = rstrip(opt.text);
        if (text.len > 0) {
            try draw.enc.draw_text(
                rect.left() +| 5,
                rect.top() +| 4,
                opt.font orelse draw.theme.widget_font,
                draw.theme.text_color,
                text,
            );
        }
    }

    pub fn tool_button(draw: *const Draw, opt: struct {
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

    pub fn hscrollbar(draw: *const Draw, opt: struct {
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

    pub fn vscrollbar(draw: *const Draw, opt: struct {
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

    pub fn window(draw: *const Draw, opt: struct {
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
                rect.right() -| 8,
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

    const IconStack = BitmapStack(.{
        .unchecked_radio_icon =
        \\  NNNNN
        \\ NNDDDBN
        \\NND____NN
        \\ND_____BN
        \\ND_____BN
        \\ND_____BN
        \\NN____BNN
        \\ NNBBBNN
        \\  NNNNN
        ,

        .checked_radio_icon =
        \\  NNNNN
        \\ NNDDDBN
        \\NND____NN
        \\ND__II_BN
        \\ND_III_BN
        \\ND_II__BN
        \\NN____BNN
        \\ NNBBBNN
        \\  NNNNN
        ,

        .unchecked_box_icon =
        \\NNNNNNNNN
        \\NDDDDDDDN
        \\ND_____BN
        \\ND_____BN
        \\ND_____BN
        \\ND_____BN
        \\ND_____BN
        \\NBBBBBBBN
        \\NNNNNNNNN
        ,

        .checked_box_icon =
        \\NNNNNNNNN
        \\NDDDDDDDN
        \\ND_____BN
        \\ND_I_I_BN
        \\ND__I__BN
        \\ND_I_I_BN
        \\ND_____BN
        \\NBBBBBBBN
        \\NNNNNNNNN
        ,
    });

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
            .transparency_key = tkey,
            .width = width,
            .height = height,
            .stride = width,
            .pixels = &const_pixels,
        };
    }

    fn genicon(comptime color_map: anytype, pattern: []const u8) agp.Bitmap {
        const width, const height, const tkey = comptime blk: {
            var width = 0;
            var height = 1;
            var len = 0;
            var used_colors: std.StaticBitSet(256) = .initFull();

            for (pattern) |c| {
                if (c == '\n') {
                    len = 0;
                    height += 1;
                } else {
                    if (c != ' ') {
                        const color: Color = @field(color_map, &.{c});
                        used_colors.unset(color.to_u8());
                    }
                    len += 1;
                    width = @max(width, len);
                }
            }
            break :blk .{
                width,
                height,
                Color.from_u8(@intCast(used_colors.toggleFirstSet().?)),
            };
        };

        var pixels: [width * height]Color = @splat(tkey);
        {
            var x = 0;
            var y = 0;
            inline for (pattern) |c| {
                if (c == '\n') {
                    x = 0;
                    y += 1;
                } else {
                    if (c != ' ')
                        pixels[y * width + x] = @field(color_map, &.{c});
                    x += 1;
                }
            }
        }

        const const_pixels align(4) = pixels;

        return .{
            .has_transparency = true,
            .transparency_key = tkey,
            .width = width,
            .height = height,
            .stride = width,
            .pixels = &const_pixels,
        };
    }
};

const AutoBitmap = struct {
    offset: usize,
    width: u16,
    height: u16,
};

fn BitmapStack(comptime icon_set: anytype) type {
    var bmp_offset: usize = 0;

    var fields: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(@TypeOf(icon_set)).@"struct".fields) |fld| {
        const pattern = @field(icon_set, fld.name);

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

        bmp_offset = std.mem.alignForward(usize, bmp_offset, 4);

        const newfield: std.builtin.Type.StructField = .{
            .name = fld.name,
            .type = AutoBitmap,

            .alignment = @alignOf(AutoBitmap),
            .default_value_ptr = &AutoBitmap{
                .width = width,
                .height = height,
                .offset = bmp_offset,
            },
            .is_comptime = false,
        };
        fields = fields ++ [1]std.builtin.Type.StructField{newfield};
        bmp_offset += width * height;
    }

    const ImageSet = @Type(.{
        .@"struct" = .{
            .backing_integer = null,
            .decls = &.{},
            .fields = fields,
            .is_tuple = false,
            .layout = .auto,
        },
    });

    const pixelcount = bmp_offset;
    const image_set: ImageSet = .{};
    const cfields = fields;

    return struct {
        buffer: [pixelcount]Color align(4),
        tkey: Color,

        pub fn init(color_map: anytype) @This() {
            var used_colors: std.StaticBitSet(256) = .initFull();
            inline for (@typeInfo(@TypeOf(color_map)).@"struct".fields) |fld| {
                used_colors.unset(@field(color_map, fld.name).to_u8());
            }

            const tkey: Color = .from_u8(@intCast(used_colors.toggleFirstSet().?));

            var buffer: [pixelcount]Color = @splat(tkey);
            _ = &buffer;

            inline for (cfields) |fld| {
                const pattern = @field(icon_set, fld.name);
                const image: AutoBitmap = @field(image_set, fld.name);

                comptime var x = 0;
                comptime var y = 0;
                var bmp = buffer[image.offset..][0 .. image.width * image.height];
                inline for (pattern) |c| {
                    if (c == '\n') {
                        x = 0;
                        y += 1;
                    } else {
                        const color = if (c == ' ')
                            tkey
                        else
                            @field(color_map, &.{c});
                        bmp[y * image.width + x] = color;
                        x += 1;
                    }
                }
                comptime std.debug.assert(y == image.height - 1);
            }

            return .{ .buffer = buffer, .tkey = tkey };
        }

        pub fn get(set: *const @This(), comptime tag: std.meta.FieldEnum(ImageSet)) agp.Bitmap {
            const meta: AutoBitmap = @field(image_set, @tagName(tag));

            return .{
                .has_transparency = true,
                .transparency_key = set.tkey,

                .width = meta.width,
                .height = meta.height,
                .stride = meta.width,
                .pixels = @alignCast(set.buffer[meta.offset..][0 .. meta.width * meta.height].ptr),
            };
        }
    };
}
