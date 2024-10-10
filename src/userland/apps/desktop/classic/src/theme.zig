const std = @import("std");
const ashet = @import("ashet");

const ColorIndex = ashet.abi.ColorIndex;
const Font = ashet.abi.Font;

pub const Theme = struct {
    active_window: WindowStyle,
    inactive_window: WindowStyle,
    dark: ColorIndex,
    desktop_color: ColorIndex,
    window_fill: ColorIndex,
    title_font: Font,
};

pub const WindowStyle = struct {
    border: ColorIndex,
    font: ColorIndex,
    title: ColorIndex,
};
