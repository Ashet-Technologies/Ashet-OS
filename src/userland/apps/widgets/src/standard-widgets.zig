const std = @import("std");
const ashet = @import("ashet");

const draw_lib = @import("draw.zig");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

const abi = ashet.abi;
const Size = abi.Size;
const Point = abi.Point;
const Rectangle = abi.Rectangle;
const UUID = abi.UUID;
const Widget = abi.Widget;
const WidgetType = abi.WidgetType;
const WidgetEvent = abi.WidgetEvent;

const CommandQueue = ashet.graphics.CommandQueue;

var render_queue: CommandQueue = CommandQueue.init(ashet.process.mem.allocator()) catch unreachable;

pub const Theme = draw_lib.Theme;

pub const draw = draw_lib;

var theme: Theme = undefined;

pub fn main() !void {
    errdefer |err| std.log.err("Failed to setup standard widgets: {s}", .{@errorName(err)});

    // TODO: Load theme from disk via common implementation shared between desktop server and
    //       widget server.
    _ = try initialize_default_theme(ashet.graphics.get_system_font);

    const button_type = try register_widget_type(Button);
    defer button_type.destroy_now();

    const tool_button_type = try register_widget_type(ToolButton);
    defer tool_button_type.destroy_now();

    const label_type = try register_widget_type(Label);
    defer label_type.destroy_now();

    const text_box_type = try register_widget_type(TextBox);
    defer text_box_type.destroy_now();

    const list_box_type = try register_widget_type(ListBox);
    defer list_box_type.destroy_now();

    // TODO: Implement TSR
    while (true) {
        ashet.abi.process.thread.yield();
    }
}

const FontLoader = fn ([]const u8) error{ Unexpected, FileNotFound, SystemResources }!ashet.graphics.Font;

pub fn initialize_default_theme(comptime get_system_font: FontLoader) !*const Theme {
    theme = .create_default(.{
        .hue = .purple,
        .saturation = 2,
        .value = 4,
        .border = .yellow,
        .menu_font = try get_system_font("sans-6"),
        .item_font = try get_system_font("sans-6"),
        .title_font = try get_system_font("sans-6"),
        .widget_font = try get_system_font("mono-8"),
    });
    return &theme;
}

fn register_widget_type(comptime WidgetImpl: type) !ashet.gui.WidgetType {
    const Wrapper = WidgetWrapper(WidgetImpl);
    return try ashet.gui.register_widget_type(.{
        .uuid = Wrapper.uuid.*,
        .data_size = @sizeOf(Wrapper),
        .flags = Wrapper.flags,
        .handle_event = Wrapper.handle_event,
    });
}

