const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../main.zig");
const abi = @import("ashet-abi");
const logger = std.log.scoped(.syscalls);

const strace = std.log.scoped(.strace);

const ashet_abi_v2_impl = @import("ashet-abi-impl");

pub const SystemCall = ashet_abi_v2_impl.Syscall_ID;

const copy_slice = ashet.utils.copy_slice;

comptime {
    // Force exports into existence:
    _ = exports;
}

pub const exports = ashet_abi_v2_impl.create_exports(syscalls, callbacks);

pub var strace_enabled: std.enums.EnumSet(SystemCall) = std.enums.EnumSet(SystemCall).initFull();

pub fn get_address(syscall: SystemCall) usize {
    return switch (syscall) {
        inline else => |call| return @intFromPtr(&@field(exports, "ashet_syscalls_" ++ @tagName(call))),
    };
}

inline fn print_strace(name: []const u8) void {
    var it = std.debug.StackIterator.init(@returnAddress(), null);
    var current = it.next() orelse @returnAddress();
    current = it.next() orelse current;
    strace.info("{s} from {}", .{ name, ashet.fmtCodeLocation(current) });
}

noinline fn not_implemented_yet(location: std.builtin.SourceLocation) noreturn {
    logger.err("{s}:{}:{}: TODO: syscall {s}/{s} not implemented yet", .{
        location.file,   location.line,    location.column,
        location.module, location.fn_name,
    });
    @panic("Syscall not implemented yet!");
}

const callbacks = struct {
    pub inline fn before_syscall(sc: SystemCall) void {
        ashet.stackCheck();
        if (strace_enabled.contains(sc)) {
            print_strace(@tagName(sc));
        }
    }

    pub inline fn after_syscall(sc: SystemCall) void {
        _ = sc;
        ashet.stackCheck();
    }
};

