const std = @import("std");
const ashet = @import("ashet");
const TextEditor = @import("text-editor");

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;

/// An event that can be passed to widgets.
/// Each event carries information about what happends (`id`) and
/// potentially additional pointer information (`tag`).
pub const Event = struct {
    id: EventID,
    tag: ?*anyopaque,

    pub fn new(id: EventID) Event {
        return Event{ .id = id, .tag = null };
    }

    pub fn newTagged(id: EventID, tag: ?*anyopaque) Event {
        return Event{ .id = id, .tag = tag };
    }
};

/// A unique event id.
pub const EventID = enum(usize) {
    _,
};

pub const Framebuffer = @import("Framebuffer.zig");
pub const Bitmap = @import("Bitmap.zig");

pub const Theme = struct {
    area: ColorIndex, // filling for panels, buttons, text boxes, ...
    area_light: ColorIndex, // a brighter version of `area`
    area_shadow: ColorIndex, // a darker version of `area`

    label: ColorIndex, // the text of a label
    text: ColorIndex, // the text of a button, text box, ...

    pub const default = Theme{
        .area = ColorIndex.get(7),
        .area_light = ColorIndex.get(10),
        .area_shadow = ColorIndex.get(3),
        .label = ColorIndex.get(15),
        .text = ColorIndex.get(0),
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
            .button_press => if (event.button == .left) {
                if (gui.widgetFromPoint(Point.new(event.x, event.y))) |widget| {
                    switch (widget.control) {
                        .button => |btn| return btn.clickEvent,
                        .text_box => @panic("not implemented yet!"),
                        .label, .panel, .picture => {},
                    }
                }
            },
            .button_release => {},
            .motion => {},
        }

        return null;
    }

    pub fn sendKeyboardEvent(gui: *Interface, event: ashet.abi.KeyboardEvent) ?Event {
        _ = gui;
        _ = event;
        return null;
    }

    pub fn paint(gui: Interface, target: Framebuffer) void {
        for (gui.widgets) |widget| {
            const b = .{
                .x = widget.bounds.x,
                .y = widget.bounds.y,
                .width = @intCast(u15, widget.bounds.width),
                .height = @intCast(u15, widget.bounds.height),
            };
            switch (widget.control) {
                .button => |ctrl| {
                    target.fillRectangle(widget.bounds.shrink(1), gui.theme.area);

                    if (b.width > 2 and b.height > 2) {
                        target.drawLine(
                            Point.new(b.x + 1, b.y),
                            Point.new(b.x + b.width - 2, b.y),
                            gui.theme.area_light,
                        );
                        target.drawLine(
                            Point.new(b.x + 1, b.y + b.height - 1),
                            Point.new(b.x + b.width - 2, b.y + b.height - 1),
                            gui.theme.area_shadow,
                        );

                        target.drawLine(
                            Point.new(b.x, b.y + 1),
                            Point.new(b.x, b.y + b.height - 2),
                            gui.theme.area_shadow,
                        );
                        target.drawLine(
                            Point.new(b.x + b.width - 1, b.y + 1),
                            Point.new(b.x + b.width - 1, b.y + b.height - 2),
                            gui.theme.area_light,
                        );
                    }

                    target.drawString(b.x + 2, b.y + 2, ctrl.text, gui.theme.text, b.width -| 2);
                },
                .label => |ctrl| {
                    target.drawString(b.x, b.y, ctrl.text, gui.theme.label, b.width);
                },
                .text_box => |ctrl| {
                    target.fillRectangle(widget.bounds.shrink(1), gui.theme.area);

                    if (b.width > 2 and b.height > 2) {
                        target.drawLine(
                            Point.new(b.x, b.y),
                            Point.new(b.x + b.width - 1, b.y),
                            gui.theme.area_shadow,
                        );
                        target.drawLine(
                            Point.new(b.x + b.width - 1, b.y + 1),
                            Point.new(b.x + b.width - 1, b.y + b.height - 1),
                            gui.theme.area_shadow,
                        );

                        target.drawLine(
                            Point.new(b.x, b.y + 1),
                            Point.new(b.x, b.y + b.height - 1),
                            gui.theme.area_light,
                        );
                        target.drawLine(
                            Point.new(b.x + 1, b.y + b.height - 1),
                            Point.new(b.x + b.width - 2, b.y + b.height - 1),
                            gui.theme.area_light,
                        );
                    }

                    var writer = target.screenWriter(b.x + 2, b.y + 2, gui.theme.text, b.width -| 2);
                    if (ctrl.flags.password) {
                        writer.writer().writeByteNTimes('*', ctrl.content().len) catch {};
                    } else {
                        writer.writer().writeAll(ctrl.content()) catch {};
                    }
                },
                .panel => {
                    target.fillRectangle(widget.bounds.shrink(2), gui.theme.area);
                    if (b.width > 3 and b.height > 3) {
                        target.drawRectangle(Rectangle{
                            .x = b.x + 1,
                            .y = b.y,
                            .width = b.width - 1,
                            .height = b.height - 1,
                        }, gui.theme.area_light);
                        target.drawRectangle(Rectangle{
                            .x = b.x,
                            .y = b.y + 1,
                            .width = b.width - 1,
                            .height = b.height - 1,
                        }, gui.theme.area_shadow);
                    }
                },
                .picture => |ctrl| {
                    _ = ctrl;
                    @panic("painting not picture implemented yet!");
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
    picture: Picture,
};

pub const Button = struct {
    clickEvent: ?Event = null,
    text: []const u8,

    pub fn new(x: i16, y: i16, width: ?u15, text: []const u8) Widget {
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = width orelse (@intCast(u15, text.len * 6) + 3),
                .height = 11,
            },
            .control = .{
                .button = Button{
                    .clickEvent = null,
                    .text = text,
                },
            },
        };
    }
};

pub const Label = struct {
    text: []const u8,

    pub fn new(x: i16, y: i16, text: []const u8) Widget {
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = @intCast(u15, 6 * text.len),
                .height = 11,
            },
            .control = .{
                .label = Label{
                    .text = text,
                },
            },
        };
    }
};

