const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../libashet.zig");
const logger = std.log.scoped(.gui);

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;

// The widget definitions are auto-generated:
pub const widgets = @import("widgets");

pub const UUID = ashet.abi.UUID;

pub const Desktop = ashet.abi.Desktop;
pub const Window = ashet.abi.Window;
pub const Widget = ashet.abi.Widget;
pub const WidgetType = ashet.abi.WidgetType;
pub const WidgetEvent = ashet.abi.WidgetEvent;
pub const WidgetDescriptor = ashet.abi.WidgetDescriptor;
pub const WidgetControlMessage = ashet.abi.WidgetControlMessage;

pub const WindowFlags = ashet.abi.WindowFlags;
pub const KeyboardEvent = ashet.abi.KeyboardEvent;
pub const MouseEvent = ashet.abi.MouseEvent;
pub const WidgetNotifyEvent = ashet.abi.WidgetNotifyEvent;

pub const GetWindowEvent = ashet.abi.gui.GetWindowEvent;

pub fn get_desktop_data(window: Window) error{ InvalidHandle, Unexpected }!*anyopaque {
    return try ashet.abi.gui.get_desktop_data(window);
}

pub fn post_window_event(window: Window, event: ashet.abi.WindowEvent) !void {
    try ashet.abi.gui.post_window_event(window, event);
}

pub const DesktopCreateOptions = ashet.abi.DesktopDescriptor;

pub fn create_desktop(name: []const u8, options: DesktopCreateOptions) !ashet.abi.Desktop {
    return try ashet.abi.gui.create_desktop(name, &options);
}

pub const CreateWindowOptions = struct {
    min_size: ?Size = null,
    max_size: ?Size = null,
    initial_size: Size,
    title: []const u8,
    popup: bool = false,
};

pub fn create_window(desktop: Desktop, options: CreateWindowOptions) !ashet.abi.Window {
    return try ashet.abi.gui.create_window(
        desktop,
        options.title,
        options.min_size orelse options.initial_size,
        options.max_size orelse options.initial_size,
        options.initial_size,
        .{
            .popup = options.popup,
        },
    );
}

pub fn get_window_title(window: Window, buffer: ?[]u8) error{ InvalidHandle, Unexpected }!usize {
    return try ashet.abi.gui.get_window_title(window, buffer);
}

pub fn get_window_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.get_window_size(window);
}

pub fn get_window_min_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.get_window_min_size(window);
}

pub fn get_window_max_size(window: Window) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.get_window_max_size(window);
}

pub fn get_window_flags(window: Window) error{ InvalidHandle, Unexpected }!WindowFlags {
    return try ashet.abi.gui.get_window_flags(window);
}

pub fn set_window_size(window: Window, size: Size) error{ InvalidHandle, Unexpected }!Size {
    return try ashet.abi.gui.set_window_size(window, size);
}

pub fn get_window_event(window: Window) error{ Unexpected, InvalidHandle, SystemResources, Cancelled, InProgress }!WindowEvent {
    const event_res = try ashet.overlapped.performOne(ashet.abi.gui.GetWindowEvent, .{
        .window = window,
    });
    return .from_abi(event_res.event);
}

pub const WindowEvent = union(ashet.abi.WindowEvent.Type) {
    widget_notify: WidgetNotifyEvent,
    key_press: KeyboardEvent,
    key_release: KeyboardEvent,
    mouse_enter: MouseEvent,
    mouse_leave: MouseEvent,
    mouse_motion: MouseEvent,
    mouse_button_press: MouseEvent,
    mouse_button_release: MouseEvent,
    window_close,
    window_minimize,
    window_restore,
    window_moving,
    window_moved,
    window_resizing,
    window_resized,

    pub fn from_abi(event: ashet.abi.WindowEvent) WindowEvent {
        return ashet.utility.wrap_abi_union(WindowEvent, event, .{
            .widget_notify = .widget_notify,
            .key_press = .keyboard,
            .key_release = .keyboard,
            .mouse_enter = .mouse,
            .mouse_leave = .mouse,
            .mouse_motion = .mouse,
            .mouse_button_press = .mouse,
            .mouse_button_release = .mouse,
            .window_close = null,
            .window_minimize = null,
            .window_restore = null,
            .window_moving = null,
            .window_moved = null,
            .window_resizing = null,
            .window_resized = null,
        });
    }
};

pub fn create_widget(window: Window, uuid: *const UUID) !Widget {
    return try ashet.abi.gui.create_widget(window, uuid);
}

pub fn place_widget(widget: Widget, bounds: Rectangle) !Rectangle {
    return try ashet.abi.gui.place_widget(widget, bounds);
}

