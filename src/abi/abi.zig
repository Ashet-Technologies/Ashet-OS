const std = @import("std");

/// defines the syscall interface
pub const system_magic: usize = 0x9a9d5a1b; // chosen by a fair dice roll

pub const syscall_definitions = [_]SysCallDefinition{
    defineSysCall("process.yield", fn () void, 0),
    defineSysCall("process.exit", fn (u32) noreturn, 1),
    defineSysCall("process.getBaseAddress", fn () usize, 2),
    defineSysCall("process.breakpoint", fn () void, 3),

    defineSysCall("time.nanoTimestamp", fn () i128, 4),

    // Aquires direct access to the screen. When `true` is returned,
    // this process has the sole access to the screen buffers.
    defineSysCall("video.acquire", fn () bool, 5),

    // Releases the access to the video and returns to desktop mode.
    defineSysCall("video.release", fn () void, 6),

    // Changes the border color of the screen. Parameter is an index into
    // the palette.
    defineSysCall("video.setBorder", fn (ColorIndex) void, 7),

    // Sets the screen resolution. Legal values are between 1×1 and 400×300.
    // Everything out of bounds will be clamped into that range.
    defineSysCall("video.setResolution", fn (u16, u16) void, 8),

    // Returns a pointer to linear video memory, row-major.
    // Pixels rows will have a stride of the current video buffer width.
    // The first pixel in the memory is the top-left pixel.
    defineSysCall("video.getVideoMemory", fn () [*]align(4) ColorIndex, 9),

    // Returns a pointer to the current palette. Changing this palette
    // will directly change the associated colors on the screen.
    defineSysCall("video.getPaletteMemory", fn () *[palette_size]Color, 10),

    defineSysCall("ui.createWindow", fn (title: [*]const u8, title_len: usize, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) ?*const Window, 14),
    defineSysCall("ui.destroyWindow", fn (*const Window) void, 15),
    defineSysCall("ui.moveWindow", fn (*const Window, x: i16, y: i16) void, 16),
    defineSysCall("ui.resizeWindow", fn (*const Window, x: u16, y: u16) void, 17),
    defineSysCall("ui.setWindowTitle", fn (*const Window, title: [*]const u8, title_len: usize) void, 18),
    defineSysCall("ui.invalidate", fn (*const Window, rect: Rectangle) void, 20),

    defineSysCall("fs.delete", fn (path_ptr: [*]const u8, path_len: usize) FileSystemError.Enum, 21),
    defineSysCall("fs.mkdir", fn (path_ptr: [*]const u8, path_len: usize) FileSystemError.Enum, 22),
    defineSysCall("fs.rename", fn (old_path_ptr: [*]const u8, old_path_len: usize, new_path_ptr: [*]const u8, new_path_len: usize) callconv(.C) FileSystemError.Enum, 23),
    defineSysCall("fs.stat", fn (path_ptr: [*]const u8, path_len: usize, *FileInfo) FileSystemError.Enum, 24),

    defineSysCall("fs.openFile", fn (path_ptr: [*]const u8, path_len: usize, FileAccess, FileMode, out: *FileHandle) FileOpenError.Enum, 25),

    defineSysCall("fs.read", fn (FileHandle, ptr: [*]u8, len: usize, out: *usize) FileReadError.Enum, 26),
    defineSysCall("fs.write", fn (FileHandle, ptr: [*]const u8, len: usize, out: *usize) FileWriteError.Enum, 27),

    defineSysCall("fs.seekTo", fn (FileHandle, offset: u64) FileSeekError.Enum, 28),
    // seekBy: fn (FileHandle, offset: i64)  usize,
    // seekFromEnd: fn (FileHandle, offset: u64)  usize,

    defineSysCall("fs.flush", fn (FileHandle) FileWriteError.Enum, 29),
    defineSysCall("fs.close", fn (FileHandle) void, 30),

    defineSysCall("fs.openDir", fn (path_ptr: [*]const u8, path_len: usize, out: *DirectoryHandle) DirOpenError.Enum, 31),
    defineSysCall("fs.nextFile", fn (DirectoryHandle, *FileInfo, eof: *bool) DirNextError.Enum, 32),
    defineSysCall("fs.closeDir", fn (DirectoryHandle) void, 33),

    // resolves the dns entry `host` for the given `service`.
    // - `host` is a legal dns entry
    // - `port` is either a port number
    // - `buffer` and `limit` define a structure where all resolved IPs can be stored.
    // Function returns the number of host entries found or 0 if the host name could not be resolved.
    // defineSysCall("network.dns.resolve", fn (host: [*:0]const u8, port: u16, buffer: [*]EndPoint, limit: usize) usize, 34),

    // getStatus: FnPtr(fn () NetworkStatus),
    // ping: FnPtr(fn ([*]Ping, usize) void),
    // TODO: Implement NIC-specific queries (mac, ips, names, ...)

    defineSysCall("network.udp.createSocket", fn (result: *UdpSocket) udp.CreateError.Enum, 35),
    defineSysCall("network.udp.destroySocket", fn (UdpSocket) void, 36),

    defineSysCall("network.tcp.createSocket", fn (out: *tcp.Socket) tcp.CreateError.Enum, 44),
    defineSysCall("network.tcp.destroySocket", fn (tcp.Socket) void, 45),

    // Starts new I/O operations and returns completed ones.
    //
    // If `start_queue` is given, the kernel will schedule the events in the kernel.
    // All events in this queue must not be freed until they are returned by this function
    // at a later point.
    //
    // The function will optionally block based on the `wait` parameter.
    //
    // The return value is the HEAD element of a linked list of completed I/O events.
    defineSysCall("io.scheduleAndAwait", fn (?*IOP, WaitIO) ?*IOP, 50),

    defineSysCall("io.cancel", fn (*IOP) void, 51),
};

