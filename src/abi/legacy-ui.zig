pub const UiEvent = extern union {
    mouse: MouseEvent,
    keyboard: KeyboardEvent,
};

pub const UiEventType = enum(u16) {
    mouse,

    /// A keyboard event happened while the window had focus.
    keyboard,

    /// The user requested the window to be closed.
    window_close,

    /// The window was minimized and is not visible anymore.
    window_minimize,

    /// The window was restored from minimized state.
    window_restore,

    /// The window is currently moving on the screen. Query `window.bounds` to get the new position.
    window_moving,

    /// The window was moved on the screen. Query `window.bounds` to get the new position.
    window_moved,

    /// The window size is currently changing. Query `window.bounds` to get the new size.
    window_resizing,

    /// The window size changed. Query `window.bounds` to get the new size.
    window_resized,
};

pub const Window = extern struct {
    /// Pointer to a linear buffer of pixels. These pixels define the content of the window.
    /// The data is layed out row-major, with `stride` bytes between each row.
    pixels: [*]ColorIndex,

    /// The number of bytes in each row in `pixels`.
    stride: u32,

    /// The current position of the window on the screen. Will not contain the decorators, but only
    /// the position of the framebuffer.
    client_rectangle: Rectangle,

    /// The minimum size of this window. The window can never be smaller than this.
    min_size: Size,

    /// The maximum size of this window. The window can never be bigger than this.
    max_size: Size,

    /// A pointer to the NUL terminated window title.
    title: [*:0]const u8,

    /// A collection of informative flags.
    flags: Flags,

    pub const Flags = packed struct(u8) {
        /// The window is currently minimized.
        minimized: bool,

        /// The window currently has keyboard focus.
        focus: bool,

        /// This window is a popup and cannot be minimized
        popup: bool,

        padding: u5 = 0,
    };
};

pub const CreateWindowFlags = packed struct(u32) {
    popup: bool = false,
    padding: u31 = 0,
};

///////////////////////////////////////////////////////////////////////////////

pub const ui = struct {
    const Error = ErrorSet(.{
        .Unexpected = 1,
        .InProgress = 2,
    });

    pub const GetEvent = IOP.define(.{
        .type = .ui_get_event,
        .@"error" = Error,
        .inputs = struct { window: *const Window },
        .outputs = struct {
            event_type: UiEventType,
            event: UiEvent,
        },
    });
};

/// Computes the character attributes and selects both foreground and background color.
pub fn charAttributes(foreground: u4, background: u4) u8 {
    return (CharAttributes{ .fg = foreground, .bg = background }).toByte();
}

pub const CharAttributes = packed struct { // (u8)
    bg: u4, // lo nibble
    fg: u4, // hi nibble

    pub fn fromByte(val: u8) CharAttributes {
        return @as(CharAttributes, @bitCast(val));
    }

    pub fn toByte(attr: CharAttributes) u8 {
        return @as(u8, @bitCast(attr));
    }
};
