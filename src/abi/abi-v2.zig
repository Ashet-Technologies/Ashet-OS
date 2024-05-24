//!
//! WARNING:
//!     THIS FILE IS MEANT TO BE PREPROCESSED BY A TOOL TO CONVERT INTO
//!     C-COMPATIBLE APIS!
//!

const std = @import("std");

// const ErrorSet = @import("error_set.zig").ErrorSet;
const iops = @import("iops.zig");

const abi = @This();

///////////////////////////////////////////////////////////
// Generated code: {{ syscalls }}

///////////////////////////////////////////////////////////
// Constants:

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

pub const palette_size = std.math.maxInt(@typeInfo(ColorIndex).Enum.tag_type) + 1;

pub const system_widgets = struct {
    pub const label = UUID.constant("53b8be36-969a-46a3-bdf5-e3d197890219");
    pub const button = UUID.constant("782ccd0e-bae4-4093-93fe-12c1f86ff43c");
    pub const text_box = UUID.constant("02eddbc3-b882-41e9-8aba-10d12b451e11");
    pub const multi_line_text_box = UUID.constant("84d40a1a-04ab-4e00-ae93-6e91e6b3d10a");
    pub const vertical_scroll_bar = UUID.constant("d1c52f74-e9b8-4067-8bb6-fe01c49d97ae");
    pub const horizontal_scroll_bar = UUID.constant("2899397f-ede2-46e9-8458-1eea29c81fa1");
    pub const progress_bar = UUID.constant("b96290a9-542f-45f5-9e37-1ce9084fc0e3");
    pub const check_box = UUID.constant("051c6bff-d491-4e5a-8b77-6f4244da52ee");
    pub const radio_button = UUID.constant("4f18fde6-944c-494f-a55c-ba11f45fcfa3");
    pub const panel = UUID.constant("1fa5b237-0bda-48d1-b95a-fcf80616318b");
    pub const group_box = UUID.constant("b96bc6a2-6df0-4f76-962a-4af18fdf3548");
};

///////////////////////////////////////////////////////////
// System resources:

/// Handle to an abstract system resource.
pub const SystemResource = opaque {
    pub const get_type = syscalls.resources.get_type;
    pub const get_owner = syscalls.resources.get_owner;
    pub const set_owner = syscalls.resources.set_owner;
    pub const close = syscalls.resources.close;

    /// Casts the resource into a concrete type. Fails, if the type does not match.
    pub fn cast(resource: *SystemResource, comptime t: Type) error{InvalidType}!*CastResult(t) {
        const actual = resource.get_type();
        if (actual != t)
            return error.InvalidType;
        return @ptrCast(resource);
    }

    fn CastResult(comptime t: Type) type {
        return switch (t) {
            .process => Process,
            .thread => Thread,

            .tcp_socket => TcpSocket,
            .udp_socket => UdpSocket,

            .service => Service,

            .file => File,

            .directory => Directory,
            .video_output => VideoOutput,

            .font => Font,
            .framebuffer => Framebuffer,

            .window => Window,
            .widget => Widget,
            .desktop => Desktop,
            .widget_type => WidgetType,

            _ => @compileError("Undefined type passed."),
        };
    }

    pub const Type = enum(u16) {
        process,
        thread,

        tcp_socket,
        udp_socket,

        file,
        directory,

        video_output,

        font,
        framebuffer,

        window,
        widget,
        desktop,

        _,
    };
};

pub const Service = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const SharedMemory = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Pipe = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Process = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Thread = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const TcpSocket = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const UdpSocket = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const File = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Directory = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const VideoOutput = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Font = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

/// A framebuffer is something that can be drawn on.
pub const Framebuffer = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Window = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Widget = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const Desktop = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

pub const WidgetType = opaque {
    pub fn as_resource(value: *@This()) *SystemResource {
        return @ptrCast(value);
    }
};

///////////////////////////////////////////////////////////
// Simple types:

pub const UUID = struct {
    bytes: [16]u8,

    /// Parses a UUID in the format
    /// `3ad20402-1711-4bbc-b6c3-ff8a1da068c6`
    /// and returns a pointer to it.
    pub fn constant(str: *const [36:0]u8) *const UUID {
        _ = str;
        unreachable;
    }
};