const SysCallDefinition = struct {
    name: []const u8,
    signature: type,
    index: u32,
};

fn defineSysCall(comptime name: []const u8, comptime Func: type, comptime index: u32) SysCallDefinition {
    var ti = @typeInfo(Func);
    ti.Fn.calling_convention = .C;
    const T2 = @Type(ti);

    return SysCallDefinition{
        .name = name,
        .signature = std.meta.FnPtr(T2),
        .index = index,
    };
}

fn SysCallFunc(comptime call: SysCall) type {
    for (syscall_definitions) |def| {
        if (def.index == @enumToInt(call))
            return def.signature;
    }
    unreachable;
}

pub fn syscall(comptime name: []const u8) SysCallFunc(@field(SysCall, name)) {
    const target = @import("builtin").target.cpu.arch;
    const table = switch (target) {
        .riscv32 => asm (""
            : [ptr] "={tp}" (-> *const SysCallTable),
        ),
        .x86 => @panic("no syscalls on x86 yet"),
        .arm => @panic("no syscalls on arm yet"),
        else => unreachable,
    };
    return @field(table, name);
}

pub const SysCall: type = blk: {
    var fields: []const std.builtin.Type.EnumField = &.{};
    for (syscall_definitions) |def| {
        const field = std.builtin.Type.EnumField{
            .name = def.name,
            .value = def.index,
        };
        fields = fields ++ [1]std.builtin.Type.EnumField{field};
    }

    break :blk @Type(.{
        .Enum = .{
            .layout = .Auto,
            .decls = &.{},
            .fields = fields,
            .tag_type = u32,
            .is_exhaustive = false,
        },
    });
};

