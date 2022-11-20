const std = @import("std");
const ashet = @import("ashet");
const TextEditor = @import("text-editor");
const logger = std.log.scoped(.gui);

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
    window: ColorIndex, // filling for text-editable things like text boxes, ...

    area: ColorIndex, // filling for panels, buttons, (read only) text boxes, ...
    area_light: ColorIndex, // a brighter version of `area`
    area_shadow: ColorIndex, // a darker version of `area`

    label: ColorIndex, // the text of a label
    text: ColorIndex, // the text of a button, text box, ...

    focus: ColorIndex, // color of the dithered focus border
    text_cursor: ColorIndex, // color of the text cursor

    pub const default = Theme{
        .window = ColorIndex.get(15),
        .area = ColorIndex.get(7),
        .area_light = ColorIndex.get(10),
        .area_shadow = ColorIndex.get(3),
        .label = ColorIndex.get(15),
        .text = ColorIndex.get(0),
        .focus = ColorIndex.get(1),
        .text_cursor = ColorIndex.get(2),
    };
};

pub const Interface = struct {
    /// List of widgets, bottom to top
    widgets: []Widget,
    theme: *const Theme = &Theme.default,
    focus: ?usize = null,

    pub fn widgetFromPoint(gui: *Interface, pt: Point, index: ?*usize) ?*Widget {
        var i: usize = gui.widgets.len;
        while (i > 0) {
            i -= 1;
            const widget = &gui.widgets[i];
            if (widget.bounds.contains(pt)) {
                if (index) |dst| dst.* = i;
                return widget;
            }
        }
        return null;
    }

    pub fn sendMouseEvent(gui: *Interface, event: ashet.abi.MouseEvent) ?Event {
        switch (event.type) {
            .button_press => if (event.button == .left) {
                var index: usize = 0;
                if (gui.widgetFromPoint(Point.new(event.x, event.y), &index)) |widget| {
                    if (widget.control.canFocus()) {
                        gui.focus = index;
                    }

                    switch (widget.control) {
                        .button => |btn| return btn.clickEvent,
                        .text_box => |*box| {
                            const offset = @intCast(usize, event.x - widget.bounds.x) -| 2; // adjust to "left text edge"

                            // compute the index:
                            // left half of character is "cursor left of character", right half is "cursor right of character"
                            const text_index = std.math.min((offset +| 3) / 6, box.editor.graphemeCount());

                            box.editor.cursor = text_index;
                        },
                        .label, .panel, .picture => {},
                    }
                }
            },
            .button_release => {},
            .motion => {},
        }

        return null;
    }

    const FocusDir = enum { backward, forward };
    fn moveFocus(gui: *Interface, dir: FocusDir) void {
        const initial = gui.focus orelse return;

        var index = initial;

        switch (dir) {
            .forward => while (true) {
                index += 1;
                if (index >= gui.widgets.len)
                    index = 0;
                if (index == initial)
                    return; // nothing changed
                if (gui.widgets[index].control.canFocus()) {
                    gui.focus = index;
                    return;
                }
            },
            .backward => while (true) {
                if (index > 0) {
                    index -= 1;
                } else {
                    index = gui.widgets.len - 1;
                }
                if (index == initial)
                    return; // nothing changed
                if (gui.widgets[index].control.canFocus()) {
                    gui.focus = index;
                    return;
                }
            },
        }
    }

    pub fn sendKeyboardEvent(gui: *Interface, event: ashet.abi.KeyboardEvent) ?Event {
        const widget_index = gui.focus orelse return null;

        const widget = &gui.widgets[widget_index];

        switch (widget.control) {
            .button => |*ctrl| {
                if (!event.pressed)
                    return null;

                return switch (event.key) {
                    .@"return", .space => ctrl.clickEvent,

                    .tab => {
                        gui.moveFocus(if (event.modifiers.shift) .backward else .forward);
                        return null;
                    },

                    else => null,
                };
            },
            .text_box => |*ctrl| {
                if (event.pressed) {
                    switch (event.key) {
                        .@"return" => {
                            // send event
                        },

                        .home => ctrl.editor.moveCursor(.left, .line),
                        .end => ctrl.editor.moveCursor(.right, .line),

                        .left => ctrl.editor.moveCursor(.left, if (event.modifiers.ctrl) .word else .letter),
                        .right => ctrl.editor.moveCursor(.right, if (event.modifiers.ctrl) .word else .letter),

                        .backspace => ctrl.editor.delete(.left, if (event.modifiers.ctrl) .word else .letter),
                        .delete => ctrl.editor.delete(.right, if (event.modifiers.ctrl) .word else .letter),

                        .tab => gui.moveFocus(if (event.modifiers.shift) .backward else .forward),

                        else => {
                            if (event.text) |text_ptr| {
                                const text = std.mem.sliceTo(text_ptr, 0);

                                ctrl.editor.insertText(text) catch |err| logger.err("failed to insert string: {s}", .{@errorName(err)});
                            } else {
                                std.log.info("handle key {} for text box", .{event});
                            }
                        },
                    }

                    // adjust scroll to cursor position
                    const cursor_offset = @intCast(i16, 6 * ctrl.editor.cursor);
                    const cursor_pos = (cursor_offset - ctrl.scroll);
                    const limit = @intCast(u15, (widget.bounds.width -| 4));

                    if (cursor_pos < 0) {
                        ctrl.scroll -|= @intCast(u15, -cursor_pos) + limit / 4; // scroll to the left - 25% width
                    }
                    if (cursor_pos >= limit) {
                        ctrl.scroll = @intCast(u15, (cursor_offset - limit) + limit / 4); // scroll to the right + 25% width
                    }
                }
            },

            // these cannot be focused:
            .label, .panel, .picture => unreachable,
        }

        return null;
    }

    fn paintFocusMarker(target: Framebuffer, rect: Rectangle, theme: Theme) void {
        const H = struct {
            fn dither(x: i16, y: i16) bool {
                const rx = @bitCast(u16, x);
                const ry = @bitCast(u16, y);
                return ((rx ^ ry) & 1) == 0;
            }
        };

        var dst = target.clip(rect);

        var top = dst.pixels;
        var bot = dst.pixels + (dst.height - 1) * target.stride;

        var x: u15 = 0;
        while (x < dst.width) : (x += 1) {
            if (dst.dy == 0) {
                if (H.dither(dst.x + x, rect.top())) {
                    top[0] = theme.focus;
                }
            }
            if (dst.y + dst.height == rect.bottom()) {
                if (H.dither(dst.x + x, rect.bottom())) {
                    bot[0] = theme.focus;
                }
            }
            top += 1;
            bot += 1;
        }

        var left = dst.pixels;
        var right = dst.pixels + (dst.width - 1);

        var y: u15 = 0;
        while (y < dst.height) : (y += 1) {
            if (dst.dx == 0) {
                if (H.dither(rect.left(), dst.y + y)) {
                    left[0] = theme.focus;
                }
            }
            if (dst.x + dst.width == rect.right()) {
                if (H.dither(rect.right(), dst.y + y)) {
                    right[0] = theme.focus;
                }
            }

            left += target.stride;
            right += target.stride;
        }
    }

    pub fn paint(gui: Interface, target: Framebuffer) void {
        for (gui.widgets) |widget, index| {
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
                    target.fillRectangle(widget.bounds.shrink(1), if (ctrl.flags.read_only)
                        gui.theme.area
                    else
                        gui.theme.window);

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

                    var edit_view = target.view(Rectangle{
                        .x = b.x + 1,
                        .y = b.y + 1,
                        .width = b.width - 2,
                        .height = 9,
                    });

                    var writer = edit_view.screenWriter(1 - @as(i16, ctrl.scroll), 0, gui.theme.text, null);
                    if (ctrl.flags.password) {
                        writer.writer().writeByteNTimes('*', ctrl.content().len) catch {};
                    } else {
                        writer.writer().writeAll(ctrl.content()) catch {};
                    }

                    if (gui.focus == index) {
                        const cursor_x = 6 * ctrl.editor.cursor - ctrl.scroll;
                        edit_view.drawLine(
                            Point.new(1 + @intCast(i16, cursor_x), 1),
                            Point.new(1 + @intCast(i16, cursor_x), 8),
                            gui.theme.text_cursor,
                        );
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
                    target.blit(widget.bounds.position(), ctrl.bitmap);
                },
            }
            if (gui.focus == index) {
                paintFocusMarker(target, widget.bounds.shrink(1), gui.theme.*);
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

    pub fn canFocus(ctrl: Control) bool {
        return switch (ctrl) {
            .button => true,
            .text_box => true,

            .label => false,
            .panel => false,
            .picture => false,
        };
    }
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
    scroll: u15 = 0, // horizontal text scroll in pixels. value shifts the text to the left, so the cursor can stay in the text box

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
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = bitmap.width,
                .height = bitmap.height,
            },
            .control = .{
                .picture = Picture{
                    .bitmap = bitmap,
                },
            },
        };
    }
};

