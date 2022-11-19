const std = @import("std");
const ashet = @import("ashet");
const TextEditor = @import("text-editor");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

pub const Event = enum(usize) {
    _,

    pub fn get(comptime name: []const u8) Event {
        return innerGet(name.len, name[0..name.len].*);
    }

    fn innerGet(comptime len: usize, id: [len]u8) Event {
        const T = struct { tag: u8 };
        _ = id;
        return @intToEnum(Event, @ptrToInt(&T.tag));
    }
};

pub const Framebuffer = struct {
    width: u16, // width of the image
    height: u16, // height of the image
    stride: u16, // row length in pixels
    pixels: [*]ColorIndex, // height * stride pixels

    const ScreenRect = struct {
        x: i16,
        y: i16,
        pixels: [*]ColorIndex,
        width: u16,
        height: u16,
    };

    fn clip(fb: Framebuffer, rect: Rectangle) ScreenRect {
        var width: u16 = 0;
        var height: u16 = 0;

        width -|= @intCast(u16, std.math.max(0, -rect.x));
        height -|= @intCast(u16, std.math.max(0, -rect.y));

        const x = @intCast(u15, std.math.max(0, rect.x));
        const y = @intCast(u15, std.math.max(0, rect.y));

        if (x + width > fb.width) {
            width = (fb.width - x);
        }
        if (y + height > fb.height) {
            height = (fb.height - y);
        }

        return ScreenRect{
            .x = x,
            .y = y,
            .pixels = fb.pixels + @as(usize, y) * fb.stride + @as(usize, x),
            .width = width,
            .height = height,
        };
    }

    pub fn fillRectangle(fb: Framebuffer, rect: Rectangle, color: ColorIndex) void {
        var dst = fb.clip(rect);
        while (dst.height > 0) {
            dst.height -= 1;
            for (dst.pixels[0..dst.width]) |*c| {
                c.* = color;
            }
            dst.pixels += fb.stride;
        }
    }

    pub fn drawRectangle(fb: Framebuffer, rect: Rectangle, color: ColorIndex) void {
        var dst = fb.clip(rect);

        var top = dst.pixels;
        var bot = dst.pixels + (dst.height - 1) * fb.stride;

        var x: u16 = 0;
        while (x < dst.width) : (x += 1) {
            if (dst.y == rect.y) top[0] = color;
            if (dst.y + dst.height == rect.y + rect.height) bot[0] = color;
            top += 1;
            bot += 1;
        }

        var left = dst.pixels;
        var right = dst.pixels + dst.width;

        var y: u16 = 0;
        while (y < dst.width) : (y += 1) {
            if (dst.x == rect.x) left[0] = color;
            if (dst.y + dst.height == rect.y + rect.height) right[0] = color;
            left += fb.stride;
            right += fb.stride;
        }
    }
};

pub const Theme = struct {
    border: ColorIndex,
    panel_bg: ColorIndex,
    button_bg: ColorIndex,
    font_color: ColorIndex,

    pub const default = Theme{
        .border = ColorIndex.get(),
        .panel_bg = ColorIndex.get(),
        .button_bg = ColorIndex.get(),
        .font_color = ColorIndex.get(),
    };
};

pub const Interface = struct {
    /// List of widgets, bottom to top
    widgets: []Widget,
    theme: *const Theme = &Theme.default,

    pub fn widgetFromPoint(gui: *Interface, pt: Point) ?*Widget {
        var i: usize = gui.widgets.len;
        while (i > 0) {
            i -= 1;
            const widget = &gui.widgets[i];
            if (widget.bounds.contains(pt))
                return widget;
        }
        return null;
    }

    pub fn sendMouseEvent(gui: *Interface, event: ashet.abi.MouseEvent) ?Event {
        switch (event.type) {
            .mouse_press => if (event.button == .left) {
                if (gui.widgetFromPoint(Point.new(event.x, event.y))) |widget| {
                    switch (widget.control) {
                        .button => |btn| return btn.clickEvent,
                        .text_box => @panic("not implemented yet!"),
                        .label, .panel => {},
                    }
                }
            },
            .mouse_release => {},
            .motion => {},
        }

        return null;
    }

    pub fn sendKeyboardEvent(gui: *Interface, event: ashet.abi.MouseEvent) ?Event {
        _ = gui;
        _ = event;
        return null;
    }

    pub fn paint(gui: Interface, target: Framebuffer) void {
        for (gui.widgets) |widget| {
            switch (widget.control) {
                .button => |ctrl| {
                    _ = ctrl;
                    target.fillRectangle(widget.bounds, gui.theme.button_bg);
                    target.drawRectangle(widget.bounds, gui.theme.button_border);
                },
                .label => |ctrl| {
                    _ = ctrl;
                },
                .text_box => |ctrl| {
                    _ = ctrl;
                },
                .panel => |ctrl| {
                    _ = ctrl;
                },
            }
        }
    }
};

pub const Widget = struct {
    bounds: Rectangle,
    control: Control,
};

pub const Control = union(enum) {
    button: Button,
    label: Label,
    text_box: TextBox,
    panel: Panel,
};

pub const Button = struct {
    clickEvent: ?Event = null,

    pub fn new(x: i16, y: i16, width: u15, label: []const u8) Widget {
        _ = x;
        _ = y;
        _ = width;
        _ = label;
    }
};

pub const Label = struct {
    pub fn new(x: i16, y: i16, text: []const u8) Widget {
        _ = x;
        _ = y;
        _ = text;
    }
};

pub const TextBox = struct {
    pub fn new(x: i16, y: i16, width: u15, text: []const u8) Widget {
        //
        _ = x;
        _ = y;
        _ = width;
        _ = text;
    }
};

pub const Panel = struct {
    pub fn new(x: i16, y: i16, width: u15, height: u15) Widget {
        //
        _ = x;
        _ = y;
        _ = width;
        _ = height;
    }
};

test "framebuffer basic draw" {
    var target: [8][8]ColorIndex = [1][8]ColorIndex{[1]ColorIndex{ColorIndex.get(0)} ** 8} ** 8;
    var fb = Framebuffer{
        .pixels = &target[0],
        .stride = 8,
        .width = 8,
        .height = 8,
    };

    fb.fillRectangle(Rectangle{ .x = 2, .y = 2, .width = 3, .height = 4 }, ColorIndex.get(1));
}