pub const SysCallTable: type = blk: {
    @setEvalBranchQuota(100_000);

    var fields: []const std.builtin.Type.StructField = &.{};

    const default_padding: usize = 0;
    const padding_field = std.builtin.Type.StructField{
        .name = undefined,
        .field_type = usize,
        .default_value = &default_padding,
        .is_comptime = false,
        .alignment = @alignOf(usize),
    };

    const magic_number_value: usize = system_magic;
    const magic_number_field = std.builtin.Type.StructField{
        .name = "magic_number",
        .field_type = usize,
        .default_value = &magic_number_value,
        .is_comptime = false,
        .alignment = @alignOf(usize),
    };
    fields = fields ++ [1]std.builtin.Type.StructField{magic_number_field};

    var used_slots = [1]?[]const u8{null} ** syscall_table_size;

    var index: usize = 0;
    var offset: usize = 0;
    while (index < syscall_definitions.len) : (index += 1) {
        const def = syscall_definitions[index];

        if (used_slots[def.index]) |other| {
            @compileError(std.fmt.comptimePrint("The syscall {s} uses slot {}, which is already occupied by syscall {s}.", .{
                def.name,
                def.index,
                other,
            }));
        }
        used_slots[def.index] = def.name;

        std.debug.assert(def.index >= offset);

        while (offset < def.index) : (offset += 1) {
            var clone = padding_field;
            clone.name = std.fmt.comptimePrint("padding{d}", .{offset});
            fields = fields ++ [1]std.builtin.Type.StructField{clone};
        }

        const field = std.builtin.Type.StructField{
            .name = def.name,
            .field_type = def.signature,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(usize),
        };
        fields = fields ++ [1]std.builtin.Type.StructField{field};
        offset += 1;
    }

    if (fields.len != syscall_table_size)
        @compileError("Mismatch in table size vs. index");

    break :blk @Type(.{
        .Struct = .{
            .layout = .Extern,
            .backing_integer = null,
            .fields = fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
};

/// The total size of the syscall table. Each entry is one `usize` large.
pub const syscall_table_size: u32 = blk: {
    var limit: u32 = 0;
    for (syscall_definitions) |def| {
        if (def.index > limit)
            limit = def.index;
    }
    break :blk limit + 2; // off-by-one + magic number
};

pub const NetworkStatus = enum(u8) {
    disconnected = 0, // no cable is plugged in
    mac_available = 1, // cable is plugged in and connected, no DHCP or static IP performed yet
    ip_available = 2, // interface got at least one IP assigned
    gateway_available = 3, // the gateway, if any, is reachable
};

pub const MAC = [6]u8;

pub const IP_Type = enum(u8) { ipv4, ipv6 };

pub const IP = extern struct {
    type: IP_Type,
    addr: extern union {
        v4: IPv4,
        v6: IPv6,
    },

    pub fn ipv4(addr: [4]u8) IP {
        return IP{ .type = .ipv4, .addr = .{ .v4 = .{ .addr = addr } } };
    }

    pub fn ipv6(addr: [16]u8, zone: u8) IP {
        return IP{ .type = .ipv6, .addr = .{ .v6 = .{ .addr = addr, .zone = zone } } };
    }

    pub fn format(ip: IP, comptime fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        switch (ip.type) {
            .ipv4 => try ip.addr.v4.format(fmt, opt, writer),
            .ipv6 => try ip.addr.v6.format(fmt, opt, writer),
        }
    }
};

pub const IPv4 = extern struct {
    addr: [4]u8 align(4),

    pub fn format(ip: IPv4, comptime fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opt;
        try writer.print("{}.{}.{}.{}", .{
            ip.addr[0],
            ip.addr[1],
            ip.addr[2],
            ip.addr[3],
        });
    }
};

pub const IPv6 = extern struct {
    addr: [16]u8 align(4),
    zone: u8,

    pub fn format(ip: IPv6, comptime fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opt;
        try writer.print("[{X:0>2}{X:0>2}:{X:0>2}{X:0>2}:{X:0>2}{X:0>2}:{X:0>2}{X:0>2}:{X:0>2}{X:0>2}:{X:0>2}{X:0>2}:{X:0>2}{X:0>2}:{X:0>2}{X:0>2}/{}]", .{
            ip.addr[0],
            ip.addr[1],
            ip.addr[2],
            ip.addr[3],
            ip.addr[4],
            ip.addr[5],
            ip.addr[6],
            ip.addr[7],
            ip.addr[8],
            ip.addr[9],
            ip.addr[10],
            ip.addr[11],
            ip.addr[12],
            ip.addr[13],
            ip.addr[14],
            ip.addr[15],
            ip.zone,
        });
    }
};

pub const EndPoint = extern struct {
    ip: IP,
    port: u16,

    pub fn new(ip: IP, port: u16) EndPoint {
        return EndPoint{ .ip = ip, .port = port };
    }
};

pub const Ping = extern struct {
    destination: IP, // who to ping
    ttl: u16, // hops
    timeout: u16, // ms, a minute timeout for ping is enough. if you have a higher ping, you have other problems
    response: u16 = undefined, // response time in ms
};

pub const TcpSocket = enum(u32) { invalid = std.math.maxInt(u32), _ };
pub const UdpSocket = enum(u32) { invalid = std.math.maxInt(u32), _ };

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

    pub fn shift(c: ColorIndex, offset: u8) ColorIndex {
        return get(index(c) +% offset);
    }
};

pub const palette_size = std.math.maxInt(@typeInfo(ColorIndex).Enum.tag_type) + 1;

/// A 16 bpp color value using RGB565 encoding.
pub const Color = packed struct(u16) {
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
    size: u64,
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
    mouse = 1,
    keyboard = 2,
};

pub const InputEvent = extern union {
    mouse: MouseEvent,
    keyboard: KeyboardEvent,
};

pub const MouseEvent = extern struct {
    type: Type,
    x: i16,
    y: i16,
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
    /// The raw scancode for the key. Meaning depends on the layout,
    /// represents kinda the physical position on the keyboard.
    scancode: u32,

    /// The virtual key, independent of layout. Represents the logical
    /// function of the key.
    key: KeyCode,

    /// If set, the pressed key combination has a mapping that produces
    /// text input. UTF-8 encoded.
    text: ?[*:0]const u8,

    /// The key in this event was pressed or released
    pressed: bool,

    /// The modifier keys currently active
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

// pub const ReadLineParams = extern struct {
//     buffer: [*]u8,
//     buffer_len: usize,

//     width: u16,
// };

// pub const ReadLineResult = enum(u8) {
//     ok = 0,
//     cancelled = 1,
//     failed = 2,
// };

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

pub const Point = extern struct {
    x: i16,
    y: i16,

    pub fn new(x: i16, y: i16) Point {
        return Point{ .x = x, .y = y };
    }

    pub fn eql(a: Point, b: Point) bool {
        return (a.x == b.x) and (a.y == b.y);
    }

    pub fn manhattenDistance(a: Point, b: Point) u16 {
        return std.math.absCast(a.x - b.x) + std.math.absCast(a.y - b.y);
    }
};

pub const Size = extern struct {
    width: u16,
    height: u16,

    pub fn new(w: u16, h: u16) Size {
        return Size{ .width = w, .height = h };
    }

    pub fn eql(a: Size, b: Size) bool {
        return (a.width == b.width) and (a.height == b.height);
    }
};

pub const Rectangle = extern struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,

    pub fn new(pos: Point, siz: Size) Rectangle {
        return Rectangle{
            .x = pos.x,
            .y = pos.y,
            .width = siz.width,
            .height = siz.height,
        };
    }

    pub fn position(rect: Rectangle) Point {
        return Point{ .x = rect.x, .y = rect.y };
    }

    pub fn size(rect: Rectangle) Size {
        return Size{ .width = rect.width, .height = rect.height };
    }

    pub fn empty(rect: Rectangle) bool {
        return (rect.width == 0) and (rect.height == 0);
    }

    pub fn contains(rect: Rectangle, pt: Point) bool {
        return (pt.x >= rect.x) and
            (pt.x < rect.x + @intCast(u15, rect.width)) and
            (pt.y >= rect.y) and
            (pt.y < rect.y + @intCast(u15, rect.height));
    }

    pub fn containsRectangle(boundary: Rectangle, region: Rectangle) bool {
        return boundary.contains(region.position()) and
            boundary.contains(Point.new(region.x + @intCast(u15, region.width) - 1, region.y + @intCast(u15, region.height) - 1));
    }

    pub fn eql(a: Rectangle, b: Rectangle) bool {
        return a.size().eql(b.size()) and a.position().eql(b.position());
    }

    pub fn top(rect: Rectangle) i16 {
        return rect.y;
    }
    pub fn bottom(rect: Rectangle) i16 {
        return rect.y + @intCast(u15, rect.height);
    }
    pub fn left(rect: Rectangle) i16 {
        return rect.x;
    }
    pub fn right(rect: Rectangle) i16 {
        return rect.x + @intCast(u15, rect.width);
    }

    pub fn shrink(rect: Rectangle, amount: u15) Rectangle {
        var copy = rect;
        copy.x += amount;
        copy.y += amount;
        copy.width -|= 2 * amount;
        copy.height -|= 2 * amount;
        return copy;
    }
};

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

// Auxiliary helpers

const ErrorSetTag = opaque {};

pub fn ErrorSet(comptime options: anytype) type {
    const Int = u32;

    comptime var error_fields: []const std.builtin.Type.Error = &.{};
    inline for (@typeInfo(@TypeOf(options)).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, "ok"))
            @compileError("ErrorSet items cannot be called \"ok\"!");
        error_fields = error_fields ++ [1]std.builtin.Type.Error{
            .{ .name = field.name },
        };
    }

    const error_type = @Type(std.builtin.Type{
        .ErrorSet = error_fields,
    });

    comptime var enum_items: []const std.builtin.Type.EnumField = &.{};
    inline for (@typeInfo(@TypeOf(options)).Struct.fields) |field| {
        const value: Int = @field(options, field.name);
        if (value == 0)
            @compileError("ErrorSet items cannot have the reserved value 0!");
        enum_items = enum_items ++ [1]std.builtin.Type.EnumField{
            .{ .name = field.name, .value = value },
        };
    }

    enum_items = enum_items ++ [1]std.builtin.Type.EnumField{
        .{ .name = "ok", .value = 0 },
    };

    const enum_type = @Type(std.builtin.Type{
        .Enum = .{
            .layout = .Auto,
            .tag_type = Int,
            .fields = enum_items,
            .decls = &.{},
            .is_exhaustive = false, // this is important so the value passed is actually just a bare integer with all values legal
        },
    });

    comptime var error_list: []const error_type = &.{};
    comptime var enum_list: []const enum_type = &.{};
    inline for (@typeInfo(@TypeOf(options)).Struct.fields) |field| {
        error_list = error_list ++ [1]error_type{@field(error_type, field.name)};
        enum_list = enum_list ++ [1]enum_type{@field(enum_type, field.name)};
    }

    return struct {
        const error_set_marker = ErrorSetTag;

        pub const Error = error_type;
        pub const Enum = enum_type;

        pub fn throw(val: Enum) (error{Unexpected} || Error)!void {
            if (val == .ok)
                return; // 0 is the success code
            for (enum_list) |match, index| {
                if (match == val)
                    return error_list[index];
            }
            return error.Unexpected;
        }

        pub fn map(err_union: Error!void) Enum {
            if (err_union) |_| {
                return .ok;
            } else |err| {
                for (error_list) |match, index| {
                    if (match == err)
                        return enum_list[index];
                }
                unreachable;
            }
        }
    };
}

