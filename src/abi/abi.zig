const std = @import("std");

/// A structure containing all system calls Ashet OS provides.
///
/// As Ashet OS is single-threaded by design and supports no thread local
/// structures, we use the `tp` register to store a fast-path to the syscall
/// interface.
/// This allows several benefits:
/// - Ashet OS can freely place this structure in RAM or ROM.
/// - A syscall is just an indirect call with the minimum number of only two instructions
pub const SysCallInterface = extern struct {
    pub inline fn get() *align(16) const SysCallInterface {
        const target = @import("builtin").target.cpu.arch;
        return switch (target) {
            .riscv32 => asm (""
                : [ptr] "={tp}" (-> *align(16) SysCallInterface),
            ),
            .x86 => @panic("no syscalls on x86 yet"),
            .arm => @panic("no syscalls on arm yet"),
            else => unreachable,
        };
    }

    magic: u32 = 0x9a9d5a1b, // chosen by a fair dice roll

    video: Video,
    process: Process,
    fs: FileSystem,
    input: Input,
    ui: UserInterface,

    pub const Video = extern struct {
        /// Aquires direct access to the screen. When `true` is returned,
        /// this process has the sole access to the screen buffers.
        aquire: std.meta.FnPtr(fn () callconv(.C) bool),

        /// Releases the access to the video and returns to desktop mode.
        release: std.meta.FnPtr(fn () callconv(.C) void),

        /// Changes the border color of the screen. Parameter is an index into
        /// the palette.
        setBorder: std.meta.FnPtr(fn (ColorIndex) callconv(.C) void),

        /// Sets the screen resolution. Legal values are between 1×1 and 400×300.
        /// Everything out of bounds will be clamped into that range.
        setResolution: std.meta.FnPtr(fn (u16, u16) callconv(.C) void),

        /// Returns a pointer to linear video memory, row-major.
        /// Pixels rows will have a stride of the current video buffer width.
        /// The first pixel in the memory is the top-left pixel.
        getVideoMemory: std.meta.FnPtr(fn () callconv(.C) [*]align(4) ColorIndex),

        /// Returns a pointer to the current palette. Changing this palette
        /// will directly change the associated colors on the screen.
        getPaletteMemory: std.meta.FnPtr(fn () callconv(.C) *[palette_size]u16),
    };

    pub const UserInterface = extern struct {
        createWindow: std.meta.FnPtr(fn (title: [*:0]const u8, min: Size, max: Size, flags: CreateWindowFlags) ?*const Window),
        destroyWindow: std.meta.FnPtr(fn (*const Window) void),
        moveWindow: std.meta.FnPtr(fn (*const Window, x: i16, y: i16) void),
        resizeWindow: std.meta.FnPtr(fn (*const Window, x: u16, y: u16) void),
        setWindowTitle: std.meta.FnPtr(fn (*const Window, title: [*:0]const u8) void),
        getEvent: std.meta.FnPtr(fn (*const Window, *UiEvent) UiEventType),
        invalidate: std.meta.FnPtr(fn (*const Window, rect: Rectangle) void),
    };

    pub const Process = extern struct {
        yield: std.meta.FnPtr(fn () callconv(.C) void),
        exit: std.meta.FnPtr(fn (u32) callconv(.C) noreturn),
    };

    pub const FileSystem = extern struct {
        delete: std.meta.FnPtr(fn (path_ptr: [*]const u8, path_len: usize) callconv(.C) bool),
        mkdir: std.meta.FnPtr(fn (path_ptr: [*]const u8, path_len: usize) callconv(.C) bool),
        rename: std.meta.FnPtr(fn (old_path_ptr: [*]const u8, old_path_len: usize, new_path_ptr: [*]const u8, new_path_len: usize) callconv(.C) bool),
        stat: std.meta.FnPtr(fn (path_ptr: [*]const u8, path_len: usize, *FileInfo) callconv(.C) bool),

        openFile: std.meta.FnPtr(fn (path_ptr: [*]const u8, path_len: usize, FileAccess, FileMode) callconv(.C) FileHandle),

        read: std.meta.FnPtr(fn (FileHandle, ptr: [*]u8, len: usize) callconv(.C) usize),
        write: std.meta.FnPtr(fn (FileHandle, ptr: [*]const u8, len: usize) callconv(.C) usize),

        seekTo: std.meta.FnPtr(fn (FileHandle, offset: u64) callconv(.C) bool),
        // seekBy: fn (FileHandle, offset: i64) callconv(.C) usize,
        // seekFromEnd: fn (FileHandle, offset: u64) callconv(.C) usize,

        flush: std.meta.FnPtr(fn (FileHandle) callconv(.C) bool),
        close: std.meta.FnPtr(fn (FileHandle) callconv(.C) void),

        openDir: std.meta.FnPtr(fn (path_ptr: [*]const u8, path_len: usize) callconv(.C) DirectoryHandle),
        nextFile: std.meta.FnPtr(fn (DirectoryHandle, *FileInfo) callconv(.C) bool),
        closeDir: std.meta.FnPtr(fn (DirectoryHandle) callconv(.C) void),
    };

    pub const Input = extern struct {
        getEvent: std.meta.FnPtr(fn (*InputEvent) callconv(.C) InputEventType),
        getKeyboardEvent: std.meta.FnPtr(fn (*KeyboardEvent) callconv(.C) bool),
        getMouseEvent: std.meta.FnPtr(fn (*MouseEvent) callconv(.C) bool),
    };
};

