const std = @import("std");
const builtin = @import("builtin");

pub const abi = @import("ashet-abi");
pub const userland = @import("ashet-abi-access");

pub const syscall = abi.syscall;

pub const is_hosted = builtin.is_test or (builtin.target.os.tag != .other and builtin.target.os.tag != .freestanding);

// comptime {
//     TODO:
//     if (builtin.target.os.tag == .freestanding) {
//         @compileError("OS tag '.freestanding' is legacy code and must not be used anymore. Apps now have to be compiled with OS tag '.other!'");
//     }
// }

fn _start() callconv(.C) u32 {
    const res = @import("root").main();
    const Res = @TypeOf(res);

    if (@typeInfo(Res) == .ErrorUnion) {
        if (res) |unwrapped_res| {
            const UnwrappedRes = @TypeOf(unwrapped_res);

            if (UnwrappedRes == u32) {
                return unwrapped_res;
            } else if (UnwrappedRes == void) {
                return @intFromEnum(abi.ExitCode.success);
            } else {
                @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
            }
        } else |err| {
            std.log.err("main() returned the following error code: {s}", .{@errorName(err)});
            return @intFromEnum(abi.ExitCode.failure);
        }
    } else if (Res == u32) {
        return res;
    } else if (Res == void) {
        return @intFromEnum(abi.ExitCode.success);
    } else {
        @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
    }

    unreachable;
}

fn log_app_message(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    const writer = process.debug.LogWriter{
        .context = switch (message_level) {
            .debug => .debug,
            .err => .err,
            .info => .notice,
            .warn => .warn,
        },
    };

    writer.print(level_txt ++ prefix2 ++ format ++ "\r\n", args) catch unreachable;
}

const GenericError = error{
    Unexpected,
    SystemResources,
};

pub const core = struct {
    var nested_panic: bool = false;

    comptime {
        if (!is_hosted) {
            if (@hasDecl(@import("root"), "main")) {
                @export(_start, .{
                    .linkage = .strong,
                    .name = "_start",
                });
            }
        }
    }

    pub const std_options = std.Options{
        .logFn = log_app_message,
    };

    fn write_panic_text(text: []const u8) void {
        process.debug.write_log(.critical, text);
    }

    pub fn panic(msg: []const u8, maybe_error_trace: ?*std.builtin.StackTrace, maybe_return_address: ?usize) noreturn {
        if (nested_panic) {
            write_panic_text("PANIC LOOP DETECTED: ");
            write_panic_text(msg);
            write_panic_text("\r\n");
            process.terminate(.failure);
        }
        nested_panic = true;

        write_panic_text("PANIC: ");
        write_panic_text(msg);
        write_panic_text("\r\n");

        const base_address = process.get_base_address(null);
        const proc_name = process.get_file_name(null);

        process.debug.log_writer(.critical).print("process base:  {s}:0x{X:0>8}\n", .{ proc_name, base_address }) catch {};

        if (maybe_return_address) |return_address| {
            var buf: [64]u8 = undefined;
            write_panic_text(std.fmt.bufPrint(&buf, "return address: {s}:0x{X:0>8}\n", .{ proc_name, return_address - base_address }) catch "return address: ???\n");
        }

        if (@import("builtin").mode == .Debug) {
            write_panic_text("stack trace:\n");
            var iter = std.debug.StackIterator.init(null, null);
            while (iter.next()) |item| {
                var buf: [64]u8 = undefined;
                write_panic_text(std.fmt.bufPrint(&buf, "- {s}:0x{X:0>8}\n", .{ proc_name, item - base_address }) catch "- ???\n");
            }
        }

        if (maybe_error_trace) |stack_trace| {
            write_panic_text("error trace:\n");
            var frame_index: usize = 0;
            var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);

            while (frames_left != 0) : ({
                frames_left -= 1;
                frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
            }) {
                const return_address = stack_trace.instruction_addresses[frame_index];
                process.debug.log_writer(.critical).print("- {s}:0x{X:0>8}\n", .{ proc_name, return_address - base_address }) catch {};
            }

            if (stack_trace.index > stack_trace.instruction_addresses.len) {
                const dropped_frames = stack_trace.index - stack_trace.instruction_addresses.len;
                process.debug.log_writer(.critical).print("({d} additional stack frames skipped...)\n", .{dropped_frames}) catch {};
            }
        }

        if (@import("builtin").mode == .Debug) {
            write_panic_text("breakpoint.\n");
            process.debug.breakpoint();
        }

        process.terminate(.failure);
    }
};