fn WidgetWrapper(comptime WidgetImpl: type) type {
    return struct {
        const Wrapper = @This();

        pub const uuid: *const UUID = WidgetImpl.uuid;
        pub const flags: ashet.gui.WidgetDescriptor.Flags = WidgetImpl.flags;

        impl: WidgetImpl,
        widget: Widget,
        framebuffer: ?ashet.graphics.Framebuffer,

        pub fn from_impl(impl: *WidgetImpl) *Wrapper {
            return @fieldParentPtr("impl", impl);
        }

        /// Invalidates the widget and forces a repaint before the next display.
        pub fn invalidate(wrapper: *Wrapper) !void {
            // TODO: Only invalidate the widget here instead of force-repainting!
            try wrapper.paint();
        }

        fn paint(wrapper: *Wrapper) !void {
            const fb = wrapper.framebuffer orelse blk: {
                wrapper.framebuffer = ashet.graphics.create_widget_framebuffer(wrapper.widget) catch |err| {
                    std.log.err("failed to create widget framebuffer: {s}", .{@errorName(err)});
                    return;
                };
                break :blk wrapper.framebuffer.?;
            };

            const size = try ashet.graphics.get_framebuffer_size(fb);

            const cq = &render_queue;
            cq.reset();

            try wrapper.impl.paint(cq, size);

            try cq.submit(fb, .{});
        }

        fn control(wrapper: *Wrapper, message: ashet.gui.WidgetControlMessage) !usize {
            // TODO: Implement auto-magic control functions with parameter unwrapping
            return try wrapper.impl.control(message);
        }

        fn handle_event(widget_type: WidgetType, widget: Widget, event: *const WidgetEvent) callconv(.c) usize {
            _ = widget_type;

            const data_ptr = ashet.abi.gui.get_widget_data(widget) catch |err| {
                std.log.err("failed to fetch widget data: {s}", .{@errorName(err)});
                return 0;
            };
            const wrapper: *Wrapper = @ptrCast(data_ptr);

            init: switch (event.event_type) {
                .create => {
                    wrapper.* = .{
                        .widget = widget,
                        .framebuffer = ashet.graphics.create_widget_framebuffer(widget) catch null,
                        .impl = WidgetImpl.init(widget),
                    };
                    if (wrapper.framebuffer == null) {
                        std.log.err("failed to initialize widget framebuffer.", .{});
                        // TODO: Return error code: widget could not be created!
                    }

                    // TODO: Move the below into the GUI framework, as this is true for every widget:
                    // Each widget must be drawn after creation:
                    wrapper.invalidate() catch |err| {
                        std.log.err("failed to invalidate {s}: {s}", .{ @typeName(WidgetImpl), @errorName(err) });
                    };

                    continue :init .paint; // widgets should be drawn at least once
                },

                .destroy => {
                    wrapper.impl.deinit();
                    if (wrapper.framebuffer) |fb| {
                        fb.release();
                    }
                    wrapper.* = undefined;
                },

                .paint => wrapper.paint() catch |err| {
                    std.log.err("failed to paint {s}: {s}", .{ @typeName(WidgetImpl), @errorName(err) });
                },

                .control => return wrapper.control(event.control) catch |err| {
                    std.log.err("failed to control {s}: {s}", .{ @typeName(WidgetImpl), @errorName(err) });
                    return 0;
                },

                else => {
                    if (@hasDecl(WidgetImpl, "handle_event")) {
                        wrapper.impl.handle_event(event.*) catch |err| {
                            std.log.err("failed to handle event {} for {s}: {s}", .{ event.event_type, @typeName(WidgetImpl), @errorName(err) });
                        };
                    } else {
                        // TODO: Implement the other messages
                        std.log.info("{s}.handle_event({f}, {}): unhandled event", .{ @typeName(WidgetImpl), widget, event.event_type });
                    }
                },
            }
            return 0;
        }

        fn notify_owner(wrapper: *Wrapper, event: ashet.gui.NotifyEvent, params: [4]usize) !void {
            try ashet.gui.notify_owner(
                wrapper.widget,
                event,
                params,
            );
        }
    };
}

pub const Label = struct {
    pub const uuid = ashet.gui.widgets.Label.uuid;

    pub const flags: ashet.gui.WidgetDescriptor.Flags = .{
        .focusable = false,
        .context_menu = false,
        .hit_test_visible = false,
        .allow_drop = false,
        .clipboard_sensitive = false,
    };

    const wrapper = WidgetWrapper(@This()).from_impl;

    text: std.ArrayListUnmanaged(u8) = .empty,

    fn init(widget: Widget) Label {
        _ = widget;
        return .{};
    }

    fn deinit(label: *Label) void {
        label.text.deinit(ashet.process.mem.allocator());
        label.* = undefined;
    }

    pub fn paint(label: *Label, cq: *CommandQueue, size: Size) !void {
        try cq.clear(theme.window_active.background);

        try draw_aligned_text(
            cq,
            .new(.new(1, 1), .new(size.width -| 2, size.height -| 2)),
            theme.widget_font,
            theme.text_color,
            label.text.items,
            .{
                .vertical = .middle,
                .horizontal = .middle,
            },
        );
    }

    fn control(label: *Label, msg: ashet.abi.WidgetControlMessage) !usize {
        switch (msg.type) {
            ashet.gui.widgets.Label.set_text => {
                const ptr: [*]const u8 = @ptrFromInt(msg.params[0]);
                const text = ptr[0..msg.params[1]];

                try label.text.ensureTotalCapacity(ashet.process.mem.allocator(), text.len);

                label.text.clearRetainingCapacity();
                label.text.appendSliceAssumeCapacity(text);

                try WidgetWrapper(Label).from_impl(label).invalidate();
            },
            ashet.gui.widgets.Label.set_alignment => {
                return error.Unimplemented;
            },

            else => return error.UnknownControl,
        }
        return 0;
    }
};

