const std = @import("std");
const builtin = @import("builtin");

pub const abi = @import("ashet-abi");

pub const graphics = @import("libashet/graphics.zig");
pub const input = @import("libashet/input.zig");
pub const gui = @import("libashet/gui.zig");
pub const video = @import("libashet/video.zig");

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

    if (@typeInfo(Res) == .error_union) {
        if (res) |unwrapped_res| {
            const UnwrappedRes = @TypeOf(unwrapped_res);

            if (UnwrappedRes == u32) {
                return unwrapped_res;
            } else if (UnwrappedRes == void) {
                return @intFromEnum(abi.process.ExitCode.success);
            } else {
                @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
            }
        } else |err| {
            std.log.err("main() returned the following error code: {s}", .{@errorName(err)});
            return @intFromEnum(abi.process.ExitCode.failure);
        }
    } else if (Res == u32) {
        return res;
    } else if (Res == void) {
        return @intFromEnum(abi.process.ExitCode.success);
    } else {
        @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
    }

    unreachable;
}

fn log_app_message(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
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
                @export(&_start, .{
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

        const base_address = process.get_base_address(null) catch 0;
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
    pub fn get_file_name(proc: ?abi.Process) []const u8 {
        return abi.process.get_file_name(proc) catch "<undefined>";
    }

    pub fn get_base_address(proc: ?abi.Process) !usize {
        return try abi.process.get_base_address(proc);
    }

    pub fn get_arguments(proc: ?abi.Process, argv_buffer: []abi.SpawnProcessArg) ![]abi.SpawnProcessArg {
        const argv_len = try abi.process.get_arguments(proc, argv_buffer);
        return argv_buffer[0..argv_len];
    }

    pub fn terminate(exit_code: abi.process.ExitCode) noreturn {
        abi.process.terminate(exit_code);
    }

    pub const thread = struct {
        pub fn yield() void {
            abi.process.thread.yield();
        }
    };

    pub const mem = struct {
        pub fn allocator() std.mem.Allocator {
            return .{
                .ptr = undefined,
                .vtable = &allocator_vtable,
            };
        }

        const allocator_vtable = std.mem.Allocator.VTable{
            .alloc = globalAlloc,
            .resize = globalResize,
            .free = globalFree,
            .remap = globalRemap,
        };

        /// Attempt to allocate exactly `len` bytes aligned to `1 << ptr_align`.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn globalAlloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            _ = ctx;
            _ = ret_addr;
            return abi.process.memory.allocate(len, @intFromEnum(ptr_align)) catch return null;
        }

        /// Attempt to expand or shrink memory in place. `buf.len` must equal the
        /// length requested from the most recent successful call to `alloc` or
        /// `resize`. `buf_align` must equal the same value that was passed as the
        /// `ptr_align` parameter to the original `alloc` call.
        ///
        /// A result of `true` indicates the resize was successful and the
        /// allocation now has the same address but a size of `new_len`. `false`
        /// indicates the resize could not be completed without moving the
        /// allocation to a different address.
        ///
        /// `new_len` must be greater than zero.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn globalResize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            _ = ctx;
            _ = buf;
            _ = buf_align;
            _ = new_len;
            _ = ret_addr;
            // TODO: Introduce process.memory.resize syscall
            return false;
        }

        fn globalRemap(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            _ = memory;
            _ = alignment;
            _ = new_len;
            _ = ret_addr;
            return null;
        }

        /// Free and invalidate a buffer.
        ///
        /// `buf.len` must equal the most recent length returned by `alloc` or
        /// given to a successful `resize` call.
        ///
        /// `buf_align` must equal the same value that was passed as the
        /// `ptr_align` parameter to the original `alloc` call.
        ///
        /// `ret_addr` is optionally provided as the first return address of the
        /// allocation call stack. If the value is `0` it means no return address
        /// has been provided.
        fn globalFree(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
            _ = ctx;
            _ = ret_addr;
            return abi.process.memory.release(buf, @intFromEnum(buf_align));
        }
    };

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
            abi.process.debug.write_log(log_level, message);
        }

        pub fn breakpoint() void {
            abi.process.debug.breakpoint();
        }
    };
};