pub const MAC = [6]u8;

pub const AbstractFunction = fn () callconv(.C) void;

pub const ThreadFunction = *const fn (?*anyopaque) callconv(.C) u32;

/// A date-and-time type encoding the time point in question as a
/// Unix timestamp in milliseconds
pub const DateTime = enum(i64) {
    _,
};

/// Index into a color palette.
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

///////////////////////////////////////////////////////////
// Enumerations:

pub const NotificationKind = enum(u8) {
    /// Important information that require immediate action
    /// by the user.
    ///
    /// This should be handled with care and only for reall
    /// urgent situations like low battery power or
    /// unsufficient disk memory.
    attention = 0,

    /// This is a regular user notification, which should be used
    /// sparingly.
    ///
    /// Typical notifications of this kind are in the category of
    /// "download completed", "video fully rendered" or similar.
    information = 128,

    /// Silent notifications that might be informational, but do not
    /// require attention by the user at all.
    whisper = 255,
};

pub const IP_Type = enum(u8) { ipv4, ipv6 };

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

/// Index of the systems video outputs.
pub const VideoOutputID = enum(u8) {
    /// The primary video output
    primary = 0,
    _,
};

pub const FontType = enum(u32) {
    bitmap = 0,
    vector = 1,
    _,
};

pub const FramebufferType = enum(u8) {
    /// A pure in-memory frame buffer used for off-screen rendering.
    memory = 0,

    /// A video device backed frame buffer. Can be used to paint on a screen
    /// directly.
    video = 1,

    /// A frame buffer provided by a window. These frame buffers
    /// may hold additional semantic information.
    window = 2,

    /// A frame buffer provided by a user interface element. These frame buffers
    /// may hold additional semantic information.
    widget = 3,
};

pub const MessageBoxIcon = enum(u8) {
    information = 0,
    question = 1,
    warning = 2,
    @"error" = 3,
};

pub const MessageBoxResult = enum(u8) {
    ok = @bitOffsetOf(MessageBoxButtons, "ok"),
    cancel = @bitOffsetOf(MessageBoxButtons, "cancel"),
    yes = @bitOffsetOf(MessageBoxButtons, "yes"),
    no = @bitOffsetOf(MessageBoxButtons, "no"),
    abort = @bitOffsetOf(MessageBoxButtons, "abort"),
    retry = @bitOffsetOf(MessageBoxButtons, "retry"),
    @"continue" = @bitOffsetOf(MessageBoxButtons, "continue"),
    ignore = @bitOffsetOf(MessageBoxButtons, "ignore"),
};

pub const ExitCode = enum(u32) {
    success = @as(u32, 0),
    failure = @as(u32, 1),

    killed = ~@as(u32, 0),

    _,
};

pub const LogLevel = enum(u8) {
    critical = 0,
    err = 1,
    warn = 2,
    notice = 3,
    debug = 4,
    _,
};