pub const syscalls = struct {
    pub const resources = struct {
        pub fn get_type(src_handle: abi.SystemResource) error{InvalidHandle}!abi.SystemResource.Type {
            _, const resource = resolve_base_resource(src_handle) catch return error.InvalidHandle;
            return resource.type;
        }

        pub fn get_owners(src_handle: abi.SystemResource, maybe_owners: ?[]abi.Process) usize {
            _, const src = resolve_base_resource(src_handle) catch return 0;

            if (maybe_owners) |owners| {
                const limit = @min(src.owners.len, owners.len);
                var iter = src.owners.first;
                for (0..limit) |i| {
                    owners[i] = undefined; // TODO! @ptrCast(iter.?.data.process); // TODO: Transform to handle here!
                    iter = iter.?.next;
                    @panic("TODO: Fix this!");
                }
                return limit;
            } else {
                return src.owners.len;
            }
        }

        pub fn send_to_process(src_handle: abi.SystemResource, proc_handle: abi.Process) error{ SystemResources, InvalidHandle, DeadProcess }!void {
            const kproc1, const resource = try resolve_base_resource(src_handle);
            const kproc2, const tproc = try resolve_process_handle(proc_handle.as_resource());
            std.debug.assert(kproc1 == kproc2);

            _ = try ashet.resources.add_to_process(tproc, resource);
        }

        pub fn release(src_handle: abi.SystemResource) void {
            const proc, const resource = resolve_base_resource(src_handle) catch return;
            ashet.resources.remove_from_process(proc, resource);
        }

        pub fn destroy(src_handle: abi.SystemResource) void {
            _, const resource = resolve_base_resource(src_handle) catch return;
            ashet.resources.destroy(resource);
        }
    };

    pub const process = struct {
        fn _resolve_maybe_proc(maybe_proc: ?abi.Process) !*ashet.multi_tasking.Process {
            return if (maybe_proc) |handle| blk: {
                _, const proc = try resolve_process_handle(handle.as_resource());
                break :blk proc;
            } else get_current_process();
        }

        pub fn get_file_name(maybe_proc: ?abi.Process) []const u8 {
            const kproc = _resolve_maybe_proc(maybe_proc) catch |err| {
                return @errorName(err);
            };
            return kproc.name;
        }

        pub fn get_base_address(maybe_proc: ?abi.Process) usize {
            const kproc = _resolve_maybe_proc(maybe_proc) catch {
                // TODO: Log err
                return 0;
            };

            return if (kproc.executable_memory) |mem|
                @intFromPtr(mem.ptr)
            else
                0x00;
        }

        pub fn get_arguments(maybe_proc: ?abi.Process, maybe_argv: ?[]abi.SpawnProcessArg) usize {
            const cproc = get_current_process();
            const kproc = _resolve_maybe_proc(maybe_proc) catch {
                // TODO: Log err
                return 0;
            };

            if (maybe_argv) |argv| {
                const count = @min(argv.len, kproc.cli_arguments.len);
                for (argv[0..count], kproc.cli_arguments[0..count]) |*out, in| {
                    out.* = .{
                        .type = in,
                        .value = switch (in) {
                            .string => |value| .{ .text = ashet.abi.SpawnProcessArg.String.new(value) },
                            .resource => |handle| .{
                                .resource = if (kproc == cproc) handle else @panic("TODO: Implement resource transition!"),
                            },
                        },
                    };
                }
                return count;
            } else {
                return kproc.cli_arguments.len;
            }
        }

        pub fn terminate(exit_code: abi.process.ExitCode) noreturn {
            const proc = get_current_process();

            proc.stay_resident = false;

            // var thread_iter = proc.threads.first;
            // while (thread_iter) |thread_node| : (thread_iter = thread_node.next) {
            //     thread_node.data.thread.kill();
            // }
            // std.debug.assert(proc.threads.len == 0);
            proc.kill(exit_code);

            ashet.scheduler.yield();
            @panic("terminator?");
        }

        pub fn kill(handle: abi.Process) void {
            _, const kproc = resolve_process_handle(handle.as_resource()) catch return;
            if (!kproc.is_zombie()) {
                kproc.kill(.killed);
            }
        }

        pub const thread = struct {
            pub fn yield() void {
                ashet.scheduler.yield();
            }

            pub fn exit(exit_code: abi.process.ExitCode) noreturn {
                ashet.scheduler.exit(@intFromEnum(exit_code));
            }

            pub fn join(thr: abi.Thread) abi.process.ExitCode {
                _ = thr;
                not_implemented_yet(@src());
            }

            pub fn spawn(function: abi.process.thread.ThreadFunction, arg: ?*anyopaque, stack_size: usize) error{SystemResources}!abi.Thread {
                _ = function;
                _ = arg;
                _ = stack_size;
                not_implemented_yet(@src());
            }

            pub fn kill(thr: abi.Thread, exit_code: abi.process.ExitCode) void {
                _ = thr;
                _ = exit_code;
                not_implemented_yet(@src());
            }
        };

        pub const debug = struct {
            pub fn write_log(log_level: abi.LogLevel, message: []const u8) void {
                const proc = get_current_process();
                proc.write_log(log_level, message);
            }
            pub fn breakpoint() void {
                const proc = get_current_process();
                std.log.scoped(.userland).info("breakpoint in process {s}.", .{proc.name});

                var cont: bool = false;
                while (!cont) {
                    std.mem.doNotOptimizeAway(&cont);
                }
            }
        };

        pub const memory = struct {
            pub fn allocate(size: usize, ptr_align: u8) error{SystemResource}![*]u8 {
                const proc = get_current_process();
                return proc.dynamic_allocator().rawAlloc(
                    size,
                    @enumFromInt(ptr_align),
                    @returnAddress(),
                ) orelse return error.SystemResource;
            }
            pub fn release(mem: []u8, ptr_align: u8) void {
                const proc = get_current_process();
                proc.dynamic_allocator().rawFree(
                    mem,
                    @enumFromInt(ptr_align),
                    @returnAddress(),
                );
            }
        };

        pub const monitor = struct {
            /// Queries all owned resources by a process.
            pub fn enumerate_processes(processes: ?[]abi.Process) usize {
                _ = processes;
                not_implemented_yet(@src());
            }

            /// Queries all owned resources by a process.
            pub fn query_owned_resources(owner: abi.Process, reslist: ?[]abi.SystemResource) usize {
                _ = owner;
                _ = reslist;
                not_implemented_yet(@src());
            }

            /// Returns the total number of bytes the process takes up in RAM.
            pub fn query_total_memory_usage(proc: abi.Process) usize {
                _ = proc;
                not_implemented_yet(@src());
            }

            /// Returns the number of dynamically allocated bytes for this process.
            pub fn query_dynamic_memory_usage(proc: abi.Process) usize {
                _ = proc;
                not_implemented_yet(@src());
            }

            /// Returns the number of total memory objects this process has right now.
            pub fn query_active_allocation_count(proc: abi.Process) usize {
                _ = proc;
                not_implemented_yet(@src());
            }
        };
    };

    pub const clock = struct {
        pub fn monotonic() abi.Absolute {
            return @enumFromInt(std.time.ns_per_ms * @intFromEnum(ashet.time.Instant.now()));
        }
    };

    pub const datetime = struct {
        pub fn now() abi.DateTime {
            return @enumFromInt(ashet.time.milliTimestamp());
        }
    };

    pub const video = struct {
        pub fn enumerate(ids: ?[]abi.VideoOutputID) usize {
            return ashet.video.enumerate(ids);
        }

        pub fn acquire(output: abi.VideoOutputID) error{ SystemResources, NotFound, NotAvailable }!abi.VideoOutput {
            const proc = get_current_process();

            const video_output = try ashet.video.acquire_output(output);

            const handle = try ashet.resources.add_to_process(proc, &video_output.system_resource);

            return handle.unsafe_cast(.video_output);
        }

        pub fn get_resolution(output_handle: abi.VideoOutput) error{InvalidHandle}!abi.Size {
            _, const output = try resolve_typed_resource(ashet.video.Output, output_handle.as_resource());
            return output.get_resolution();
        }

        pub fn get_video_memory(output_handle: abi.VideoOutput) error{InvalidHandle}!abi.VideoMemory {
            _, const output = try resolve_typed_resource(ashet.video.Output, output_handle.as_resource());
            return output.get_video_memory();
        }

        pub fn get_palette(output: abi.VideoOutput, palette: *[abi.palette_size]abi.Color) error{InvalidHandle}!void {
            _ = output;
            _ = palette;
            not_implemented_yet(@src());
        }

        pub fn set_palette(output: abi.VideoOutput, palette: *const [abi.palette_size]abi.Color) error{ InvalidHandle, Unsupported } {
            _ = output;
            _ = palette;
            not_implemented_yet(@src());
        }
    };

    pub const overlapped = struct {
        pub fn schedule(async_call: *abi.overlapped.ARC) error{ SystemResources, AlreadyScheduled }!void {
            const proc = get_current_process();

            return try ashet.overlapped.schedule(proc, &proc.async_context, async_call);
        }

        pub fn await_completion(completed: []*abi.overlapped.ARC, options: abi.Await_Options) error{Unscheduled}!usize {
            const proc = get_current_process();

            return try ashet.overlapped.await_completion(&proc.async_context, completed, options);
        }

        pub fn await_completion_of(completed: []?*abi.overlapped.ARC) error{ Unscheduled, InvalidOperation }!usize {
            const proc = get_current_process();

            return try ashet.overlapped.await_completion_of(&proc.async_context, completed);
        }

        pub fn cancel(arc: *abi.overlapped.ARC) error{ Unscheduled, Completed }!void {
            return try ashet.overlapped.cancel(arc);
        }
    };

    pub const draw = struct {
        // Fonts:

        /// Returns the font data for the given font name, if any.
        pub fn get_system_font(font_name: []const u8) error{
            FileNotFound,
            SystemResources,
        }!abi.Font {
            const proc = get_current_process();

            const system_font = try ashet.graphics.get_system_font(font_name);

            const handle = try ashet.resources.add_to_process(proc, &system_font.system_resource);

            return handle.unsafe_cast(.font);
        }

        /// Creates a new custom font from the given data.
        pub fn create_font(data: []const u8) error{
            InvalidData,
            SystemResources,
        }!abi.Font {
            const proc = get_current_process();

            const font = try ashet.graphics.Font.create(data);
            errdefer font.destroy();

            const handle = try ashet.resources.add_to_process(proc, &font.system_resource);

            return handle.unsafe_cast(.font);
        }

        /// Returns true if the given font is a system-owned font.
        pub fn is_system_font(font_handle: abi.Font) error{InvalidHandle}!bool {
            _, const font = try resolve_typed_resource(ashet.graphics.Font, font_handle.as_resource());
            return font.system_font;
        }

        pub fn measure_text_size(font_handle: abi.Font, text: []const u8) error{InvalidHandle}!abi.Size {
            _, const font = try resolve_typed_resource(ashet.graphics.Font, font_handle.as_resource());
            return font.measure_text_size(text);
        }

        // Framebuffer management:

        /// Creates a new in-memory framebuffer that can be used for offscreen painting.
        pub fn create_memory_framebuffer(size: abi.Size) error{SystemResources}!abi.Framebuffer {
            const proc = get_current_process();

            const fb = try ashet.graphics.Framebuffer.create_memory(size.width, size.height);
            errdefer fb.destroy();

            const handle = try ashet.resources.add_to_process(proc, &fb.system_resource);

            return handle.unsafe_cast(.framebuffer);
        }

        /// Creates a new framebuffer based off a video output. Can be used to output pixels
        /// to the screen.
        pub fn create_video_framebuffer(video_output: abi.VideoOutput) error{ SystemResources, InvalidHandle }!abi.Framebuffer {
            const proc, const output = try resolve_typed_resource(ashet.video.Output, video_output.as_resource());

            const fb = try ashet.graphics.Framebuffer.create_video_output(output);
            errdefer fb.destroy();

            const handle = try ashet.resources.add_to_process(proc, &fb.system_resource);

            return handle.unsafe_cast(.framebuffer);
        }

        /// Creates a new framebuffer that allows painting into a GUI window.
        pub fn create_window_framebuffer(window_handle: abi.Window) error{ SystemResources, InvalidHandle }!abi.Framebuffer {
            const proc, const output = try resolve_typed_resource(ashet.gui.Window, window_handle.as_resource());

            const fb = try ashet.graphics.Framebuffer.create_window(output);
            errdefer fb.destroy();

            const handle = try ashet.resources.add_to_process(proc, &fb.system_resource);

            return handle.unsafe_cast(.framebuffer);
        }

        /// Creates a new framebuffer that allows painting into a widget.
        pub fn create_widget_framebuffer(widget_handle: abi.Widget) error{ SystemResources, InvalidHandle }!abi.Framebuffer {
            const proc, const output = try resolve_typed_resource(ashet.gui.Widget, widget_handle.as_resource());

            const fb = try ashet.graphics.Framebuffer.create_widget(output);
            errdefer fb.destroy();

            const handle = try ashet.resources.add_to_process(proc, &fb.system_resource);

            return handle.unsafe_cast(.framebuffer);
        }

        /// Returns the type of a framebuffer object.
        pub fn get_framebuffer_type(framebuffer: abi.Framebuffer) error{InvalidHandle}!abi.FramebufferType {
            _, const fb = try resolve_typed_resource(ashet.graphics.Framebuffer, framebuffer.as_resource());

            return fb.type;
        }

        /// Returns the size of a framebuffer object.
        pub fn get_framebuffer_size(framebuffer: abi.Framebuffer) error{InvalidHandle}!abi.Size {
            _, const fb = try resolve_typed_resource(ashet.graphics.Framebuffer, framebuffer.as_resource());

            return fb.get_size();
        }

        pub fn get_framebuffer_memory(framebuffer: abi.Framebuffer) error{ InvalidHandle, Unsupported }!abi.VideoMemory {
            _, const fb = try resolve_typed_resource(ashet.graphics.Framebuffer, framebuffer.as_resource());
            switch (fb.type) {
                .memory => |mem| return .{
                    .width = mem.width,
                    .height = mem.height,
                    .stride = mem.stride,
                    .base = mem.pixels,
                },
                else => return error.Unsupported,
            }
        }

        /// Marks a portion of the framebuffer as changed and forces the OS to
        /// perform an update action if necessary.
        pub fn invalidate_framebuffer(framebuffer: abi.Framebuffer, rect: abi.Rectangle) void {
            _ = framebuffer;
            _ = rect;
            not_implemented_yet(@src());
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
            const kproc = get_current_process();

            const widget_type = try ashet.gui.WidgetType.create(kproc, desc);
            errdefer widget_type.destroy();

            const handle = try ashet.resources.add_to_process(kproc, &widget_type.system_resource);

            return handle.unsafe_cast(.widget_type);
        }

        // Window API:

        /// Spawns a new window.
        pub fn create_window(
            desktop_handle: abi.Desktop,
            title: []const u8,
            min: abi.Size,
            max: abi.Size,
            startup: abi.Size,
            flags: abi.CreateWindowFlags,
        ) error{
            SystemResources,
            InvalidDimensions,
            InvalidHandle,
        }!abi.Window {
            const kproc, const desktop = try resolve_typed_resource(ashet.gui.Desktop, desktop_handle.as_resource());

            const window = try ashet.gui.Window.create(
                desktop,
                title,
                min,
                max,
                startup,
                flags,
            );
            errdefer window.destroy();

            const handle = try ashet.resources.add_to_process(kproc, &window.system_resource);
            return handle.unsafe_cast(.window);
        }

        pub fn get_window_title(window: abi.Window, title_buf: ?[]u8) error{InvalidHandle}!usize {
            _, const win = try resolve_typed_resource(ashet.gui.Window, window.as_resource());
            return copy_slice(u8, title_buf, win.title);
        }

        pub fn get_window_size(window: abi.Window) error{InvalidHandle}!abi.Size {
            _, const win = try resolve_typed_resource(ashet.gui.Window, window.as_resource());
            return win.size;
        }

        pub fn get_window_min_size(window: abi.Window) error{InvalidHandle}!abi.Size {
            _, const win = try resolve_typed_resource(ashet.gui.Window, window.as_resource());
            return win.min_size;
        }

        pub fn get_window_max_size(window: abi.Window) error{InvalidHandle}!abi.Size {
            _, const win = try resolve_typed_resource(ashet.gui.Window, window.as_resource());
            return win.max_size;
        }

        pub fn get_window_flags(window: abi.Window) error{InvalidHandle}!abi.WindowFlags {
            _, const win = try resolve_typed_resource(ashet.gui.Window, window.as_resource());
            return .{
                .popup = win.is_popup,
                .resizable = !win.min_size.eql(win.max_size),
            };
        }

        pub fn set_window_size(window: abi.Window, size: abi.Size) error{InvalidHandle}!abi.Size {
            _, const win = try resolve_typed_resource(ashet.gui.Window, window.as_resource());
            win.size = abi.Size.new(
                std.math.clamp(size.width, win.min_size.width, win.max_size.width),
                std.math.clamp(size.height, win.min_size.height, win.max_size.height),
            );
            return win.size;
        }

        /// Resizes a window to the new size.
        pub fn resize_window(window: abi.Window, size: abi.Size) void {
            _ = window;
            _ = size;
            not_implemented_yet(@src());
        }

        /// Changes a window title.
        pub fn set_window_title(window: abi.Window, title: []const u8) void {
            _ = window;
            _ = title;
            not_implemented_yet(@src());
        }

        /// Notifies the desktop that a window wants attention from the user.
        /// This could just pop the window to the front, make it blink, show a small notification, ...
        pub fn mark_window_urgent(window: abi.Window) void {
            _ = window;
            not_implemented_yet(@src());
        }

        // TODO: gui.app_menu

        // Widget API:

        /// Create a new widget identified by `uuid` on the given `window`.
        /// Position and size of the widget are undetermined at start and a call to `place_widget` should be performed on success.
        pub fn create_widget(window: abi.Window, uuid: *const abi.UUID) error{
            SystemResources,
            WidgetNotFound,
            InvalidHandle,
        }!abi.Widget {
            const kproc, const win = try resolve_typed_resource(ashet.gui.Window, window.as_resource());

            const widget = try ashet.gui.Widget.create(win, uuid);
            errdefer widget.destroy();

            const handle = try ashet.resources.add_to_process(kproc, &widget.system_resource);
            return handle.unsafe_cast(.widget);
        }

        /// Moves and resizes a widget in one.
        pub fn place_widget(widget: abi.Widget, bounds: abi.Rectangle) error{InvalidHandle}!abi.Rectangle {
            _, const wid = try resolve_typed_resource(ashet.gui.Widget, widget.as_resource());
            return wid.place(bounds);
        }

        /// Triggers the `control` event of the widget with the given `message` as a payload.
        pub fn control_widget(widget: abi.Widget, message: abi.WidgetControlMessage) error{ InvalidHandle, SystemResources }!void {
            _, const wid = try resolve_typed_resource(ashet.gui.Widget, widget.as_resource());
            wid.control(message);
        }

        /// Triggers the `widget_notify` event of the `Window` that owns `widget` with `event` as the payload.
        pub fn notify_owner(widget: abi.Widget, notify: ashet.abi.gui.WidgetNotifyID, params: *const [4]usize) error{ InvalidHandle, SystemResources }!void {
            _, const wid = try resolve_typed_resource(ashet.gui.Widget, widget.as_resource());
            wid.notify_owner(notify, params.*);
        }

        /// Returns WidgetType-associated "opaque" data for this widget.
        ///
        /// This is meant as a convenience tool to store additional information per widget
        /// like internal state and such.
        ///
        /// The size of this must be known and cannot be queried.
        pub fn get_widget_data(widget: abi.Widget) error{InvalidHandle}![*]align(16) u8 {
            _, const wid = try resolve_typed_resource(ashet.gui.Widget, widget.as_resource());
            return wid.widget_data.ptr;
        }

        pub fn get_widget_bounds(widget_handle: abi.Widget) error{InvalidHandle}!abi.Rectangle {
            _, const widget = try resolve_typed_resource(ashet.gui.Widget, widget_handle.as_resource());
            return widget.bounds;
        }

        // Context Menu API:

        // TODO: gui.context_menu

        // Desktop Server API:

        /// Creates a new desktop with the given name.
        pub fn create_desktop(
            name: []const u8,
            descriptor: *const abi.DesktopDescriptor,
        ) error{
            SystemResources,
        }!abi.Desktop {
            const proc = get_current_process();

            const desktop = try ashet.gui.Desktop.create(
                proc,
                name,
                descriptor.*,
            );
            errdefer desktop.destroy();

            const handle = try ashet.resources.add_to_process(proc, &desktop.system_resource);

            return handle.unsafe_cast(.desktop);
        }

        /// Returns the name of the provided desktop.
        pub fn get_desktop_name(desktop_handle: abi.Desktop, name_buf: ?[]u8) error{InvalidHandle}!usize {
            _, const desktop = try resolve_typed_resource(ashet.gui.Desktop, desktop_handle.as_resource());

            return copy_slice(u8, name_buf, desktop.name);
        }

        /// Enumerates all available desktops.
        pub fn enumerate_desktops(maybe_list: ?[]abi.Desktop) usize {
            const proc = get_current_process();

            var iter = ashet.gui.iterate_desktops();

            if (maybe_list) |list| {
                var cnt: usize = 0;
                while (cnt < list.len) : (cnt += 1) {
                    const desktop = iter.next() orelse break;
                    const handle = ashet.resources.add_to_process(proc, &desktop.system_resource) catch {
                        for (list[0..cnt]) |handle| {
                            _, const base_resource = resolve_base_resource(handle.as_resource()) catch unreachable;
                            ashet.resources.remove_from_process(proc, base_resource);
                        }
                        return 0;
                    };
                    list[cnt] = handle.unsafe_cast(.desktop);
                }
                return cnt;
            } else {
                var cnt: usize = 0;
                while (iter.next() != null) {
                    cnt += 1;
                }
                return cnt;
            }
        }

        /// Returns all windows for a desktop handle.
        pub fn enumerate_desktop_windows(desktop: abi.Desktop, windows: ?[]abi.Window) error{InvalidHandle}!usize {
            _ = desktop;
            _ = windows;
            not_implemented_yet(@src());
        }

        /// Returns desktop-associated "opaque" data for this window.
        ///
        /// This is meant as a convenience tool to store additional information per window
        /// like position on the screen, orientation, alignment, ...
        ///
        /// The size of this must be known and cannot be queried.
        pub fn get_desktop_data(window_handle: abi.Window) error{InvalidHandle}![*]align(16) u8 {
            _, const window = try resolve_typed_resource(ashet.gui.Window, window_handle.as_resource());
            return window.window_data.ptr;
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
            not_implemented_yet(@src());
        }

        /// Posts an event into the window event queue so the window owner
        /// can handle the event.
        pub fn post_window_event(
            window_handle: abi.Window,
            event: abi.WindowEvent,
        ) error{ SystemResources, InvalidHandle }!void {
            _, const window = try resolve_typed_resource(ashet.gui.Window, window_handle.as_resource());

            window.post_event(event);
        }

        /// Sends a notification to the provided `desktop`.
        pub fn send_notification(
            /// Where to show the notification?
            desktop: abi.Desktop,
            /// What text is displayed in the notification?
            message: []const u8,
            /// How urgent is the notification to the user?
            severity: abi.NotificationSeverity,
        ) error{SystemResources}!void {
            _ = desktop;
            _ = message;
            _ = severity;
            not_implemented_yet(@src());
        }

        pub const clipboard = struct {
            /// Sets the contents of the clip board.
            /// Takes a mime type as well as the value in the provided format.
            pub fn set(desktop: abi.Desktop, mime: []const u8, value: []const u8) error{SystemResources}!void {
                _ = desktop;
                _ = mime;
                _ = value;
                not_implemented_yet(@src());
            }

            /// Returns the current type present in the clipboard, if any.
            pub fn get_type(desktop: abi.Desktop, type_buf: ?[]u8) error{InvalidHandle}!usize {
                _ = desktop;
                _ = type_buf;
                not_implemented_yet(@src());
            }

            /// Returns the current clipboard value as the provided mime type.
            /// The os provides a conversion *if possible*, otherwise returns an error.
            /// The returned memory for `value` is owned by the process and must be freed with `ashet.process.memory.release`.
            pub fn get_value(desktop: abi.Desktop, mime: []const u8) error{
                ConversionFailed,
                SystemResources,
                InvalidHandle,
                ClipboardEmpty,
            }![]const u8 {
                _ = desktop;
                _ = mime;
                not_implemented_yet(@src());
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
            const proc = get_current_process();

            const memref = ashet.shared_memory.SharedMemory.create(size) catch {
                return error.SystemResources;
            };
            errdefer memref.destroy();

            const handle = try ashet.resources.add_to_process(proc, &memref.system_resource);

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
                const proc = get_current_process();

                const sock = try ashet.network.udp.Socket.create();
                errdefer sock.destroy();

                const handle = try ashet.resources.add_to_process(proc, &sock.system_resource);

                return handle.unsafe_cast(.udp_socket);
            }
        };

        pub const tcp = struct {
            pub fn create_socket() error{SystemResources}!abi.TcpSocket {
                const proc = get_current_process();

                const sock = try ashet.network.tcp.Socket.create();
                errdefer sock.destroy();

                const handle = try ashet.resources.add_to_process(proc, &sock.system_resource);

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
            not_implemented_yet(@src());
        }

        /// Returns the length of the pipe-internal FIFO in elements.
        pub fn get_fifo_length(pip: abi.Pipe) usize {
            _ = pip;
            not_implemented_yet(@src());
        }

        /// Returns the size of the objects stored in the pipe.
        pub fn get_object_size(pip: abi.Pipe) usize {
            _ = pip;
            not_implemented_yet(@src());
        }
    };

    pub const sync = struct {
        /// Creates a new `SyncEvent` object that can be used to synchronize
        /// different processes.
        pub fn create_event() error{SystemResources}!abi.SyncEvent {
            not_implemented_yet(@src());
        }

        /// Completes one `WaitForEvent` IOP waiting for the given event.
        pub fn notify_one(evt: abi.SyncEvent) void {
            _ = evt;
            not_implemented_yet(@src());
        }

        /// Completes all `WaitForEvent` IOP waiting for the given event.
        pub fn notify_all(evt: abi.SyncEvent) void {
            _ = evt;
            not_implemented_yet(@src());
        }

        /// Creates a new mutual exclusion.
        pub fn create_mutex() error{SystemResources}!abi.Mutex {
            not_implemented_yet(@src());
        }

        /// Tries to lock a mutex and returns if it was successful.
        pub fn try_lock(mutex: abi.Mutex) bool {
            _ = mutex;
            not_implemented_yet(@src());
        }

        /// Unlocks a mutual exclusion. Completes a single `Lock` IOP if it exists.
        pub fn unlock(mutex: abi.Mutex) void {
            _ = mutex;
            not_implemented_yet(@src());
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
        pub fn create(uuid: *const abi.UUID, funcs: []const *const anyopaque, name: []const u8) error{
            AlreadyRegistered,
            SystemResources,
        }!abi.Service {
            _ = uuid;
            _ = funcs;
            _ = name;
            not_implemented_yet(@src());
        }

        /// Enumerates all registered services.
        pub fn enumerate(uuid: *const abi.UUID, services: ?[]abi.Service) usize {
            _ = uuid;
            _ = services;
            not_implemented_yet(@src());
        }

        /// Returns the name of the service.
        pub fn get_name(svc: abi.Service, name_buf: ?[]u8) error{InvalidHandle}!usize {
            _ = svc;
            _ = name_buf;
            not_implemented_yet(@src());
        }

        /// Returns the process that created this service.
        pub fn get_process(svc: abi.Service) abi.Process {
            _ = svc;
            not_implemented_yet(@src());
        }

        /// Returns the functions registerd by the service.
        pub fn get_functions(svc: abi.Service, funcs: ?[]*const anyopaque) usize {
            _ = svc;
            _ = funcs;
            not_implemented_yet(@src());
        }
    };

    pub const io = struct {
        // pub const serial = struct {
        //     pub fn enumerate()1 void {}
        //     pub fn query_metadata() void {}
        //     pub fn open() void {}
        // };

        pub const i2c = struct {
            pub fn enumerate(list: ?[]ashet.abi.io.i2c.BusID) usize {
                return ashet.io.i2c.enumerate(list);
            }

            pub fn query_metadata(id: ashet.abi.io.i2c.BusID, name_buf: ?[]u8) error{NotFound}!usize {
                return try ashet.io.i2c.query_metadata(id, name_buf);
            }

            pub fn open(id: ashet.abi.io.i2c.BusID) error{ SystemResources, NotFound }!ashet.abi.io.i2c.Bus {
                const proc = get_current_process();

                const bus = try ashet.io.i2c.Bus.open(id);

                const handle = try ashet.resources.add_to_process(proc, &bus.system_resource);

                return handle.unsafe_cast(.io_i2c_bus);
            }
        };
    };
};

fn resolve_base_resource(handle: ashet.resources.Handle) error{InvalidHandle}!struct { *ashet.multi_tasking.Process, *ashet.resources.SystemResource } {
    const process = get_current_process();

    const resource = try ashet.resources.resolve_untyped(process, handle);

    return .{ process, resource };
}

fn resolve_typed_resource(comptime Resource: type, handle: ashet.resources.Handle) error{InvalidHandle}!struct { *ashet.multi_tasking.Process, *Resource } {
    const process, const resource = resolve_base_resource(handle) catch return error.InvalidHandle;

    const typed = resource.cast(Resource) catch return error.InvalidHandle;

    return .{ process, typed };
}

fn resolve_process_handle(handle: ashet.resources.Handle) error{ InvalidHandle, DeadProcess }!struct { *ashet.multi_tasking.Process, *ashet.multi_tasking.Process } {
    const kproc, const uproc = try resolve_typed_resource(ashet.multi_tasking.Process, handle);
    if (uproc.is_zombie())
        return error.DeadProcess;
    return .{ kproc, uproc };
}

fn get_current_thread() *ashet.scheduler.Thread {
    return ashet.scheduler.Thread.current() orelse @panic("syscall only legal in a thread");
}

var current_process_overwrite: ?*ashet.multi_tasking.Process = null;

/// TODO: This function is broken as a virtual process overwrite is still per-thread
///       and not globally.
///       Any call to `yield()` in this context will also overwrite the process
///       which is unrelated to our local overwrite.
fn get_current_process() *ashet.multi_tasking.Process {
    const kproc = current_process_overwrite orelse get_current_thread().get_process();
    if (kproc.is_zombie())
        @panic("zombie process called a system call!");
    return kproc;
}

pub const VirtualContextSwitch = struct {
    previous_process: ?*ashet.multi_tasking.Process,
    current_process: *ashet.multi_tasking.Process, // TODO(fqu): Make this optional in release modes, it's just for

    pub fn enter(new_process: *ashet.multi_tasking.Process) VirtualContextSwitch {
        const previous_process = current_process_overwrite;
        current_process_overwrite = new_process;
        return .{
            .previous_process = previous_process,
            .current_process = new_process,
        };
    }

    pub fn leave(vcs: *VirtualContextSwitch) void {
        std.debug.assert(get_current_process() == vcs.current_process);
        std.debug.assert(current_process_overwrite == vcs.current_process);
        current_process_overwrite = vcs.previous_process;
    }
};
