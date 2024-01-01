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

    // Sets the screen resolution. Legal values are between 1×1 and the platform specific
    // maximum resolution returned by `video.getMaxResolution()`.
    // Everything out of bounds will be clamped into that range.
    defineSysCall("video.setResolution", fn (u16, u16) void, 8),

    // Returns a pointer to linear video memory, row-major.
    // Pixels rows will have a stride of the current video buffer width.
    // The first pixel in the memory is the top-left pixel.
    defineSysCall("video.getVideoMemory", fn () [*]align(4) ColorIndex, 9),

    // Returns a pointer to the current palette. Changing this palette
    // will directly change the associated colors on the screen.
    defineSysCall("video.getPaletteMemory", fn () *[palette_size]Color, 10),

    // Fetches a copy of the current system pallete.
    defineSysCall("video.getPalette", fn (*[palette_size]Color) void, 11),

    defineSysCall("ui.createWindow", fn (title: [*]const u8, title_len: usize, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) ?*const Window, 14),
    defineSysCall("ui.destroyWindow", fn (*const Window) void, 15),
    defineSysCall("ui.moveWindow", fn (*const Window, x: i16, y: i16) void, 16),
    defineSysCall("ui.resizeWindow", fn (*const Window, x: u16, y: u16) void, 17),
    defineSysCall("ui.setWindowTitle", fn (*const Window, title: [*]const u8, title_len: usize) void, 18),
    defineSysCall("ui.invalidate", fn (*const Window, rect: Rectangle) void, 20),

    defineSysCall("ui.getSystemFont", fn (font_name_ptr: [*]const u8, font_name_len: usize, font_data_ptr: *[*]const u8, font_data_len: *usize) GetSystemFontError.Enum, 21),

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

    defineSysCall("network.tcp.createSocket", fn (out: *TcpSocket) tcp.CreateError.Enum, 44),
    defineSysCall("network.tcp.destroySocket", fn (TcpSocket) void, 45),

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

    // Cancels a single I/O operation.
    defineSysCall("io.cancel", fn (*IOP) void, 51),

    // Returns the maximum possible screen resolution.
    defineSysCall("video.getMaxResolution", fn () Size, 52),

    // Returns the current resolution
    defineSysCall("video.getResolution", fn () Size, 53),

    // Finds a file system by name
    defineSysCall("fs.findFilesystem", fn (name_ptr: [*]const u8, name_len: usize) FileSystemId, 60),

    // Allocates memory pages from the system.
    defineSysCall("process.memory.allocate", fn (size: usize, ptr_align: u8) ?[*]u8, 70),
    defineSysCall("process.memory.release", fn (ptr: [*]u8, size: usize, ptr_align: u8) void, 71),

    defineSysCall("process.getFileName", fn () [*:0]const u8, 72),

    defineSysCall("process.writeLog", fn (log_level: LogLevel, ptr: [*]const u8, len: usize) void, 73),
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
        .signature = *const T2,
        .index = index,
    };
}

fn SysCallFunc(comptime call: SysCall) type {
    for (syscall_definitions) |def| {
        if (def.index == @intFromEnum(call))
            return def.signature;
    }
    unreachable;
}