pub const FileSystemId = enum(u32) {
    /// This is the file system which the os has bootet from.
    system = 0,

    /// the filesystem isn't valid.
    invalid = ~@as(u32, 0),

    /// All other ids are unique file systems.
    _,
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

pub const InputEventType = enum(u8) {
    mouse = 1,
    keyboard = 2,
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

///////////////////////////////////////////////////////////
// Compound types:

pub const CreateWindowFlags = packed struct(u32) {
    popup: bool = false,
    padding: u31 = 0,
};

pub const WidgetDescriptor = extern struct {
    // TODO: Fill this out
};

pub const MessageBoxButtons = packed struct(u8) {
    pub const ok: MessageBoxButtons = .{ .ok = true };
    pub const ok_cancel: MessageBoxButtons = .{ .ok = true, .cancel = true };
    pub const yes_no: MessageBoxButtons = .{ .yes = true, .no = true };
    pub const yes_no_cancel: MessageBoxButtons = .{ .yes = true, .no = true, .cancel = true };
    pub const retry_cancel: MessageBoxButtons = .{ .retry = true, .cancel = true };
    pub const abort_retry_ignore: MessageBoxButtons = .{ .abort = true, .retry = true, .ignore = true };

    ok: bool = false,
    cancel: bool = false,
    yes: bool = false,
    no: bool = false,
    abort: bool = false,
    retry: bool = false,
    @"continue": bool = false,
    ignore: bool = false,
};

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
        const exp = color.toRgb888();
        return @as(u32, exp.r) << 0 |
            @as(u32, exp.g) << 8 |
            @as(u32, exp.b) << 16;
    }

    pub fn toRgb888(color: Color) RGB888 {
        const src_r: u8 = color.r;
        const src_g: u8 = color.g;
        const src_b: u8 = color.b;

        // expand bits to form a linear range between 0…255
        return .{
            .r = (src_r << 3) | (src_r >> 2),
            .g = (src_g << 2) | (src_g >> 4),
            .b = (src_b << 3) | (src_b >> 2),
        };
    }

    pub const RGB888 = extern struct {
        r: u8,
        g: u8,
        b: u8,
    };
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

///////////////////////////////////////////////////////////
// Callback types:

///////////////////////////////////////////////////////////
// IO Operations:

pub const IOP = iops.Generic_IOP(IOP_Type);

pub const IOP_Type = enum(u32) {
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

pub const Timer = IOP.define(.{
    .type = .timer,
    .@"error" = ErrorSet(.{ .Unexpected = 1 }),
    .inputs = struct {
        timeout: i128,
    },
});

/// A file or directory on Ashet OS can be named with any legal UTF-8 sequence
/// that does not contain `/` and `:`. It is recommended to only create file names
/// that are actually typeable on the operating system tho.
///
/// There are some special file names:
/// - `.` is the "current directory" selector and does not add to the path.
/// - `..` is the "parent directory" selector and navigates up in the directory hierarchy if possible.
/// - Any sequence of upper case ASCII letters and digits (`A-Z`, `0-9`) that ends with `:` is a file system name. This name specifies
///   the root directory of a certain file system.
///
/// Paths are either a relative or absolute addyessing of a file system entity.
/// Paths are composed of a sequence of names, each name separated by `/`.
/// A file system name is only legal as the first element of a path sequence, making the path an absolute path.
///
/// There is a limit on how long a file/directory name can be, but there's no limit on how long a total
/// path can be.
///
/// Here are some examples for valid paths:
/// - `example.txt`
/// - `docs/wiki.txt`
/// - `SYS:/apps/editor/code`
/// - `USB0:/foo/../bar` (which is equivalent to `USB0:/bar`)
///
/// The filesystem that is used to boot the OS from has an alias `SYS:` that is always a legal way to address this file system.
pub const fs = struct {
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
        .Overflow = 17,
        .Timeout = 18,
        .TooManyOpenFiles = 19,
        .WriteProtected = 20,
        .InvalidFileHandle = 21,
        .InvalidDevice = 22,
        .PathTooLong = 23,
        .Unimplemented = 24,
    });

    pub const SyncError = ErrorSet(.{
        .DiskError = 1,
    });
    pub const GetFilesystemInfoError = ErrorSet(.{
        .DiskError = 1,
        .InvalidFileSystem = 2,
    });
    pub const OpenDriveError = ErrorSet(.{
        .DiskError = 1,
        .InvalidFileSystem = 2,
        .FileNotFound = 3,
        .NotADir = 4,
        .InvalidPath = 5,
        .SystemFdQuotaExceeded = 6,
        .SystemResources = 7,
    });
    pub const OpenDirError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .FileNotFound = 3,
        .NotADir = 4,
        .InvalidPath = 5,
        .SystemFdQuotaExceeded = 6,
        .SystemResources = 7,
    });
    pub const CloseDirError = ErrorSet(.{
        .InvalidHandle = 1,
    });
    pub const ResetDirEnumerationError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .SystemResources = 3,
    });
    pub const EnumerateDirError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .SystemResources = 3,
    });
    pub const DeleteFileError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .FileNotFound = 3,
        .InvalidPath = 4,
    });
    pub const MkDirError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .Exists = 3,
        .InvalidPath = 4,
    });
    pub const StatEntryError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .FileNotFound = 3,
        .InvalidPath = 4,
    });
    pub const NearMoveError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .FileNotFound = 3,
        .InvalidPath = 4,
        .Exists = 5,
    });
    pub const FarMoveError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .FileNotFound = 3,
        .InvalidPath = 4,
        .Exists = 5,
        .NoSpaceLeft = 6,
    });
    pub const CopyFileError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .FileNotFound = 3,
        .InvalidPath = 4,
        .Exists = 5,
        .NoSpaceLeft = 6,
    });
    pub const OpenFileError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .FileNotFound = 3,
        .InvalidPath = 4,
        .Exists = 5,
        .NoSpaceLeft = 6,
        .SystemFdQuotaExceeded = 7,
        .SystemResources = 8,
        .WriteProtected = 9,
        .FileAlreadyExists = 10,
    });
    pub const FlushFileError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .SystemResources = 3,
    });
    pub const ReadError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .SystemResources = 3,
    });
    pub const WriteError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .NoSpaceLeft = 3,
        .SystemResources = 4,
        .WriteProtected = 5,
    });
    pub const StatFileError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .SystemResources = 3,
    });
    pub const ResizeFileError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .NoSpaceLeft = 3,
        .SystemResources = 4,
    });
    pub const CloseFileError = ErrorSet(.{
        .DiskError = 1,
        .InvalidHandle = 2,
        .SystemResources = 3,
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
        .outputs = struct { dir: ?*Directory },
    });

    /// opens a directory relative to the given dir handle.
    pub const OpenDir = IOP.define(.{
        .type = .fs_open_dir,
        .@"error" = OpenDirError,
        .inputs = struct { dir: *Directory, path_ptr: [*]const u8, path_len: usize },
        .outputs = struct { dir: ?*Directory },
    });

    /// closes the directory handle
    pub const CloseDir = IOP.define(.{
        .type = .fs_close_dir,
        .@"error" = CloseDirError,
        .inputs = struct { dir: *Directory },
        .outputs = struct {},
    });

    /// resets the directory iterator to the starting point
    pub const ResetDirEnumeration = IOP.define(.{
        .type = .fs_reset_dir_enumeration,
        .@"error" = ResetDirEnumerationError,
        .inputs = struct { dir: *Directory },
    });

    /// returns the info for the current file or "eof", and advances the iterator to the next entry if possible
    pub const EnumerateDir = IOP.define(.{
        .type = .fs_enumerate_dir,
        .@"error" = EnumerateDirError,
        .inputs = struct { dir: *Directory },
        .outputs = struct { eof: bool, info: FileInfo },
    });

    /// deletes a file or directory by the given path.
    pub const Delete = IOP.define(.{
        .type = .fs_delete,
        .@"error" = DeleteFileError,
        .inputs = struct { dir: *Directory, path_ptr: [*]const u8, path_len: usize, recurse: bool },
    });

    /// creates a new directory relative to dir. If `path` contains subdirectories, all
    /// directories are created.
    pub const MkDir = IOP.define(.{
        .type = .fs_mkdir,
        .@"error" = MkDirError,
        .inputs = struct { dir: *Directory, path_ptr: [*]const u8, path_len: usize, mkopen: bool },
        .outputs = struct { ?*Directory },
    });

    /// returns the type of the file/dir at path, also adds size and modification dates
    pub const StatEntry = IOP.define(.{
        .type = .fs_stat_entry,
        .@"error" = StatEntryError,
        .inputs = struct {
            dir: *Directory,
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
            src_dir: *Directory,
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
            src_dir: *Directory,
            src_path_ptr: [*]const u8,
            src_path_len: usize,
            dst_dir: *Directory,
            dst_path_ptr: [*]const u8,
            dst_path_len: usize,
        },
    });

    /// copies a file or directory between two unrelated directories. Can also move between different file systems.
    pub const Copy = IOP.define(.{
        .type = .fs_copy,
        .@"error" = CopyFileError,
        .inputs = struct {
            src_dir: *Directory,
            src_path_ptr: [*]const u8,
            src_path_len: usize,
            dst_dir: *Directory,
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
            dir: *Directory,
            path_ptr: [*]const u8,
            path_len: usize,
            access: FileAccess,
            mode: FileMode,
        },
        .outputs = struct { handle: ?*File },
    });

    /// closes the handle and flushes the file.
    pub const CloseFile = IOP.define(.{
        .type = .fs_close_file,
        .@"error" = CloseFileError,
        .inputs = struct { file: *File },
    });

    /// makes sure this file is safely stored to mass storage device
    pub const FlushFile = IOP.define(.{
        .type = .fs_flush_file,
        .@"error" = FlushFileError,
        .inputs = struct { file: *File },
    });

    /// directly reads data from a given offset into the file. no streaming API to the kernel
    pub const Read = IOP.define(.{
        .type = .fs_read,
        .@"error" = ReadError,
        .inputs = struct {
            file: *File,
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
            file: *File,
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
        .inputs = struct { file: *File },
        .outputs = struct { info: FileInfo },
    });

    /// Resizes the file to the given length in bytes. Can be also used to truncate a file to zero length.
    pub const Resize = IOP.define(.{
        .type = .fs_resize,
        .@"error" = ResizeFileError,
        .inputs = struct { file: *File, length: u64 },
    });
};