pub const Button = struct {
    pub const uuid = ashet.gui.widgets.Button.uuid;

    pub const flags: ashet.gui.WidgetDescriptor.Flags = .{
        .focusable = true,
        .context_menu = false,
        .hit_test_visible = true,
        .allow_drop = false,
        .clipboard_sensitive = false,
    };

    const wrapper = WidgetWrapper(@This()).from_impl;

    text: std.ArrayListUnmanaged(u8) = .empty,

    fn init(widget: Widget) Button {
        _ = widget;
        return .{};
    }

    fn deinit(button: *Button) void {
        button.text.deinit(ashet.process.mem.allocator());
        button.* = undefined;
    }

    fn control(button: *Button, msg: ashet.abi.WidgetControlMessage) !usize {
        switch (msg.type) {
            ashet.gui.widgets.Button.set_text => {
                const ptr: [*]const u8 = @ptrFromInt(msg.params[0]);
                const text = ptr[0..msg.params[1]];

                try button.text.ensureTotalCapacity(ashet.process.mem.allocator(), text.len);

                button.text.clearRetainingCapacity();
                button.text.appendSliceAssumeCapacity(text);

                try WidgetWrapper(Button).from_impl(button).invalidate();
                return 0;
            },

            else => return error.UnknownControl,
        }
    }

    fn handle_event(button: *Button, event: ashet.gui.WidgetEvent) !void {
        switch (event.event_type) {
            .resize_requested => {
                event.resize_requested.requested_size.height = 15;
            },

            .click => {
                try button.wrapper().notify_owner(
                    ashet.gui.widgets.Button.clicked,
                    .{ 0, 0, 0, 0 },
                );
            },

            // Ignore standard mouse events:
            .mouse_enter,
            .mouse_leave,
            .mouse_button_press,
            .mouse_button_release,
            .mouse_hover,
            .mouse_motion,
            .scroll,
            => {},

            .key_press, .key_release => {},

            .focus_enter, .focus_leave => {},

            // ignored events:

            .resized => {},

            .clipboard_copy, .clipboard_cut, .clipboard_paste => {}, // TODO: These should be unreachable

            .drag_enter, .drag_leave, .drag_over, .drag_drop => {}, // TODO: These should be unreachable

            .context_menu_request => {}, // TODO: These should be unreachable

            // Implemented in the wrapper
            .paint, .control, .create, .destroy => unreachable,

            _ => {},
        }
    }

    pub fn paint(button: *Button, cq: *CommandQueue, size: Size) !void {
        const rect: Rectangle = .new(.zero, size);

        try cq.draw_line(
            .new(rect.left(), rect.top()),
            .new(rect.right() -| 1, rect.top()),
            theme.border_bright,
        );
        try cq.draw_line(
            .new(rect.left(), rect.top() +| 1),
            .new(rect.left(), rect.bottom() -| 1),
            theme.border_bright,
        );
        try cq.draw_rect(
            rect.shrink(1),
            theme.border_normal,
        );
        try cq.draw_line(
            .new(rect.right(), rect.top() +| 1),
            .new(rect.right(), rect.bottom()),
            theme.border_dark,
        );
        try cq.draw_line(
            .new(rect.left() +| 1, rect.bottom()),
            .new(rect.right(), rect.bottom()),
            theme.border_dark,
        );
        try cq.fill_rect(
            rect.shrink(2),
            theme.widget_background,
        );

        const text = rstrip(button.text.items);
        if (text.len > 0) {
            try draw_aligned_text(
                cq,
                .{ .x = rect.left() +| 5, .y = rect.top() +| 4, .width = rect.width -| 10, .height = rect.height -| 8 },
                theme.widget_font, // TODO: How to make font customizable?
                theme.text_color,
                text,
                .{
                    .horizontal = .middle,
                    .vertical = .middle,
                },
            );
        }
    }
};