pub const FileSystemError = ErrorSet(.{
    .Denied = 1,
    .DiskErr = 2,
    .Exist = 3,
    .IntErr = 4,
    .InvalidDrive = 5,
    .InvalidName = 6,
    .InvalidObject = 7,
    .InvalidParameter = 8,
    .Locked = 9,
    .MkfsAborted = 10,
    .NoFile = 11,
    .NoFilesystem = 12,
    .NoPath = 13,
    .NotEnabled = 14,
    .NotEnoughCore = 15,
    .NotReady = 16,
    .Overflow = 17,
    .Timeout = 18,
    .TooManyOpenFiles = 19,
    .WriteProtected = 20,
    .InvalidFileHandle = 21,
    .InvalidDevice = 22,
    .PathTooLong = 23,
});

pub const FileOpenError = ErrorSet(.{
    .Denied = 1,
    .DiskErr = 2,
    .Exist = 3,
    .IntErr = 4,
    .InvalidDrive = 5,
    .InvalidName = 6,
    .InvalidObject = 7,
    .InvalidParameter = 8,
    .Locked = 9,
    .MkfsAborted = 10,
    .NoFile = 11,
    .NoFilesystem = 12,
    .NoPath = 13,
    .NotEnabled = 14,
    .NotEnoughCore = 15,
    .NotReady = 16,
    .Overflow = 17,
    .Timeout = 18,
    .TooManyOpenFiles = 19,
    .WriteProtected = 20,
    .InvalidFileHandle = 21,
    .InvalidDevice = 22,
    .PathTooLong = 23,
    .SystemFdQuotaExceeded = 24,
});

