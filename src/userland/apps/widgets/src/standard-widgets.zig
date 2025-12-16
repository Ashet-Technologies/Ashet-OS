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

var render_queue: ashet.graphics.CommandQueue = ashet.graphics.CommandQueue.init(ashet.process.mem.allocator()) catch unreachable;

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

    const button_type = try ashet.abi.gui.register_widget_type(&.{
        .uuid = Button.uuid.*,
        .data_size = @sizeOf(Button),
        .flags = .{
            .focusable = true,
            .context_menu = false,
            .hit_test_visible = true,
            .allow_drop = false,
            .clipboard_sensitive = false,
        },
        .handle_event = Button.handle_event,
    });
    defer button_type.destroy_now();

    const label_type = try ashet.abi.gui.register_widget_type(&.{
        .uuid = Label.uuid.*,
        .data_size = @sizeOf(Label),
        .flags = .{
            .focusable = true,
            .context_menu = false,
            .hit_test_visible = true,
            .allow_drop = false,
            .clipboard_sensitive = false,
        },
        .handle_event = Label.handle_event,
    });
    defer label_type.destroy_now();

    // TODO: Implement TSR
    while (true) {
        ashet.abi.process.thread.yield();
    }
}

pub const Label = struct {
    pub const uuid = ashet.gui.widgets.label;
    pub const ControlMessage = enum(u32) {
        set_text,
        set_alignment,
    };

    pub const NotifyEvent = enum(u32) {};

    widget: Widget,

    pub fn handle_event(widget_type: WidgetType, widget: Widget, event: *const WidgetEvent) callconv(.c) void {
        _ = widget_type;

        std.log.info("Label.handle_event({}, {})", .{ widget, event.event_type });
        switch (event.event_type) {
            .create, .paint => {
                const fb = ashet.graphics.create_widget_framebuffer(widget) catch return;
                defer fb.release();

                const size = ashet.graphics.get_framebuffer_size(fb) catch Size.empty;

                std.log.info("Label size: {}", .{size});

                const cq = &render_queue;
                cq.reset();
                cq.clear(.from_gray(0x30)) catch {};
                cq.draw_text(
                    .new(1, 1),
                    theme.widget_font,
                    .black,
                    "Hello, World!",
                ) catch {};

                cq.submit(fb, .{}) catch |err| {
                    std.log.err("failed to draw: {s}", .{@errorName(err)});
                };
            },

            else => {},
        }
    }
};

pub const Button = struct {
    pub const uuid = ashet.gui.widgets.button;
    pub const ControlMessage = enum(u32) {
        set_text,
    };

    pub const NotifyEvent = enum(u32) {
        clicked,
    };

    widget: Widget,

    pub fn handle_event(widget_type: WidgetType, widget: Widget, event: *const WidgetEvent) callconv(.c) void {
        _ = widget_type;
        std.log.info("Button.handle_event({*}, {})", .{ widget, event.event_type });

        switch (event.event_type) {
            .create, .paint => {
                const bounds = ashet.gui.get_widget_bounds(widget) catch return;

                draw(widget, bounds, "Click me", null) catch |err| {
                    std.log.err("failed to draw: {s}", .{@errorName(err)});
                };
            },

            else => {},
        }
    }
    fn draw(widget: Widget, rect: Rectangle, full_text: []const u8, font: ?ashet.graphics.Font) !void {
        const fb = ashet.graphics.create_widget_framebuffer(widget) catch return;
        defer fb.release();

        const cq = &render_queue;
        cq.reset();

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

        const text = rstrip(full_text);
        if (text.len > 0) {
            try cq.draw_text(
                .new(rect.left() +| 5, rect.top() +| 4),
                font orelse theme.widget_font,
                theme.text_color,
                text,
            );
        }

        try cq.submit(fb, .{});
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