pub const ToolButton = struct {
    pub const uuid = ashet.gui.widgets.ToolButton.uuid;

    pub const flags: ashet.gui.WidgetDescriptor.Flags = .{
        .focusable = true,
        .context_menu = false,
        .hit_test_visible = true,
        .allow_drop = false,
        .clipboard_sensitive = false,
    };

    const wrapper = WidgetWrapper(@This()).from_impl;

    _dummy: u32 = 0,

    fn init(widget: Widget) ToolButton {
        _ = widget;
        return .{};
    }

    fn deinit(button: *ToolButton) void {
        // button.text.deinit(ashet.process.mem.allocator());
        button.* = undefined;
    }

    fn control(button: *ToolButton, msg: ashet.abi.WidgetControlMessage) !usize {
        _ = button;
        switch (msg.type) {
            else => return error.UnknownControl,
        }
    }

    fn handle_event(button: *ToolButton, event: ashet.gui.WidgetEvent) !void {
        switch (event.event_type) {
            .resize_requested => {
                // Enforce the 9x9 size:
                event.resize_requested.requested_size.* = .new(9, 9);
            },

            .click => {
                try ashet.gui.notify_owner(
                    WidgetWrapper(ToolButton).from_impl(button).widget,
                    ashet.gui.widgets.ToolButton.clicked,
                    .{ 0, 0, 0, 0 },
                );
            },

            // Ignore standard mouse events:
            .mouse_enter,
            .mouse_leave,
            .mouse_button_press,
            .mouse_button_release,
            .mouse_hover,
            .mouse_motion,
            .scroll,
            => {},

            .resized => {},

            .key_press, .key_release => {},

            .focus_enter, .focus_leave => {},

            .clipboard_copy, .clipboard_cut, .clipboard_paste => {}, // TODO: These should be unreachable

            .drag_enter, .drag_leave, .drag_over, .drag_drop => {}, // TODO: These should be unreachable

            .context_menu_request => {}, // TODO: These should be unreachable

            // Implemented in the wrapper
            .paint, .control, .create, .destroy => unreachable,

            _ => {},
        }
    }

    pub fn paint(button: *ToolButton, cq: *CommandQueue, size: Size) !void {
        _ = button;
        const rect: Rectangle = .new(.zero, size);
        try cq.draw_line(
            .new(rect.left(), rect.top()),
            .new(rect.right(), rect.top()),
            theme.border_bright,
        );
        try cq.draw_line(
            .new(rect.left(), rect.top() +| 1),
            .new(rect.left(), rect.bottom()),
            theme.border_bright,
        );
        try cq.draw_line(
            .new(rect.right(), rect.top() +| 1),
            .new(rect.right(), rect.bottom()),
            theme.border_dark,
        );
        try cq.draw_line(
            .new(rect.left(), rect.bottom()),
            .new(rect.right(), rect.bottom()),
            theme.border_dark,
        );
        try cq.fill_rect(
            rect.shrink(1),
            theme.border_normal,
        );

        // TODO: Implement bitmaps:
        // if (opt.icon) |icon| {
        //     try cq.blit_bitmap(
        //         rect.left() +| 2,
        //         rect.top() +| 2,
        //         icon,
        //     );
        // }
    }
};

