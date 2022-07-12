const std = @import("std");

pub const abi = @import("ashet-abi");

pub const syscalls = abi.SysCallInterface.get;

export fn _start() linksection(".entry_point") callconv(.C) u32 {
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
        std.log.err("PANIC: {s}", .{msg});
        _ = maybe_stack_trace;
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

        writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch unreachable;
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

pub const console = struct {
    pub const WriteError = error{};

    pub fn clear() void {
        syscalls().console.clear();
    }

    fn writeRaw(_: void, buffer: []const u8) WriteError!usize {
        syscalls().console.print(buffer.ptr, buffer.len);
        return buffer.len;
    }

    pub const Writer = std.io.Writer(void, WriteError, writeRaw);

    pub fn writer() Writer {
        return Writer{ .context = {} };
    }

    pub fn write(buffer: []const u8) void {
        writer().writeAll(buffer) catch unreachable;
    }

    pub fn print(comptime fmt: []const u8, args: anytype) void {
        writer().print(fmt, args) catch unreachable;
    }
};

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

    pub fn getVideoMemory() [*]abi.ColorIndex {
        return syscalls().video.getVideoMemory();
    }

    pub fn getPaletteMemory() *[abi.palette_size]u16 {
        return syscalls().video.getPaletteMemory();
    }
};