pub const udp = struct {
    pub const Bind = IOP.define(.{
        .type = .udp_bind,
        .@"error" = BindError,
        .inputs = struct {
            socket: *UdpSocket,
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
            socket: *UdpSocket,
            target: EndPoint,
        },
    });

    pub const Disconnect = IOP.define(.{
        .type = .udp_disconnect,
        .@"error" = DisconnectError,
        .inputs = struct {
            socket: *UdpSocket,
        },
    });

    pub const Send = IOP.define(.{
        .type = .udp_send,
        .@"error" = SendError,
        .inputs = struct {
            socket: *UdpSocket,
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
            socket: *UdpSocket,
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
            socket: *UdpSocket,
            buffer_ptr: [*]u8,
            buffer_len: usize,
        },
        .outputs = struct {
            bytes_received: usize,
            sender: EndPoint,
        },
    });

    pub const BindError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .AddressInUse = 3,
        .IllegalValue = 4,
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
    });

    pub const DisconnectError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .NotConnected = 3,
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
    });
};

pub const tcp = struct {
    pub const Bind = IOP.define(.{
        .type = .tcp_bind,
        .@"error" = BindError,
        .inputs = struct {
            socket: *TcpSocket,
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
            socket: *TcpSocket,
            target: EndPoint,
        },
    });

    pub const Send = IOP.define(.{
        .type = .tcp_send,
        .@"error" = SendError,
        .inputs = struct {
            socket: *TcpSocket,
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
            socket: *TcpSocket,
            buffer_ptr: [*]u8,
            buffer_len: usize,
            read_all: bool, // if true, will read until `buffer_len` bytes arrived. otherwise will read until the end of a single packet
        },
        .outputs = struct {
            bytes_received: usize,
        },
    });

    pub const BindError = ErrorSet(.{
        .InvalidHandle = 1,
        .SystemResources = 2,
        .AddressInUse = 3,
        .IllegalValue = 4,
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
    });
};

pub const input = struct {
    const Error = ErrorSet(.{
        .NonExclusiveAccess = 1,
        .InProgress = 2,
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

///////////////////////////////////////////////////////////
// Legacy:

// pub const NetworkStatus = enum(u8) {
//     disconnected = 0, // no cable is plugged in
//     mac_available = 1, // cable is plugged in and connected, no DHCP or static IP performed yet
//     ip_available = 2, // interface got at least one IP assigned
//     gateway_available = 3, // the gateway, if any, is reachable
// };

// pub const Ping = extern struct {
//     destination: IP, // who to ping
//     ttl: u16, // hops
//     timeout: u16, // ms, a minute timeout for ping is enough. if you have a higher ping, you have other problems
//     response: u16 = undefined, // response time in ms
// };