pub const process = struct {
    pub fn get_file_name(proc: ?abi.Process) [:0]const u8 {
        return std.mem.sliceTo(userland.process.get_file_name(proc), 0);
    }

    pub fn get_base_address(proc: ?abi.Process) usize {
        return userland.process.get_base_address(proc);
    }

    pub fn terminate(exit_code: abi.ExitCode) noreturn {
        userland.process.terminate(exit_code);
    }

    pub const debug = struct {
        pub const WriteError = error{};
        pub const LogWriter = std.io.Writer(abi.LogLevel, WriteError, _write_log);

        pub fn log_writer(log_level: abi.LogLevel) LogWriter {
            return .{ .context = log_level };
        }

        fn _write_log(log_level: abi.LogLevel, message: []const u8) WriteError!usize {
            write_log(log_level, message);
            return message.len;
        }

        pub fn write_log(log_level: abi.LogLevel, message: []const u8) void {
            userland.process.debug.write_log(log_level, message);
        }

        pub fn breakpoint() void {
            userland.process.debug.breakpoint();
        }
    };
};

pub const overlapped = struct {
    pub const ARC = abi.ARC;
    pub const WaitIO = abi.WaitIO;
    pub const ThreadAffinity = abi.ThreadAffinity;

    // pub fn scheduleAndAwait(start_queue: ?*IOP, wait: WaitIO) ?*IOP {
    //     const result = abi.syscalls.@"ashet.overlapped.scheduleAndAwait"(start_queue, wait);
    //     if (wait == .schedule_only)
    //         std.debug.assert(result == null);
    //     return result;
    // }

    pub fn cancel(event: *ARC) !void {
        try userland.arcs.cancel(event);
    }

    pub fn singleShot(op: anytype) !void {
        const Type = @TypeOf(op);
        const ti = @typeInfo(Type);
        if (comptime (ti != .Pointer or ti.Pointer.size != .One or !ARC.is_arc(ti.Pointer.child)))
            @compileError("singleShot expects a pointer to an ARC instance");
        const event: *ARC = &op.arc;

        try userland.overlapped.schedule(event);

        var completed: [1]*ARC = undefined;

        const count = try userland.overlapped.await_completion(&completed, .{
            .thread_affinity = .this_thread,
            .wait = .wait_one,
        });
        std.debug.assert(count == 1);
        std.debug.assert(completed[0] == event);

        try op.check_error();
    }

    pub fn performOne(comptime T: type, inputs: T.Inputs) (error{ Unexpected, SystemResources } || T.Error)!T.Outputs {
        var value = T.new(inputs);
        singleShot(&value) catch |err| switch (err) {
            error.AlreadyScheduled => unreachable,
            error.Unscheduled => unreachable,
            else => |e| return e,
        };
        return value.outputs;
    }
};

// pub const input = struct {
//     pub const Event = union(enum) {
//         keyboard: abi.KeyboardEvent,
//         mouse: abi.MouseEvent,
//     };

//     pub fn getEvent() !Event {
//         const out = try overlapped.performOne(abi.input.GetEvent, .{});
//         return switch (out.event_type) {
//             .keyboard => Event{ .keyboard = out.event.keyboard },
//             .mouse => Event{ .mouse = out.event.mouse },
//         };
//     }

//     pub fn getMouseEvent() abi.MouseEvent {
//         const out = try overlapped.performOne(abi.input.GetMouseEvent, .{});
//         return out.event;
//     }

//     pub fn getKeyboardEvent() abi.KeyboardEvent {
//         const out = try overlapped.performOne(abi.input.GetKeyboardEvent, .{});
//         return out.event;
//     }
// };

// pub const process = struct {
//     pub fn getBaseAddress() usize {
//         return abi.syscalls.@"ashet.process.getBaseAddress"();
//     }

//     pub fn getFileName() []const u8 {
//         return std.mem.sliceTo(abi.syscalls.@"ashet.process.getFileName"(), 0);
//     }

