const std = @import("std");
const ashet = @import("ashet");
const TextEditor = @import("text-editor");
const logger = std.log.scoped(.gui);

pub const Point = ashet.abi.Point;
pub const Size = ashet.abi.Size;
pub const Rectangle = ashet.abi.Rectangle;
pub const ColorIndex = ashet.abi.ColorIndex;

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

    pub fn fromNumber(id: usize) EventID {
        return @intToEnum(EventID, id);
    }

    /// Constructs a new EventID from the given enum literal.
    /// This basically makes this enum a distributed enum that can create ad-hoc values.
    pub fn from(comptime tag: anytype) EventID {
        if (@typeInfo(@TypeOf(tag)) != .EnumLiteral)
            @compileError("tag must be a enum literal!");
        return @intToEnum(EventID, @errorToInt(@field(anyerror, @tagName(tag))));

        // const T = struct {
        //     var x: u8 = undefined;
        // };
        // return @intToEnum(EventID, @ptrToInt(&T.x));
    }
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
        .text = ColorIndex.get(0x0), // black
        .window = ColorIndex.get(0xF), // white
        .area_shadow = ColorIndex.get(0x9), // dark gray
        .area = ColorIndex.get(0xA), // gray
        .area_light = ColorIndex.get(0xB), // bright gray
        .label = ColorIndex.get(0xF), // white
        .focus = ColorIndex.get(0xC), // violet
        .text_cursor = ColorIndex.get(0x11), // dim gray
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
                const click_point = Point.new(event.x, event.y);
                if (gui.widgetFromPoint(click_point, &index)) |widget| {
                    if (widget.control.canFocus()) {
                        gui.focus = index;
                    } else {
                        gui.focus = null;
                    }

                    switch (widget.control) {
                        inline .button, .tool_button, .check_box, .radio_button => |*box| return box.click(),

                        .text_box => |*box| {
                            const offset = @intCast(usize, event.x - widget.bounds.x) -| 2; // adjust to "left text edge"

                            // compute the index:
                            // left half of character is "cursor left of character", right half is "cursor right of character"
                            const text_index = std.math.min((offset +| 3) / 6, box.editor.graphemeCount());

                            box.editor.cursor = text_index;
                        },

                        .label, .panel, .picture => {},

                        .scroll_bar => |*bar| {
                            const rects: ScrollBar.Boxes = bar.computeRectangles(widget.bounds) orelse return null;

                            const step_size = std.math.max(1, bar.range / 10);
                            const prev = bar.level;
                            if (rects.decrease_button.contains(click_point)) {
                                bar.level -|= step_size;
                            } else if (rects.increase_button.contains(click_point)) {
                                bar.level +|= step_size;
                            } else if (rects.scroll_area.contains(click_point)) {
                                const size = switch (bar.direction) {
                                    .vertical => @intCast(i16, rects.scroll_area.height),
                                    .horizontal => @intCast(i16, rects.scroll_area.width),
                                };
                                const pos = switch (bar.direction) {
                                    .vertical => click_point.y - rects.knob_button.y,
                                    .horizontal => click_point.x - rects.knob_button.x,
                                };
                                const rel_pos = @divTrunc(100 * pos, size);
                                const abs_jump = std.math.absCast(rel_pos);

                                const var_step_size: u15 = if (abs_jump > 50)
                                    30
                                else if (abs_jump > 25)
                                    25
                                else if (abs_jump > 10)
                                    10
                                else
                                    5;

                                // std.log.info("clickrel {} {} {} {}\n", .{ pos, rel_pos, abs_jump, var_step_size });

                                const delta = @intCast(u15, std.math.max(1, (var_step_size * @as(u32, bar.range)) / 100));
                                if (pos < 0) {
                                    bar.level -|= delta;
                                } else {
                                    bar.level +|= delta;
                                }
                            }

                            if (bar.level > bar.range)
                                bar.level = bar.range;

                            if (bar.level != prev) {
                                return bar.changedEvent;
                            }
                        },
                    }
                } else {
                    gui.focus = null;
                }
            },
            .button_release => {},
            .motion => {},
        }

        return null;
    }

    const FocusDir = enum { backward, forward };
    fn moveFocus(gui: *Interface, dir: FocusDir) void {
        const initial = gui.focus orelse {
            // nothing is focused right now, try focusing the first available widget

            for (gui.widgets, 0..) |w, i| {
                if (w.control.canFocus()) {
                    gui.focus = i;
                    return;
                }
            }

            return;
        };

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
        if (event.pressed and event.key == .tab) {
            gui.moveFocus(if (event.modifiers.shift) .backward else .forward);
            return null;
        }

        const widget_index = gui.focus orelse return null;

        const widget = &gui.widgets[widget_index];

        switch (widget.control) {
            inline .button, .tool_button, .check_box, .radio_button => |*ctrl| {
                if (!event.pressed)
                    return null;

                return switch (event.key) {
                    .@"return", .space => return ctrl.click(),

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

            .scroll_bar => @panic("scroll bar not implemented yet!"),

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

    const ElementStyle = enum {
        sunken, //
        raised, // button, ...
        groove, // ???
        ridge, // panel
    };
    const ElementBackground = enum {
        window_enabled,
        window_disabled,
        area,
    };

    fn drawRectangle(gui: Interface, target: Framebuffer, rect: Rectangle, style: ElementStyle, background: ElementBackground) void {
        const b = .{
            .x = rect.x,
            .y = rect.y,
            .width = @intCast(u15, rect.width),
            .height = @intCast(u15, rect.height),
        };

        target.fillRectangle(rect.shrink(1), switch (background) {
            .area, .window_disabled => gui.theme.area,
            .window_enabled => gui.theme.window,
        });

        switch (style) {
            .raised => {
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
            },
            .sunken => {
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
            },
            .ridge => {
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
            .groove => @panic("crease border not implemented yet!"),
        }
    }

    pub fn paint(gui: Interface, target: Framebuffer) void {
        for (gui.widgets, 0..) |widget, index| {
            const b = .{
                .x = widget.bounds.x,
                .y = widget.bounds.y,
                .width = @intCast(u15, widget.bounds.width),
                .height = @intCast(u15, widget.bounds.height),
            };
            switch (widget.control) {
                inline .tool_button, .button => |ctrl| {
                    gui.drawRectangle(target, widget.bounds, .raised, .area);

                    if (@hasField(@TypeOf(ctrl), "text")) {
                        target.drawString(b.x + 2, b.y + 2, ctrl.text, gui.theme.text, b.width -| 2);
                    }
                    if (@hasField(@TypeOf(ctrl), "icon")) {
                        const icon: Bitmap = ctrl.icon;
                        target.blit(
                            Point.new(
                                b.x + (b.width -| icon.width) / 2,
                                b.y + (b.height -| icon.height) / 2,
                            ),
                            icon,
                        );
                    }
                },
                .label => |ctrl| {
                    target.drawString(b.x, b.y, ctrl.text, gui.theme.label, b.width);
                },
                .text_box => |ctrl| {
                    gui.drawRectangle(target, widget.bounds, .sunken, if (ctrl.flags.read_only) .window_disabled else .window_enabled);

                    var edit_view = target.view(Rectangle{
                        .x = b.x + 1,
                        .y = b.y + 1,
                        .width = b.width -| 2,
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
                    gui.drawRectangle(target, widget.bounds, .ridge, .area);
                },
                .picture => |ctrl| {
                    target.blit(widget.bounds.position(), ctrl.bitmap);
                },
                .check_box => |ctrl| {
                    std.debug.assert(b.width == 7 and b.height == 7);
                    target.fillRectangle(widget.bounds.shrink(1), gui.theme.window);
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

                    if (ctrl.checked) {
                        target.blit(Point.new(b.x + 1, b.y + 1), CheckBox.checked_icon);
                    }
                },

                .radio_button => |ctrl| {
                    std.debug.assert(b.width == 7 and b.height == 7);
                    target.fillRectangle(widget.bounds.shrink(1), gui.theme.window);

                    target.drawLine(
                        Point.new(b.x + 2, b.y),
                        Point.new(b.x + b.width - 3, b.y),
                        gui.theme.area_shadow,
                    );
                    target.drawLine(
                        Point.new(b.x + b.width - 1, b.y + 2),
                        Point.new(b.x + b.width - 1, b.y + b.height - 3),
                        gui.theme.area_shadow,
                    );

                    target.drawLine(
                        Point.new(b.x, b.y + 2),
                        Point.new(b.x, b.y + b.height - 3),
                        gui.theme.area_light,
                    );
                    target.drawLine(
                        Point.new(b.x + 2, b.y + b.height - 1),
                        Point.new(b.x + b.width - 3, b.y + b.height - 1),
                        gui.theme.area_light,
                    );

                    target.setPixel(b.x + 1, b.y + 1, gui.theme.area_shadow);
                    target.setPixel(b.x + b.width - 2, b.y + 1, gui.theme.area_shadow);
                    target.setPixel(b.x + 1, b.y + b.height - 2, gui.theme.area_light);
                    target.setPixel(b.x + b.width - 2, b.y + b.height - 2, gui.theme.area_shadow);

                    if (ctrl.group.selected == ctrl.value) {
                        target.blit(Point.new(b.x + 1, b.y + 1), RadioButton.checked_icon);
                    }
                },

                .scroll_bar => |bar| widget: {
                    const positions = bar.computeRectangles(b) orelse {
                        // TODO: Filler
                        break :widget;
                    };

                    gui.drawRectangle(target, positions.decrease_button, .raised, .area);
                    gui.drawRectangle(target, positions.scroll_area, .sunken, .area);
                    gui.drawRectangle(target, positions.increase_button, .raised, .area);
                    gui.drawRectangle(target, positions.knob_button, .raised, .area);

                    target.blit(
                        Point.new(
                            positions.decrease_button.x + @intCast(u15, positions.decrease_button.width -| ScrollBar.arrow_up.width) / 2,
                            positions.decrease_button.y + @intCast(u15, positions.decrease_button.height -| ScrollBar.arrow_up.height) / 2,
                        ),
                        switch (bar.direction) {
                            .vertical => ScrollBar.arrow_up,
                            .horizontal => ScrollBar.arrow_left,
                        },
                    );
                    target.blit(
                        Point.new(
                            positions.increase_button.x + @intCast(u15, positions.increase_button.width -| ScrollBar.arrow_up.width) / 2,
                            positions.increase_button.y + @intCast(u15, positions.increase_button.height -| ScrollBar.arrow_up.height) / 2,
                        ),
                        switch (bar.direction) {
                            .vertical => ScrollBar.arrow_down,
                            .horizontal => ScrollBar.arrow_right,
                        },
                    );
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
    check_box: CheckBox,
    radio_button: RadioButton,
    scroll_bar: ScrollBar,
    tool_button: ToolButton,

    pub fn canFocus(ctrl: Control) bool {
        return switch (ctrl) {
            .button => true,
            .text_box => true,
            .check_box => true,
            .radio_button => true,
            .scroll_bar => true,
            .tool_button => true,

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

    pub fn click(button: *Button) ?Event {
        return button.clickEvent;
    }
};

pub const ToolButton = struct {
    clickEvent: ?Event = null,
    icon: Bitmap,

    pub fn new(x: i16, y: i16, icon: Bitmap) Widget {
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = icon.width + 4,
                .height = icon.height + 4,
            },
            .control = .{
                .tool_button = ToolButton{
                    .clickEvent = null,
                    .icon = icon,
                },
            },
        };
    }

    pub fn click(button: *ToolButton) ?Event {
        return button.clickEvent;
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

pub const CheckBox = struct {
    const checked_icon = Bitmap.parse(0,
        \\.....
        \\.0.0.
        \\..0..
        \\.0.0.
        \\.....
    );

    checked: bool,
    checkedChanged: ?Event = null,

    pub fn new(x: i16, y: i16, checked: bool) Widget {
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = 7,
                .height = 7,
            },
            .control = .{
                .check_box = CheckBox{
                    .checked = checked,
                },
            },
        };
    }

    pub fn click(checkbox: *CheckBox) ?Event {
        checkbox.checked = !checkbox.checked;
        return checkbox.checkedChanged;
    }
};

/// A group of radio buttons.
/// Each radio button has a value that is transferred to `.selected` on click.
/// If no button is selected, `RadioGroup.none` is set.
pub const RadioGroup = struct {
    pub const none = std.math.maxInt(u32);

    selected: u32 = none,
    selectionChanged: ?Event = null,
};

pub const RadioButton = struct {
    const checked_icon = Bitmap.parse(0,
        \\.....
        \\.000.
        \\.000.
        \\.000.
        \\.....
    );

    group: *RadioGroup,
    value: u32,

    pub fn new(x: i16, y: i16, group: *RadioGroup, value: u32) Widget {
        std.debug.assert(value != RadioGroup.none);
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = 7,
                .height = 7,
            },
            .control = .{
                .radio_button = RadioButton{
                    .value = value,
                    .group = group,
                },
            },
        };
    }

    pub fn click(radiobutton: *RadioButton) ?Event {
        radiobutton.group.selected = radiobutton.value;
        return radiobutton.group.selectionChanged;
    }
};

pub const ScrollBar = struct {
    pub const Direction = enum { vertical, horizontal };

    const arrow_up = Bitmap.parse(0,
        \\.......
        \\.......
        \\...0...
        \\..0.0..
        \\.0...0.
        \\.......
        \\.......
    );
    const arrow_down = Bitmap.parse(0,
        \\.......
        \\.......
        \\.0...0.
        \\..0.0..
        \\...0...
        \\.......
        \\.......
    );
    const arrow_left = Bitmap.parse(0,
        \\.......
        \\....0..
        \\...0...
        \\..0....
        \\...0...
        \\....0..
        \\.......
    );
    const arrow_right = Bitmap.parse(0,
        \\.......
        \\..0....
        \\...0...
        \\....0..
        \\...0...
        \\..0....
        \\.......
    );
    const handle_vert = Bitmap.parse(0,
        \\.......
        \\..0....
        \\...0...
        \\....0..
        \\...0...
        \\..0....
        \\.......
    );
    const handle_horiz = Bitmap.parse(0,
        \\.......
        \\..0....
        \\...0...
        \\....0..
        \\...0...
        \\..0....
        \\.......
    );

    pub fn handleSize(bar: ScrollBar, available_space: u16) u16 {
        return std.math.max(
            std.math.min(std.math.max(available_space / 22, 5), 30),
            available_space -| bar.range,
        );
    }

    range: u15,
    level: u15 = 0,
    direction: Direction,

    changedEvent: ?Event = null,

    pub fn new(x: i16, y: i16, direction: Direction, length: u15, range: u15) Widget {
        std.debug.assert(length > 33);
        return Widget{
            .bounds = Rectangle{
                .x = x,
                .y = y,
                .width = switch (direction) {
                    .vertical => 11,
                    .horizontal => length,
                },
                .height = switch (direction) {
                    .vertical => length,
                    .horizontal => 11,
                },
            },
            .control = .{
                .scroll_bar = ScrollBar{
                    .changedEvent = null,
                    .level = 0,
                    .range = range,
                    .direction = direction,
                },
            },
        };
    }

    fn computeRectangles(bar: ScrollBar, b: Rectangle) ?Boxes {
        switch (bar.direction) {
            .vertical => {
                const bsize = @intCast(u15, b.width);
                const height = @intCast(u15, b.height);

                if (height < 3 * bsize)
                    return null;

                const decrease_button = Rectangle{
                    .x = b.x,
                    .y = b.y,
                    .width = bsize,
                    .height = bsize,
                };
                const scroll_area = Rectangle{
                    .x = b.x,
                    .y = b.y + bsize,
                    .width = b.width,
                    .height = height - 2 * bsize,
                };
                const increase_button = Rectangle{
                    .x = b.x,
                    .y = b.y + height - bsize,
                    .width = bsize,
                    .height = bsize,
                };

                const scroll_range = scroll_area.shrink(2);

                var knob_button = scroll_area.shrink(2);
                knob_button.height = bar.handleSize(scroll_range.height);
                if (bar.range > 0)
                    knob_button.y += @intCast(u15, (@as(u32, scroll_range.height -| knob_button.height -| 1) * bar.level) / bar.range);

                return Boxes{
                    .decrease_button = decrease_button,
                    .scroll_area = scroll_area,
                    .increase_button = increase_button,
                    .knob_button = knob_button,
                };
            },

            .horizontal => {
                const width = @intCast(u15, b.width);
                const bsize = @intCast(u15, b.height);

                if (width < 3 * bsize)
                    return null;

                const decrease_button = Rectangle{
                    .x = b.x,
                    .y = b.y,
                    .width = bsize,
                    .height = bsize,
                };
                const scroll_area = Rectangle{
                    .x = b.x + bsize,
                    .y = b.y,
                    .width = width - 2 * bsize,
                    .height = b.height,
                };
                const increase_button = Rectangle{
                    .x = b.x + width - bsize,
                    .y = b.y,
                    .width = bsize,
                    .height = bsize,
                };
                const scroll_range = scroll_area.shrink(2);

                var knob_button = scroll_area.shrink(2);
                knob_button.width = bar.handleSize(scroll_range.width);
                if (bar.range > 0)
                    knob_button.x += @intCast(u15, (@as(u32, scroll_range.width -| knob_button.width -| 1) * bar.level) / bar.range);

                return Boxes{
                    .decrease_button = decrease_button,
                    .scroll_area = scroll_area,
                    .increase_button = increase_button,
                    .knob_button = knob_button,
                };
            },
        }
    }

    pub fn setRange(bar: *ScrollBar, range: u15) void {
        bar.range = range;
        bar.level = std.math.clamp(bar.level, 0, bar.range);
    }

    const Boxes = struct {
        decrease_button: Rectangle,
        scroll_area: Rectangle,
        increase_button: Rectangle,
        knob_button: Rectangle,
    };
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

    var radio_group = RadioGroup{};

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

        Label.new(80, 70, "Magic"),
        Label.new(80, 80, "Turbo"),

        CheckBox.new(70, 70, true),
        CheckBox.new(70, 80, false),

        Label.new(80, 90, "Tall"),
        Label.new(80, 98, "Grande"),
        Label.new(80, 106, "Venti"),

        RadioButton.new(70, 90, &radio_group, 0),
        RadioButton.new(70, 98, &radio_group, 1),
        RadioButton.new(70, 106, &radio_group, 2),
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