test "smoke test 01" {
    var tb_user_backing: [64]u8 = undefined;
    var tb_passwd_backing: [64]u8 = undefined;

    const demo_bitmap =
        \\................................
        \\...........CCCCCCCCCCC..........
        \\........CCCCCCCCCCCCCCCC........
        \\.......CCCCCCCCCCCCCCCCCC.......
        \\.....CCCCCCCCCCCCCCCCCCCCCC.....
        \\....CCC5555CCCCCCCCCCCCCCCC.....
        \\....C5555555CCCCCCCCC55555CC....
        \\...C555555555CCCCCCC5555555CC...
        \\..CC555555555CCCCCCC5555555CC...
        \\..CC55555F555CCCCCCC5555555CCC..
        \\..CC5555FFF5CCCCCCCC55F5555CCC..
        \\.CCC55555F5CCCCCCCCC5FFF555CCC..
        \\.CCCC55555CCCCCCCCCC55F555CCCC..
        \\.CCCCCCCCCCCCCCCCCCCC5555CCCCC..
        \\.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC.
        \\.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC.
        \\.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC.
        \\.CCCCCCCCCCCCCCCCCCCCCCCCCCCCCC.
        \\.CCCCCCCCCCCCCCCCCCCCCCCCCCCCC..
        \\.CCCC666CCCCCCCCCCCCCC666CCCCC..
        \\.CCC66666CCCCCCCCCCCC66666CCCC..
        \\..CC666666CCCCCCCCC6666666CCCC..
        \\..CC666666666CCCCC66666666CCC...
        \\..CC6666666666666666666666CCC...
        \\...CC66666666666666666666CCCC...
        \\....CC66666666666666666CCCCC....
        \\....CCCC6666666666666CCCCCC.....
        \\......CCCCC666666666CCCCCC......
        \\.......CCCCCCCCCCCCCCCCCC.......
        \\.........CCCCCCCCCCCCC..........
        \\................................
        \\................................
    ;

    var widgets = [_]Widget{
        Panel.new(5, 5, 172, 57),
        Panel.new(5, 65, 172, 57),
        Button.new(69, 42, null, "Cancel"),
        Button.new(135, 42, null, "Login"),
        try TextBox.new(69, 14, 99, &tb_user_backing, "xq"),
        try TextBox.new(69, 28, 99, &tb_passwd_backing, "********"),
        Label.new(15, 16, "Username:"),
        Label.new(15, 30, "Password:"),
        Picture.new(17, 78, Bitmap.parse(0, demo_bitmap)),
    };
    var interface = Interface{ .widgets = &widgets };

    var pixel_storage: [1][182]ColorIndex = undefined;
    var fb = Framebuffer{
        .pixels = @ptrCast([*]ColorIndex, &pixel_storage),
        .stride = 0, // just overwrite the first line again
        .width = 182,
        .height = 127,
    };

    interface.paint(fb);
}