//     pub fn writeLog(level: abi.LogLevel, msg: []const u8) void {
//         abi.syscalls.@"ashet.process.writeLog"(level, msg.ptr, msg.len);
//     }

//     pub fn yield() void {
//         abi.syscalls.@"ashet.process.yield"();
//     }

//     pub fn exit(code: u32) noreturn {
//         abi.syscalls.@"ashet.process.exit"(code);
//     }

//     pub fn allocator() std.mem.Allocator {
//         return .{
//             .ptr = undefined,
//             .vtable = &allocator_vtable,
//         };
//     }

//     const allocator_vtable = std.mem.Allocator.VTable{
//         .alloc = globalAlloc,
//         .resize = globalResize,
//         .free = globalFree,
//     };

//     /// Attempt to allocate exactly `len` bytes aligned to `1 << ptr_align`.
//     ///
//     /// `ret_addr` is optionally provided as the first return address of the
//     /// allocation call stack. If the value is `0` it means no return address
//     /// has been provided.
//     fn globalAlloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
//         _ = ctx;
//         _ = ret_addr;
//         return abi.syscalls.@"ashet.process.memory.allocate"(len, ptr_align);
//     }

//     /// Attempt to expand or shrink memory in place. `buf.len` must equal the
//     /// length requested from the most recent successful call to `alloc` or
//     /// `resize`. `buf_align` must equal the same value that was passed as the
//     /// `ptr_align` parameter to the original `alloc` call.
//     ///
//     /// A result of `true` indicates the resize was successful and the
//     /// allocation now has the same address but a size of `new_len`. `false`
//     /// indicates the resize could not be completed without moving the
//     /// allocation to a different address.
//     ///
//     /// `new_len` must be greater than zero.
//     ///
//     /// `ret_addr` is optionally provided as the first return address of the
//     /// allocation call stack. If the value is `0` it means no return address
//     /// has been provided.
//     fn globalResize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
//         _ = ctx;
//         _ = buf;
//         _ = buf_align;
//         _ = new_len;
//         _ = ret_addr;
//         // TODO: Introduce process.memory.resize syscall
//         return false;
//     }

//     /// Free and invalidate a buffer.
//     ///
//     /// `buf.len` must equal the most recent length returned by `alloc` or
//     /// given to a successful `resize` call.
//     ///
//     /// `buf_align` must equal the same value that was passed as the
//     /// `ptr_align` parameter to the original `alloc` call.
//     ///
//     /// `ret_addr` is optionally provided as the first return address of the
//     /// allocation call stack. If the value is `0` it means no return address
//     /// has been provided.
//     fn globalFree(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
//         _ = ctx;
//         _ = ret_addr;
//         return abi.syscalls.@"ashet.process.memory.release"(buf.ptr, buf.len, buf_align);
//     }
// };

// pub const video = struct {
//     pub fn acquire() bool {
//         return abi.syscalls.@"ashet.video.acquire"();
//     }

//     pub fn release() void {
//         abi.syscalls.@"ashet.video.release"();
//     }

//     pub fn setBorder(color: abi.ColorIndex) void {
//         abi.syscalls.@"ashet.video.setBorder"(color);
//     }

//     pub fn setResolution(width: u16, height: u16) void {
//         abi.syscalls.@"ashet.video.setResolution"(width, height);
//     }

//     pub fn getVideoMemory() [*]align(4) abi.ColorIndex {
//         return abi.syscalls.@"ashet.video.getVideoMemory"();
//     }

//     pub fn getPaletteMemory() *[abi.palette_size]abi.Color {
//         return abi.syscalls.@"ashet.video.getPaletteMemory"();
//     }
// };

// pub const ui = struct {
//     pub const Window = abi.Window;
//     pub const CreateWindowFlags = abi.CreateWindowFlags;
//     pub const Size = abi.Size;
//     pub const Point = abi.Point;
//     pub const Rectangle = abi.Rectangle;
//     pub const Color = abi.Color;
//     pub const ColorIndex = abi.ColorIndex;