pub const FileReadError = ErrorSet(.{
    .Denied = 1,
    .DiskErr = 2,
    .Exist = 3,
    .IntErr = 4,
    .InvalidDrive = 5,
    .InvalidName = 6,
    .InvalidObject = 7,
    .InvalidParameter = 8,
    .Locked = 9,
    .MkfsAborted = 10,
    .NoFile = 11,
    .NoFilesystem = 12,
    .NoPath = 13,
    .NotEnabled = 14,
    .NotEnoughCore = 15,
    .NotReady = 16,
    .Overflow = 17,
    .Timeout = 18,
    .TooManyOpenFiles = 19,
    .WriteProtected = 20,
    .InvalidFileHandle = 21,
    .InvalidDevice = 22,
    .PathTooLong = 23,
});

pub const FileWriteError = ErrorSet(.{
    .Denied = 1,
    .DiskErr = 2,
    .Exist = 3,
    .IntErr = 4,
    .InvalidDrive = 5,
    .InvalidName = 6,
    .InvalidObject = 7,
    .InvalidParameter = 8,
    .Locked = 9,
    .MkfsAborted = 10,
    .NoFile = 11,
    .NoFilesystem = 12,
    .NoPath = 13,
    .NotEnabled = 14,
    .NotEnoughCore = 15,
    .NotReady = 16,
    .Overflow = 17,
    .Timeout = 18,
    .TooManyOpenFiles = 19,
    .WriteProtected = 20,
    .InvalidFileHandle = 21,
    .InvalidDevice = 22,
    .PathTooLong = 23,
});

