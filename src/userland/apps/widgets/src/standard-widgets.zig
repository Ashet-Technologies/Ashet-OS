const std = @import("std");
const ashet = @import("ashet");

const draw_lib = @import("draw.zig");

pub usingnamespace ashet.core;

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

var theme: draw_lib.Theme = undefined;

pub fn main() !void {
    errdefer |err| std.log.err("Failed to setup standard widgets: {s}", .{@errorName(err)});

    theme = .create_default(.{
        .hue = .purple,
        .saturation = 2,
        .value = 4,
        .border = .yellow,
        .menu_font = try ashet.graphics.get_system_font("sans-6"),
        .title_font = try ashet.graphics.get_system_font("sans-6"),
        .widget_font = try ashet.graphics.get_system_font("mono-8"),
    });

    const button_type = try register_widget_type(Button);
    defer button_type.destroy_now();

    const label_type = try register_widget_type(Label);
    defer label_type.destroy_now();

    // TODO: Implement TSR
    while (true) {
        ashet.abi.process.thread.yield();
    }
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

        fn control(wrapper: *Wrapper, message: ashet.gui.WidgetControlMessage) !void {
            // TODO: Implement auto-magic control functions with parameter unwrapping
            try wrapper.impl.control(message);
        }

        fn handle_event(widget_type: WidgetType, widget: Widget, event: *const WidgetEvent) callconv(.c) void {
            _ = widget_type;

            const data_ptr = ashet.abi.gui.get_widget_data(widget) catch |err| {
                std.log.err("failed to fetch widget data: {s}", .{@errorName(err)});
                return;
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

                .control => wrapper.control(event.control) catch |err| {
                    std.log.err("failed to control {s}: {s}", .{ @typeName(WidgetImpl), @errorName(err) });
                },

                else => {
                    if (@hasDecl(WidgetImpl, "handle_event")) {
                        wrapper.impl.handle_event(event.*) catch |err| {
                            std.log.err("failed to handle event {} for {s}: {s}", .{ event.event_type, @typeName(WidgetImpl), @errorName(err) });
                        };
                    } else {
                        // TODO: Implement the other messages
                        std.log.info("{s}.handle_event({}, {}): unhandled event", .{ @typeName(WidgetImpl), widget, event.event_type });
                    }
                },
            }
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

    text: std.ArrayListUnmanaged(u8) = .empty,

    fn init(widget: Widget) Label {
        _ = widget;
        return .{};
    }

    fn deinit(label: *Label) void {
        label.text.deinit(ashet.process.mem.allocator());
        label.* = undefined;
    }

    fn paint(label: *Label, cq: *CommandQueue, size: Size) !void {
        _ = size;

        try cq.clear(theme.window_active.background);
        try cq.draw_text(
            .new(1, 1),
            theme.widget_font,
            theme.text_color,
            label.text.items,
        );
    }

    fn control(label: *Label, msg: ashet.abi.WidgetControlMessage) !void {
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

    text: std.ArrayListUnmanaged(u8) = .empty,

    fn init(widget: Widget) Button {
        _ = widget;
        return .{};
    }

    fn deinit(button: *Button) void {
        button.text.deinit(ashet.process.mem.allocator());
        button.* = undefined;
    }

    fn control(button: *Button, msg: ashet.abi.WidgetControlMessage) !void {
        switch (msg.type) {
            ashet.gui.widgets.Button.set_text => {
                const ptr: [*]const u8 = @ptrFromInt(msg.params[0]);
                const text = ptr[0..msg.params[1]];

                try button.text.ensureTotalCapacity(ashet.process.mem.allocator(), text.len);

                button.text.clearRetainingCapacity();
                button.text.appendSliceAssumeCapacity(text);

                try WidgetWrapper(Button).from_impl(button).invalidate();
            },

            else => return error.UnknownControl,
        }
    }

    fn handle_event(button: *Button, event: ashet.gui.WidgetEvent) !void {
        switch (event.event_type) {
            .click => {
                try ashet.gui.notify_owner(
                    WidgetWrapper(Button).from_impl(button).widget,
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

    fn paint(button: *Button, cq: *CommandQueue, size: Size) !void {
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
            try cq.draw_text(
                .new(rect.left() +| 5, rect.top() +| 4),
                theme.widget_font, // TODO: How to make font customizable?
                theme.text_color,
                text,
            );
        }
    }
};

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
