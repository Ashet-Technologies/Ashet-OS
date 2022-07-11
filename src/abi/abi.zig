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

    console: Console,
    video: Video,
    process: Process,
    fs: FileSystem,

    pub const Console = extern struct {
        clear: fn () callconv(.C) void,
        print: fn ([*]const u8, usize) callconv(.C) void,
    };

    pub const Video = extern struct {
        setMode: fn (VideoMode) callconv(.C) void,
        setBorder: fn (ColorIndex) callconv(.C) void,
        setResolution: fn (u16, u16) callconv(.C) void,
        getVideoMemory: fn () callconv(.C) [*]ColorIndex,
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