pub const FileSeekError = ErrorSet(.{
    .Denied = 1,
    .DiskErr = 2,
    .Exist = 3,
    .IntErr = 4,
    .InvalidDrive = 5,
    .InvalidName = 6,
    .InvalidObject = 7,
    .InvalidParameter = 8,
    .Locked = 9,
    .MkfsAborted = 10,
    .NoFile = 11,
    .NoFilesystem = 12,
    .NoPath = 13,
    .NotEnabled = 14,
    .NotEnoughCore = 15,
    .NotReady = 16,
    .Overflow = 17,
    .Timeout = 18,
    .TooManyOpenFiles = 19,
    .WriteProtected = 20,
    .InvalidFileHandle = 21,
    .InvalidDevice = 22,
    .PathTooLong = 23,
    .OutOfBounds = 24,
});

pub const DirOpenError = ErrorSet(.{
    .SystemFdQuotaExceeded = 1,
    .InvalidDevice = 2,
    .PathTooLong = 3,
    .Denied = 4,
    .DiskErr = 5,
    .Exist = 6,
    .IntErr = 7,
    .InvalidDrive = 8,
    .InvalidName = 9,
    .InvalidObject = 10,
    .InvalidParameter = 11,
    .Locked = 12,
    .MkfsAborted = 13,
    .NoFile = 14,
    .NoFilesystem = 15,
    .NoPath = 16,
    .NotEnabled = 17,
    .NotEnoughCore = 18,
    .NotReady = 19,
    .Timeout = 20,
    .TooManyOpenFiles = 21,
    .WriteProtected = 22,
});

pub const DirNextError = ErrorSet(.{
    .InvalidFileHandle = 1,
    .Denied = 2,
    .DiskErr = 3,
    .Exist = 4,
    .IntErr = 5,
    .InvalidDrive = 6,
    .InvalidName = 7,
    .InvalidObject = 8,
    .InvalidParameter = 9,
    .Locked = 10,
    .MkfsAborted = 11,
    .NoFile = 12,
    .NoFilesystem = 13,
    .NoPath = 14,
    .NotEnabled = 15,
    .NotEnoughCore = 16,
    .NotReady = 17,
    .Timeout = 18,
    .TooManyOpenFiles = 19,
    .WriteProtected = 20,
});

///////////////////////////////////////////////////////////////////////////////

