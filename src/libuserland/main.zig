const std = @import("std");

const abi = @import("ashet-abi");
const astd = @import("ashet-std");
const app = @import("app");
const libashet = @import("ashet");
const logger = std.log.scoped(.userland);

const sdl = @cImport({
    @cInclude("SDL.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

fn appThread() !void {
    try system_fonts.load();

    app.main() catch |err| {
        std.log.err("system failure: {s}", .{@errorName(err)});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.os.exit(1);
    };
    std.os.exit(0);
}

var host_root_dir: std.fs.Dir = undefined;
var sys_root_dir: std.fs.Dir = undefined;
var startup_root_dir: std.fs.Dir = undefined;

pub fn main() !void {
    defer _ = gpa.deinit();

    if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) != 0)
        @panic("sdl error");
    defer _ = sdl.SDL_Quit();

    host_root_dir = try std.fs.cwd().openDir("/", .{});
    defer host_root_dir.close();

    // TODO: Don't hardcode this!
    sys_root_dir = try std.fs.cwd().openDir("/home/felix/projects/ashet/os/rootfs", .{});
    defer sys_root_dir.close();

    startup_root_dir = try std.fs.cwd().openDir(".", .{});
    defer startup_root_dir.close();

    var thread = try std.Thread.spawn(.{}, appThread, .{});
    thread.detach();

    var next_dump = std.time.nanoTimestamp() + std.time.ns_per_s;

    while (true) {
        if (std.time.nanoTimestamp() > next_dump) {
            next_dump += std.time.ns_per_s;

            iop_schedule_queue.mutex.lock();
            defer iop_schedule_queue.mutex.unlock();

            var it = iop_schedule_queue.head;
            while (it) |node| : (it = node.next) {
                std.log.info("waiting iop: {}", .{node.type});
            }

            std.log.info("waiting iops: {}", .{@atomicLoad(u32, &iops_waiting, .SeqCst)});
        }

        var deferred_iops_start: ?*abi.IOP = null;
        var deferred_iops_end: ?*abi.IOP = null;
        while (iop_schedule_queue.popItem()) |raw_iop| {
            const type_map = .{
                // Timer
                .timer = abi.Timer,

                // TCP IOPs:
                .tcp_connect = abi.tcp.Connect,
                .tcp_bind = abi.tcp.Bind,
                .tcp_send = abi.tcp.Send,
                .tcp_receive = abi.tcp.Receive,

                // UDP IOPs:
                .udp_bind = abi.udp.Bind,
                .udp_connect = abi.udp.Connect,
                .udp_disconnect = abi.udp.Disconnect,
                .udp_send = abi.udp.Send,
                .udp_send_to = abi.udp.SendTo,
                .udp_receive_from = abi.udp.ReceiveFrom,

                // Input IOPS:
                .input_get_event = abi.input.GetEvent,

                // UI IOPS:
                .ui_get_event = abi.ui.GetEvent,

                //
                .fs_sync = abi.fs.Sync,
                .fs_open_drive = abi.fs.OpenDrive,
                .fs_open_dir = abi.fs.OpenDir,
                .fs_close_dir = abi.fs.CloseDir,
                .fs_reset_dir_enumeration = abi.fs.ResetDirEnumeration,
                .fs_enumerate_dir = abi.fs.EnumerateDir,
                .fs_delete = abi.fs.Delete,
                .fs_mkdir = abi.fs.MkDir,
                .fs_stat_entry = abi.fs.StatEntry,
                .fs_near_move = abi.fs.NearMove,
                .fs_far_move = abi.fs.FarMove,
                .fs_copy = abi.fs.Copy,
                .fs_open_file = abi.fs.OpenFile,
                .fs_close_file = abi.fs.CloseFile,
                .fs_flush_file = abi.fs.FlushFile,
                .fs_read = abi.fs.Read,
                .fs_write = abi.fs.Write,
                .fs_stat_file = abi.fs.StatFile,
                .fs_resize = abi.fs.Resize,
                .fs_get_filesystem_info = abi.fs.GetFilesystemInfo,
            };

            switch (raw_iop.type) {
                inline else => |tag| {
                    const iop = abi.IOP.cast(@field(type_map, @tagName(tag)), raw_iop);

                    const handlerFunction = @field(iop_handlers, @tagName(tag));
                    const err_or_result = handlerFunction(iop);
                    // @compileLog(tag, handlerFunction, @TypeOf(err_or_result));
                    if (err_or_result) |result| {
                        finalizeWithResult(iop, result);
                    } else |err| {
                        if (err == error.WouldBlock) {
                            // std.log.info("blocking on {}...", .{raw_iop.type});
                            raw_iop.next = null;
                            if (deferred_iops_start == null) {
                                deferred_iops_start = raw_iop;
                                deferred_iops_end = raw_iop;
                            } else {
                                deferred_iops_end.?.next = raw_iop;
                                deferred_iops_end = raw_iop;
                            }
                            continue;
                        } else {
                            std.log.err("iop {s} failed: {s}", .{
                                @tagName(raw_iop.type),
                                @errorName(err),
                            });
                        }
                        finalizeWithError(iop, err);
                    }
                },
            }
        }

        if (deferred_iops_start) |start| {
            iop_schedule_queue.appendList(start, false);
        }

        {
            Window.queue_lock.lock();
            defer Window.queue_lock.unlock();

            var event: sdl.SDL_Event = undefined;
            while (sdl.SDL_PollEvent(&event) != 0) {
                if (event.type == sdl.SDL_QUIT) {
                    std.os.exit(0);
                }
                switch (event.type) {
                    sdl.SDL_QUIT => unreachable,

                    sdl.SDL_MOUSEBUTTONDOWN => {
                        const window = windowFromSdl(event.button.windowID) orelse {
                            logger.warn("received event for dead window", .{});
                            continue;
                        };

                        window.pushEvent(.{ .mouse = .{
                            .type = .button_press,
                            .x = @divTrunc(@as(i16, @intCast(event.button.x)), 2),
                            .y = @divTrunc(@as(i16, @intCast(event.button.y)), 2),
                            .dx = 0,
                            .dy = 0,
                            .button = mapMouseButton(event.button.button) orelse continue,
                        } });
                    },
                    sdl.SDL_MOUSEBUTTONUP => {
                        const window = windowFromSdl(event.button.windowID) orelse {
                            logger.warn("received event for dead window", .{});
                            continue;
                        };

                        window.pushEvent(.{ .mouse = .{
                            .type = .button_release,
                            .x = @divTrunc(@as(i16, @intCast(event.button.x)), 2),
                            .y = @divTrunc(@as(i16, @intCast(event.button.y)), 2),
                            .dx = 0,
                            .dy = 0,
                            .button = mapMouseButton(event.button.button) orelse continue,
                        } });
                    },
                    sdl.SDL_MOUSEWHEEL => {
                        const window = windowFromSdl(event.wheel.windowID) orelse {
                            logger.warn("received event for dead window", .{});
                            continue;
                        };

                        if (event.wheel.y < 0) {
                            window.pushEvent(.{ .mouse = .{
                                .type = .button_release,
                                .x = @divTrunc(@as(i16, @intCast(event.wheel.x)), 2),
                                .y = @divTrunc(@as(i16, @intCast(event.wheel.y)), 2),
                                .dx = 0,
                                .dy = 0,
                                .button = .wheel_down,
                            } });
                        }
                        if (event.wheel.y > 0) {
                            window.pushEvent(.{ .mouse = .{
                                .type = .button_release,
                                .x = @divTrunc(@as(i16, @intCast(event.wheel.x)), 2),
                                .y = @divTrunc(@as(i16, @intCast(event.wheel.y)), 2),
                                .dx = 0,
                                .dy = 0,
                                .button = .wheel_up,
                            } });
                        }
                    },
                    sdl.SDL_MOUSEMOTION => {
                        const window = windowFromSdl(event.motion.windowID) orelse {
                            logger.warn("received event for dead window", .{});
                            continue;
                        };

                        if (event.wheel.y > 0) {
                            window.pushEvent(.{ .mouse = .{
                                .type = .motion,
                                .x = @divTrunc(@as(i16, @intCast(event.motion.x)), 2),
                                .y = @divTrunc(@as(i16, @intCast(event.motion.y)), 2),
                                .dx = @divTrunc(@as(i16, @intCast(event.motion.xrel)), 2),
                                .dy = @divTrunc(@as(i16, @intCast(event.motion.yrel)), 2),
                                .button = .none,
                            } });
                        }
                    },

                    sdl.SDL_WINDOWEVENT => {
                        const window = windowFromSdl(event.window.windowID) orelse {
                            logger.warn("received event for dead window", .{});
                            continue;
                        };

                        var w: c_int = 0;
                        var h: c_int = 0;
                        sdl.SDL_GetWindowSize(window.sdl_window, &w, &h);
                        window.abi_window.client_rectangle.width = @as(u16, @intCast(w)) / 2;
                        window.abi_window.client_rectangle.height = @as(u16, @intCast(h)) / 2;

                        switch (event.window.event) {
                            sdl.SDL_WINDOWEVENT_MOVED => window.pushEvent(.window_moved),
                            sdl.SDL_WINDOWEVENT_RESIZED, sdl.SDL_WINDOWEVENT_SIZE_CHANGED => {
                                window.pushEvent(.window_resizing);
                                window.pushEvent(.window_resized);
                            },
                            sdl.SDL_WINDOWEVENT_CLOSE => window.pushEvent(.window_close),

                            else => {},
                        }

                        //
                    },

                    else => {},
                }
            }

            var iter = Window.all_windows.first;
            while (iter) |window_node| : (iter = window_node.next) {
                const window: *Window = &window_node.data;

                if (!window.mutex.tryLock())
                    continue;
                defer window.mutex.unlock();

                _ = sdl.SDL_UpdateTexture(
                    window.sdl_texture,
                    null,
                    window.rgba_storage.ptr,
                    @as(c_int, @intCast(2 * window.abi_window.stride)),
                );

                _ = sdl.SDL_RenderClear(window.sdl_renderer);

                var src_rect = sdl.SDL_Rect{
                    .x = 0,
                    .y = 0,
                    .w = window.abi_window.client_rectangle.width,
                    .h = window.abi_window.client_rectangle.height,
                };

                var dst_rect = sdl.SDL_Rect{
                    .x = 0,
                    .y = 0,
                    .w = 2 * window.abi_window.client_rectangle.width,
                    .h = 2 * window.abi_window.client_rectangle.height,
                };
                _ = sdl.SDL_RenderCopy(window.sdl_renderer, window.sdl_texture, &src_rect, &dst_rect);

                sdl.SDL_RenderPresent(window.sdl_renderer);
            }
        }

        std.Thread.yield() catch {};
    }
}

fn windowFromSdl(id: u32) ?*Window {
    var iter = Window.all_windows.first;
    while (iter) |window_node| : (iter = window_node.next) {
        const window: *Window = &window_node.data;
        if (sdl.SDL_GetWindowID(window.sdl_window) == id)
            return window;
    }
    return null;
}
fn mapMouseButton(in: c_int) ?abi.MouseButton {
    return switch (in) {
        sdl.SDL_BUTTON_LEFT => .left,
        sdl.SDL_BUTTON_RIGHT => .right,
        sdl.SDL_BUTTON_MIDDLE => .middle,
        sdl.SDL_BUTTON_X1 => .nav_previous,
        sdl.SDL_BUTTON_X2 => .nav_next,
        else => null,
    };
}

var iops_waiting: u32 = 0;

const iop_schedule_queue = struct {
    var mutex: std.Thread.Mutex = .{};
    var head: ?*abi.IOP = null;
    var tail: ?*abi.IOP = null;

    pub fn appendList(list: ?*abi.IOP, increment: bool) void {
        mutex.lock();
        defer mutex.unlock();

        var iter = list;
        while (iter) |item| {
            iter = item.next;
            item.next = null;
            if (head == null) {
                head = item;
                tail = item;
            } else {
                tail.?.next = item;
                tail = item;
            }

            if (increment)
                _ = @atomicRmw(u32, &iops_waiting, .Add, 1, .SeqCst);
        }
    }

    pub fn remove(iop: *abi.IOP) void {
        mutex.lock();
        defer mutex.unlock();

        var prev: ?*abi.IOP = null;
        var iter = head;
        while (iter) |item| {
            defer prev = item;
            iter = item.next;

            if (item != iop)
                continue;

            if (head == item)
                head = item.next;
            if (tail == item)
                tail = prev;
            if (prev) |p|
                p.next = item.next;

            item.next = null;

            _ = @atomicRmw(u32, &iops_waiting, .Sub, 1, .SeqCst);

            return;
        }
    }

    pub fn popItem() ?*abi.IOP {
        mutex.lock();
        defer mutex.unlock();

        const h = head orelse return null;
        head = h.next;
        if (head == null) {
            tail = null;
        }
        h.next = null;
        return h;
    }
};

const iop_done_queue = struct {
    var mutex: std.Thread.Mutex = .{};
    var head: ?*abi.IOP = null;
    var tail: ?*abi.IOP = null;

    pub fn appendList(list: ?*abi.IOP) void {
        mutex.lock();
        defer mutex.unlock();

        var iter = list;
        while (iter) |item| {
            iter = item.next;
            item.next = null;
            if (head == null) {
                head = item;
                tail = item;
            } else {
                tail.?.next = item;
                tail = item;
            }
            _ = @atomicRmw(u32, &iops_waiting, .Sub, 1, .SeqCst);
        }
    }

    pub fn remove(iop: *abi.IOP) void {
        mutex.lock();
        defer mutex.unlock();

        var prev: ?*abi.IOP = null;
        var iter = head;
        while (iter) |item| {
            defer prev = item;
            iter = item.next;

            if (item != iop)
                continue;

            if (head == item)
                head = item.next;
            if (tail == item)
                tail = prev;
            if (prev) |p|
                p.next = item.next;

            item.next = null;

            _ = @atomicRmw(u32, &iops_waiting, .Sub, 1, .SeqCst);

            return;
        }
    }

    pub fn popDoneList() ?*abi.IOP {
        mutex.lock();
        defer mutex.unlock();

        const h = head orelse return null;
        head = h.next;
        if (tail == h) {
            std.debug.assert(head == null);
            tail = null;
        }
        h.next = null;
        return h;
    }
};

pub fn finalize(event: *abi.IOP) void {
    iop_done_queue.appendList(event);
}

pub fn finalizeWithError(generic: anytype, err: anyerror) void {
    if (!comptime abi.IOP.isIOP(@TypeOf(generic.*)))
        @compileError("finalizeWithError requires an IOP instance!");
    generic.outputs = undefined; // explicitly kill the content here in debug kernels
    generic.setError(astd.mapToUnexpected(@TypeOf(generic.*).Error, err));
    finalize(&generic.iop);
}

pub fn finalizeWithResult(generic: anytype, outputs: @TypeOf(generic.*).Outputs) void {
    if (!comptime abi.IOP.isIOP(@TypeOf(generic.*)))
        @compileError("finalizeWithError requires an IOP instance!");
    generic.outputs = outputs;
    generic.setOk();
    finalize(&generic.iop);
}

const File = struct {
    file: std.fs.File,
};

const Directory = struct {
    dir: std.fs.IterableDir,
    iter: std.fs.IterableDir.Iterator,
};

const file_handles = HandleAllocator(abi.FileHandle, File);
const directory_handles = HandleAllocator(abi.DirectoryHandle, Directory);

const filesystem_sys = abi.FileSystemId.system;
const filesystem_host = @as(abi.FileSystemId, @enumFromInt(1));
const filesystem_cwd = @as(abi.FileSystemId, @enumFromInt(2));

fn dateTimeFromTimestamp(ts: i128) abi.DateTime {
    return @as(i64, @intCast(@divTrunc(ts, std.time.ns_per_ms)));
}

fn IopReturnType(comptime IOP: type) type {
    const E = error{WouldBlock} || IOP.Error;
    return E!IOP.Outputs;
}

const iop_handlers = struct {
    pub fn timer(iop: *abi.Timer) IopReturnType(abi.Timer) {
        if (iop.inputs.timeout > time_nanoTimestamp())
            return error.WouldBlock;

        return .{};
    }

    pub fn tcp_connect(iop: *abi.tcp.Connect) IopReturnType(abi.tcp.Connect) {
        _ = iop;
        @panic("tcp_connect not implemented yet!");
    }

    pub fn tcp_bind(iop: *abi.tcp.Bind) IopReturnType(abi.tcp.Bind) {
        _ = iop;
        @panic("tcp_bind not implemented yet!");
    }

    pub fn tcp_send(iop: *abi.tcp.Send) IopReturnType(abi.tcp.Send) {
        _ = iop;
        @panic("tcp_send not implemented yet!");
    }

    pub fn tcp_receive(iop: *abi.tcp.Receive) IopReturnType(abi.tcp.Receive) {
        _ = iop;
        @panic("tcp_receive not implemented yet!");
    }

    pub fn udp_bind(iop: *abi.udp.Bind) IopReturnType(abi.udp.Bind) {
        _ = iop;
        @panic("udp_bind not implemented yet!");
    }

    pub fn udp_connect(iop: *abi.udp.Connect) IopReturnType(abi.udp.Connect) {
        _ = iop;
        @panic("udp_connect not implemented yet!");
    }

    pub fn udp_disconnect(iop: *abi.udp.Disconnect) IopReturnType(abi.udp.Disconnect) {
        _ = iop;
        @panic("udp_disconnect not implemented yet!");
    }

    pub fn udp_send(iop: *abi.udp.Send) IopReturnType(abi.udp.Send) {
        _ = iop;
        @panic("udp_send not implemented yet!");
    }

    pub fn udp_send_to(iop: *abi.udp.SendTo) IopReturnType(abi.udp.SendTo) {
        _ = iop;
        @panic("udp_send_to not implemented yet!");
    }

    pub fn udp_receive_from(iop: *abi.udp.ReceiveFrom) IopReturnType(abi.udp.ReceiveFrom) {
        _ = iop;
        @panic("udp_receive_from not implemented yet!");
    }

    pub fn input_get_event(iop: *abi.input.GetEvent) IopReturnType(abi.input.GetEvent) {
        _ = iop;
        @panic("input_get_event not implemented yet!");
    }

    pub fn ui_get_event(iop: *abi.ui.GetEvent) IopReturnType(abi.ui.GetEvent) {
        const window = Window.fromAbi(iop.inputs.window);
        const event = window.popEvent() orelse return error.WouldBlock;

        return .{
            .event_type = event,
            .event = switch (event) {
                .mouse => |data| .{ .mouse = data },
                .keyboard => |data| .{ .keyboard = data },
                else => undefined,
            },
        };
    }

    fn fs_sync(iop: *abi.fs.Sync) IopReturnType(abi.fs.Sync) {
        _ = iop;
        @panic("open_dir not implemented yet!");
    }

    fn fs_open_drive(iop: *abi.fs.OpenDrive) IopReturnType(abi.fs.OpenDrive) {
        const drive_dir = switch (iop.inputs.fs) {
            filesystem_sys => &sys_root_dir,
            filesystem_host => &host_root_dir,
            filesystem_cwd => &startup_root_dir,
            else => return error.InvalidFileSystem,
        };

        var dir = drive_dir.openIterableDir(iop.inputs.path_ptr[0..iop.inputs.path_len], .{}) catch |err| return try mapFileSystemError(err);
        errdefer dir.close();

        const handle = try directory_handles.alloc();
        errdefer directory_handles.free(handle);

        const backing = directory_handles.handleToBackingUnsafe(handle);

        backing.* = Directory{
            .dir = dir,
            .iter = dir.iterate(),
        };

        return .{ .dir = handle };
    }

    fn fs_open_dir(iop: *abi.fs.OpenDir) IopReturnType(abi.fs.OpenDir) {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        var dir = ctx.dir.dir.openIterableDir(iop.inputs.path_ptr[0..iop.inputs.path_len], .{}) catch |err| return try mapFileSystemError(err);

        const handle = try directory_handles.alloc();
        errdefer directory_handles.free(handle);

        const backing = directory_handles.handleToBackingUnsafe(handle);

        backing.* = Directory{
            .dir = dir,
            .iter = dir.iterate(),
        };

        return .{ .dir = handle };
    }

    fn fs_close_dir(iop: *abi.fs.CloseDir) IopReturnType(abi.fs.CloseDir) {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        ctx.dir.close();
        directory_handles.free(iop.inputs.dir);

        return .{};
    }

    fn fs_reset_dir_enumeration(iop: *abi.fs.ResetDirEnumeration) IopReturnType(abi.fs.ResetDirEnumeration) {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        ctx.iter = ctx.dir.iterate();

        return .{};
    }

    fn fs_enumerate_dir(iop: *abi.fs.EnumerateDir) IopReturnType(abi.fs.EnumerateDir) {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        const next_or_null: ?std.fs.IterableDir.Entry = ctx.iter.next() catch |err| return try mapFileSystemError(err);

        if (next_or_null) |info| {
            const stat = ctx.dir.dir.statFile(info.name) catch |err| return try mapFileSystemError(err);

            var namebuf = std.mem.zeroes([120]u8);
            std.mem.copyForwards(u8, &namebuf, info.name[0..std.math.min(info.name.len, namebuf.len)]);

            return .{
                .eof = false,
                .info = .{
                    .name = namebuf,
                    .size = stat.size,
                    .attributes = .{
                        .directory = (info.kind == .directory),
                    },
                    .creation_date = dateTimeFromTimestamp(stat.ctime),
                    .modified_date = dateTimeFromTimestamp(stat.mtime),
                },
            };
        } else {
            return .{ .eof = true, .info = undefined };
        }
    }

    fn fs_delete(iop: *abi.fs.Delete) IopReturnType(abi.fs.Delete) {
        _ = iop;
        @panic("fs.delete not implemented yet!");
    }

    fn fs_mkdir(iop: *abi.fs.MkDir) IopReturnType(abi.fs.MkDir) {
        _ = iop;
        @panic("fs.mkdir not implemented yet!");
    }

    fn fs_stat_entry(iop: *abi.fs.StatEntry) IopReturnType(abi.fs.StatEntry) {
        _ = iop;
        @panic("stat_entry not implemented yet!");
    }

    fn fs_near_move(iop: *abi.fs.NearMove) IopReturnType(abi.fs.NearMove) {
        _ = iop;
        @panic("fs.nearMove not implemented yet!");
    }

    fn fs_far_move(iop: *abi.fs.FarMove) IopReturnType(abi.fs.FarMove) {
        _ = iop;
        @panic("fs.farMove not implemented yet!");
    }

    fn fs_copy(iop: *abi.fs.Copy) IopReturnType(abi.fs.Copy) {
        _ = iop;
        @panic("fs.copy not implemented yet!");
    }

    fn fs_open_file(iop: *abi.fs.OpenFile) IopReturnType(abi.fs.OpenFile) {
        const ctx: *Directory = try directory_handles.resolve(iop.inputs.dir);

        var file = ctx.dir.dir.openFile(iop.inputs.path_ptr[0..iop.inputs.path_len], .{}) catch |err| return try mapFileSystemError(err);

        const handle = try file_handles.alloc();
        errdefer file_handles.free(handle);

        const backing = file_handles.handleToBackingUnsafe(handle);

        backing.* = File{
            .file = file,
        };

        return .{ .handle = handle };
    }

    fn fs_close_file(iop: *abi.fs.CloseFile) IopReturnType(abi.fs.CloseFile) {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);
        ctx.file.close();
        file_handles.free(iop.inputs.file);
        return .{};
    }

    fn fs_flush_file(iop: *abi.fs.FlushFile) IopReturnType(abi.fs.FlushFile) {
        _ = iop;
        @panic("flush_file not implemented yet!");
    }

    fn fs_read(iop: *abi.fs.Read) IopReturnType(abi.fs.Read) {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);

        ctx.file.seekTo(iop.inputs.offset) catch |err| return try mapFileSystemError(err);

        const len = ctx.file.readAll(
            iop.inputs.buffer_ptr[0..iop.inputs.buffer_len],
        ) catch |err| return try mapFileSystemError(err);

        return .{ .count = len };
    }

    fn fs_write(iop: *abi.fs.Write) IopReturnType(abi.fs.Write) {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);

        ctx.file.seekTo(iop.inputs.offset) catch |err| return try mapFileSystemError(err);

        ctx.file.writeAll(
            iop.inputs.buffer_ptr[0..iop.inputs.buffer_len],
        ) catch |err| return try mapFileSystemError(err);

        return .{ .count = iop.inputs.buffer_len };
    }

    fn fs_stat_file(iop: *abi.fs.StatFile) IopReturnType(abi.fs.StatFile) {
        const ctx: *File = try file_handles.resolve(iop.inputs.file);

        const meta = ctx.file.stat() catch |err| return try mapFileSystemError(err);

        var info = abi.FileInfo{
            .name = std.mem.zeroes([120]u8),
            .size = meta.size,
            .attributes = .{ .directory = false },
            .creation_date = dateTimeFromTimestamp(meta.ctime),
            .modified_date = dateTimeFromTimestamp(meta.mtime),
        };

        return .{ .info = info };
    }

    fn fs_resize(iop: *abi.fs.Resize) IopReturnType(abi.fs.Resize) {
        _ = iop;
        @panic("resize not implemented yet!");
    }

    fn fs_get_filesystem_info(iop: *abi.fs.GetFilesystemInfo) IopReturnType(abi.fs.GetFilesystemInfo) {
        _ = iop;
        @panic("fs_get_filesystem_info not implemented yet!");
    }
};