pub fn syscall(comptime name: []const u8) SysCallFunc(@field(SysCall, name)) {
    const target = @import("builtin").target;

    switch (target.os.tag) {
        .linux, .windows => {
            return @field(@import("root").syscall_table, name);
        },
        .freestanding => switch (target.cpu.arch) {
            .riscv32 => {
                const table = asm (""
                    : [ptr] "={tp}" (-> *const SysCallTable),
                );
                return @field(table, name);
            },
            .x86 => {
                const offset: u32 = @offsetOf(SysCallTable, name);
                return asm ("mov %fs:%[off], %[out]"
                    : [out] "=r" (-> SysCallFunc(@field(SysCall, name))),
                    : [off] "p" (offset),
                );
            },
            .arm => @panic("no syscalls on arm yet"),
            else => @compileError("unsupported platform"),
        },
        else => @compileError("unsupported os"),
    }
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
        .type = usize,
        .default_value = &default_padding,
        .is_comptime = false,
        .alignment = @alignOf(usize),
    };

    const magic_number_value: usize = system_magic;
    const magic_number_field = std.builtin.Type.StructField{
        .name = "magic_number",
        .type = usize,
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
            .type = def.signature,
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

pub const LogLevel = enum(u8) {
    critical = 0,
    err = 1,
    warn = 2,
    notice = 3,
    debug = 4,
    _,
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

pub const ThreadFunction = *const fn (?*anyopaque) callconv(.C) u32;

pub const ColorIndex = enum(u8) {
    _,

    pub fn get(val: u8) ColorIndex {
        return @as(ColorIndex, @enumFromInt(val));
    }

    pub fn index(c: ColorIndex) @typeInfo(ColorIndex).Enum.tag_type {
        return @intFromEnum(c);
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
        return @as(u16, @bitCast(c));
    }

    pub fn fromU16(u: u16) Color {
        return @as(Color, @bitCast(u));
    }

    pub fn fromRgb888(r: u8, g: u8, b: u8) Color {
        return Color{
            .r = @as(u5, @truncate(r >> 3)),
            .g = @as(u6, @truncate(g >> 2)),
            .b = @as(u5, @truncate(b >> 3)),
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

pub const KeyboardModifiers = packed struct(u16) {
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

pub const Point = extern struct {
    pub const zero = new(0, 0);

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

    pub fn format(point: Point, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Point({},{})", .{
            point.x, point.y,
        });
    }
};

pub const Size = extern struct {
    pub const empty = new(0, 0);
    pub const max = new(std.math.maxInt(u16), std.math.maxInt(u16));

    width: u16,
    height: u16,

    pub fn new(w: u16, h: u16) Size {
        return Size{ .width = w, .height = h };
    }

    pub fn eql(a: Size, b: Size) bool {
        return (a.width == b.width) and (a.height == b.height);
    }

    pub fn format(size: Size, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Size({}x{})", .{
            size.width,
            size.height,
        });
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
            (pt.x < rect.x + @as(u15, @intCast(rect.width))) and
            (pt.y >= rect.y) and
            (pt.y < rect.y + @as(u15, @intCast(rect.height)));
    }

    pub fn containsRectangle(boundary: Rectangle, region: Rectangle) bool {
        return boundary.contains(region.position()) and
            boundary.contains(Point.new(region.x + @as(u15, @intCast(region.width)) - 1, region.y + @as(u15, @intCast(region.height)) - 1));
    }

    pub fn intersects(a: Rectangle, b: Rectangle) bool {
        return a.x + @as(u15, @intCast(a.width)) >= b.x and
            a.y + @as(u15, @intCast(a.height)) >= b.y and
            a.x <= b.x + @as(u15, @intCast(b.width)) and
            a.y <= b.y + @as(u15, @intCast(b.height));
    }

    pub fn eql(a: Rectangle, b: Rectangle) bool {
        return a.size().eql(b.size()) and a.position().eql(b.position());
    }

    pub fn top(rect: Rectangle) i16 {
        return rect.y;
    }
    pub fn bottom(rect: Rectangle) i16 {
        return rect.y + @as(u15, @intCast(rect.height));
    }
    pub fn left(rect: Rectangle) i16 {
        return rect.x;
    }
    pub fn right(rect: Rectangle) i16 {
        return rect.x +| @as(u15, @intCast(rect.width));
    }

    pub fn shrink(rect: Rectangle, amount: u15) Rectangle {
        var copy = rect;
        copy.x +|= amount;
        copy.y +|= amount;
        copy.width -|= 2 * amount;
        copy.height -|= 2 * amount;
        return copy;
    }

    pub fn grow(rect: Rectangle, amount: u15) Rectangle {
        var copy = rect;
        copy.x -|= amount;
        copy.y -|= amount;
        copy.width +|= 2 * amount;
        copy.height +|= 2 * amount;
        return copy;
    }

    pub fn format(rect: Rectangle, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Rectangle({},{},{}x{})", .{
            rect.x,
            rect.y,
            rect.width,
            rect.height,
        });
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

pub const GetSystemFontError = ErrorSet(.{
    .FileNotFound = 1,
    .SystemResources = 2,
    .OutOfMemory = 3,
    .Unexpected = 4,
});

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
            for (enum_list, 0..) |match, index| {
                if (match == val)
                    return error_list[index];
            }
            return error.Unexpected;
        }

        pub fn map(err_union: Error!void) Enum {
            if (err_union) |_| {
                return .ok;
            } else |err| {
                for (error_list, 0..) |match, index| {
                    if (match == err)
                        return enum_list[index];
                }
                unreachable;
            }
        }
    };
}