pub const ExitCode = struct {
    pub const success = @as(u32, 0);
    pub const failure = @as(u32, 1);

    pub const killed = ~@as(u32, 0);
};

pub const ThreadFunction = std.meta.FnPtr(fn (?*anyopaque) callconv(.C) u32);

pub const ColorIndex = enum(u8) {
    _,

    pub fn get(val: u8) ColorIndex {
        return @intToEnum(ColorIndex, val);
    }

    pub fn index(c: ColorIndex) @typeInfo(ColorIndex).Enum.tag_type {
        return @enumToInt(c);
    }
};

pub const palette_size = std.math.maxInt(@typeInfo(ColorIndex).Enum.tag_type) + 1;

/// A 16 bpp color value using RGB565 encoding.
pub const Color = packed struct { //(u16)
    r: u5,
    g: u6,
    b: u5,

    pub fn toU16(c: Color) u16 {
        return @bitCast(u16, c);
    }

    pub fn fromU16(u: u16) Color {
        return @bitCast(Color, u);
    }

    pub fn fromRgb888(r: u8, g: u8, b: u8) Color {
        return Color{
            .r = @truncate(u5, r >> 3),
            .g = @truncate(u6, g >> 2),
            .b = @truncate(u5, b >> 3),
        };
    }

    pub fn toRgb32(color: Color) u32 {
        const src_r: u32 = color.r;
        const src_g: u32 = color.g;
        const src_b: u32 = color.b;

        // expand bits to form a linear range between 0…255
        const exp_r = (src_r << 3) | (src_r >> 2);
        const exp_g = (src_g << 2) | (src_g >> 4);
        const exp_b = (src_b << 3) | (src_b >> 2);

        return exp_r << 0 |
            exp_g << 8 |
            exp_b << 16;
    }
};

pub const max_path = 256;

pub const FileHandle = enum(u32) { invalid, _ };
pub const DirectoryHandle = enum(u32) { invalid, _ };