fn mapFileSystemError(err: anytype) !noreturn {
    const E = @TypeOf(err) || error{
        InvalidObject,
        DeviceError,
        OperationTimeout,
        WriteProtected,
        CorruptFilesystem,
        AccessDenied,
        Unseekable,
        BrokenPipe,
        ConnectionResetByPeer,
        DeviceBusy,
        DiskQuota,
        FileTooBig,
        InputOutput,
        InvalidArgument,
        LockViolation,
        NotOpenForWriting,
        OperationAborted,
        SystemResources,
        WouldBlock,
        ConnectionTimedOut,
        IsDir,
        NetNameDeleted,
        NotOpenForReading,
        BadPathName,
        FileBusy,
        FileLocksNotSupported,
        InvalidUtf8,
        NameTooLong,
        NoDevice,
        NotDir,
        PathAlreadyExists,
        PipeBusy,
        ProcessFdQuotaExceeded,
        SharingViolation,
        SymLinkLoop,
        InvalidHandle,
        FileNotFound,
        NoSpaceLeft,
        SystemFdQuotaExceeded,
    };

    return switch (@as(E, err)) {
        error.InvalidObject => error.DiskError,
        error.DeviceError => error.DiskError,
        error.OperationTimeout => error.DiskError,
        error.WriteProtected => error.DiskError,
        error.CorruptFilesystem => error.DiskError,
        error.AccessDenied => error.DiskError,
        error.Unseekable => error.DiskError,
        error.BrokenPipe => error.DiskError,
        error.ConnectionResetByPeer => error.DiskError,
        error.DeviceBusy => error.DiskError,
        error.DiskQuota => error.DiskError,
        error.FileTooBig => error.DiskError,
        error.InputOutput => error.DiskError,
        error.InvalidArgument => error.DiskError,
        error.LockViolation => error.DiskError,
        error.NotOpenForWriting => error.DiskError,
        error.OperationAborted => error.DiskError,
        error.SystemResources => error.DiskError,
        error.WouldBlock => error.DiskError,
        error.ConnectionTimedOut => error.DiskError,
        error.IsDir => error.DiskError,
        error.NetNameDeleted => error.DiskError,
        error.NotOpenForReading => error.DiskError,
        error.BadPathName => error.DiskError,
        error.FileBusy => error.DiskError,
        error.FileLocksNotSupported => error.DiskError,
        error.InvalidUtf8 => error.DiskError,
        error.NameTooLong => error.DiskError,
        error.NoDevice => error.DiskError,
        error.NotDir => error.DiskError,
        error.PathAlreadyExists => error.DiskError,
        error.PipeBusy => error.DiskError,
        error.ProcessFdQuotaExceeded => error.DiskError,
        error.SharingViolation => error.DiskError,
        error.SymLinkLoop => error.DiskError,
        error.InvalidHandle => unreachable,
        error.FileNotFound => error.DiskError,
        error.NoSpaceLeft => error.DiskError,
        error.SystemFdQuotaExceeded => error.DiskError,
        else => |e| return e,
    };
}