pub const TextBox = struct {
    pub const uuid = ashet.gui.widgets.TextBox.uuid;

    pub const flags: ashet.gui.WidgetDescriptor.Flags = .{
        .focusable = true,
        .context_menu = false,
        .hit_test_visible = true,
        .allow_drop = false,
        .clipboard_sensitive = false,
    };

    const wrapper = WidgetWrapper(@This()).from_impl;

    text: std.ArrayListUnmanaged(u8) = .empty,

    fn init(widget: Widget) TextBox {
        _ = widget;
        return .{};
    }

    fn deinit(button: *TextBox) void {
        button.text.deinit(ashet.process.mem.allocator());
        button.* = undefined;
    }

    fn control(textbox: *TextBox, msg: ashet.abi.WidgetControlMessage) !usize {
        switch (msg.type) {
            ashet.gui.widgets.TextBox.set_text => {
                const ptr: [*]const u8 = @ptrFromInt(msg.params[0]);
                const text = ptr[0..msg.params[1]];

                try textbox.text.ensureTotalCapacity(ashet.process.mem.allocator(), text.len);

                textbox.text.clearRetainingCapacity();
                textbox.text.appendSliceAssumeCapacity(text);

                try WidgetWrapper(TextBox).from_impl(textbox).invalidate();
                return 0;
            },

            else => return error.UnknownControl,
        }
    }

    fn handle_event(textbox: *TextBox, event: ashet.gui.WidgetEvent) !void {
        switch (event.event_type) {
            .resize_requested => {
                event.resize_requested.requested_size.height = 15;
            },

            .key_press => {
                const kbd = event.keyboard;

                const prevlen = textbox.text.items.len;
                switch (kbd.usage) {
                    .backspace, .kp_backspace => {
                        // TODO: Right now, we're dropping the last codepoint, which is
                        //       wrong. We have to drop the last codepoint:
                        var popped: usize = 0;
                        while (textbox.text.pop()) |last| {
                            popped += 1;
                            if (std.unicode.utf8ByteSequenceLength(last)) |length| {
                                std.debug.assert(popped == length);
                                break;
                            } else |err| switch (err) {
                                error.Utf8InvalidStartByte => {},
                            }
                        }
                    },

                    .enter, .kp_enter => {
                        try ashet.gui.notify_owner(
                            WidgetWrapper(TextBox).from_impl(textbox).widget,
                            ashet.gui.widgets.TextBox.accepted,
                            .{ 0, 0, 0, 0 },
                        );
                    },

                    .escape => {
                        try ashet.gui.notify_owner(
                            WidgetWrapper(TextBox).from_impl(textbox).widget,
                            ashet.gui.widgets.TextBox.accepted,
                            .{ 0, 0, 0, 0 },
                        );
                    },

                    else => if (kbd.text_ptr != null and kbd.text_len > 0) {
                        try textbox.text.appendSlice(ashet.process.mem.allocator(), kbd.text_ptr.?[0..kbd.text_len]);
                    },
                }

                if (textbox.text.items.len != prevlen) {
                    try WidgetWrapper(TextBox).from_impl(textbox).invalidate();

                    try ashet.gui.notify_owner(
                        WidgetWrapper(TextBox).from_impl(textbox).widget,
                        ashet.gui.widgets.TextBox.text_changed,
                        .{ 0, 0, 0, 0 },
                    );
                }
            },
            .key_release => {},

            .click => {},
            .resized => {},

            // Ignore standard mouse events:
            .mouse_enter,
            .mouse_leave,
            .mouse_button_press,
            .mouse_button_release,
            .mouse_hover,
            .mouse_motion,
            .scroll,
            => {},

            .focus_enter, .focus_leave => {},

            // ignored events:

            .clipboard_copy, .clipboard_cut, .clipboard_paste => {}, // TODO: These should be unreachable

            .drag_enter, .drag_leave, .drag_over, .drag_drop => {}, // TODO: These should be unreachable

            .context_menu_request => {}, // TODO: These should be unreachable

            // Implemented in the wrapper
            .paint, .control, .create, .destroy => unreachable,

            _ => {},
        }
    }

    pub fn paint(textbox: *TextBox, cq: *CommandQueue, size: Size) !void {
        const rect: Rectangle = .new(.zero, size);

        try draw_panel(cq, .{
            .bounds = rect,
            .style = .sunken,
        });

        try cq.fill_rect(
            rect.shrink(2),
            theme.widget_background,
        );

        const text = rstrip(textbox.text.items);
        if (text.len > 0) {
            try cq.draw_text(
                .new(rect.left() +| 4, rect.top() +| 4),
                theme.widget_font,
                theme.text_color,
                text,
            );
        }
    }
};