pub const overlapped = struct {
    pub const ARC = abi.overlapped.ARC;
    pub const Wait = abi.overlapped.Await_Options.Wait;
    pub const Thread_Affinity = abi.overlapped.Await_Options.Thread_Affinity;

    // pub fn scheduleAndAwait(start_queue: ?*IOP, wait: WaitIO) ?*IOP {
    //     const result = abi.syscalls.@"ashet.overlapped.scheduleAndAwait"(start_queue, wait);
    //     if (wait == .schedule_only)
    //         std.debug.assert(result == null);
    //     return result;
    // }

    pub fn schedule(event: *ARC) !void {
        try abi.overlapped.schedule(event);
    }

    pub fn await_completion(buffer: []*ARC, options: abi.Await_Options) ![]*ARC {
        const count = try abi.overlapped.await_completion(buffer, options);
        return buffer[0..count];
    }

    pub fn await_completion_of(buffer: []?*ARC) !usize {
        return try abi.overlapped.await_completion_of(buffer);
    }

    fn Awaited_Events_Enum(comptime Events: type) type {
        const info = @typeInfo(Events).@"struct";

        var items: [info.fields.len]std.builtin.Type.EnumField = undefined;
        for (&items, info.fields, 0..) |*enum_field, struct_field, i| {
            enum_field.* = .{
                .name = struct_field.name,
                .value = i,
            };
        }
        const EventEnum = @Type(.{
            .@"enum" = .{
                .tag_type = u32,
                .fields = &items,
                .decls = &.{},
                .is_exhaustive = true,
            },
        });

        return EventEnum;
    }

    fn Awaited_Events_Set(comptime Events: type) type {
        return std.enums.EnumSet(Awaited_Events_Enum(Events));
    }

    /// Awaits all provided asynchronous `events`.
    ///
    /// Returns a bit set with all bits set for the events that have completed.
    pub fn await_events(events: anytype) !Awaited_Events_Set(@TypeOf(events)) {
        const Events = @TypeOf(events);
        const info = @typeInfo(Events).@"struct";

        if (info.fields.len == 0)
            @compileError("Must await at least one event!");

        var completed: [info.fields.len]?*ARC = undefined;
        inline for (&completed, info.fields) |*event, field| {
            const value = @field(events, field.name);
            event.* = if (@TypeOf(value) == *ARC)
                value
            else
                &value.arc;
        }

        const count = try await_completion_of(&completed);

        var set = Awaited_Events_Set(Events).initEmpty();
        for (completed, 0..) |arc, i| {
            if (arc != null)
                set.insert(@enumFromInt(i));
        }
        std.debug.assert(set.count() == count);
        return set;
    }

    pub fn cancel(event: *ARC) !void {
        try abi.arcs.cancel(event);
    }

    pub fn singleShot(op: anytype) !void {
        const Type = @TypeOf(op);
        const ti = @typeInfo(Type);
        if (comptime (ti != .pointer or ti.pointer.size != .one or !ARC.is_arc(ti.pointer.child)))
            @compileError("singleShot expects a pointer to an ARC instance");
        const event: *ARC = &op.arc;

        try schedule(event);

        const completed = try await_events(.{ .event = event });
        std.debug.assert(completed.count() == 1);

        try op.check_error();
    }

    pub fn performOne(comptime T: type, inputs: T.Inputs) (error{ Unexpected, SystemResources } || T.Error)!T.Outputs {
        var value = T.new(inputs);
        singleShot(&value) catch |err| switch (err) {
            error.AlreadyScheduled => unreachable,
            error.Unscheduled => unreachable,
            error.InvalidOperation => unreachable,
            else => |e| return e,
        };
        return value.outputs;
    }
};

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
                .fs_id = filesystem,
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

        pub const ResetError = abi.fs.ResetDirEnumeration.Error || GenericError;
        pub fn reset(dir: *Directory) ResetError!void {
            _ = try overlapped.performOne(abi.fs.ResetDirEnumeration, .{ .dir = dir.handle });
        }

        pub const NextError = abi.fs.EnumerateDir.Error || GenericError;
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

pub const clock = struct {
    pub const Absolute = abi.Absolute;
    pub const Duration = abi.Duration;

    /// Returns the time since system startup.
    /// This clock is monotonically increasing.
    pub fn monotonic() Absolute {
        return abi.clock.monotonic();
    }

    pub const Timer = abi.clock.Timer;
};

pub const datetime = struct {
    pub const DateTime = abi.DateTime;

    pub const Alarm = abi.datetime.Alarm;

    pub fn now() DateTime {
        return abi.datetime.now();
    }
};