pub const syscall_table: abi.SysCallTable = .{
    .@"process.yield" = process_yield,
    .@"process.exit" = process_exit,
    .@"process.getBaseAddress" = process_getBaseAddress,
    .@"process.breakpoint" = process_breakpoint,
    .@"time.nanoTimestamp" = time_nanoTimestamp,
    .@"video.acquire" = video_acquire,
    .@"video.release" = video_release,
    .@"video.setBorder" = video_setBorder,
    .@"video.setResolution" = video_setResolution,
    .@"video.getVideoMemory" = video_getVideoMemory,
    .@"video.getPaletteMemory" = video_getPaletteMemory,
    .@"video.getPalette" = video_getPalette,
    .@"ui.createWindow" = ui_createWindow,
    .@"ui.destroyWindow" = ui_destroyWindow,
    .@"ui.moveWindow" = ui_moveWindow,
    .@"ui.resizeWindow" = ui_resizeWindow,
    .@"ui.setWindowTitle" = ui_setWindowTitle,
    .@"ui.invalidate" = ui_invalidate,
    .@"network.udp.createSocket" = network_udp_createSocket,
    .@"network.udp.destroySocket" = network_udp_destroySocket,
    .@"network.tcp.createSocket" = network_tcp_createSocket,
    .@"network.tcp.destroySocket" = network_tcp_destroySocket,
    .@"io.scheduleAndAwait" = io_scheduleAndAwait,
    .@"io.cancel" = io_cancel,
    .@"video.getMaxResolution" = video_getMaxResolution,
    .@"video.getResolution" = video_getResolution,
    .@"fs.findFilesystem" = fs_findFilesystem,
    .@"process.memory.allocate" = process_memory_allocate,
    .@"process.memory.release" = process_memory_release,
    .@"ui.getSystemFont" = @"ui.getSystemFont",
};