pub const ListBox = struct {
    pub const Item = ashet.gui.widgets.ListBox.Item;
    pub const GetItemCallback = ashet.gui.widgets.ListBox.GetItemCallback;

    pub const uuid = ashet.gui.widgets.ListBox.uuid;

    pub const flags: ashet.gui.WidgetDescriptor.Flags = .{
        .focusable = true,
        .context_menu = false,
        .hit_test_visible = true,
        .allow_drop = false,
        .clipboard_sensitive = false,
    };

    const wrapper = WidgetWrapper(@This()).from_impl;

    item_count: usize = 9,
    selected_index: ?usize = null,

    get_item_callback: ?GetItemCallback = null,
    get_item_context: ?*anyopaque = null,

    item_height: u15 = 0,

    fn init(widget: Widget) ListBox {
        _ = widget;
        return .{};
    }

    fn deinit(listbox: *ListBox) void {
        listbox.* = undefined;
    }

    fn select_item(listbox: *ListBox, new_index: ?usize) !void {
        if (listbox.selected_index == new_index)
            return;

        if (new_index) |index| {
            std.debug.assert(index < listbox.item_count);
        }

        listbox.selected_index = new_index;

        try listbox.wrapper().invalidate();

        try listbox.wrapper().notify_owner(
            ashet.gui.widgets.ListBox.selected_item_changed,
            .{ listbox.selected_index orelse ashet.gui.widgets.ListBox.empty_selection_index, 0, 0, 0 },
        );
    }

    fn control(listbox: *ListBox, msg: ashet.abi.WidgetControlMessage) !usize {
        switch (msg.type) {
            ashet.gui.widgets.ListBox.set_list => {
                const count: usize = msg.params[0];
                const callback: ?GetItemCallback = @ptrFromInt(msg.params[1]);
                const context: usize = msg.params[2];
                const selection: usize = msg.params[3];

                if (count > 0 and callback != null) {
                    // If we got a new list callback provided:

                    switch (selection) {
                        ashet.gui.widgets.ListBox.set_list_keep_selection => {
                            if (listbox.selected_index) |index| {
                                // If we currently have a selected index, reset it to
                                // null if it can't be retained.
                                if (index >= count) {
                                    listbox.selected_index = null;
                                }
                            }
                        },

                        ashet.gui.widgets.ListBox.set_list_clear_selection => listbox.selected_index = null,

                        else => listbox.selected_index = @min(selection, count -| 1),
                    }

                    listbox.item_count = count;
                    listbox.get_item_callback = callback;
                    listbox.get_item_context = @ptrFromInt(context);
                } else {
                    listbox.item_count = 0;
                    listbox.get_item_callback = null;
                    listbox.get_item_context = null;
                }

                try listbox.wrapper().invalidate();
                return 0;
            },

            ashet.gui.widgets.ListBox.get_selected_item => {
                return listbox.selected_index orelse ashet.gui.widgets.ListBox.empty_selection_index;
            },

            ashet.gui.widgets.ListBox.set_selected_item => {
                const raw_index = msg.params[0];

                const index = if (raw_index !=
                    ashet.gui.widgets.ListBox.empty_selection_index)
                    raw_index
                else
                    null;

                if (index) |i| {
                    if (i >= listbox.item_count)
                        return 0;
                }

                try listbox.select_item(index);

                return 0;
            },

            else => return error.UnknownControl,
        }
    }

    fn handle_event(listbox: *ListBox, event: ashet.gui.WidgetEvent) !void {
        switch (event.event_type) {
            .click => {
                switch (event.clicked.source) {
                    .keyboard, .synthetic => {
                        // always accept synthetic or keyboard clicks
                    },
                    .mouse => {
                        // reject mouse clicks outside items:
                        if (listbox.item_height <= 0)
                            return;

                        const top_offset: i16 = 2;

                        const index_signed = @divFloor(event.clicked.position.y -| top_offset, listbox.item_height);

                        if (index_signed < 0 or index_signed >= listbox.item_count) {
                            return;
                        }

                        const index: usize = @intCast(index_signed);

                        // Emit clicks only when the clicked item is already selected:
                        if (listbox.selected_index != index) {
                            try listbox.select_item(index);
                            return;
                        }
                    },
                }

                if (listbox.selected_index) |index| {
                    try listbox.wrapper().notify_owner(
                        ashet.gui.widgets.ListBox.item_clicked,
                        .{ index, 0, 0, 0 },
                    );
                }
            },

            // Ignore standard mouse events:
            .mouse_button_press => {},
            .mouse_button_release => {},
            .mouse_enter,
            .mouse_leave,
            .mouse_hover,
            .mouse_motion,
            .scroll,
            => {},

            .key_press => switch (event.keyboard.usage) {
                .up_arrow => {
                    if (listbox.selected_index) |index| {
                        std.debug.assert(listbox.item_count > 0);
                        if (index > 0) {
                            try listbox.select_item(index - 1);
                        }
                    } else if (listbox.item_count > 0) {
                        // Default-select the last item when nothing was selected before:
                        try listbox.select_item(listbox.item_count -| 1);
                    }
                },
                .down_arrow => {
                    if (listbox.selected_index) |index| {
                        std.debug.assert(listbox.item_count > 0);
                        if (index < listbox.item_count - 1) {
                            try listbox.select_item(index + 1);
                        }
                    } else if (listbox.item_count > 0) {
                        // Default-select the last item when nothing was selected before:
                        try listbox.select_item(0);
                    }
                },

                else => {},
            },

            .key_release => {},

            .focus_enter, .focus_leave => {},

            // ignored events:
            .resized => {},
            .resize_requested => {},

            .clipboard_copy, .clipboard_cut, .clipboard_paste => {}, // TODO: These should be unreachable

            .drag_enter, .drag_leave, .drag_over, .drag_drop => {}, // TODO: These should be unreachable

            .context_menu_request => {}, // TODO: These should be unreachable

            // Implemented in the wrapper
            .paint, .control, .create, .destroy => unreachable,

            _ => {},
        }
    }

    pub fn paint(listbox: *ListBox, cq: *CommandQueue, size: Size) !void {
        const rect: Rectangle = .new(.zero, size);

        try draw_panel(cq, .{
            .bounds = rect,
            .style = .sunken,
        });

        try cq.fill_rect(
            rect.shrink(2),
            theme.widget_background,
        );

        if (listbox.get_item_callback) |get_item_callback| {
            var item_rect: Rectangle = .{
                .x = 2,
                .y = 2,
                .width = rect.width -| 4,
                .height = 9,
            };

            for (0..listbox.item_count) |index| {
                const selected = (index == listbox.selected_index);

                var item: Item = .{ .text_len = 0, .text_ptr = "" };
                get_item_callback(listbox.get_item_context, index, &item);

                const src_text = item.text_ptr[0..item.text_len];

                const stripped = rstrip(src_text);

                const text_size = try ashet.graphics.measure_text_size(theme.item_font, stripped);

                if (selected) {
                    // TODO: Set proper "selected item" theme color
                    try cq.fill_rect(item_rect, theme.text_color);
                }

                if (stripped.len > 0) {
                    try cq.draw_text(
                        .new(item_rect.left() +| 1, item_rect.top() +| 1),
                        theme.item_font,
                        if (selected) theme.widget_background else theme.text_color,
                        stripped,
                    );
                }

                listbox.item_height = @as(u15, @intCast(text_size.height)) +| 2;

                item_rect.y += @intCast(text_size.height);
                item_rect.y += 2;
                if (item_rect.y >= rect.height)
                    break;
            }
        }
    }
};