// I/O Operation
pub const IOP = extern struct {
    type: Type,
    next: ?*IOP,
    tag: usize, // user specified data

    kernel_data: [7]usize = undefined, // internal data used by the kernel to store

    pub const Type = enum(u32) {
        // TCP IOPs:
        tcp_connect,
        tcp_bind,
        tcp_send,
        tcp_receive,

        // UDP IOPs:
        udp_bind,
        udp_connect,
        udp_disconnect,
        udp_send,
        udp_send_to,
        udp_receive_from,

        // Input IOPS:
        input_get_event,

        // UI IOPS:
        ui_get_event,
    };

    pub const Definition = struct {
        type: Type,
        @"error": type,
        outputs: type = struct {},
        inputs: type = struct {},
    };

    pub fn define(comptime def: Definition) type {
        if (!@hasDecl(def.@"error", "error_set_marker") or (def.@"error".error_set_marker != ErrorSetTag)) {
            @compileError("IOP.define expects .error to be a type created by ErrorSet()!");
        }

        const inputs = @typeInfo(def.inputs).Struct.fields;
        const outputs = @typeInfo(def.outputs).Struct.fields;

        const inputs_augmented = @Type(.{
            .Struct = .{
                .layout = .Extern,
                .fields = inputs,
                .decls = &.{},
                .is_tuple = false,
            },
        });

        var output_fields = outputs[0..outputs.len].*;

        for (output_fields) |*fld| {
            if (fld.default_value != null) {
                @compileError(std.fmt.comptimePrint("IOP outputs are not allowed to have default values. {s}/{s} has one.", .{
                    @tagName(def.type),
                    fld.name,
                }));
            }
            fld.default_value = undefinedDefaultFor(fld.field_type);
        }

        const outputs_augmented = @Type(.{
            .Struct = .{
                .layout = .Extern,
                .fields = &output_fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });

        return extern struct {
            const Self = @This();

            /// Marker used to recognize types as I/O ops.
            /// This marker cannot be accessed outside this file, so *all* IOPs must be
            /// defined in this file.
            /// This allows a certain safety against programming mistakes, as a foreign type cannot be accidently marked as an IOP.
            const iop_marker = IOP_Tag;

            pub const iop_type = def.type;

            pub const Inputs = inputs_augmented;
            pub const Outputs = outputs_augmented;
            pub const ErrorSet = def.@"error";
            pub const Error = Self.ErrorSet.Error;

            iop: IOP = .{
                .type = def.type,
                .next = null,
                .tag = 0,
                .kernel_data = undefined,
            },
            @"error": Self.ErrorSet.Enum = undefined,
            inputs: Inputs,
            outputs: Outputs = undefined,

            pub fn new(inputs_: Inputs) Self {
                return Self{ .inputs = inputs_ };
            }

            pub fn check(val: Self) Error!void {
                return Self.ErrorSet.throw(val.@"error");
            }

            pub fn setOk(val: *Self) void {
                val.@"error" = .ok;
            }

            pub fn setError(val: *Self, err: Error) void {
                val.@"error" = Self.ErrorSet.map(err);
            }
        };
    }

    const IOP_Tag = opaque {};
    pub fn isIOP(comptime T: type) bool {
        return @hasDecl(T, "iop_marker") and (T.iop_marker == IOP_Tag);
    }

    pub fn cast(comptime T: type, iop: *IOP) *T {
        if (comptime !isIOP(T)) @compileError("Only a type created by IOP.define can be passed to cast!");
        std.debug.assert(iop.type == T.iop_type);
        return @fieldParentPtr(T, "iop", iop);
    }

    fn undefinedDefaultFor(comptime T: type) *T {
        comptime var value: T = undefined;
        return &value;
    }
};

pub const WaitIO = enum(u32) {
    /// Don't wait for any I/O to complete.
    dont_block,

    /// Wait for at least one I/O to complete operation.
    wait_one,

    /// Wait until all scheduled I/O operations have completed.
    wait_all,
};

pub const udp = struct {
    const Socket = UdpSocket;

    pub const Bind = IOP.define(.{
        .type = .udp_bind,
        .@"error" = BindError,
        .inputs = struct {
            socket: UdpSocket,
            bind_point: EndPoint,
        },
        .outputs = struct {
            bind_point: EndPoint,
        },
    });

    pub const Connect = IOP.define(.{
        .type = .udp_connect,
        .@"error" = ConnectError,
        .inputs = struct {
            socket: UdpSocket,
            target: EndPoint,
        },
    });

    pub const Disconnect = IOP.define(.{
        .type = .udp_disconnect,
        .@"error" = DisconnectError,
        .inputs = struct {
            socket: UdpSocket,
        },
    });

    pub const Send = IOP.define(.{
        .type = .udp_send,
        .@"error" = SendError,
        .inputs = struct {
            socket: UdpSocket,
            data_ptr: [*]const u8,
            data_len: usize,
        },
        .outputs = struct {
            bytes_sent: usize,
        },
    });

    pub const SendTo = IOP.define(.{
        .type = .udp_send_to,
        .@"error" = SendError,
        .inputs = struct {
            socket: UdpSocket,
            receiver: EndPoint,
            data_ptr: [*]const u8,
            data_len: usize,
        },
        .outputs = struct {
            bytes_sent: usize,
        },
    });

    pub const ReceiveFrom = IOP.define(.{
        .type = .udp_receive_from,
        .@"error" = ReceiveFromError,
        .inputs = struct {
            socket: UdpSocket,
            buffer_ptr: [*]u8,
            buffer_len: usize,
        },
        .outputs = struct {
            bytes_received: usize,
            sender: EndPoint,
        },
    });

    pub const CreateError = ErrorSet(.{
        .SystemResources = 1,
    });

    pub const BindError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .AddressInUse = 3,
        .IllegalValue = 4,
        .Unexpected = 5,
    });

    pub const ConnectError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .AlreadyConnected = 4,
        .AlreadyConnecting = 5,
        .BufferError = 6,
        .IllegalArgument = 10,
        .IllegalValue = 11,
        .InProgress = 12,
        .LowlevelInterfaceError = 13,
        .OutOfMemory = 15,
        .Routing = 16,
        .Timeout = 17,
        .Unexpected = 19,
    });

    pub const DisconnectError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .NotConnected = 3,
        .Unexpected = 4,
    });

    pub const SendError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .BufferError = 6,
        .IllegalArgument = 10,
        .IllegalValue = 11,
        .InProgress = 12,
        .LowlevelInterfaceError = 13,
        .NotConnected = 14,
        .OutOfMemory = 15,
        .Routing = 16,
        .Timeout = 17,
        .Unexpected = 19,
    });

    pub const SendToError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .BufferError = 6,
        .IllegalArgument = 10,
        .IllegalValue = 11,
        .InProgress = 12,
        .LowlevelInterfaceError = 13,
        .OutOfMemory = 15,
        .Routing = 16,
        .Timeout = 17,
        .Unexpected = 19,
    });

    pub const ReceiveFromError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .BufferError = 6,
        .IllegalArgument = 10,
        .IllegalValue = 11,
        .InProgress = 12,
        .LowlevelInterfaceError = 13,
        .OutOfMemory = 15,
        .Routing = 16,
        .Timeout = 17,
        .Unexpected = 19,
    });
};