fn process_yield() callconv(.C) void {
    std.Thread.yield() catch {};
}

fn process_exit(exit_code: u32) callconv(.C) noreturn {
    std.os.exit(@as(u8, @truncate(exit_code)));
}

fn process_getBaseAddress() callconv(.C) usize {
    @panic("process_getBaseAddress not implemented yet!");
}

fn process_breakpoint() callconv(.C) void {
    @breakpoint();
}

fn time_nanoTimestamp() callconv(.C) i128 {
    return std.time.nanoTimestamp();
}

fn video_acquire() callconv(.C) bool {
    @panic("video_acquire not implemented yet!");
}
fn video_release() callconv(.C) void {
    @panic("video_release not implemented yet!");
}
fn video_setBorder(color: abi.ColorIndex) callconv(.C) void {
    _ = color;
    @panic("video_setBorder not implemented yet!");
}
fn video_setResolution(width: u16, height: u16) callconv(.C) void {
    _ = width;
    _ = height;
    @panic("video_setResolution not implemented yet!");
}
fn video_getVideoMemory() callconv(.C) [*]align(4) abi.ColorIndex {
    @panic("video_getVideoMemory not implemented yet!");
}
fn video_getPaletteMemory() callconv(.C) *[256]abi.Color {
    return &palette;
}
fn video_getPalette(pal: *[256]abi.Color) callconv(.C) void {
    pal.* = palette;
}

