const std = @import("std");

/// The offset in memory where an application will be loaded to.
/// The entry point of an application is also at this address,
/// but `libashet` a tiny load stub that jumps to `_start`.
pub const application_load_address = 0x80800000;

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
        return asm (""
            : [ptr] "={tp}" (-> *align(16) SysCallInterface),
        );
    }

    magic: u32 = 0x9a9d5a1b, // chosen by a fair dice roll

    // console: Console,
    video: Video,
    process: Process,
    fs: FileSystem,
    input: Input,

    pub const Console = extern struct {
        clear: fn () callconv(.C) void,
        print: fn ([*]const u8, usize) callconv(.C) void,
        output: fn ([*]const u8, usize) callconv(.C) void,
        setCursor: fn (x: u8, y: u8) callconv(.C) void,
        readLine: fn (params: *ReadLineParams) callconv(.C) ReadLineResult,
    };

    pub const Video = extern struct {
        setMode: fn (VideoMode) callconv(.C) void,
        setBorder: fn (ColorIndex) callconv(.C) void,
        setResolution: fn (u16, u16) callconv(.C) void,
        getVideoMemory: fn () callconv(.C) [*]align(4) ColorIndex,
        getPaletteMemory: fn () callconv(.C) *[palette_size]u16,
    };

    pub const Process = extern struct {
        yield: fn () callconv(.C) void,
        exit: fn (u32) callconv(.C) noreturn,
    };

    pub const FileSystem = extern struct {
        delete: fn (path_ptr: [*]const u8, path_len: usize) callconv(.C) bool,
        mkdir: fn (path_ptr: [*]const u8, path_len: usize) callconv(.C) bool,
        rename: fn (old_path_ptr: [*]const u8, old_path_len: usize, new_path_ptr: [*]const u8, new_path_len: usize) callconv(.C) bool,
        stat: fn (path_ptr: [*]const u8, path_len: usize, *FileInfo) callconv(.C) bool,

        openFile: fn (path_ptr: [*]const u8, path_len: usize, FileAccess, FileMode) callconv(.C) FileHandle,

        read: fn (FileHandle, ptr: [*]u8, len: usize) callconv(.C) usize,
        write: fn (FileHandle, ptr: [*]const u8, len: usize) callconv(.C) usize,

        seekTo: fn (FileHandle, offset: u64) callconv(.C) bool,
        // seekBy: fn (FileHandle, offset: i64) callconv(.C) usize,
        // seekFromEnd: fn (FileHandle, offset: u64) callconv(.C) usize,

        flush: fn (FileHandle) callconv(.C) bool,
        close: fn (FileHandle) callconv(.C) void,

        openDir: fn (path_ptr: [*]const u8, path_len: usize) callconv(.C) DirectoryHandle,
        nextFile: fn (DirectoryHandle, *FileInfo) callconv(.C) bool,
        closeDir: fn (DirectoryHandle) callconv(.C) void,
    };

    pub const Input = extern struct {
        getEvent: fn (*InputEvent) callconv(.C) InputEventType,
        getKeyboardEvent: fn (*KeyboardEvent) callconv(.C) bool,
        getMouseEvent: fn (*MouseEvent) callconv(.C) bool,
    };
};

pub const ExitCode = struct {
    pub const success = @as(u32, 0);
    pub const failure = @as(u32, 1);

    pub const killed = ~@as(u32, 0);
};

pub const ThreadFunction = fn (?*anyopaque) callconv(.C) u32;

pub const VideoMode = enum(u32) {
    text = 0,
    graphics = 1,
};

pub const ColorIndex = u8;

pub const palette_size = std.math.maxInt(ColorIndex) + 1;

/// A 16 bpp color value using RGB565 encoding.
pub const Color = packed struct {
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

pub const FileAttributes = packed struct {
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

pub const KeyboardModifiers = packed struct {
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

pub const CharAttributes = packed struct {
    bg: u4, // lo nibble
    fg: u4, // hi nibble

    pub fn fromByte(val: u8) CharAttributes {
        return @bitCast(CharAttributes, val);
    }

    pub fn toByte(attr: CharAttributes) u8 {
        return @bitCast(u8, attr);
    }
};