//     pub fn createWindow(title: []const u8, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) error{OutOfMemory}!*const Window {
//         return abi.syscalls.@"ashet.ui.createWindow"(title.ptr, title.len, min, max, startup, flags) orelse return error.OutOfMemory;
//     }
//     pub fn destroyWindow(win: *const Window) void {
//         abi.syscalls.@"ashet.ui.destroyWindow"(win);
//     }

//     pub fn moveWindow(win: *const Window, x: i16, y: i16) void {
//         abi.syscalls.@"ashet.ui.moveWindow"(win, x, y);
//     }

//     pub fn resizeWindow(win: *const Window, x: u16, y: u16) void {
//         abi.syscalls.@"ashet.ui.resizeWindow"(win, x, y);
//     }

//     pub fn setWindowTitle(win: *const Window, title: []const u8) void {
//         abi.syscalls.@"ashet.ui.setWindowTitle"(win, title.ptr, title.len);
//     }

//     pub fn getEvent(win: *const Window) Event {
//         const out = overlapped.performOne(abi.ui.GetEvent, .{ .window = win }) catch unreachable;
//         return constructEvent(out.event_type, out.event);
//     }

//     pub fn constructEvent(event_type: abi.UiEventType, event_data: abi.UiEvent) Event {
//         return switch (event_type) {
//             .mouse => .{ .mouse = event_data.mouse },
//             .keyboard => .{ .keyboard = event_data.keyboard },
//             .window_close => .window_close,
//             .window_minimize => .window_minimize,
//             .window_restore => .window_restore,
//             .window_moving => .window_moving,
//             .window_moved => .window_moved,
//             .window_resizing => .window_resizing,
//             .window_resized => .window_resized,
//         };
//     }

//     pub fn invalidate(win: *const Window, rect: Rectangle) void {
//         abi.syscalls.@"ashet.ui.invalidate"(win, rect);
//     }

//     pub fn getSystemFont(font_name: []const u8) ![]const u8 {
//         var out_slice: []const u8 = undefined;
//         const err = abi.syscalls.@"ashet.ui.getSystemFont"(font_name.ptr, font_name.len, &out_slice.ptr, &out_slice.len);
//         try abi.GetSystemFontError.throw(err);
//         return out_slice;
//     }

//     pub const Event = union(abi.UiEventType) {
//         mouse: abi.MouseEvent,
//         keyboard: abi.KeyboardEvent,
//         window_close,
//         window_minimize,
//         window_restore,
//         window_moving,
//         window_moved,
//         window_resizing,
//         window_resized,
//     };
// };

