const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi;
const UUID = abi.UUID;
const Widget = abi.Widget;
const WidgetEvent = abi.WidgetEvent;

pub fn main() !void {
    errdefer |err| std.log.err("Failed to setup standard widgets: {s}", .{@errorName(err)});

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
    pub const uuid = UUID.constant("53b8be36-969a-46a3-bdf5-e3d197890219");
    pub const ControlMessage = enum(u32) {
        set_text,
        set_alignment,
    };

    pub const NotifyEvent = enum(u32) {};

    widget: Widget,

    pub fn handle_event(widget: Widget, event: *const WidgetEvent) callconv(.c) void {
        std.log.info("Label.handle_event({*}, {})", .{ widget, event.event_type });
    }
};

pub const Button = struct {
    pub const uuid = UUID.constant("782ccd0e-bae4-4093-93fe-12c1f86ff43c");
    pub const ControlMessage = enum(u32) {
        set_text,
    };

    pub const NotifyEvent = enum(u32) {
        clicked,
    };

    widget: Widget,

    pub fn handle_event(widget: Widget, event: *const WidgetEvent) callconv(.c) void {
        std.log.info("Button.handle_event({*}, {})", .{ widget, event.event_type });
    }
};

// indicators / passive elements:

pub const Panel = struct {
    pub const uuid = UUID.constant("1fa5b237-0bda-48d1-b95a-fcf80616318b");
    pub const ControlMessage = enum(u32) {};
    pub const NotifyEvent = enum(u32) {};

    widget: Widget,
};

pub const PictureBox = struct {
    pub const uuid = UUID.constant("bb33e7a1-74ad-4040-a248-0015ba6b9dac");
    pub const ControlMessage = enum(u32) {
        set_image,
        get_image,
    };
    pub const NotifyEvent = enum(u32) {};

    widget: Widget,
};

pub const ProgressBar = struct {
    pub const uuid = UUID.constant("b96290a9-542f-45f5-9e37-1ce9084fc0e3");
    pub const ControlMessage = enum(u32) {
        set_limits,
        get_limits,

        set_value,
        get_value,
    };

    pub const NotifyEvent = enum(u32) {};

    widget: Widget,
};

pub const GroupBox = struct {
    pub const uuid = UUID.constant("b96bc6a2-6df0-4f76-962a-4af18fdf3548");
    pub const ControlMessage = enum(u32) {
        set_text,
        get_text,
    };

    pub const NotifyEvent = enum(u32) {};

    widget: Widget,
};

// inputs / active elements:

pub const TextBox = struct {
    pub const uuid = UUID.constant("02eddbc3-b882-41e9-8aba-10d12b451e11");
    pub const ControlMessage = enum(u32) {
        set_text,
        get_text,
        get_length,

        get_cursor,
        set_cursor,

        get_readonly,
        set_readonly,

        copy,
        cut,
        paste,
    };

    pub const NotifyEvent = enum(u32) {
        text_changed,
        cursor_position_changed,
        selection_changed,
    };

    widget: Widget,
};

pub const MultiLineTextBox = struct {
    pub const uuid = UUID.constant("84d40a1a-04ab-4e00-ae93-6e91e6b3d10a");
    pub const ControlMessage = enum(u32) {
        // TODO:
    };

    pub const NotifyEvent = enum(u32) {
        //
    };

    widget: Widget,
};

pub const VerticalScrollBar = struct {
    pub const uuid = UUID.constant("d1c52f74-e9b8-4067-8bb6-fe01c49d97ae");
    pub const ControlMessage = enum(u32) {
        set_limits,
        get_limits,

        set_position,
        get_position,
    };

    pub const NotifyEvent = enum(u32) {
        value_changed,
    };

    widget: Widget,
};

pub const HorizontalScrollBar = struct {
    pub const uuid = UUID.constant("2899397f-ede2-46e9-8458-1eea29c81fa1");
    pub const ControlMessage = enum(u32) {
        set_limits,
        get_limits,

        set_position,
        get_position,
    };

    pub const NotifyEvent = enum(u32) {
        value_changed,
    };

    widget: Widget,
};

pub const CheckBox = struct {
    pub const uuid = UUID.constant("051c6bff-d491-4e5a-8b77-6f4244da52ee");
    pub const ControlMessage = enum(u32) {
        set_checked,
        get_checked,
    };

    pub const NotifyEvent = enum(u32) {
        checked_changed,
    };

    widget: Widget,
};

pub const RadioButton = struct {
    pub const uuid = UUID.constant("4f18fde6-944c-494f-a55c-ba11f45fcfa3");
    pub const ControlMessage = enum(u32) {
        set_checked,
        get_checked,
        get_group,
        set_group,
    };

    pub const NotifyEvent = enum(u32) {
        selected,
    };

    widget: Widget,
};