pub const TextBox = struct {
    editor: TextEditor,
    flags: Flags = .{},

    pub fn new(x: i16, y: i16, width: u15, backing: []u8, text: []const u8) !Widget {
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = width,
                .height = 11,
            },
            .control = .{
                .text_box = TextBox{
                    .editor = try TextEditor.init(TextEditor.Buffer.initStatic(backing), text),
                },
            },
        };
    }

    pub fn content(tb: TextBox) []const u8 {
        return tb.editor.getText();
    }

    pub fn setText(tb: *TextBox, string: []const u8) !void {
        return tb.editor.setText(string);
    }

    pub const Flags = packed struct(u16) {
        /// The text box is a password box and will hide all text behind "*".
        password: bool = false,

        /// The text box is not editable. The user can move the cursor, but not change the text.
        read_only: bool = false,

        unused: u14 = 0,
    };
};

pub const Panel = struct {
    pub fn new(x: i16, y: i16, width: u15, height: u15) Widget {
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = width,
                .height = height,
            },
            .control = .{
                .panel = Panel{},
            },
        };
    }
};

pub const Picture = struct {
    bitmap: Bitmap,
    pub fn new(x: i16, y: i16, bitmap: Bitmap) Widget {
        //
        _ = x;
        _ = y;
        _ = bitmap;
    }
};

test "smoke test 01" {
    var tb_user_backing: [64]u8 = undefined;
    var tb_passwd_backing: [64]u8 = undefined;

    var widgets = [_]Widget{
        Panel.new(5, 5, 172, 57),
        Panel.new(5, 65, 172, 57),
        Button.new(69, 42, null, "Cancel"),
        Button.new(135, 42, null, "Login"),
        try TextBox.new(69, 14, 99, &tb_user_backing, "xq"),
        try TextBox.new(69, 28, 99, &tb_passwd_backing, "********"),
        Label.new(15, 16, "Username:"),
        Label.new(15, 30, "Password:"),
    };
    var interface = Interface{ .widgets = &widgets };

    var pixel_storage: [1][200]ColorIndex = undefined;
    var fb = Framebuffer{
        .pixels = @ptrCast([*]ColorIndex, &pixel_storage),
        .stride = 0, // just overwrite the first line again
        .width = 200,
        .height = 150,
    };

    interface.paint(fb);
}
