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
        return innerGet(name.len, name[0..len].*);
    }

    fn getInner(comptime len: usize, id: [len]u8) Event {
        const T = struct { tag: u8 };
        _ = len;
        _ = id;
        return @intToEnum(Event, @ptrToInt(&T.tag));
    }
};

pub const Framebuffer = struct {
    width: u16, // width of the image
    height: u16, // height of the image
    stride: u16, // row length in pixels
    pixels: [*]u8, // height * stride pixels

    pub fn fillRectangle(fb: Framebuffer, rect: Rectangle, color: ColorIndex) void {
        _ = fb;
        _ = rect;
        _ = color;
    }
    pub fn drawRectangle(fb: Framebuffer, rect: Rectangle, color: ColorIndex) void {
        _ = fb;
        _ = rect;
        _ = color;
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
                if (widgetFromPoint(Point.new(event.x, event.y))) |widget| {
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
        //
    }
};

pub const Label = struct {
    pub fn new(x: i16, y: i16, text: []const u8) Widget {
        //
    }
};

pub const TextBox = struct {
    pub fn new(x: i16, y: i16, width: u15, text: []const u8) Widget {
        //
    }
};

pub const Panel = struct {
    pub fn new(x: i16, y: i16, width: u15, height: u15) Widget {
        //
    }
};