pub const PanelStyle = enum { sunken, raised };

pub fn draw_panel(cq: *CommandQueue, opt: struct {
    bounds: Rectangle,
    style: PanelStyle,
}) !void {
    const rect = opt.bounds;
    switch (opt.style) {
        .raised => {
            try cq.draw_line(
                .new(rect.left(), rect.top()),
                .new(rect.right(), rect.top()),
                theme.border_bright,
            );

            try cq.draw_line(
                .new(rect.left(), rect.top()),
                .new(rect.left(), rect.bottom() -| 1),
                theme.border_bright,
            );

            try cq.draw_line(
                .new(rect.left(), rect.bottom()),
                .new(rect.right(), rect.bottom()),
                theme.border_dark,
            );

            try cq.draw_line(
                .new(rect.right(), rect.top() +| 1),
                .new(rect.right(), rect.bottom() -| 1),
                theme.border_dark,
            );

            try cq.draw_rect(
                rect.shrink(1),
                theme.border_normal,
            );
        },

        .sunken => {
            try cq.draw_rect(
                rect,
                theme.border_normal,
            );

            try cq.draw_line(
                .new(rect.left() +| 1, rect.top() +| 1),
                .new(rect.right() -| 2, rect.top() +| 1),
                theme.border_dark,
            );
            try cq.draw_line(
                .new(rect.left() +| 1, rect.top() +| 2),
                .new(rect.left() +| 1, rect.bottom() -| 2),
                theme.border_dark,
            );

            try cq.draw_line(
                .new(rect.right() -| 1, rect.top() +| 1),
                .new(rect.right() -| 1, rect.bottom() -| 2),
                theme.border_bright,
            );

            try cq.draw_line(
                .new(rect.left() +| 1, rect.bottom() -| 1),
                .new(rect.right() -| 1, rect.bottom() -| 1),
                theme.border_bright,
            );
        },
    }
}

// // indicators / passive elements:

// pub const Panel = struct {
//     pub const uuid = UUID.constant("1fa5b237-0bda-48d1-b95a-fcf80616318b");
//     pub const ControlMessage = enum(u32) {};
//     pub const NotifyEvent = enum(u32) {};

//     widget: Widget,
// };

// pub const PictureBox = struct {
//     pub const uuid = UUID.constant("bb33e7a1-74ad-4040-a248-0015ba6b9dac");
//     pub const ControlMessage = enum(u32) {
//         set_image,
//         get_image,
//     };
//     pub const NotifyEvent = enum(u32) {};

