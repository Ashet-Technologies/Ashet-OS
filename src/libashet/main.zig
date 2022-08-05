const std = @import("std");

pub const abi = @import("ashet-abi");

pub const syscalls = abi.SysCallInterface.get;

comptime {
    if (@hasDecl(@import("root"), "main")) {
        @export(_start, .{
            .linkage = .Strong,
            .name = "_start",
        });
    }
}

fn _start() callconv(.C) u32 {
    const res = @import("root").main();
    const Res = @TypeOf(res);

    if (@typeInfo(Res) == .ErrorUnion) {
        if (res) |unwrapped_res| {
            const UnwrappedRes = @TypeOf(unwrapped_res);

            if (UnwrappedRes == u32) {
                return unwrapped_res;
            } else if (UnwrappedRes == void) {
                return abi.ExitCode.success;
            } else {
                @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
            }
        } else |err| {
            std.log.err("main() returned the following error code: {s}", .{@errorName(err)});
            return abi.ExitCode.failure;
        }
    } else if (Res == u32) {
        return res;
    } else if (Res == void) {
        return abi.ExitCode.success;
    } else {
        @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
    }

    unreachable;
}

pub const core = struct {
    pub fn panic(msg: []const u8, maybe_stack_trace: ?*std.builtin.StackTrace) noreturn {
        _ = maybe_stack_trace;

        debug.write("PANIC: ");
        debug.write(msg);
        debug.write("\r\n");

        syscalls().process.exit(1);
    }

    pub fn log(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

        var writer = std.io.Writer(void, debug.WriteError, debug.writeString){ .context = {} };

        writer.print(level_txt ++ prefix2 ++ format ++ "\r\n", args) catch unreachable;
    }
};

pub const input = struct {
    pub const Event = union(enum) {
        keyboard: abi.KeyboardEvent,
        mouse: abi.MouseEvent,
    };

    pub fn getEvent() ?Event {
        var evt: abi.InputEvent = undefined;
        return switch (syscalls().input.getEvent(&evt)) {
            .none => null,
            .keyboard => Event{ .keyboard = evt.keyboard },
            .mouse => Event{ .mouse = evt.mouse },
        };
    }

    pub fn getMouseEvent() ?abi.MouseEvent {
        var evt: abi.MouseEvent = undefined;
        return if (syscalls().input.getMouseEvent(&evt))
            evt
        else
            null;
    }

    pub fn getKeyboardEvent() ?abi.KeyboardEvent {
        var evt: abi.KeyboardEvent = undefined;
        return if (syscalls().input.getKeyboardEvent(&evt))
            evt
        else
            null;
    }
};

pub const console = @import("console.zig");

pub const debug = struct {
    pub fn write(buffer: []const u8) void {
        for (buffer) |char| {
            @intToPtr(*volatile u8, 0x1000_0000).* = char;
        }
    }

    const WriteError = error{};
    fn writeString(_: void, buf: []const u8) WriteError!usize {
        write(buf);
        return buf.len;
    }
};

pub const process = struct {
    pub fn yield() void {
        syscalls().process.yield();
    }

    pub fn exit(code: u32) noreturn {
        syscalls().process.exit(code);
    }
};

pub const video = struct {
    pub fn setMode(mode: abi.VideoMode) void {
        syscalls().video.setMode(mode);
    }

    pub fn setBorder(color: abi.ColorIndex) void {
        syscalls().video.setBorder(color);
    }

    pub fn setResolution(width: u16, height: u16) void {
        syscalls().video.setResolution(width, height);
    }

    pub fn getVideoMemory() [*]align(4) abi.ColorIndex {
        return syscalls().video.getVideoMemory();
    }

    pub fn getPaletteMemory() *[abi.palette_size]u16 {
        return syscalls().video.getPaletteMemory();
    }
};

pub const fs = struct {
    pub const File = struct {
        pub const ReadError = error{};
        pub const WriteError = error{};
        pub const SeekError = error{Failed};
        pub const GetPosError = error{};

        pub const Reader = std.io.Reader(*File, ReadError, read);
        pub const Writer = std.io.Writer(*File, WriteError, write);
        pub const SeekableStream = std.io.SeekableStream(*File, SeekError, GetPosError, seekTo, seekBy, getPos, getEndPos);

        handle: abi.FileHandle,
        offset: u64,

        pub fn open(path: []const u8, access: abi.FileAccess, mode: abi.FileMode) !File {
            const handle = syscalls().fs.openFile(path.ptr, path.len, access, mode);
            if (handle == .invalid)
                return error.InvalidFile;
            return File{
                .handle = handle,
                .offset = 0,
            };
        }

        pub fn close(file: *File) void {
            syscalls().fs.close(file.handle);
            file.* = undefined;
        }

        pub fn read(file: *File, buffer: []u8) ReadError!usize {
            return syscalls().fs.read(file.handle, buffer.ptr, buffer.len);
        }

        pub fn write(file: *File, buffer: []const u8) WriteError!usize {
            return syscalls().fs.write(file.handle, buffer.ptr, buffer.len);
        }

        pub fn seekTo(file: *File, pos: u64) SeekError!void {
            if (!syscalls().fs.seekTo(file.handle, pos))
                return error.Failed;
            file.offset = pos;
        }

        pub fn seekBy(file: *File, delta: i64) SeekError!void {
            _ = file;
            _ = delta;
            @panic("not implemented yet");
        }

        pub fn getPos(file: *File) GetPosError!u64 {
            return file.offset;
        }
        pub fn getEndPos(file: *File) GetPosError!u64 {
            _ = file;
            @panic("not implemented");
        }

        pub fn reader(self: *File) Reader {
            return Reader{ .context = self };
        }

        pub fn writer(self: *File) Writer {
            return Writer{ .context = self };
        }

        pub fn seekableStream(self: *File) SeekableStream {
            return SeekableStream{ .context = self };
        }
    };
};