pub const tcp = struct {
    const Socket = TcpSocket;

    pub const Bind = IOP.define(.{
        .type = .tcp_bind,
        .@"error" = BindError,
        .inputs = struct {
            socket: Socket,
            bind_point: EndPoint,
        },
        .outputs = struct {
            bind_point: EndPoint,
        },
    });

    pub const Connect = IOP.define(.{
        .type = .tcp_connect,
        .@"error" = ConnectError,
        .inputs = struct {
            socket: Socket,
            target: EndPoint,
        },
    });

    pub const Send = IOP.define(.{
        .type = .tcp_send,
        .@"error" = SendError,
        .inputs = struct {
            socket: Socket,
            data_ptr: [*]const u8,
            data_len: usize,
        },
        .outputs = struct {
            bytes_sent: usize,
        },
    });

    pub const Receive = IOP.define(.{
        .type = .tcp_receive,
        .@"error" = ReceiveError,
        .inputs = struct {
            socket: Socket,
            buffer_ptr: [*]u8,
            buffer_len: usize,
            read_all: bool, // if true, will read until `buffer_len` bytes arrived. otherwise will read until the end of a single packet
        },
        .outputs = struct {
            bytes_received: usize,
        },
    });

    pub const CreateError = ErrorSet(.{
        .SystemResources = 1,
    });

    pub const BindError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .AddressInUse = 3,
        .IllegalValue = 4,
        .Unexpected = 5,
    });

    pub const ConnectError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .AlreadyConnected = 4,
        .AlreadyConnecting = 5,
        .BufferError = 6,
        .ConnectionAborted = 7,
        .ConnectionClosed = 8,
        .ConnectionReset = 9,
        .IllegalArgument = 10,
        .IllegalValue = 11,
        .InProgress = 12,
        .LowlevelInterfaceError = 13,
        .OutOfMemory = 15,
        .Routing = 16,
        .Timeout = 17,
        .Unexpected = 19,
    });

    pub const SendError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .BufferError = 3,
        .ConnectionAborted = 4,
        .ConnectionClosed = 5,
        .ConnectionReset = 6,
        .IllegalArgument = 7,
        .IllegalValue = 8,
        .InProgress = 9,
        .LowlevelInterfaceError = 10,
        .NotConnected = 11,
        .OutOfMemory = 12,
        .Routing = 13,
        .Timeout = 14,
        .Unexpected = 15,
    });

    pub const ReceiveError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .AlreadyConnected = 3,
        .AlreadyConnecting = 4,
        .BufferError = 5,
        .ConnectionAborted = 6,
        .ConnectionClosed = 7,
        .ConnectionReset = 8,
        .IllegalArgument = 9,
        .IllegalValue = 10,
        .InProgress = 11,
        .LowlevelInterfaceError = 12,
        .NotConnected = 13,
        .OutOfMemory = 14,
        .Routing = 15,
        .Timeout = 16,
        .Unexpected = 17,
    });
};

pub const input = struct {
    const Error = ErrorSet(.{
        .NonExclusiveAccess = 1,
        .InProgress = 2,
        .Unexpected = 3,
    });

    pub const GetEvent = IOP.define(.{
        .type = .input_get_event,
        .@"error" = Error,
        .outputs = struct {
            event_type: InputEventType,
            event: InputEvent,
        },
    });
};

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