//     widget: Widget,
// };

// pub const ProgressBar = struct {
//     pub const uuid = UUID.constant("b96290a9-542f-45f5-9e37-1ce9084fc0e3");
//     pub const ControlMessage = enum(u32) {
//         set_limits,
//         get_limits,

//         set_value,
//         get_value,
//     };

//     pub const NotifyEvent = enum(u32) {};

//     widget: Widget,
// };

// pub const GroupBox = struct {
//     pub const uuid = UUID.constant("b96bc6a2-6df0-4f76-962a-4af18fdf3548");
//     pub const ControlMessage = enum(u32) {
//         set_text,
//         get_text,
//     };

//     pub const NotifyEvent = enum(u32) {};

//     widget: Widget,
// };

// // inputs / active elements:

// pub const TextBox = struct {
//     pub const uuid = UUID.constant("02eddbc3-b882-41e9-8aba-10d12b451e11");
//     pub const ControlMessage = enum(u32) {
//         set_text,
//         get_text,
//         get_length,

//         get_cursor,
//         set_cursor,

//         get_readonly,
//         set_readonly,

//         copy,
//         cut,
//         paste,
//     };

//     pub const NotifyEvent = enum(u32) {
//         text_changed,
//         cursor_position_changed,
//         selection_changed,
//     };

//     widget: Widget,
// };

// pub const MultiLineTextBox = struct {
//     pub const uuid = UUID.constant("84d40a1a-04ab-4e00-ae93-6e91e6b3d10a");
//     pub const ControlMessage = enum(u32) {
//         // TODO:
//     };

//     pub const NotifyEvent = enum(u32) {
//         //
//     };

//     widget: Widget,
// };

// pub const VerticalScrollBar = struct {
//     pub const uuid = UUID.constant("d1c52f74-e9b8-4067-8bb6-fe01c49d97ae");
//     pub const ControlMessage = enum(u32) {
//         set_limits,
//         get_limits,

//         set_position,
//         get_position,
//     };

//     pub const NotifyEvent = enum(u32) {
//         value_changed,
//     };

//     widget: Widget,
// };

// pub const HorizontalScrollBar = struct {
//     pub const uuid = UUID.constant("2899397f-ede2-46e9-8458-1eea29c81fa1");
//     pub const ControlMessage = enum(u32) {
//         set_limits,
//         get_limits,

//         set_position,
//         get_position,
//     };

//     pub const NotifyEvent = enum(u32) {
//         value_changed,
//     };

//     widget: Widget,
// };

// pub const CheckBox = struct {
//     pub const uuid = UUID.constant("051c6bff-d491-4e5a-8b77-6f4244da52ee");
//     pub const ControlMessage = enum(u32) {
//         set_checked,
//         get_checked,
//     };

//     pub const NotifyEvent = enum(u32) {
//         checked_changed,
//     };

//     widget: Widget,
// };

// pub const RadioButton = struct {
//     pub const uuid = UUID.constant("4f18fde6-944c-494f-a55c-ba11f45fcfa3");
//     pub const ControlMessage = enum(u32) {
//         set_checked,
//         get_checked,
//         get_group,
//         set_group,
//     };

//     pub const NotifyEvent = enum(u32) {
//         selected,
//     };

//     widget: Widget,
// };

fn rstrip(text: []const u8) []const u8 {
    return std.mem.trimRight(u8, text, " \r\n\t");
}

const Alignment = enum {
    near,
    middle,
    far,

    fn compute(al: Alignment, aligned_size: u16, available_size: u16) i16 {
        return @intCast(switch (al) {
            .near => 0,
            .middle => (available_size -| aligned_size) / 2,
            .far => available_size -| aligned_size,
        });
    }
};

fn draw_aligned_text(
    cq: *CommandQueue,
    bounds: Rectangle,
    font: ashet.graphics.Font,
    color: ashet.graphics.Color,
    text: []const u8,
    options: struct {
        vertical: Alignment,
        horizontal: Alignment,
    },
) !void {
    const size = try ashet.graphics.measure_text_size(font, text);
    try cq.draw_text(
        .new(
            bounds.x + options.horizontal.compute(size.width, bounds.width),
            bounds.y + options.vertical.compute(size.height, bounds.height),
        ),
        font,
        color,
        text,
    );
}