pub const DefaultError = ErrorSet(.{
    .Unexpected = 1,
});

///////////////////////////////////////////////////////////////////////////////

// I/O Operation
pub const IOP = extern struct {
    type: Type,
    next: ?*IOP,
    tag: usize, // user specified data

    kernel_data: [7]usize = undefined, // internal data used by the kernel to store

    pub const Type = enum(u32) {
        // Timer
        timer = 1,

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

        // FS IOPS:
        fs_sync,
        fs_get_filesystem_info,
        fs_open_drive,
        fs_open_dir,
        fs_close_dir,
        fs_reset_dir_enumeration,
        fs_enumerate_dir,
        fs_delete,
        fs_mkdir,
        fs_stat_entry,
        fs_near_move,
        fs_far_move,
        fs_copy,
        fs_open_file,
        fs_close_file,
        fs_flush_file,
        fs_read,
        fs_write,
        fs_stat_file,
        fs_resize,
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

        for (&output_fields) |*fld| {
            if (fld.default_value != null) {
                @compileError(std.fmt.comptimePrint("IOP outputs are not allowed to have default values. {s}/{s} has one.", .{
                    @tagName(def.type),
                    fld.name,
                }));
            }
            fld.default_value = undefinedDefaultFor(fld.type);
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

            pub fn chain(self: *Self, next: anytype) void {
                const Next = @TypeOf(next.*);
                if (comptime !isIOP(Next))
                    @compileError("next must be a pointer to IOP!");
                const next_ptr: *Next = next;
                const next_iop: *IOP = &next_ptr.iop;

                var it: ?*IOP = &self.iop;
                while (it) |p| : (it = p.next) {
                    if (p == &next_iop) // already in the chain
                        return;

                    if (p.next == null) {
                        p.next = &next_iop;
                        return;
                    }
                }

                unreachable;
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

    /// Doesn't block the call, and guarantees that no event is returned by `scheduleAndAwait`.
    /// This can be used to enqueue new IOPs outside of the event loop.
    schedule_only,

    /// Wait for at least one I/O to complete operation.
    wait_one,

    /// Wait until all scheduled I/O operations have completed.
    wait_all,

    /// Returns whether the operation is blocking or not.
    pub fn isBlocking(wait: WaitIO) bool {
        return switch (wait) {
            .dont_block => false,
            .schedule_only => false,
            .wait_one => true,
            .wait_all => true,
        };
    }
};

pub const Timer = IOP.define(.{
    .type = .timer,
    .@"error" = ErrorSet(.{ .Unexpected = 1 }),
    .inputs = struct {
        timeout: i128,
    },
});

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

// A file or directory on Ashet OS can be named with any legal UTF-8 sequence
// that does not contain `/` and `:`. It is recommended to only create file names
// that are actually typeable on the operating system tho.
//
// There are some special file names:
// - `.` is the "current directory" selector and does not add to the path.
// - `..` is the "parent directory" selector and navigates up in the directory hierarchy if possible.
// - Any sequence of upper case ASCII letters and digits (`A-Z`, `0-9`) that ends with `:` is a file system name. This name specifies
//   the root directory of a certain file system.
//
// Paths are either a relative or absolute addyessing of a file system entity.
// Paths are composed of a sequence of names, each name separated by `/`.
// A file system name is only legal as the first element of a path sequence, making the path an absolute path.
//
// There is a limit on how long a file/directory name can be, but there's no limit on how long a total
// path can be.
//
// Here are some examples for valid paths:
// - `example.txt`
// - `docs/wiki.txt`
// - `SYS:/apps/editor/code`
// - `USB0:/foo/../bar` (which is equivalent to `USB0:/bar`)
//
// The filesystem that is used to boot the OS from has an alias `SYS:` that is always a legal way to address this file system.

/// The maximum number of bytes in a file system identifier name.
/// This is chosen to be a power of two, and long enough to accommodate
/// typical file system names:
/// - `SYS`
/// - `USB0`
/// - `USB10`
/// - `PF0`
/// - `CF7`
pub const max_fs_name_len = 8;

/// The maximum number of bytes in a file system type name.
/// Chosen to be a power of two, and long enough to accomodate typical names:
/// - `FAT16`
/// - `FAT32`
/// - `exFAT`
/// - `NTFS`
/// - `ReiserFS`
/// - `ISO 9660`
/// - `btrfs`
/// - `AFFS`
pub const max_fs_type_len = 32;

/// The maximum number of bytes in a file name.
/// This is chosen to be a power of two, and reasonably long.
/// As some programs use sha256 checksums and 64 bytes are enough to store
/// a hex-encoded 256 bit sequence:
/// - `114ac2caf8fefad1116dbfb1bd68429f68e9e088b577c9b3f5a3ff0fe77ec886`
/// This should also enough for most reasonable file names in the wild.
pub const max_file_name_len = 120;

/// Unix timestamp in milliseconds
pub const DateTime = i64;

pub const FileSystemId = enum(u32) {
    /// This is the file system which the os has bootet from.
    system = 0,

    /// the filesystem isn't valid.
    invalid = ~@as(u32, 0),

    /// All other ids are unique file systems.
    _,
};

pub const FileHandle = enum(u32) { invalid, _ };
pub const DirectoryHandle = enum(u32) { invalid, _ };

pub const FileSystemInfo = extern struct {
    id: FileSystemId, // system-unique id of this file system
    flags: Flags, // binary infos about the file system
    name: [max_fs_name_len]u8, // user addressable file system identifier ("USB0", ...)
    filesystem: [max_fs_type_len]u8, // string identifier of a file system driver ("FAT32", ...)

    pub const Flags = packed struct(u16) {
        system: bool, // is the system boot disk
        removable: bool, // the file system can be removed by the user
        read_only: bool, // the file system is mounted as read-only
        reserved: u13 = 0,
    };

    pub fn getName(fi: *const FileInfo) []const u8 {
        return std.mem.sliceTo(&fi.name, 0);
    }

    pub fn getFileSystem(fi: *const FileInfo) []const u8 {
        return std.mem.sliceTo(&fi.filesystem, 0);
    }
};

pub const FileInfo = extern struct {
    name: [max_file_name_len]u8,
    size: u64,
    attributes: FileAttributes,
    creation_date: DateTime,
    modified_date: DateTime,

    pub fn getName(fi: *const FileInfo) []const u8 {
        return std.mem.sliceTo(&fi.name, 0);
    }
};

pub const FileAttributes = packed struct(u16) {
    directory: bool,
    reserved: u15 = 0,
};

pub const FileAccess = enum(u8) {
    read_only = 0,
    write_only = 1,
    read_write = 2,
};

pub const FileMode = enum(u8) {
    open_existing = 0, // opens file when it exists on disk
    open_always = 1, // creates file when it does not exist, or opens the file without truncation.
    create_new = 2, // creates file when there is no file with that name
    create_always = 3, // creates file when it does not exist, or opens the file and truncates it to zero length
};

pub const fs = struct {
    pub const FileSystemError = ErrorSet(.{
        .Unexpected = 1,
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
        .Overflow = 18,
        .Timeout = 19,
        .TooManyOpenFiles = 20,
        .WriteProtected = 21,
        .InvalidFileHandle = 22,
        .InvalidDevice = 23,
        .PathTooLong = 24,
        .Unimplemented = 25,
    });

    pub const SyncError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
    });
    pub const GetFilesystemInfoError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidFileSystem = 3,
    });
    pub const OpenDriveError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidFileSystem = 3,
        .FileNotFound = 4,
        .NotADir = 5,
        .InvalidPath = 6,
        .SystemFdQuotaExceeded = 7,
        .SystemResources = 8,
    });
    pub const OpenDirError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .FileNotFound = 4,
        .NotADir = 5,
        .InvalidPath = 6,
        .SystemFdQuotaExceeded = 7,
        .SystemResources = 8,
    });
    pub const CloseDirError = ErrorSet(.{
        .Unexpected = 1,
        .InvalidHandle = 2,
    });
    pub const ResetDirEnumerationError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .SystemResources = 4,
    });
    pub const EnumerateDirError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .SystemResources = 4,
    });
    pub const DeleteFileError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .FileNotFound = 4,
        .InvalidPath = 5,
    });
    pub const MkDirError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .Exists = 4,
        .InvalidPath = 5,
    });
    pub const StatEntryError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .FileNotFound = 4,
        .InvalidPath = 5,
    });
    pub const NearMoveError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .FileNotFound = 4,
        .InvalidPath = 5,
        .Exists = 6,
    });
    pub const FarMoveError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .FileNotFound = 4,
        .InvalidPath = 5,
        .Exists = 6,
        .NoSpaceLeft = 7,
    });
    pub const CopyFileError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .FileNotFound = 4,
        .InvalidPath = 5,
        .Exists = 6,
        .NoSpaceLeft = 7,
    });
    pub const OpenFileError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .FileNotFound = 4,
        .InvalidPath = 5,
        .Exists = 6,
        .NoSpaceLeft = 7,
        .SystemFdQuotaExceeded = 8,
        .SystemResources = 9,
        .WriteProtected = 10,
        .FileAlreadyExists = 11,
    });
    pub const FlushFileError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .SystemResources = 4,
    });
    pub const ReadError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .SystemResources = 4,
    });
    pub const WriteError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .NoSpaceLeft = 4,
        .SystemResources = 5,
        .WriteProtected = 6,
    });
    pub const StatFileError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .SystemResources = 4,
    });
    pub const ResizeFileError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .NoSpaceLeft = 4,
        .SystemResources = 5,
    });
    pub const CloseFileError = ErrorSet(.{
        .Unexpected = 1,
        .DiskError = 2,
        .InvalidHandle = 3,
        .SystemResources = 4,
    });

    /// Flushes all open files to disk.
    pub const Sync = IOP.define(.{
        .type = .fs_sync,
        .@"error" = SyncError,
        .inputs = struct {},
    });

    /// Gets information about a file system.
    /// Also returns a `next` id that can be used to iterate over all filesystems.
    /// The `system` filesystem is guaranteed to be the first one.
    pub const GetFilesystemInfo = IOP.define(.{
        .type = .fs_get_filesystem_info,
        .@"error" = GetFilesystemInfoError,
        .inputs = struct { fs: FileSystemId },
        .outputs = struct { info: FileSystemInfo, next: FileSystemId },
    });

    /// opens a directory on a filesystem
    pub const OpenDrive = IOP.define(.{
        .type = .fs_open_drive,
        .@"error" = OpenDriveError,
        .inputs = struct { fs: FileSystemId, path_ptr: [*]const u8, path_len: usize },
        .outputs = struct { dir: DirectoryHandle },
    });

    /// opens a directory relative to the given dir handle.
    pub const OpenDir = IOP.define(.{
        .type = .fs_open_dir,
        .@"error" = OpenDirError,
        .inputs = struct { dir: DirectoryHandle, path_ptr: [*]const u8, path_len: usize },
        .outputs = struct { dir: DirectoryHandle },
    });

    /// closes the directory handle
    pub const CloseDir = IOP.define(.{
        .type = .fs_close_dir,
        .@"error" = CloseDirError,
        .inputs = struct { dir: DirectoryHandle },
        .outputs = struct {},
    });

    /// resets the directory iterator to the starting point
    pub const ResetDirEnumeration = IOP.define(.{
        .type = .fs_reset_dir_enumeration,
        .@"error" = ResetDirEnumerationError,
        .inputs = struct { dir: DirectoryHandle },
    });

    /// returns the info for the current file or "eof", and advances the iterator to the next entry if possible
    pub const EnumerateDir = IOP.define(.{
        .type = .fs_enumerate_dir,
        .@"error" = EnumerateDirError,
        .inputs = struct { dir: DirectoryHandle },
        .outputs = struct { eof: bool, info: FileInfo },
    });

    /// deletes a file or directory by the given path.
    pub const Delete = IOP.define(.{
        .type = .fs_delete,
        .@"error" = DeleteFileError,
        .inputs = struct { dir: DirectoryHandle, path_ptr: [*]const u8, path_len: usize, recurse: bool },
    });

    /// creates a new directory relative to dir. If `path` contains subdirectories, all
    /// directories are created.
    pub const MkDir = IOP.define(.{
        .type = .fs_mkdir,
        .@"error" = MkDirError,
        .inputs = struct { dir: DirectoryHandle, path_ptr: [*]const u8, path_len: usize },
        .outputs = struct { DirectoryHandle },
    });

    /// returns the type of the file/dir at path, also adds size and modification dates
    pub const StatEntry = IOP.define(.{
        .type = .fs_stat_entry,
        .@"error" = StatEntryError,
        .inputs = struct {
            dir: DirectoryHandle,
            path_ptr: [*]const u8,
            path_len: usize,
        },
        .outputs = struct { info: FileInfo },
    });

    /// renames a file inside the same file system.
    /// NOTE: This is a cheap operation and does not require the copying of data.
    pub const NearMove = IOP.define(.{
        .type = .fs_near_move,
        .@"error" = NearMoveError,
        .inputs = struct {
            src_dir: DirectoryHandle,
            src_path_ptr: [*]const u8,
            src_path_len: usize,
            dst_path_ptr: [*]const u8,
            dst_path_len: usize,
        },
    });

    // GROUP: modification

    /// moves a file or directory between two unrelated directories. Can also move between different file systems.
    /// NOTE: This syscall might copy the data.
    pub const FarMove = IOP.define(.{
        .type = .fs_far_move,
        .@"error" = FarMoveError,
        .inputs = struct {
            src_dir: DirectoryHandle,
            src_path_ptr: [*]const u8,
            src_path_len: usize,
            dst_dir: DirectoryHandle,
            dst_path_ptr: [*]const u8,
            dst_path_len: usize,
        },
    });

    /// copies a file or directory between two unrelated directories. Can also move between different file systems.
    pub const Copy = IOP.define(.{
        .type = .fs_copy,
        .@"error" = CopyFileError,
        .inputs = struct {
            src_dir: DirectoryHandle,
            src_path_ptr: [*]const u8,
            src_path_len: usize,
            dst_dir: DirectoryHandle,
            dst_path_ptr: [*]const u8,
            dst_path_len: usize,
        },
    });

    // // GROUP: file handling

    /// opens a file from the given directory.
    pub const OpenFile = IOP.define(.{
        .type = .fs_open_file,
        .@"error" = OpenFileError,
        .inputs = struct {
            dir: DirectoryHandle,
            path_ptr: [*]const u8,
            path_len: usize,
            access: FileAccess,
            mode: FileMode,
        },
        .outputs = struct { handle: FileHandle },
    });

    /// closes the handle and flushes the file.
    pub const CloseFile = IOP.define(.{
        .type = .fs_close_file,
        .@"error" = CloseFileError,
        .inputs = struct { file: FileHandle },
    });

    /// makes sure this file is safely stored to mass storage device
    pub const FlushFile = IOP.define(.{
        .type = .fs_flush_file,
        .@"error" = FlushFileError,
        .inputs = struct { file: FileHandle },
    });

    /// directly reads data from a given offset into the file. no streaming API to the kernel
    pub const Read = IOP.define(.{
        .type = .fs_read,
        .@"error" = ReadError,
        .inputs = struct {
            file: FileHandle,
            offset: u64,
            buffer_ptr: [*]u8,
            buffer_len: usize,
        },
        .outputs = struct { count: usize },
    });

    /// directly writes data to a given offset into the file. no streaming API to the kernel
    pub const Write = IOP.define(.{
        .type = .fs_write,
        .@"error" = WriteError,
        .inputs = struct {
            file: FileHandle,
            offset: u64,
            buffer_ptr: [*]const u8,
            buffer_len: usize,
        },
        .outputs = struct { count: usize },
    });

    /// allows us to get the current size of the file, modification dates, and so on
    pub const StatFile = IOP.define(.{
        .type = .fs_stat_file,
        .@"error" = StatFileError,
        .inputs = struct { file: FileHandle },
        .outputs = struct { info: FileInfo },
    });

    /// Resizes the file to the given length in bytes. Can be also used to truncate a file to zero length.
    pub const Resize = IOP.define(.{
        .type = .fs_resize,
        .@"error" = ResizeFileError,
        .inputs = struct { file: FileHandle, length: u64 },
    });
};