const UiEvent = union(abi.UiEventType) {
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

const Window = struct {
    var all_windows = std.TailQueue(Window){};
    var queue_lock: std.Thread.Mutex = .{};

    title0: [:0]u8,

    abi_window: abi.Window,

    sdl_window: *sdl.SDL_Window,
    sdl_renderer: *sdl.SDL_Renderer,
    sdl_texture: *sdl.SDL_Texture,

    rgba_storage: []abi.Color,
    index_storage: []abi.ColorIndex,

    mutex: std.Thread.Mutex = .{},
    events: std.TailQueue(UiEvent) = .{},
    pool: std.heap.MemoryPool(std.TailQueue(UiEvent).Node),

    fn fromAbi(win: *const abi.Window) *Window {
        const ptr = @fieldParentPtr(Window, "abi_window", win);
        return @constCast(ptr);
    }

    pub fn pushEvent(window: *Window, evt: UiEvent) void {
        {
            window.mutex.lock();
            defer window.mutex.unlock();

            const node = window.pool.create() catch return;
            node.* = .{ .data = evt };
            window.events.append(node);
        }

        if (window.events.len > 32)
            _ = window.popEvent(); // discard events that have started piling up

        // std.log.info("queue size up to {}", .{window.events.len});
    }

    pub fn popEvent(window: *Window) ?UiEvent {
        window.mutex.lock();
        defer window.mutex.unlock();

        const node = window.events.popFirst() orelse return null;

        const evt = node.data;

        window.pool.destroy(node);

        // std.log.info("queue size down to {}", .{window.events.len});

        return evt;
    }

    fn clampSizes(siz: abi.Size) abi.Size {
        return abi.Size.new(
            std.math.clamp(siz.width, 0, 1920),
            std.math.clamp(siz.height, 0, 1080),
        );
    }

    fn create(title: []const u8, _min_size: abi.Size, _max_size: abi.Size, init_size: abi.Size, flags: abi.CreateWindowFlags) !*const abi.Window {
        queue_lock.lock();
        defer queue_lock.unlock();

        const min_size = clampSizes(_min_size);
        const max_size = clampSizes(_max_size);

        const window_node = try allocator.create(std.TailQueue(Window).Node);
        errdefer allocator.destroy(window_node);

        window_node.* = .{
            .data = undefined,
        };

        const window = &window_node.data;

        window.* = Window{
            .title0 = undefined,
            .abi_window = undefined,
            .sdl_window = undefined,
            .sdl_renderer = undefined,
            .sdl_texture = undefined,
            .rgba_storage = undefined,
            .index_storage = undefined,
            .pool = std.heap.MemoryPool(std.TailQueue(UiEvent).Node).init(allocator),
        };
        errdefer window.pool.deinit();

        window.title0 = try allocator.dupeZ(u8, title);
        defer allocator.free(window.title0);

        window.sdl_window = sdl.SDL_CreateWindow(
            window.title0.ptr,
            sdl.SDL_WINDOWPOS_CENTERED,
            sdl.SDL_WINDOWPOS_CENTERED,
            2 * init_size.width,
            2 * init_size.height,
            @as(u32, @intCast(sdl.SDL_WINDOW_SHOWN | sdl.SDL_WINDOW_RESIZABLE | if (flags.popup) sdl.SDL_WINDOW_UTILITY else 0)),
        ) orelse @panic("err");
        errdefer sdl.SDL_DestroyWindow(window.sdl_window);

        sdl.SDL_SetWindowMinimumSize(window.sdl_window, 2 * min_size.width, 2 * min_size.height);
        sdl.SDL_SetWindowMaximumSize(window.sdl_window, 2 * max_size.width, 2 * max_size.height);

        window.sdl_renderer = sdl.SDL_CreateRenderer(
            window.sdl_window,
            -1,
            sdl.SDL_RENDERER_ACCELERATED,
        ) orelse @panic("error");
        errdefer sdl.SDL_DestroyRenderer(window.sdl_renderer);

        window.sdl_texture = sdl.SDL_CreateTexture(
            window.sdl_renderer,
            sdl.SDL_PIXELFORMAT_RGB565,
            sdl.SDL_TEXTUREACCESS_STREAMING,
            max_size.width,
            max_size.height,
        ) orelse @panic("sdl error");
        errdefer sdl.SDL_DestroyTexture(window.sdl_texture);

        const stride = @as(usize, max_size.width);
        const max_pixel_count = @as(usize, max_size.width) * @as(usize, max_size.height);

        window.rgba_storage = try allocator.alloc(abi.Color, max_pixel_count);
        errdefer allocator.free(window.rgba_storage);

        window.index_storage = try allocator.alloc(abi.ColorIndex, max_pixel_count);
        errdefer allocator.free(window.index_storage);

        @memset(window.index_storage, abi.ColorIndex.get(0));

        window.abi_window = abi.Window{
            .pixels = window.index_storage.ptr,
            .stride = @as(u32, @intCast(stride)),
            .client_rectangle = .{ .x = 0, .y = 0, .width = init_size.width, .height = init_size.height },
            .min_size = min_size,
            .max_size = max_size,
            .title = window.title0,
            .flags = .{
                .minimized = false,
                .focus = false,
                .popup = flags.popup,
            },
        };

        all_windows.append(window_node);

        return &window.abi_window;
    }

    fn destroy(window: *Window) void {
        window.mutex.lock();

        const window_node = @fieldParentPtr(std.TailQueue(Window).Node, "data", window);
        {
            queue_lock.lock();
            defer queue_lock.unlock();

            all_windows.remove(window_node);
        }

        std.time.sleep(100 * std.time.ns_per_us);

        sdl.SDL_DestroyTexture(window.sdl_texture);
        sdl.SDL_DestroyRenderer(window.sdl_renderer);
        sdl.SDL_DestroyWindow(window.sdl_window);

        allocator.free(window.rgba_storage);
        allocator.free(window.index_storage);

        // allocator.free(window.title0);
        window.pool.deinit();

        allocator.destroy(window_node);
    }
};

fn ui_createWindow(title_ptr: [*]const u8, title_len: usize, min_size: abi.Size, max_size: abi.Size, init_size: abi.Size, flags: abi.CreateWindowFlags) callconv(.C) ?*const abi.Window {
    const title = title_ptr[0..title_len];
    return Window.create(title, min_size, max_size, init_size, flags) catch null;
}

fn ui_destroyWindow(abi_window: *const abi.Window) callconv(.C) void {
    const window = Window.fromAbi(abi_window);
    window.destroy();
}

fn ui_moveWindow(window: *const abi.Window, x: i16, y: i16) callconv(.C) void {
    _ = window;
    _ = x;
    _ = y;
    @panic("ui_moveWindow not implemented yet!");
}

fn ui_resizeWindow(window: *const abi.Window, width: u16, height: u16) callconv(.C) void {
    _ = window;
    _ = width;
    _ = height;
    @panic("ui_resizeWindow not implemented yet!");
}

fn ui_setWindowTitle(window: *const abi.Window, title: [*]const u8, title_len: usize) callconv(.C) void {
    _ = window;
    _ = title;
    _ = title_len;
    @panic("ui_setWindowTitle not implemented yet!");
}

fn ui_invalidate(abi_window: *const abi.Window, rect: abi.Rectangle) callconv(.C) void {
    _ = rect;

    const window = Window.fromAbi(abi_window);

    for (window.rgba_storage, window.index_storage) |*color, index| {
        color.* = palette[@intFromEnum(index)];
    }
}

fn network_udp_createSocket(result: *abi.UdpSocket) callconv(.C) abi.udp.CreateError.Enum {
    _ = result;
    @panic("network_udp_createSocket not implemented yet!");
}

fn network_udp_destroySocket(sock: abi.UdpSocket) callconv(.C) void {
    _ = sock;
    @panic("network_udp_destroySocket not implemented yet!");
}

fn network_tcp_createSocket(out: *abi.TcpSocket) callconv(.C) abi.tcp.CreateError.Enum {
    _ = out;
    @panic("network_tcp_createSocket not implemented yet!");
}

fn network_tcp_destroySocket(sock: abi.TcpSocket) callconv(.C) void {
    _ = sock;
    @panic("network_tcp_destroySocket not implemented yet!");
}

fn io_scheduleAndAwait(new_tasks: ?*abi.IOP, wait: abi.WaitIO) callconv(.C) ?*abi.IOP {
    iop_schedule_queue.appendList(new_tasks, true);

    switch (wait) {
        .dont_block => {
            return iop_done_queue.popDoneList();
        },
        .schedule_only => {
            return null;
        },
        .wait_one => while (true) {
            var item = iop_done_queue.popDoneList();
            if (item != null) {
                return item;
            }
            std.Thread.yield() catch {};
        },
        .wait_all => {
            while (@atomicLoad(u32, &iops_waiting, .SeqCst) > 0) {
                std.Thread.yield() catch {};
            }
            return iop_done_queue.popDoneList();
        },
    }
}

fn io_cancel(iop: *abi.IOP) callconv(.C) void {
    iop_schedule_queue.remove(iop);
    iop_done_queue.remove(iop);
}

fn video_getMaxResolution() callconv(.C) abi.Size {
    @panic("video_getMaxResolution not implemented yet!");
}

fn video_getResolution() callconv(.C) abi.Size {
    @panic("video_getResolution not implemented yet!");
}

fn fs_findFilesystem(name_ptr: [*]const u8, name_len: usize) callconv(.C) abi.FileSystemId {
    _ = name_ptr;
    _ = name_len;
    @panic("fs_findFilesystem not implemented yet!");
}

fn process_memory_allocate(len: usize, ptr_align: u8) callconv(.C) ?[*]u8 {
    return gpa.allocator().rawAlloc(len, ptr_align, @returnAddress());
}

fn process_memory_release(buf: [*]u8, buf_len: usize, ptr_align: u8) callconv(.C) void {
    gpa.allocator().rawFree(buf[0..buf_len], ptr_align, @returnAddress());
}

var palette: [256]abi.Color = blk: {
    @setEvalBranchQuota(10_000);

    var pal = std.mem.zeroes([256]abi.Color);
    for (pal[0..default_palette.len], default_palette) |*dst, src| {
        const rgba = @as([4]u8, @bitCast(std.fmt.parseInt(u32, src, 16) catch unreachable));
        dst.* = abi.Color.fromRgb888(
            rgba[0],
            rgba[1],
            rgba[2],
        );
    }
    for (pal[default_palette.len..], 0..) |*dst, index| {
        dst.* = @as(abi.Color, @bitCast(@as(u16, @truncate(std.hash.CityHash32.hash(std.mem.asBytes(&@as(u32, @intCast(index))))))));
    }
    break :blk pal;
};

const default_palette = [_][]const u8{
    "000000",
    "2d1a71",
    "3e32d5",
    "af102e",
    "e4162b",
    "0e3e12",
    "38741a",
    "8d4131",
    "ffff40",
    "505d6d",
    "7b95a0",
    "a6cfd0",
    "b44cef",
    "e444c3",
    "00bc9f",
    "ffffff",
    "afe356",
    "2f3143",
    "fbc800",
    "6cb328",
    "0c101b",
    "0d384c",
    "140e1e",
    "177578",
    "190c12",
    "3257be",
    "353234",
    "409def",
    "480e55",
    "491d1e",
    "492917",
    "550e2b",
    "652bbc",
    "665d5b",
    "6becbd",
    "6e6aff",
    "70dbff",
    "941887",
    "97530f",
    "998d86",
    "9c2b3b",
    "a6adff",
    "aa2c1e",
    "bfffff",
    "c9fccc",
    "cb734d",
    "cdbfb3",
    "d8e0ff",
    "dd8c00",
    "dfeae4",
    "e45761",
    "e4fca2",
    "eae6da",
    "ec8cff",
    "efaf79",
    "f66d1e",
    "ff424f",
    "ff91e2",
    "ff9792",
    "ffae68",
    "ffcdff",
    "ffd5cf",
    "ffe1b5",
    "fff699",
};

const max_file_name_len = abi.max_file_name_len;
const max_fs_name_len = abi.max_fs_name_len;
const max_fs_type_len = abi.max_fs_type_len;

const max_open_files = 64;

fn HandleAllocator(comptime Handle: type, comptime Backing: type) type {
    return struct {
        const HandleType = std.meta.Tag(Handle);
        const HandleSet = std.bit_set.ArrayBitSet(u32, max_open_files);

        comptime {
            if (!std.math.isPowerOfTwo(max_open_files))
                @compileError("max_open_files must be a power of two!");
        }

        const handle_index_mask = max_open_files - 1;

        var generations = std.mem.zeroes([max_open_files]HandleType);
        var active_handles = HandleSet.initFull();
        var backings: [max_open_files]Backing = undefined;

        fn alloc() error{SystemFdQuotaExceeded}!Handle {
            if (active_handles.toggleFirstSet()) |index| {
                while (true) {
                    const generation = generations[index];
                    const numeric = generation *% max_open_files + index;

                    const handle = @as(Handle, @enumFromInt(numeric));
                    if (handle == .invalid) {
                        generations[index] += 1;
                        continue;
                    }
                    return handle;
                }
            } else {
                return error.SystemFdQuotaExceeded;
            }
        }

        fn resolve(handle: Handle) !*Backing {
            const index = try resolveIndex(handle);
            return &backings[index];
        }

        fn resolveIndex(handle: Handle) !usize {
            const numeric = @intFromEnum(handle);

            const index = numeric & handle_index_mask;
            const generation = numeric / max_open_files;

            if (generations[index] != generation)
                return error.InvalidHandle;

            return index;
        }

        fn handleToBackingUnsafe(handle: Handle) *Backing {
            return &backings[handleToIndexUnsafe(handle)];
        }

        fn handleToIndexUnsafe(handle: Handle) usize {
            const numeric = @intFromEnum(handle);
            return @as(usize, numeric & handle_index_mask);
        }

        fn free(handle: Handle) void {
            const numeric = @intFromEnum(handle);

            const index = numeric & handle_index_mask;
            const generation = numeric / max_open_files;

            if (generations[index] != generation) {
                std.log.err("freeFileHandle received invalid file handle: {}(index:{}, gen:{})", .{
                    numeric,
                    index,
                    generation,
                });
            } else {
                active_handles.set(index);
                generations[index] += 1;
            }
        }
    };
}

fn @"ui.getSystemFont"(font_name_ptr: [*]const u8, font_name_len: usize, font_data_ptr: *[*]const u8, font_data_len: *usize) callconv(.C) abi.GetSystemFontError.Enum {
    const font_name = font_name_ptr[0..font_name_len];

    const font_data = system_fonts.get(font_name) catch |err| {
        return abi.GetSystemFontError.map(err);
    };

    font_data_ptr.* = font_data.ptr;
    font_data_len.* = font_data.len;

    return .ok;
}

const system_fonts = struct {
    var arena: std.heap.ArenaAllocator = undefined;

    var fonts: std.StringArrayHashMap([]const u8) = undefined;

    fn load() !void {
        arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        fonts = std.StringArrayHashMap([]const u8).init(arena.allocator());
        errdefer fonts.deinit();

        var font_dir = try libashet.fs.Directory.openDrive(.system, "system/fonts");
        defer font_dir.close();

        while (try font_dir.next()) |ent| {
            if (ent.attributes.directory)
                continue;
            const file_name = ent.getName();
            if (!std.mem.endsWith(u8, file_name, ".font") or file_name.len <= 5)
                continue;

            var file = try font_dir.openFile(file_name, .read_only, .open_existing);
            defer file.close();

            loadAndAddFont(&file, file_name[0 .. file_name.len - 5]) catch |err| {
                std.log.err("failed to load font {s}: {s}", .{
                    file_name,
                    @errorName(err),
                });
            };
        }

        std.log.info("available system fonts:", .{});
        for (fonts.keys()) |name| {
            std.log.info("- {s}", .{name});
        }
    }

    fn loadAndAddFont(file: *libashet.fs.File, name: []const u8) !void {
        const name_dupe = try arena.allocator().dupe(u8, name);
        errdefer arena.allocator().free(name_dupe);

        const stat = try file.stat();

        if (stat.size > 1_000_000) // hard limit: 1 MB
            return error.OutOfMemory;

        const buffer = try arena.allocator().alloc(u8, @as(u32, @intCast(stat.size)));
        errdefer arena.allocator().free(buffer);

        const len = try file.read(0, buffer);
        if (len != buffer.len)
            return error.UnexpectedEndOfFile;

        try fonts.putNoClobber(name_dupe, buffer);
    }

    fn get(font_name: []const u8) error{FileNotFound}![]const u8 {
        return fonts.get(font_name) orelse return error.FileNotFound;
    }
};
