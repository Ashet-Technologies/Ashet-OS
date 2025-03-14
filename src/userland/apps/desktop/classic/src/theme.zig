const std = @import("std");
const ashet = @import("ashet");

const Color = ashet.abi.Color;
const Font = ashet.abi.Font;

pub const Theme = struct {
    active_window: WindowStyle,
    inactive_window: WindowStyle,
    dark: Color,
    desktop_color: Color,
    window_fill: Color,
    title_font: Font,
};

pub const WindowStyle = struct {
    border: Color,
    font: Color,
    title: Color,
};