pub const fs = struct {
    pub const File = struct {
        pub const ReadError = abi.fs.Read.Error || GenericError;
        pub const WriteError = abi.fs.Write.Error || GenericError;
        pub const StatError = abi.fs.StatFile.Error || GenericError;
        pub const EmptyError = error{};

        pub const Reader = std.io.Reader(*File, ReadError, streamRead);
        pub const Writer = std.io.Writer(*File, WriteError, streamWrite);
        pub const SeekableStream = std.io.SeekableStream(*File, EmptyError, EmptyError, seekTo, seekBy, getPos, getEndPos);

        handle: abi.File,
        offset: u64,

        pub fn close(file: *File) void {
            _ = overlapped.performOne(abi.fs.CloseFile, .{ .file = file.handle }) catch |err| {
                std.log.scoped(.filesystem).err("failed to close file handle {}: {s}", .{ file.handle, @errorName(err) });
                return;
            };
            file.* = undefined;
        }

        pub fn flush(file: *File) !void {
            _ = try overlapped.performOne(abi.fs.file.Flush, .{ .file = file.handle });
        }

        fn streamRead(file: *File, buffer: []u8) ReadError!usize {
            const count = try file.read(file.offset, buffer);
            file.offset += count;
            return count;
        }

        fn streamWrite(file: *File, buffer: []const u8) WriteError!usize {
            const count = try file.write(file.offset, buffer);
            file.offset += count;
            return count;
        }

        pub fn read(file: File, offset: u64, buffer: []u8) ReadError!usize {
            const out = try overlapped.performOne(abi.fs.Read, .{
                .file = file.handle,
                .offset = offset,
                .buffer_ptr = buffer.ptr,
                .buffer_len = buffer.len,
            });
            return out.count;
        }

        pub fn write(file: File, offset: u64, buffer: []const u8) WriteError!usize {
            const out = try overlapped.performOne(abi.fs.Write, .{
                .file = file.handle,
                .offset = offset,
                .buffer_ptr = buffer.ptr,
                .buffer_len = buffer.len,
            });
            return out.count;
        }

        pub fn stat(file: File) StatError!abi.FileInfo {
            const out = try overlapped.performOne(abi.fs.StatFile, .{
                .file = file.handle,
            });
            return out.info;
        }

        fn seekTo(file: *File, pos: u64) !void {
            file.offset = pos;
        }

        fn seekBy(file: *File, delta: i64) !void {
            _ = file;
            _ = delta;
            @panic("not implemented yet");
        }

        fn getPos(file: *File) EmptyError!u64 {
            return file.offset;
        }

        fn getEndPos(file: *File) EmptyError!u64 {
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

    pub const Directory = struct {
        pub const OpenError = abi.fs.OpenDir.Error || GenericError;
        pub const OpenDriveError = abi.fs.OpenDrive.Error || GenericError;

        handle: abi.Directory,

        pub fn openDrive(filesystem: abi.FileSystemId, path: []const u8) OpenDriveError!Directory {
            const out = try overlapped.performOne(abi.fs.OpenDrive, .{
                .fs = filesystem,
                .path_ptr = path.ptr,
                .path_len = path.len,
            });
            return Directory{
                .handle = out.dir,
            };
        }

        pub fn openDir(dir: Directory, path: []const u8) OpenError!Directory {
            const out = try overlapped.performOne(abi.fs.OpenDir, .{
                .dir = dir.handle,
                .path_ptr = path.ptr,
                .path_len = path.len,
            });
            return Directory{
                .handle = out.dir,
            };
        }

        pub fn close(dir: *Directory) void {
            _ = overlapped.performOne(abi.fs.CloseDir, .{ .dir = dir.handle }) catch |err| {
                std.log.scoped(.filesystem).err("failed to close directory handle {}: {s}", .{ dir.handle, @errorName(err) });
                return;
            };

            dir.* = undefined;
        }

        pub const ResetError = abi.fs.ResetDirEnumerationError.Error || GenericError;
        pub fn reset(dir: *Directory) ResetError!void {
            _ = try overlapped.performOne(abi.fs.ResetDirEnumeration, .{ .dir = dir.handle });
        }

        pub const NextError = abi.fs.EnumerateDirError.Error || GenericError;
        pub fn next(dir: *Directory) NextError!?abi.FileInfo {
            const out = try overlapped.performOne(abi.fs.EnumerateDir, .{ .dir = dir.handle });

            return if (out.eof)
                null
            else
                out.info;
        }

        pub const OpenFileError = abi.fs.OpenFile.Error || GenericError;
        pub fn openFile(dir: Directory, path: []const u8, access: abi.FileAccess, mode: abi.FileMode) OpenFileError!File {
            const out = try overlapped.performOne(abi.fs.OpenFile, .{
                .dir = dir.handle,
                .path_ptr = path.ptr,
                .path_len = path.len,
                .access = access,
                .mode = mode,
            });
            return File{
                .handle = out.handle,
                .offset = 0,
            };
        }
    };
};

// pub const net = struct {
//     pub const EndPoint = abi.EndPoint;
//     pub const IP = abi.IP;
//     pub const IPv4 = abi.IPv4;
//     pub const IPv6 = abi.IPv6;

//     pub const Tcp = struct {
//         sock: abi.TcpSocket,

//         pub fn open() !Tcp {
//             var sock: abi.TcpSocket = undefined;
//             try abi.tcp.CreateError.throw(abi.syscalls.@"ashet.network.tcp.createSocket"(&sock));
//             return Tcp{ .sock = sock };
//         }

//         pub fn close(tcp: *Tcp) void {
//             abi.syscalls.@"ashet.network.tcp.destroySocket"(tcp.sock);
//             tcp.* = undefined;
//         }

//         pub fn bind(tcp: *Tcp, endpoint: EndPoint) !EndPoint {
//             const out = try overlapped.performOne(abi.tcp.Bind, .{
//                 .socket = tcp.sock,
//                 .bind_point = endpoint,
//             });
//             return out.bind_point;
//         }

//         pub fn connect(tcp: *Tcp, endpoint: EndPoint) !void {
//             _ = try overlapped.performOne(abi.tcp.Connect, .{
//                 .socket = tcp.sock,
//                 .target = endpoint,
//             });
//         }

//         pub fn write(tcp: *Tcp, data: []const u8) abi.tcp.Send.Error!usize {
//             const out = try overlapped.performOne(abi.tcp.Send, .{
//                 .socket = tcp.sock,
//                 .data_ptr = data.ptr,
//                 .data_len = data.len,
//             });
//             return out.bytes_sent;
//         }

//         pub fn read(tcp: *Tcp, buffer: []u8) abi.tcp.Receive.Error!usize {
//             const out = try overlapped.performOne(abi.tcp.Receive, .{
//                 .socket = tcp.sock,
//                 .buffer_ptr = buffer.ptr,
//                 .buffer_len = buffer.len,
//                 .read_all = false, // emulate classic read
//             });
//             return out.bytes_received;
//         }

//         pub const Writer = std.io.Writer(*Tcp, abi.tcp.Send.Error, write);
//         pub fn writer(tcp: *Tcp) Writer {
//             return Writer{ .context = tcp };
//         }

//         pub const Reader = std.io.Reader(*Tcp, abi.tcp.Receive.Error, read);
//         pub fn reader(tcp: *Tcp) Reader {
//             return Reader{ .context = tcp };
//         }
//     };

//     pub const Udp = struct {
//         const throw = abi.udp.BindError.throw;

//         sock: abi.UdpSocket,

//         pub fn open() !Udp {
//             var sock: abi.UdpSocket = undefined;
//             try abi.udp.CreateError.throw(abi.syscalls.@"ashet.network.udp.createSocket"(&sock));
//             return Udp{ .sock = sock };
//         }

//         pub fn close(udp: *Udp) void {
//             abi.syscalls.@"ashet.network.udp.destroySocket"(udp.sock);
//             udp.* = undefined;
//         }

//         pub fn bind(udp: Udp, ep: EndPoint) !EndPoint {
//             const out = try overlapped.performOne(abi.udp.Bind, .{
//                 .socket = udp.sock,
//                 .bind_point = ep,
//             });
//             return out.bind_point;
//         }

//         pub fn connect(udp: Udp, ep: EndPoint) !void {
//             _ = try overlapped.performOne(abi.udp.Connect, .{
//                 .socket = udp.sock,
//                 .target = ep,
//             });
//         }

//         pub fn disconnect(udp: Udp) !void {
//             _ = try overlapped.performOne(abi.udp.Disconnect, .{
//                 .socket = udp.sock,
//             });
//         }

//         pub fn send(udp: Udp, message: []const u8) !usize {
//             if (message.len == 0)
//                 return 0;
//             const out = try overlapped.performOne(abi.udp.Send, .{
//                 .socket = udp.sock,
//                 .data_ptr = message.ptr,
//                 .data_len = message.len,
//             });
//             return out.bytes_sent;
//         }

//         pub fn sendTo(udp: Udp, target: EndPoint, message: []const u8) !usize {
//             if (message.len == 0)
//                 return 0;
//             const out = try overlapped.performOne(abi.udp.SendTo, .{
//                 .socket = udp.sock,
//                 .receiver = target,
//                 .data_ptr = message.ptr,
//                 .data_len = message.len,
//             });
//             return out.bytes_sent;
//         }

//         pub fn receive(udp: Udp, data: []u8) !usize {
//             var dummy: EndPoint = undefined;
//             return try udp.receiveFrom(&dummy, data);
//         }

//         pub fn receiveFrom(udp: Udp, sender: *EndPoint, data: []u8) !usize {
//             if (data.len == 0)
//                 return 0;

//             const out = try overlapped.performOne(abi.udp.ReceiveFrom, .{
//                 .socket = udp.sock,
//                 .buffer_ptr = data.ptr,
//                 .buffer_len = data.len,
//             });
//             sender.* = out.sender;
//             return out.bytes_received;
//         }
//     };
// };

// pub const time = struct {
//     pub fn nanoTimestamp() i128 {
//         return abi.syscalls.@"ashet.time.nanoTimestamp"();
//     }
// };
