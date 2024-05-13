pub extern fn @"process.yield"() void;
pub extern fn @"process.exit"(u32) noreturn;
pub extern fn @"process.getBaseAddress"() usize;
pub extern fn @"process.breakpoint"() void;
pub extern fn @"process.getFileName"() [*:0]const u8;
pub extern fn @"process.writeLog"(log_level: LogLevel, ptr: [*]const u8, len: usize) void;

// Allocates memory pages from the system.
pub extern fn @"process.memory.allocate"(size: usize, ptr_align: u8) ?[*]u8;
pub extern fn @"process.memory.release"(ptr: [*]u8, size: usize, ptr_align: u8) void;

pub extern fn @"time.nanoTimestamp"() i128;

// Aquires direct access to the screen. When `true` is returned,
// this process has the sole access to the screen buffers.
pub extern fn @"video.acquire"() bool;

// Releases the access to the video and returns to desktop mode.
pub extern fn @"video.release"() void;

// Changes the border color of the screen. Parameter is an index into
// the palette.
pub extern fn @"video.setBorder"(ColorIndex) void;

// Sets the screen resolution. Legal values are between 1×1 and the platform specific
// maximum resolution returned by `video.getMaxResolution()`.
// Everything out of bounds will be clamped into that range.
pub extern fn @"video.setResolution"(u16, u16) void;

// Returns a pointer to linear video memory, row-major.
// Pixels rows will have a stride of the current video buffer width.
// The first pixel in the memory is the top-left pixel.
pub extern fn @"video.getVideoMemory"() [*]align(4) ColorIndex;

// Returns a pointer to the current palette. Changing this palette
// will directly change the associated colors on the screen.
pub extern fn @"video.getPaletteMemory"() *[palette_size]Color;

// Fetches a copy of the current system pallete.
pub extern fn @"video.getPalette"(*[palette_size]Color) void;

// Returns the maximum possible screen resolution.
pub extern fn @"video.getMaxResolution"() Size;

// Returns the current resolution
pub extern fn @"video.getResolution"() Size;

pub extern fn @"ui.createWindow"(title: [*]const u8, title_len: usize, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) ?*const Window;
pub extern fn @"ui.destroyWindow"(*const Window) void;
pub extern fn @"ui.moveWindow"(*const Window, x: i16, y: i16) void;
pub extern fn @"ui.resizeWindow"(*const Window, x: u16, y: u16) void;
pub extern fn @"ui.setWindowTitle"(*const Window, title: [*]const u8, title_len: usize) void;
pub extern fn @"ui.invalidate"(*const Window, rect: Rectangle) void;
pub extern fn @"ui.getSystemFont"(font_name_ptr: [*]const u8, font_name_len: usize, font_data_ptr: *[*]const u8, font_data_len: *usize) GetSystemFontError.Enum;

// resolves the dns entry `host` for the given `service`.
// - `host` is a legal dns entry
// - `port` is either a port number
// - `buffer` and `limit` define a structure where all resolved IPs can be stored.
// Function returns the number of host entries found or 0 if the host name could not be resolved.
// pub extern fn @"network.dns.resolve" (host: [*:0]const u8, port: u16, buffer: [*]EndPoint, limit: usize) usize;

// getStatus: FnPtr(fn () NetworkStatus),
// ping: FnPtr(fn ([*]Ping, usize) void),
// TODO: Implement NIC-specific queries (mac, ips, names, ...)

pub extern fn @"network.udp.createSocket"(result: *UdpSocket) udp.CreateError.Enum;
pub extern fn @"network.udp.destroySocket"(UdpSocket) void;

pub extern fn @"network.tcp.createSocket"(out: *TcpSocket) tcp.CreateError.Enum;
pub extern fn @"network.tcp.destroySocket"(TcpSocket) void;

// Starts new I/O operations and returns completed ones.
//
// If `start_queue` is given, the kernel will schedule the events in the kernel.
// All events in this queue must not be freed until they are returned by this function
// at a later point.
//
// The function will optionally block based on the `wait` parameter.
//
// The return value is the HEAD element of a linked list of completed I/O events.
pub extern fn @"io.scheduleAndAwait"(?*IOP, WaitIO) ?*IOP;

// Cancels a single I/O operation.
pub extern fn @"io.cancel"(*IOP) void;

// Finds a file system by name
pub extern fn @"fs.findFilesystem"(name_ptr: [*]const u8, name_len: usize) FileSystemId;