pub const FileInfo = extern struct {
    name: [max_path]u8,
    size: usize,
    attributes: FileAttributes,
    // WORD	fdate;			/* Modified date */
    // WORD	ftime;			/* Modified time */
    // BYTE	fattrib;		/* File attribute */

    pub fn getName(self: *const FileInfo) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

pub const FileAttributes = packed struct { // (u16)
    directory: bool,
    read_only: bool,
    hidden: bool,
    // system: bool,
    // archive: bool,
    padding0: u5 = 0,
    padding1: u8 = 0,
};

comptime {
    std.debug.assert(@sizeOf(FileAttributes) == 2);
}

pub const FileAccess = enum(u8) {
    read_only = 0,
    write_only = 1,
    read_write = 2,
};

pub const FileMode = enum(u8) {
    open_existing = 0,
    create_new = 1,
    create_always = 2,
    open_always = 3,
    open_append = 4,
};

pub const InputEventType = enum(u8) {
    none = 0,
    mouse = 1,
    keyboard = 2,
};

pub const InputEvent = extern union {
    mouse: MouseEvent,
    keyboard: KeyboardEvent,
};

pub const MouseEvent = extern struct {
    type: Type,
    x: u16,
    y: u16,
    dx: i16,
    dy: i16,
    button: MouseButton,

    pub const Type = enum(u8) {
        motion,
        button_press,
        button_release,
    };
};

pub const KeyboardEvent = extern struct {
    scancode: u32,
    key: KeyCode,
    text: ?[*:0]const u8,
    pressed: bool,
    modifiers: KeyboardModifiers,
};

pub const KeyCode = enum(u16) {
    escape = 1,
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"0",
    minus,
    equal,
    backspace,
    tab,
    q,
    w,
    e,
    r,
    t,
    y,
    u,
    i,
    o,
    p,
    left_brace,
    right_brace,
    @"return",
    ctrl_left,
    a,
    s,
    d,
    f,
    g,
    h,
    j,
    k,
    l,
    semicolon,
    apostrophe,
    grave,
    shift_left,
    backslash,
    z,
    x,
    c,
    v,
    b,
    n,
    m,
    comma,
    dot,
    slash,
    shift_right,
    kp_asterisk,
    alt,
    space,
    caps_lock,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    num_lock,
    scroll_lock,
    kp_7,
    kp_8,
    kp_9,
    kp_minus,
    kp_4,
    kp_5,
    kp_6,
    kp_plus,
    kp_1,
    kp_2,
    kp_3,
    kp_0,
    kp_dot,
    jp_zenkakuhankaku,
    @"102nd",
    f11,
    f12,
    jp_ro,
    jp_katakana,
    jp_hiragana,
    jp_henkan,
    jp_katakana_hiragana,
    jp_muhenkan,
    jp_kp_comma,
    kp_enter,
    ctrl_right,
    kp_slash,
    print,
    alt_graph,
    linefeed,
    home,
    up,
    page_up,
    left,
    right,
    end,
    down,
    page_down,
    insert,
    delete,
    meta,

    unknown = 0xFFFF,
};

pub const MouseButton = enum(u8) {
    none = 0,
    left = 1,
    right = 2,
    middle = 3,
    nav_previous = 4,
    nav_next = 5,
    wheel_down = 6,
    wheel_up = 7,
};

pub const KeyboardModifiers = packed struct { // (u16)
    shift: bool,
    alt: bool,
    ctrl: bool,
    shift_left: bool,
    shift_right: bool,
    ctrl_left: bool,
    ctrl_right: bool,
    alt_graph: bool,
    padding: u8 = 0,
};

comptime {
    if (@sizeOf(KeyboardModifiers) != 2)
        @compileError("KeyboardModifiers must be 2 byte large");
}

pub const ReadLineParams = extern struct {
    buffer: [*]u8,
    buffer_len: usize,

    width: u16,
};

pub const ReadLineResult = enum(u8) {
    ok = 0,
    cancelled = 1,
    failed = 2,
};

/// Computes the character attributes and selects both foreground and background color.
pub fn charAttributes(foreground: u4, background: u4) u8 {
    return (CharAttributes{ .fg = foreground, .bg = background }).toByte();
}

pub const CharAttributes = packed struct { // (u8)
    bg: u4, // lo nibble
    fg: u4, // hi nibble

    pub fn fromByte(val: u8) CharAttributes {
        return @bitCast(CharAttributes, val);
    }

    pub fn toByte(attr: CharAttributes) u8 {
        return @bitCast(u8, attr);
    }
};

pub const Size = extern struct {
    width: u16,
    height: u16,

    pub fn init(w: u16, h: u16) Size {
        return Size{ .width = w, .height = h };
    }
};

pub const Point = extern struct {
    x: i16,
    y: i16,

    pub fn init(x: i16, y: i16) Size {
        return Size{ .x = x, .y = y };
    }
};

pub const Rectangle = extern struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,

    pub fn position(rect: Rectangle) Point {
        return Point{ .x = rect.x, .y = rect.y };
    }

    pub fn size(rect: Rectangle) Size {
        return Point{ .width = rect.width, .height = rect.height };
    }
};

pub const UiEvent = extern union {
    mouse: MouseEvent,
    keyboard: KeyboardEvent,
};

pub const UiEventType = enum(u16) {
    none,
    mouse,

    /// A keyboard event happened while the window had focus.
    keyboard,

    /// The user requested the window to be closed.
    window_close,

    /// The window was minimized and is not visible anymore.
    window_minimize,

    /// The window was restored from minimized state.
    window_restore,

    /// The window was moved on the screen. Query `window.bounds` to get the new position.
    window_moved,

    /// The window size changed. Query `window.bounds` to get the new size.
    window_resized,
};

pub const Window = extern struct {
    /// Pointer to a linear buffer of pixels. These pixels define the content of the window.
    /// The data is layed out row-major, with `stride` bytes between each row.
    pixels: [*]u8,

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
    can_minimize: bool,
    padding: u31 = 0,
};
