const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../main.zig");
const abi = @import("ashet-abi");

const strace = std.log.scoped(.strace);

const ashet_abi_v2_impl = @import("ashet-abi-impl");

pub const SystemCall = ashet_abi_v2_impl.Syscall_ID;

comptime {
    // Force exports into existence:
    _ = exports;
}

pub var enable_trace: bool = false;

pub const exports = ashet_abi_v2_impl.create_exports(syscalls, callbacks);

const callbacks = struct {
    pub fn before_syscall(sc: SystemCall) void {
        if (enable_trace) {
            strace.info("{s}", .{@tagName(sc)});
        }
        ashet.stackCheck();
    }

    pub fn after_syscall(sc: SystemCall) void {
        _ = sc;
        ashet.stackCheck();
    }
};

pub const syscalls = struct {
    pub const resources = struct {
        pub fn get_type(src_handle: abi.SystemResource) !abi.SystemResource.Type {
            _, const resource = resolve_base_resource(src_handle) catch return error.BadHandle;
            return resource.type;
        }

        pub fn get_owners(src_handle: abi.SystemResource, maybe_owners: ?[]abi.Process) usize {
            _, const src = resolve_base_resource(src_handle) catch return 0;

            if (maybe_owners) |owners| {
                const limit = @min(src.owners.len, owners.len);
                var iter = src.owners.first;
                for (0..limit) |i| {
                    owners[i] = @ptrCast(iter.?.data.process); // TODO: Transform to handle here!
                    iter = iter.?.next;
                }
                return limit;
            } else {
                return src.owners.len;
            }
        }

        pub fn send_to_process(res: abi.SystemResource, proc: abi.Process) void {
            _ = res;
            _ = proc;
            @panic("not implemented yet");
        }

        pub fn release(src_handle: abi.SystemResource) void {
            const proc, const resource = resolve_base_resource(src_handle) catch return;

            const ownership = proc.resources.resolve(src_handle) catch return;

            resource.remove_owner(ownership);
        }

        pub fn destroy(src_handle: abi.SystemResource) void {
            _, const resource = resolve_base_resource(src_handle) catch return;
            resource.destroy();
        }
    };

    pub const process = struct {
        pub fn get_file_name(maybe_proc: ?abi.Process) [*:0]const u8 {
            const kproc = if (maybe_proc) |handle| blk: {
                _, const proc = resolve_typed_resource(ashet.multi_tasking.Process, handle.as_resource()) catch |err| {
                    return @errorName(err);
                };
                break :blk proc;
            } else getCurrentProcess();

            return kproc.name.ptr;
        }

        pub fn get_base_address(maybe_proc: ?abi.Process) usize {
            const kproc = if (maybe_proc) |handle| blk: {
                _, const proc = resolve_typed_resource(ashet.multi_tasking.Process, handle.as_resource()) catch {
                    // TODO: Log err
                    return 0;
                };
                break :blk proc;
            } else getCurrentProcess();

            return if (kproc.executable_memory) |mem|
                @intFromPtr(mem.ptr)
            else
                0x00;
        }

        pub fn get_arguments(proc: ?abi.Process, argv: ?[]abi.SpawnProcessArg) usize {
            _ = proc;
            _ = argv;
            @panic("not implemented yet");
        }

        pub fn terminate(exit_code: abi.ExitCode) noreturn {
            const proc = getCurrentProcess();

            proc.stay_resident = false;

            var thread_iter = proc.threads.first;
            while (thread_iter) |thread_node| : (thread_iter = thread_node.next) {
                thread_node.data.thread.kill();
            }
            _ = exit_code;

            ashet.scheduler.yield();
            @panic("terminator?");
        }

        pub fn kill(handle: abi.Process) void {
            _, const kproc = resolve_typed_resource(ashet.multi_tasking.Process, handle.as_resource()) catch return;
            if (!kproc.is_zombie()) {
                kproc.kill(.killed);
            }
        }

        pub const thread = struct {
            pub fn yield() void {
                ashet.scheduler.yield();
            }

            pub fn exit(exit_code: abi.ExitCode) noreturn {
                ashet.scheduler.exit(@intFromEnum(exit_code));
            }

            pub fn join(thr: abi.Thread) abi.ExitCode {
                _ = thr;
                @panic("not implemented yet");
            }

            pub fn spawn(function: abi.ThreadFunction, arg: ?*anyopaque, stack_size: usize) ?abi.Thread {
                _ = function;
                _ = arg;
                _ = stack_size;
                @panic("not implemented yet");
            }

            pub fn kill(thr: abi.Thread, exit_code: abi.ExitCode) void {
                _ = thr;
                _ = exit_code;
                @panic("not implemented yet");
            }
        };

        pub const debug = struct {
            pub fn write_log(log_level: abi.LogLevel, message: []const u8) void {
                const proc = getCurrentProcess();

                const logger = std.log.scoped(.userland);

                switch (log_level) {
                    .critical => logger.info("{s}(critical): {s}", .{ proc.name, message }),
                    .err => logger.info("{s}(err): {s}", .{ proc.name, message }),
                    .warn => logger.info("{s}(warn): {s}", .{ proc.name, message }),
                    .notice => logger.info("{s}(notice): {s}", .{ proc.name, message }),
                    .debug => logger.info("{s}(debug): {s}", .{ proc.name, message }),
                    _ => logger.info("{s}(unknown,{}): {s}", .{ proc.name, @intFromEnum(log_level), message }),
                }
            }
            pub fn breakpoint() void {
                const proc = getCurrentProcess();
                std.log.scoped(.userland).info("breakpoint in process {s}.", .{proc.name});

                var cont: bool = false;
                while (!cont) {
                    std.mem.doNotOptimizeAway(&cont);
                }
            }
        };

        pub const memory = struct {
            pub fn allocate(size: usize, ptr_align: u8) ?[*]u8 {
                const proc = getCurrentProcess();
                return proc.dynamic_allocator().rawAlloc(
                    size,
                    ptr_align,
                    @returnAddress(),
                );
            }
            pub fn release(mem: []u8, ptr_align: u8) void {
                const proc = getCurrentProcess();
                proc.dynamic_allocator().rawFree(
                    mem,
                    ptr_align,
                    @returnAddress(),
                );
            }
        };

        pub const monitor = struct {
            /// Queries all owned resources by a process.
            pub fn enumerate_processes(processes: ?[]abi.Process) usize {
                _ = processes;
                @panic("not done yet");
            }

            /// Queries all owned resources by a process.
            pub fn query_owned_resources(owner: abi.Process, reslist: ?[]abi.SystemResource) usize {
                _ = owner;
                _ = reslist;
                @panic("not done yet");
            }

            /// Returns the total number of bytes the process takes up in RAM.
            pub fn query_total_memory_usage(proc: abi.Process) usize {
                _ = proc;
                @panic("not done yet");
            }

            /// Returns the number of dynamically allocated bytes for this process.
            pub fn query_dynamic_memory_usage(proc: abi.Process) usize {
                _ = proc;
                @panic("not done yet");
            }

            /// Returns the number of total memory objects this process has right now.
            pub fn query_active_allocation_count(proc: abi.Process) usize {
                _ = proc;
                @panic("not done yet");
            }
        };
    };

    pub const clock = struct {
        pub fn monotonic() u64 {
            return @intFromEnum(ashet.time.Instant.now());
        }
    };

    pub const datetime = struct {
        pub fn now() abi.DateTime {
            return @enumFromInt(ashet.time.milliTimestamp());
        }
    };

    pub const video = struct {
        pub fn enumerate(ids: ?[]abi.VideoOutputID) usize {
            _ = ids;
            @panic("not implemented yet");
        }

        pub fn acquire(output: abi.VideoOutputID) ?abi.VideoOutput {
            _ = output;
            @panic("not implemented yet");
        }

        pub fn get_resolution(output: abi.VideoOutput) abi.Size {
            _ = output;
            @panic("not implemented yet");
        }

        pub fn get_video_memory(output: abi.VideoOutput) [*]align(4) abi.ColorIndex {
            _ = output;
            @panic("not implemented yet");
        }

        pub fn get_palette(output: abi.VideoOutput, palette: *[abi.palette_size]abi.Color) void {
            _ = output;
            _ = palette;
            @panic("not implemented yet");
        }

        pub fn set_palette(output: abi.VideoOutput, palette: *const [abi.palette_size]abi.Color) error{Unsupported} {
            _ = output;
            _ = palette;
            @panic("not implemented yet");
        }
    };

    pub const overlapped = struct {
        pub fn schedule(async_call: *abi.ARC) error{ SystemResources, AlreadyScheduled }!void {
            return try ashet.overlapped.schedule(async_call);
        }

        pub fn await_completion(completed: []*abi.ARC, options: abi.Await_Options) error{Unscheduled}!usize {
            return try ashet.overlapped.await_completion(completed, options);
        }

        pub fn cancel(arc: *abi.ARC) error{ Unscheduled, Completed }!void {
            return try ashet.overlapped.cancel(arc);
        }
    };

    pub const draw = struct {
        // Fonts:

        /// Returns the font data for the given font name, if any.
        pub fn get_system_font(font_name: []const u8) error{
            FileNotFound,
            SystemResources,
            OutOfMemory,
        }!abi.Font {
            _ = font_name;
            @panic("not implemented yet");
        }

        /// Creates a new custom font from the given data.
        pub fn create_font(data: []const u8) error{
            InvalidData,
            SystemResources,
            OutOfMemory,
        }!abi.Font {
            _ = data;
            @panic("not implemented yet");
        }

        /// Returns true if the given font is a system-owned font.
        pub fn is_system_font(font: abi.Font) bool {
            _ = font;
            @panic("not implemented  yet!");
        }

        // Framebuffer management:

        /// Creates a new in-memory framebuffer that can be used for offscreen painting.
        pub fn create_memory_framebuffer(size: abi.Size) error{SystemResources}!abi.Framebuffer {
            _ = size;
            @panic("not implemented yet!");
        }

        /// Creates a new framebuffer based off a video output. Can be used to output pixels
        /// to the screen.
        pub fn create_video_framebuffer(video_output: abi.VideoOutput) error{SystemResources}!abi.Framebuffer {
            _ = video_output;
            @panic("not implemented  yet!");
        }

        /// Creates a new framebuffer that allows painting into a GUI window.
        pub fn create_window_framebuffer(window: abi.Window) error{SystemResources}!abi.Framebuffer {
            _ = window;
            @panic("not implemented  yet!");
        }

        /// Creates a new framebuffer that allows painting into a widget.
        pub fn create_widget_framebuffer(widget: abi.Widget) error{SystemResources}!abi.Framebuffer {
            _ = widget;
            @panic("not implemented  yet!");
        }

        /// Returns the type of a framebuffer object.
        pub fn get_framebuffer_type(framebuffer: abi.Framebuffer) abi.FramebufferType {
            _ = framebuffer;
            @panic("not implemented  yet!");
        }

        /// Returns the size of a framebuffer object.
        pub fn get_framebuffer_size(framebuffer: abi.Framebuffer) abi.Size {
            _ = framebuffer;
            @panic("not implemented  yet!");
        }

        /// Marks a portion of the framebuffer as changed and forces the OS to
        /// perform an update action if necessary.
        pub fn invalidate_framebuffer(framebuffer: abi.Framebuffer, rect: abi.Rectangle) void {
            _ = framebuffer;
            _ = rect;
            @panic("not implemented  yet!");
        }

        // Drawing:

        // TODO: fn annotate_text(*Framebuffer, area: Rectangle, text: []const u8) AnnotationError;

        // TODO: Insert render functions here
    };

    pub const gui = struct {
        pub fn register_widget_type(desc: *const abi.WidgetDescriptor) error{
            AlreadyRegistered,
            SystemResources,
        }!abi.WidgetType {
            _ = desc;
            @panic("not implemented yet");
        }

        // Window API:

        /// Spawns a new window.
        pub fn create_window(
            desktop: abi.Desktop,
            title: []const u8,
            min: abi.Size,
            max: abi.Size,
            startup: abi.Size,
            flags: abi.CreateWindowFlags,
        ) error{
            SystemResources,
            InvalidDimensions,
        }!abi.Window {
            _ = desktop;
            _ = title;
            _ = min;
            _ = max;
            _ = startup;
            _ = flags;
            @panic("not implemented yet");
        }

        /// Resizes a window to the new size.
        pub fn resize_window(window: abi.Window, size: abi.Size) void {
            _ = window;
            _ = size;
            @panic("not implemented yet");
        }

        /// Changes a window title.
        pub fn set_window_title(window: abi.Window, title: []const u8) void {
            _ = window;
            _ = title;
            @panic("not implemented yet");
        }

        /// Notifies the desktop that a window wants attention from the user.
        /// This could just pop the window to the front, make it blink, show a small notification, ...
        pub fn mark_window_urgent(window: abi.Window) void {
            _ = window;
            @panic("not implemented yet");
        }

        // TODO: gui.app_menu

        // Widget API:

        /// Create a new widget identified by `uuid` on the given `window`.
        /// Position and size of the widget are undetermined at start and a call to `place_widget` should be performed on success.
        pub fn create_widget(window: abi.Window, uuid: *const abi.UUID) error{
            SystemResources,
            WidgetNotFound,
        }!abi.Widget {
            _ = window;
            _ = uuid;
            @panic("not implemented yet");
        }

        /// Moves and resizes a widget in one.
        pub fn place_widget(widget: abi.Widget, position: abi.Point, size: abi.Size) void {
            _ = widget;
            _ = position;
            _ = size;
            @panic("not implemented yet");
        }

        /// Triggers the `control` event of the widget with the given `message` as a payload.
        pub fn control_widget(widget: abi.Widget, message: abi.WidgetControlMessage) error{
            SystemResources,
        } {
            _ = widget;
            _ = message;
            @panic("not implemented yet");
        }

        /// Triggers the `widget_notify` event of the `Window` that owns `widget` with `event` as the payload.
        pub fn notify_owner(widget: abi.Widget, event: abi.WidgetNotifyEvent) error{
            SystemResources,
        } {
            _ = widget;
            _ = event;
            @panic("not implemented yet");
        }

        /// Returns WidgetType-associated "opaque" data for this widget.
        ///
        /// This is meant as a convenience tool to store additional information per widget
        /// like internal state and such.
        ///
        /// The size of this must be known and cannot be queried.
        pub fn get_widget_data(widget: abi.Widget) [*]align(16) u8 {
            _ = widget;
            @panic("not implemented yet");
        }

        // Context Menu API:

        // TODO: gui.context_menu

        // Desktop Server API:

        /// Creates a new desktop with the given name.
        pub fn create_desktop(
            /// User-visible name of the desktop.
            name: []const u8,
            descriptor: *const abi.DesktopDescriptor,
        ) error{
            SystemResources,
        }!abi.Desktop {
            _ = name;
            _ = descriptor;
            @panic("not implemented yet");
        }

        // TODO: Function to get the "current"/"primary"/"associated" desktop server, how?

        /// Returns the name of the provided desktop.
        pub fn get_desktop_name(desktop: abi.Desktop) [*:0]const u8 {
            _ = desktop;
            @panic("not implemented yet");
        }

        /// Enumerates all available desktops.
        pub fn enumerate_desktops(serverlist: ?[]abi.Desktop) usize {
            _ = serverlist;
            @panic("not implemented yet");
        }

        /// Returns all windows for a desktop handle.
        pub fn enumerate_desktop_windows(desktop: abi.Desktop, windows: ?[]abi.Window) usize {
            _ = desktop;
            _ = windows;
            @panic("not implemented yet");
        }

        /// Returns desktop-associated "opaque" data for this window.
        ///
        /// This is meant as a convenience tool to store additional information per window
        /// like position on the screen, orientation, alignment, ...
        ///
        /// The size of this must be known and cannot be queried.
        pub fn get_desktop_data(window: abi.Window) [*]align(16) u8 {
            _ = window;
            @panic("not implemented yet");
        }

        /// Notifies the system that a message box was confirmed by the user.
        ///
        /// **NOTE:** This function is meant to be implemented by a desktop server.
        /// Regular GUI applications should not use this function as they have no
        /// access to a `MessageBoxEvent.RequestID`.
        pub fn notify_message_box(
            /// The desktop that completed the message box.
            source: abi.Desktop,
            /// The request id that was passed in `MessageBoxEvent`.
            request_id: abi.MessageBoxEvent.RequestID,
            /// The resulting button which the user clicked.
            result: abi.MessageBoxResult,
        ) void {
            _ = source;
            _ = request_id;
            _ = result;
            @panic("not implemented yet");
        }

        /// Posts an event into the window event queue so the window owner
        /// can handle the event.
        pub fn post_window_event(
            window: abi.Window,
            event: abi.WindowEvent,
        ) error{SystemResources} {
            _ = window;
            _ = event;

            @panic("not implemented yet");
        }

        /// Sends a notification to the provided `desktop`.
        pub fn send_notification(
            /// Where to show the notification?
            desktop: abi.Desktop,
            /// What text is displayed in the notification?
            message: []const u8,
            /// How urgent is the notification to the user?
            severity: abi.NotificationSeverity,
        ) error{
            SystemResources,
        } {
            _ = desktop;
            _ = message;
            _ = severity;
            @panic("not implemented yet");
        }

        pub const clipboard = struct {
            /// Sets the contents of the clip board.
            /// Takes a mime type as well as the value in the provided format.
            pub fn set(desktop: abi.Desktop, mime: []const u8, value: []const u8) error{
                SystemResources,
            } {
                _ = desktop;
                _ = mime;
                _ = value;
                @panic("not implemented yet");
            }

            /// Returns the current type present in the clipboard, if any.
            pub fn get_type(desktop: abi.Desktop) ?[*:0]const u8 {
                _ = desktop;
                @panic("not implemented yet");
            }

            /// Returns the current clipboard value as the provided mime type.
            /// The os provides a conversion *if possible*, otherwise returns an error.
            /// The returned memory for `value` is owned by the process and must be freed with `ashet.process.memory.release`.
            pub fn get_value(desktop: abi.Desktop, mime: []const u8, value: *?[]const u8) error{
                ConversionFailed,
                OutOfMemory,
            } {
                _ = desktop;
                _ = mime;
                _ = value;
                @panic("not implemented yet");
            }
        };
    };

    pub const random = struct {
        pub fn get_soft_random(data: []u8) void {
            ashet.random.get_random_bytes(data);
        }
    };

    pub const shm = struct {
        pub fn create(size: usize) error{SystemResources}!ashet.abi.SharedMemory {
            const proc = getCurrentProcess();

            const memref = ashet.shared_memory.SharedMemory.create(size) catch {
                return error.SystemResources;
            };
            errdefer memref.destroy();

            const handle = try proc.assign_new_resource(&memref.system_resource);

            return handle.unsafe_cast(.shared_memory);
        }

        pub fn get_length(shm_handle: ashet.abi.SharedMemory) usize {
            _, const memref = resolve_typed_resource(ashet.shared_memory.SharedMemory, shm_handle.as_resource()) catch return 0;
            return memref.buffer.len;
        }

        pub fn get_pointer(shm_handle: ashet.abi.SharedMemory) [*]align(16) u8 {
            const T = struct {
                const empty: [0]u8 align(16) = .{};
            };
            _, const memref = resolve_typed_resource(ashet.shared_memory.SharedMemory, shm_handle.as_resource()) catch return &T.empty;
            return memref.buffer.ptr;
        }
    };

    pub const network = struct {
        // getStatus: FnPtr(fn () NetworkStatus),
        // ping: FnPtr(fn ([*]Ping, usize) void),
        // TODO: Implement NIC-specific queries (mac, ips, names, ...)

        const dns = struct {
            // resolves the dns entry `host` for the given `service`.
            // - `host` is a legal dns entry
            // - `port` is either a port number
            // - `buffer` and `limit` define a structure where all resolved IPs can be stored.
            // Function returns the number of host entries found or 0 if the host name could not be resolved.
            //  fn @"resolve" (host: [*:0]const u8, port: u16, buffer: [*]EndPoint, limit: usize) usize;

        };

        pub const udp = struct {
            pub fn create_socket() error{SystemResources}!abi.UdpSocket {
                const proc = getCurrentProcess();

                const sock = try ashet.network.udp.Socket.create();
                errdefer sock.destroy();

                const handle = try proc.assign_new_resource(&sock.system_resource);

                return handle.unsafe_cast(.udp_socket);
            }
        };

        pub const tcp = struct {
            pub fn create_socket() error{SystemResources}!abi.TcpSocket {
                const proc = getCurrentProcess();

                const sock = try ashet.network.tcp.Socket.create();
                errdefer sock.destroy();

                const handle = try proc.assign_new_resource(&sock.system_resource);

                return handle.unsafe_cast(.tcp_socket);
            }
        };
    };

    pub const pipe = struct {
        /// Spawns a new pipe with `fifo_length` elements of `object_size` bytes.
        /// If `fifo_length` is 0, the pipe is synchronous and can only send data
        /// if a `read` call is active. Otherwise, up to `fifo_length` elements can be
        /// stored in a FIFO.
        pub fn create(object_size: usize, fifo_length: usize) error{
            SystemResources,
        }!abi.Pipe {
            _ = object_size;
            _ = fifo_length;
            @panic("not implemented yet");
        }

        /// Returns the length of the pipe-internal FIFO in elements.
        pub fn get_fifo_length(pip: abi.Pipe) usize {
            _ = pip;
            @panic("not implemented yet");
        }

        /// Returns the size of the objects stored in the pipe.
        pub fn get_object_size(pip: abi.Pipe) usize {
            _ = pip;
            @panic("not implemented yet");
        }
    };

    pub const sync = struct {
        /// Creates a new `SyncEvent` object that can be used to synchronize
        /// different processes.
        pub fn create_event() error{SystemResources}!abi.SyncEvent {
            @panic("not implemented yet");
        }

        /// Completes one `WaitForEvent` IOP waiting for the given event.
        pub fn notify_one(evt: abi.SyncEvent) void {
            _ = evt;
            @panic("not implemented yet");
        }

        /// Completes all `WaitForEvent` IOP waiting for the given event.
        pub fn notify_all(evt: abi.SyncEvent) void {
            _ = evt;
            @panic("not implemented yet");
        }

        /// Creates a new mutual exclusion.
        pub fn create_mutex() error{SystemResources}!abi.Mutex {
            @panic("not implemented yet");
        }

        /// Tries to lock a mutex and returns if it was successful.
        pub fn try_lock(mutex: abi.Mutex) bool {
            _ = mutex;
            @panic("not implemented yet");
        }

        /// Unlocks a mutual exclusion. Completes a single `Lock` IOP if it exists.
        pub fn unlock(mutex: abi.Mutex) void {
            _ = mutex;
            @panic("not implemented yet");
        }
    };

    pub const fs = struct {
        /// Finds a file system by name
        pub fn find_filesystem(name: []const u8) abi.FileSystemId {
            if (ashet.filesystem.findFilesystem(name)) |fsid| {
                std.debug.assert(fsid != .invalid);
                return fsid;
            } else {
                return .invalid;
            }
        }
    };

    pub const service = struct {
        /// Registers a new service `uuid` in the system.
        /// Takes an array of function pointers that will be provided for IPC and a service name to be advertised.
        pub fn create(uuid: *const abi.UUID, funcs: []const abi.AbstractFunction, name: []const u8) error{
            AlreadyRegistered,
            SystemResources,
        }!abi.Service {
            _ = uuid;
            _ = funcs;
            _ = name;
            @panic("not implemented yet!");
        }

        /// Enumerates all registered services.
        pub fn enumerate(uuid: *const abi.UUID, services: ?[]abi.Service) usize {
            _ = uuid;
            _ = services;
            @panic("not implemented yet!");
        }

        /// Returns the name of the service.
        pub fn get_name(svc: abi.Service) [*:0]const u8 {
            _ = svc;
            @panic("not implemented yet!");
        }

        /// Returns the process that created this service.
        pub fn get_process(svc: abi.Service) abi.Process {
            _ = svc;
            @panic("not implemented yet!");
        }

        /// Returns the functions registerd by the service.
        pub fn get_functions(svc: abi.Service, funcs: ?[]abi.AbstractFunction) usize {
            _ = svc;
            _ = funcs;
            @panic("not implemented yet!");
        }
    };
};

fn resolve_base_resource(handle: ashet.resources.Handle) !struct { *ashet.multi_tasking.Process, *ashet.resources.SystemResource } {
    const process = getCurrentProcess();
    const ownership = try process.resources.resolve(handle);
    std.debug.assert(ownership.data.process == process);
    return .{ process, ownership.data.resource };
}

fn resolve_typed_resource(comptime Resource: type, handle: ashet.resources.Handle) !struct { *ashet.multi_tasking.Process, *Resource } {
    const process, const resource = try resolve_base_resource(handle);

    const typed = try resource.cast(Resource);

    return .{ process, typed };
}

fn getCurrentThread() *ashet.scheduler.Thread {
    return ashet.scheduler.Thread.current() orelse @panic("syscall only legal in a process");
}

fn getCurrentProcess() *ashet.multi_tasking.Process {
    return getCurrentThread().get_process();
}
