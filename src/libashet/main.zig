const std = @import("std");

pub const abi = @import("ashet-abi");

pub const syscall = abi.syscall;

comptime {
    if (!@import("builtin").is_test) {
        if (@hasDecl(@import("root"), "main")) {
            @export(_start, .{
                .linkage = .Strong,
                .name = "_start",
            });
        }
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
    pub fn panic(msg: []const u8, maybe_error_trace: ?*std.builtin.StackTrace, maybe_return_address: ?usize) noreturn {
        debug.write("PANIC: ");
        debug.write(msg);
        debug.write("\r\n");

        const base_address = syscall("process.getBaseAddress")();

        debug.writer().print("process base:  0x{X:0>8}\n", .{base_address}) catch {};

        if (maybe_return_address) |return_address| {
            var buf: [64]u8 = undefined;
            debug.write(std.fmt.bufPrint(&buf, "return address: 0x{X:0>8}\n", .{return_address - base_address}) catch "return address: ???\n");
        }

        if (@import("builtin").mode == .Debug) {
            debug.write("stack trace:\n");
            var iter = std.debug.StackIterator.init(null, null);
            while (iter.next()) |item| {
                var buf: [64]u8 = undefined;
                debug.write(std.fmt.bufPrint(&buf, "- 0x{X:0>8}\n", .{item - base_address}) catch "- ???\n");
            }
        }

        if (maybe_error_trace) |stack_trace| {
            debug.write("error trace:\n");
            var frame_index: usize = 0;
            var frames_left: usize = std.math.min(stack_trace.index, stack_trace.instruction_addresses.len);

            while (frames_left != 0) : ({
                frames_left -= 1;
                frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
            }) {
                const return_address = stack_trace.instruction_addresses[frame_index];
                debug.writer().print("- 0x{X:0>8}\n", .{return_address - base_address}) catch {};
            }

            if (stack_trace.index > stack_trace.instruction_addresses.len) {
                const dropped_frames = stack_trace.index - stack_trace.instruction_addresses.len;
                debug.writer().print("({d} additional stack frames skipped...)\n", .{dropped_frames}) catch {};
            }
        }

        if (@import("builtin").mode == .Debug) {
            debug.write("breakpoint.\n");
            syscall("process.breakpoint")();
        }

        syscall("process.exit")(1);
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

pub const io = struct {
    pub const IOP = abi.IOP;
    pub const WaitIO = abi.WaitIO;

    pub fn scheduleAndAwait(start_queue: ?*IOP, wait: WaitIO) ?*IOP {
        return syscall("io.scheduleAndAwait")(start_queue, wait);
    }

    pub fn cancel(event: *IOP) void {
        return syscall("io.cancel")(event);
    }

    pub fn singleShot(op: anytype) !void {
        const Type = @TypeOf(op);
        const ti = @typeInfo(Type);
        if (comptime (ti != .Pointer or ti.Pointer.size != .One or !IOP.isIOP(ti.Pointer.child)))
            @compileError("singleShot expects a pointer to an IOP instance");
        const event: *IOP = &op.iop;

        const result = io.scheduleAndAwait(event, .wait_all);
        std.debug.assert(result != null);
        std.debug.assert(result.? == event);

        try op.check();
    }

    pub fn performOne(comptime T: type, inputs: T.Inputs) T.Error!T.Outputs {
        var value = T.new(inputs);
        try singleShot(&value);
        return value.outputs;
    }
};

pub const input = struct {
    pub const Event = union(enum) {
        keyboard: abi.KeyboardEvent,
        mouse: abi.MouseEvent,
    };

    pub fn getEvent() !Event {
        const out = try io.performOne(abi.input.GetEvent, .{});
        return switch (out.event_type) {
            .keyboard => Event{ .keyboard = out.event.keyboard },
            .mouse => Event{ .mouse = out.event.mouse },
        };
    }

    pub fn getMouseEvent() abi.MouseEvent {
        const out = try io.performOne(abi.input.GetMouseEvent, .{});
        return out.event;
    }

    pub fn getKeyboardEvent() abi.KeyboardEvent {
        const out = try io.performOne(abi.input.GetKeyboardEvent, .{});
        return out.event;
    }
};

pub const console = @import("console.zig");

pub const debug = struct {
    pub fn write(buffer: []const u8) void {
        for (buffer) |char| {
            @intToPtr(*volatile u8, 0x1000_0000).* = char;
        }
    }

    pub const Writer = std.io.Writer(void, WriteError, writeString);
    pub fn writer() Writer {
        return Writer{ .context = {} };
    }

    const WriteError = error{};
    fn writeString(_: void, buf: []const u8) WriteError!usize {
        write(buf);
        return buf.len;
    }
};

pub const process = struct {
    pub fn yield() void {
        syscall("process.yield")();
    }

    pub fn exit(code: u32) noreturn {
        syscall("process.exit")(code);
    }
};

pub const video = struct {
    pub fn acquire() bool {
        return syscall("video.acquire")();
    }

    pub fn release() void {
        syscall("video.release")();
    }

    pub fn setBorder(color: abi.ColorIndex) void {
        syscall("video.setBorder")(color);
    }

    pub fn setResolution(width: u16, height: u16) void {
        syscall("video.setResolution")(width, height);
    }

    pub fn getVideoMemory() [*]align(4) abi.ColorIndex {
        return syscall("video.getVideoMemory")();
    }

    pub fn getPaletteMemory() *[abi.palette_size]u16 {
        return syscall("video.getPaletteMemory")();
    }
};

pub const ui = struct {
    pub const Window = abi.Window;
    pub const CreateWindowFlags = abi.CreateWindowFlags;
    pub const Size = abi.Size;
    pub const Point = abi.Point;
    pub const Rectangle = abi.Rectangle;
    pub const Color = abi.Color;
    pub const ColorIndex = abi.ColorIndex;

    pub fn createWindow(title: []const u8, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) error{OutOfMemory}!*const Window {
        return syscall("ui.createWindow")(title.ptr, title.len, min, max, startup, flags) orelse return error.OutOfMemory;
    }
    pub fn destroyWindow(win: *const Window) void {
        syscall("ui.destroyWindow")(win);
    }

    pub fn moveWindow(win: *const Window, x: i16, y: i16) void {
        syscall("ui.moveWindow")(win, x, y);
    }

    pub fn resizeWindow(win: *const Window, x: u16, y: u16) void {
        syscall("ui.resizeWindow")(win, x, y);
    }

    pub fn setWindowTitle(win: *const Window, title: []const u8) void {
        syscall("ui.setWindowTitle")(win, title.ptr, title.len);
    }

    pub fn getEvent(win: *const Window) Event {
        const out = io.performOne(abi.ui.GetEvent, .{ .window = win }) catch unreachable;

        return switch (out.event_type) {
            .mouse => .{ .mouse = out.event.mouse },
            .keyboard => .{ .keyboard = out.event.keyboard },
            .window_close => .window_close,
            .window_minimize => .window_minimize,
            .window_restore => .window_restore,
            .window_moving => .window_moving,
            .window_moved => .window_moved,
            .window_resizing => .window_resizing,
            .window_resized => .window_resized,
        };
    }
    pub fn invalidate(win: *const Window, rect: Rectangle) void {
        syscall("ui.invalidate")(win, rect);
    }

    pub const Event = union(abi.UiEventType) {
        mouse: abi.MouseEvent,
        keyboard: abi.KeyboardEvent,
        window_close,
        window_minimize,
        window_restore,
        window_moving,
        window_moved,
        window_resizing,
        window_resized,
    };
};

pub const fs = struct {
    pub const File = struct {
        pub const ReadError = abi.FileReadError.Error || error{Unexpected};
        pub const WriteError = abi.FileWriteError.Error || error{Unexpected};
        pub const SeekError = abi.FileSeekError.Error || error{Unexpected};
        pub const GetPosError = error{};

        pub const Reader = std.io.Reader(*File, ReadError, read);
        pub const Writer = std.io.Writer(*File, WriteError, write);
        pub const SeekableStream = std.io.SeekableStream(*File, SeekError, GetPosError, seekTo, seekBy, getPos, getEndPos);

        handle: abi.FileHandle,
        offset: u64,

        pub fn open(path: []const u8, access: abi.FileAccess, mode: abi.FileMode) !File {
            var handle: abi.FileHandle = undefined;
            try abi.FileOpenError.throw(syscall("fs.openFile")(path.ptr, path.len, access, mode, &handle));
            if (handle == .invalid)
                return error.InvalidFile;
            return File{
                .handle = handle,
                .offset = 0,
            };
        }

        pub fn close(file: *File) void {
            syscall("fs.close")(file.handle);
            file.* = undefined;
        }

        pub fn read(file: *File, buffer: []u8) !usize {
            var cnt: usize = 0;
            try abi.FileReadError.throw(syscall("fs.read")(file.handle, buffer.ptr, buffer.len, &cnt));
            return cnt;
        }

        pub fn write(file: *File, buffer: []const u8) !usize {
            var cnt: usize = 0;
            try abi.FileWriteError.throw(syscall("fs.write")(file.handle, buffer.ptr, buffer.len, &cnt));
            return cnt;
        }

        pub fn seekTo(file: *File, pos: u64) !void {
            try abi.FileSeekError.throw(syscall("fs.seekTo")(file.handle, pos));
            file.offset = pos;
        }

        pub fn seekBy(file: *File, delta: i64) !void {
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

pub const net = struct {
    pub const EndPoint = abi.EndPoint;
    pub const IP = abi.IP;
    pub const IPv4 = abi.IPv4;
    pub const IPv6 = abi.IPv6;

    pub const Tcp = struct {
        sock: abi.TcpSocket,

        pub fn open() !Tcp {
            var sock: abi.TcpSocket = undefined;
            try abi.tcp.CreateError.throw(syscall("network.tcp.createSocket")(&sock));
            return Tcp{ .sock = sock };
        }

        pub fn close(tcp: *Tcp) void {
            syscall("network.tcp.destroySocket")(tcp.sock);
            tcp.* = undefined;
        }

        pub fn bind(tcp: *Tcp, endpoint: EndPoint) !EndPoint {
            const out = try io.performOne(abi.tcp.Bind, .{
                .socket = tcp.sock,
                .bind_point = endpoint,
            });
            return out.bind_point;
        }

        pub fn connect(tcp: *Tcp, endpoint: EndPoint) !void {
            _ = try io.performOne(abi.tcp.Connect, .{
                .socket = tcp.sock,
                .target = endpoint,
            });
        }

        pub fn write(tcp: *Tcp, data: []const u8) abi.tcp.Send.Error!usize {
            const out = try io.performOne(abi.tcp.Send, .{
                .socket = tcp.sock,
                .data_ptr = data.ptr,
                .data_len = data.len,
            });
            return out.bytes_sent;
        }

        pub fn read(tcp: *Tcp, buffer: []u8) abi.tcp.Receive.Error!usize {
            const out = try io.performOne(abi.tcp.Receive, .{
                .socket = tcp.sock,
                .buffer_ptr = buffer.ptr,
                .buffer_len = buffer.len,
                .read_all = false, // emulate classic read
            });
            return out.bytes_received;
        }

        pub const Writer = std.io.Writer(*Tcp, abi.tcp.Send.Error, write);
        pub fn writer(tcp: *Tcp) Writer {
            return Writer{ .context = tcp };
        }

        pub const Reader = std.io.Reader(*Tcp, abi.tcp.Receive.Error, read);
        pub fn reader(tcp: *Tcp) Reader {
            return Reader{ .context = tcp };
        }
    };

    pub const Udp = struct {
        const throw = abi.udp.BindError.throw;

        sock: abi.UdpSocket,

        pub fn open() !Udp {
            var sock: abi.UdpSocket = undefined;
            try abi.udp.CreateError.throw(syscall("network.udp.createSocket")(&sock));
            return Udp{ .sock = sock };
        }

        pub fn close(udp: *Udp) void {
            syscall("network.udp.destroySocket")(udp.sock);
            udp.* = undefined;
        }

        pub fn bind(udp: Udp, ep: EndPoint) !EndPoint {
            const out = try io.performOne(abi.udp.Bind, .{
                .socket = udp.sock,
                .bind_point = ep,
            });
            return out.bind_point;
        }

        pub fn connect(udp: Udp, ep: EndPoint) !void {
            _ = try io.performOne(abi.udp.Connect, .{
                .socket = udp.sock,
                .target = ep,
            });
        }

        pub fn disconnect(udp: Udp) !void {
            _ = try io.performOne(abi.udp.Disconnect, .{
                .socket = udp.sock,
            });
        }

        pub fn send(udp: Udp, message: []const u8) !usize {
            if (message.len == 0)
                return 0;
            const out = try io.performOne(abi.udp.Send, .{
                .socket = udp.sock,
                .data_ptr = message.ptr,
                .data_len = message.len,
            });
            return out.bytes_sent;
        }

        pub fn sendTo(udp: Udp, target: EndPoint, message: []const u8) !usize {
            if (message.len == 0)
                return 0;
            const out = try io.performOne(abi.udp.SendTo, .{
                .socket = udp.sock,
                .receiver = target,
                .data_ptr = message.ptr,
                .data_len = message.len,
            });
            return out.bytes_sent;
        }

        pub fn receive(udp: Udp, data: []u8) !usize {
            var dummy: EndPoint = undefined;
            return try udp.receiveFrom(&dummy, data);
        }

        pub fn receiveFrom(udp: Udp, sender: *EndPoint, data: []u8) !usize {
            if (data.len == 0)
                return 0;

            const out = try io.performOne(abi.udp.ReceiveFrom, .{
                .socket = udp.sock,
                .buffer_ptr = data.ptr,
                .buffer_len = data.len,
            });
            sender.* = out.sender;
            return out.bytes_received;
        }
    };
};

pub const time = struct {
    pub fn nanoTimestamp() i128 {
        return syscall("time.nanoTimestamp")();
    }
};
