const syscalls = struct {
    /// Syscalls related to processes
    const process = struct {
        /// Returns a pointer to the file name of the process.
        fn get_file_name(?*Process) [*:0]const u8;

        /// Returns the base address of the process.
        fn get_base_address(?*Process) usize;

        /// Terminates the current process with the given exit code
        fn terminate(exit_code: ExitCode) noreturn;

        /// Terminates a foreign process.
        /// If the current process is passed, this function will not return
        fn kill(*Process) void;

        const thread = struct {
            /// Returns control to the scheduler. Returns when the scheduler
            /// schedules the process again.
            fn yield() void;

            /// Terminates the current thread.
            fn exit(exit_code: ExitCode) noreturn;

            /// Waits for the thread to exit and returns its return code.
            fn join(*Thread) ExitCode;

            /// Spawns a new thread with `function` passing `arg` to it.
            /// If `stack_size` is not 0, will create a stack with the given size.
            fn spawn(function: ThreadFunction, arg: ?*anyopaque, stack_size: usize) ?*Thread;

            /// Kills the given thread with `exit_code`.
            fn kill(*Thread, exit_code: ExitCode) void;
        };

        const debug = struct {
            /// Writes to the system debug log.
            fn write_log(log_level: LogLevel, message: []const u8) void;

            /// Stops the process and allows debugging.
            fn breakpoint() void;
        };

        const memory = struct {
            /// Allocates memory pages from the system.
            fn allocate(size: usize, ptr_align: u8) ?[*]u8;

            /// Returns memory to the systme.
            fn release(mem: []u8, ptr_align: u8) void;
        };

        const monitor = struct {
            /// Queries all owned resources by a process.
            fn enumerate_processes(processes: ?[]*Process) usize;

            /// Queries all owned resources by a process.
            fn query_owned_resources(*Process, resources: ?[]*SystemResource) usize;

            /// Returns the total number of bytes the process takes up in RAM.
            fn query_total_memory_usage(*Process) usize;

            /// Returns the number of dynamically allocated bytes for this process.
            fn query_dynamic_memory_usage(*Process) usize;

            /// Returns the number of total memory objects this process has right now.
            fn query_active_allocation_count(*Process) usize;
        };
    };

    const clock = struct {
        /// Returns the time in nanoseconds since system startup.
        /// This clock is monotonically increasing.
        fn monotonic() u64;
    };

    const time = struct {
        /// Get a calendar timestamp relative to UTC 1970-01-01.
        /// Precision of timing depends on the hardware.
        /// The return value is signed because it is possible to have a date that is
        /// before the epoch.
        fn now() DateTime;
    };

    const video = struct {
        /// Returns a list of all video outputs.
        ///
        /// If `ids` is `null`, the total number of available outputs is returned,
        /// otherwise, up to `ids.len` elements are written into the provided array
        /// and the number of written elements is returned.
        fn enumerate(ids: ?[]VideoOutputID) usize;

        /// Acquire exclusive access to a video output.
        fn acquire(VideoOutputID) ?*VideoOutput;

        /// Returns the current resolution
        fn get_resolution(*VideoOutput) Size;

        /// Returns a pointer to linear video memory, row-major.
        /// Pixels rows will have a stride of the current video buffer width.
        /// The first pixel in the memory is the top-left pixel.
        fn get_video_memory(*VideoOutput) [*]align(4) ColorIndex;

        /// Fetches a copy of the current color pallete.
        fn get_palette(*VideoOutput, *[palette_size]Color) void;

        /// Changes the current color palette.
        fn set_palette(*VideoOutput, *const [palette_size]Color) error{Unsupported};

        // /// Returns a pointer to the current palette. Changing this palette
        // /// will directly change the associated colors on the screen.
        // /// If `null` is returned, no direct access to the video palette is possible.
        //  fn get_palette_memory(*VideoOutput) ?*[palette_size]Color;

        // /// Changes the border color of the screen. Parameter is an index into
        // /// the palette.
        //  fn set_border(*VideoOutput, ColorIndex) void;

        // /// Returns the maximum possible screen resolution.
        //  fn get_max_resolution(*VideoOutput) Size;

        // /// Sets the screen resolution. Legal values are between 1×1 and the platform specific
        // /// maximum resolution returned by `video.getMaxResolution()`.
        // /// Everything out of bounds will be clamped into that range.
        //  fn change_resolution(*VideoOutput, u16, u16) void;

    };

    const network = struct {

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

        const udp = struct {
            fn create_socket(result: **UdpSocket) error{SystemResources};
        };

        const tcp = struct {
            fn create_socket(out: **TcpSocket) error{SystemResources};
        };
    };

    const io = struct {
        /// Starts new I/O operations and returns completed ones.
        ///
        /// If `start_queue` is given, the kernel will schedule the events in the kernel.
        /// All events in this queue must not be freed until they are returned by this function
        /// at a later point.
        ///
        /// The function will optionally block based on the `wait` parameter.
        ///
        /// The return value is the HEAD element of a linked list of completed I/O events.
        fn schedule_and_await(?*IOP, WaitIO) ?*IOP;

        /// Cancels a single I/O operation.
        fn cancel(*IOP) void;
    };

    const fs = struct {
        /// Finds a file system by name
        fn find_filesystem(name: []const u8) FileSystemId;
    };

    const service = struct {
        /// Registers a new service `uuid` in the system.
        /// Takes an array of function pointers that will be provided for IPC and a service name to be advertised.
        fn create(svc: **Service, uuid: *const UUID, funcs: []const AbstractFunction, name: []const u8) error{
            AlreadyRegistered,
            SystemResources,
        };

        /// Enumerates all registered services.
        fn enumerate(uuid: *const UUID, services: []*Service) bool;

        /// Returns the name of the service.
        fn get_name(*Service) [*:0]const u8;

        /// Returns the process that created this service.
        fn get_process(*Service) *Process;

        /// Returns the functions registerd by the service.
        fn get_functions(*Service, funcs: ?[]const AbstractFunction) usize;
    };

    const clipboard = struct {
        /// Sets the contents of the clip board.
        /// Takes a mime type as well as the value in the provided format.
        fn set(mime: []const u8, value: []const u8) error{
            SystemResources,
        };

        /// Returns the current type present in the clipboard, if any.
        fn get_type() ?[*:0]const u8;

        /// Returns the current clipboard value as the provided mime type.
        /// The os provides a conversion *if possible*, otherwise returns an error.
        /// The returned memory for `value` is owned by the process and must be freed with `ashet.process.memory.release`.
        fn get_value(mime: []const u8, value: *?[]const u8) error{
            ConversionFailed,
            OutOfMemory,
        };
    };

    const draw = struct {
        // Fonts:

        /// Returns the font data for the given font name, if any.
        fn get_system_font(font_name: []const u8, font: **Font) error{
            FileNotFound,
            SystemResources,
            OutOfMemory,
        };

        /// Creates a new custom font from the given data.
        fn create_font(data: []const u8, font: **Font) error{
            InvalidData,
            SystemResources,
            OutOfMemory,
        };

        /// Returns true if the given font is a system-owned font.
        fn is_system_font(*Font) bool;

        // Framebuffer management:

        /// Creates a new in-memory framebuffer that can be used for offscreen painting.
        fn create_memory_framebuffer(size: Size) ?*Framebuffer;

        /// Creates a new framebuffer based off a video output. Can be used to output pixels
        /// to the screen.
        fn create_video_framebuffer(*VideoOutput) ?*Framebuffer;

        /// Creates a new framebuffer that allows painting into a GUI window.
        fn create_window_framebuffer(*Window) ?*Framebuffer;

        /// Creates a new framebuffer that allows painting into a widget.
        fn create_widget_framebuffer(*Widget) ?*Framebuffer;

        /// Returns the type of a framebuffer object.
        fn get_framebuffer_type(*Framebuffer) FramebufferType;

        /// Returns the size of a framebuffer object.
        fn get_framebuffer_size(*Framebuffer) Size;

        /// Marks a portion of the framebuffer as changed and forces the OS to
        /// perform an update action if necessary.
        fn invalidate_framebuffer(*Framebuffer, Rectangle) void;

        // Drawing:

        // TODO: fn annotate_text(*Framebuffer, area: Rectangle, text: []const u8) AnnotationError;

        // TODO: Insert render functions here
    };

    const gui = struct {
        /// Opens a message box popup window and prompts the user for response.
        ///
        /// *Remarks:* This function is blocking and will only return when the user has entered their choice.
        fn message_box(message: []const u8, caption: []const u8, buttons: MessageBoxButtons, icon: MessageBoxIcon) MessageBoxResult;

        fn register_widget_type(uuid: *const UUID, *const WidgetDescriptor) error{
            AlreadyRegistered,
            SystemResources,
        };

        fn unregister_widget_type(uuid: *const UUID) void;

        // Window API:

        fn create_window(window: **Window, desktop: *Desktop, title: []const u8, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) error{
            SystemResources,
            InvalidDimensions,
        };

        fn resize_window(*Window, x: u16, y: u16) void;

        fn set_window_title(*Window, title: []const u8) void;

        fn mark_window_urgent(*Window) void;

        // TODO: gui.app_menu

        // Widget API:

        fn create_widget(widget: **Widget, window: *Window, uuid: *const UUID) error{
            SystemResources,
            WidgetNotFound,
        };

        fn place_widget(widget: *Widget, position: Point, size: Size) void;

        // Context Menu API:

        // TODO: gui.context_menu

        // Desktop Server API:

        /// Creates a new desktop with the given name.
        fn create_desktop(
            desktop: **Desktop,
            /// User-visible name of the desktop.
            name: []const u8,
            /// Number of bytes allocated in a Window for this desktop.
            /// See `get_desktop_data` function for further information.
            window_data_size: usize,
        ) error{
            SystemResources,
        };

        // TODO: Function to get the "current"/"primary"/"associated" desktop server, how?

        fn get_desktop_name(*Desktop) [*:0]const u8;

        /// Enumerates all available desktops.
        fn enumerate_desktops(serverlist: ?[]*Desktop) usize;

        /// Returns all windows for a desktop handle.
        fn enumerate_desktop_windows(*Desktop, window: ?[]*Window) usize;

        /// Returns desktop-associated "opaque" data for this window.
        ///
        /// This is meant as a convenience tool to store additional information per window
        /// like position on the screen, orientation, alignment, ...
        ///
        /// The size of this must be known and cannot be queried.
        fn get_desktop_data(*Window) [*]align(16) u8;
    };

    const resources = struct {
        /// Returns the type of the system resource.
        fn get_type(*SystemResource) SystemResource.Type;

        /// Returns the current owner of this resource.
        fn get_owner(*SystemResource) ?*Process;

        /// Transfers ownership to another process.
        fn set_owner(*SystemResource, *Process) void;

        /// Closes the system resource and releases its memory.
        /// The handle will be invalid after this function.
        fn close(*SystemResource) void;
    };

    const notification = struct {
        fn send(message: []const u8, kind: NotificationKind) error{
            SystemResources,
        };

        // TODO: Add notification listeners
    };
};