pub fn get_widget_bounds(widget: Widget) !Rectangle {
    return try ashet.abi.gui.get_widget_bounds(widget);
}

pub const ControlMessage = ashet.abi.gui.WidgetControlID;
pub const NotifyEvent = ashet.abi.gui.WidgetNotifyID;

pub fn control_widget(widget: Widget, control: ControlMessage, params: [4]usize) !usize {
    return try ashet.abi.gui.control_widget(widget, .{
        .event_type = undefined,
        .type = control,
        .params = params,
    });
}

pub fn notify_owner(widget: Widget, notify: NotifyEvent, params: [4]usize) !void {
    return ashet.abi.gui.notify_owner(widget, notify, &params);
}

pub fn register_widget_type(desc: WidgetDescriptor) !WidgetType {
    return try ashet.abi.gui.register_widget_type(&desc);
}

/// Helper function that converts a marshallable type into a `usize`.
///
/// NOTE: Use this to convert NotifyEvent/ControlMessage parameter values to `usize`.
pub fn usize_from_type(comptime T: type, value: T) usize {
    const info = @typeInfo(T);
    switch (info) {
        .@"enum" => return @intFromEnum(value),
        .int => |int| switch (int.signedness) {
            .unsigned => return value,
            .signed => return @bitCast(@as(isize, value)),
        },
        .float => |flt| {
            const ival: std.meta.Int(.unsigned, flt.bits) = @bitCast(value);
            return ival;
        },

        .optional, .pointer => return @intFromPtr(value),

        .bool => return @intFromBool(value),

        else => @compileError(std.fmt.comptimePrint("{} is not a type that can be passed through usize", .{T})),
    }
}

/// Helper function that converts a `usize` into a marshallable type.
///
/// NOTE: Use this to convert NotifyEvent/ControlMessage parameter values from the `usize`.
pub fn type_from_usize(comptime T: type, value: usize) T {
    const info = @typeInfo(T);
    switch (info) {
        .@"enum" => |enumeration| return @enumFromInt(@as(enumeration.tag_type, @truncate(value))),
        .int => |int| switch (int.signedness) {
            .unsigned => return @truncate(value),
            .signed => return @truncate(@as(isize, @bitCast(value))),
        },
        .float => {
            const fcal: std.meta.Float(@bitSizeOf(usize)) = @bitCast(value);
            return @floatCast(fcal);
        },
        .optional, .pointer => return @ptrFromInt(value),

        .bool => return (value != 0),

        else => @compileError(std.fmt.comptimePrint("{} is not a type that can be passed through usize", .{T})),
    }
}

/// The event router is a convenience structure that helps mapping out widgets into a
/// structured, unwrapped definition of events.
pub fn EventRouter(comptime Mapping: type) type {
    var mapped_event_fields: []const std.builtin.Type.UnionField = &.{};

    const mapping_info = @typeInfo(Mapping).@"struct";
    for (mapping_info.fields) |fld| {
        const ptr = @typeInfo(fld.type).pointer;
        std.debug.assert(ptr.size == .one);

        if (@typeInfo(ptr.child) != .@"opaque")
            @compileError("Mapping must be struct of fields to pointers to opaque");
        if (!@hasDecl(ptr.child, "uuid"))
            @compileError("Each widget type requires a .uuid decl in its definition");
        if (!@hasDecl(ptr.child, "Event"))
            @compileError("Each widget type requires a .Event decl in its definition");

        const mapped: std.builtin.Type.UnionField = .{
            .alignment = @alignOf(ptr.child.Event),
            .name = fld.name,
            .type = ptr.child.Event,
        };

        mapped_event_fields = mapped_event_fields ++ &[1]std.builtin.Type.UnionField{mapped};
    }

    const mapped_event_fields_const = mapped_event_fields;

    return struct {
        const Router = @This();

        pub const MappedEvent = @Type(.{
            .@"union" = .{
                .fields = mapped_event_fields_const,
                .layout = .auto,
                .tag_type = std.meta.FieldEnum(Mapping),
                .decls = &.{},
            },
        });

        mapping: Mapping,

        pub fn init(mapping: Mapping) Router {
            return .{ .mapping = mapping };
        }

        pub fn match(router: *const Router, event: *const WidgetNotifyEvent) ?MappedEvent {
            inline for (mapping_info.fields) |fld| {
                const widget = @field(router.mapping, fld.name);
                if (widget.match_event(event)) |widget_event| {
                    return @unionInit(MappedEvent, fld.name, widget_event);
                }
            }
            return null;
        }
    };
}
