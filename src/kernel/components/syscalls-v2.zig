const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../main.zig");
const abi = @import("ashet-abi-v2");

const ashet_abi_v2_impl = @import("ashet-abi-v2-impl");

comptime {
    // Force exports into existence:
    _ = ashet_abi_v2_impl.create_exports(@This());
}

pub const syscalls = struct {
    pub const resources = struct {
        pub fn get_type(res: abi.SystemResource) abi.SystemResource.Type {
            _ = res;
            @panic("not implemented yet");
        }

        pub fn get_owners(res: abi.SystemResource, owners: ?[]abi.Process) usize {
            _ = res;
            _ = owners;
            @panic("not implemented yet");
        }
        pub fn send_to_process(res: abi.SystemResource, proc: abi.Process) void {
            _ = res;
            _ = proc;
            @panic("not implemented yet");
        }
        pub fn release(res: abi.SystemResource) void {
            _ = res;
            @panic("not implemented yet");
        }
        pub fn destroy(res: abi.SystemResource) void {
            _ = res;
            @panic("not implemented yet");
        }
    };

    pub const process = struct {
        pub fn get_file_name(proc: ?abi.Process) [*:0]const u8 {
            _ = proc;
            @panic("not implemented yet");
        }

        pub fn get_base_address(proc: ?abi.Process) usize {
            _ = proc;
            @panic("not implemented yet");
        }

        pub fn get_arguments(proc: ?abi.Process, argv: ?[]abi.SpawnProcessArg) usize {
            _ = proc;
            _ = argv;
            @panic("not implemented yet");
        }

        pub fn terminate(exit_code: abi.ExitCode) noreturn {
            _ = exit_code;
            @panic("not implemented yet");
        }

        pub fn kill(proc: abi.Process) void {
            _ = proc;
            @panic("not implemented yet");
        }

        pub const thread = struct {
            pub fn yield() void {
                //
            }
            pub fn exit(exit_code: abi.ExitCode) noreturn {
                _ = exit_code;
                @panic("not implemented yet");
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
                _ = log_level;
                _ = message;
                @panic("not implemented yet");
            }
            pub fn breakpoint() void {
                @panic("not implemented yet");
            }
        };

        pub const memory = struct {
            pub fn allocate(size: usize, ptr_align: u8) ?[*]u8 {
                _ = size;
                _ = ptr_align;
                @panic("not implemented yet");
            }
            pub fn release(mem: []u8, ptr_align: u8) void {
                _ = mem;
                _ = ptr_align;
                @panic("not implemented yet");
            }
        };
    };

    pub const clock = struct {
        pub fn monotonic() u64 {
            //
            @panic("not implemented yet");
        }
    };

    pub const time = struct {
        pub fn now() abi.DateTime {
            //
            @panic("not implemented yet");
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

    pub const aops = struct {
        pub fn schedule_and_await(enqueue_list: ?*abi.AsyncOp, wait_mode: abi.WaitIO) ?*abi.AsyncOp {
            _ = enqueue_list;
            _ = wait_mode;

            @panic("not implemented yet");
        }

        pub fn cancel(iop: *abi.AsyncOp) void {
            _ = iop;
            @panic("not implemented yet");
        }
    };

    pub const draw = struct {
        // Fonts:

        pub fn get_system_font(font_name: []const u8) error{
            FileNotFound,
            SystemResources,
            OutOfMemory,
        }!abi.Font {
            _ = font_name;
            @panic("not implemented yet");
        }

        pub fn create_font(data: []const u8) error{
            InvalidData,
            SystemResources,
            OutOfMemory,
        }!abi.Font {
            _ = data;
            @panic("not implemented yet");
        }

        pub fn is_system_font(font: abi.Font) bool {
            _ = font;
            @panic("not implemented yet");
        }

        // Framebuffer management:

        pub fn create_memory_framebuffer(size: abi.Size) ?abi.Framebuffer {
            _ = size;
            @panic("not implemented yet");
        }

        pub fn create_video_framebuffer(output: abi.VideoOutput) ?abi.Framebuffer {
            _ = output;
            @panic("not implemented yet");
        }

        pub fn create_window_framebuffer(window: abi.Window) ?abi.Framebuffer {
            _ = window;
            @panic("not implemented yet");
        }

        pub fn get_framebuffer_type(fb: abi.Framebuffer) abi.FramebufferType {
            _ = fb;
            @panic("not implemented yet");
        }

        pub fn get_framebuffer_size(fb: abi.Framebuffer) abi.Size {
            _ = fb;
            @panic("not implemented yet");
        }

        pub fn invalidate_framebuffer(fb: abi.Framebuffer, rect: abi.Rectangle) void {
            _ = fb;
            _ = rect;
            @panic("not implemented yet");
        }
    };

    pub const gui = struct {
        // Window API:

        pub fn create_window(desktop: abi.Desktop, title: []const u8, min: abi.Size, max: abi.Size, startup: abi.Size, flags: abi.CreateWindowFlags) error{
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
        pub fn resize_window(window: abi.Window, size: abi.Size) void {
            _ = window;
            _ = size;
            @panic("not implemented yet");
        }
        pub fn set_window_title(window: abi.Window, title: []const u8) void {
            _ = window;
            _ = title;
            @panic("not implemented yet");
        }
        pub fn mark_window_urgent(window: abi.Window) void {
            _ = window;
            @panic("not implemented yet");
        }
        // Desktop Server API:

        pub fn create_desktop(
            name: []const u8,
            descriptor: *const abi.DesktopDescriptor,
        ) error{
            SystemResources,
        }!abi.Desktop {
            _ = name;
            _ = descriptor;
            @panic("not implemented yet");
        }
        pub fn get_desktop_name(desktop: abi.Desktop) [*:0]const u8 {
            _ = desktop;
            @panic("not implemented yet");
        }
        pub fn enumerate_desktops(serverlist: ?[]abi.Desktop) usize {
            _ = serverlist;
            @panic("not implemented yet");
        }
        pub fn enumerate_desktop_windows(desktop: abi.Desktop, window: ?[]abi.Window) usize {
            _ = desktop;
            _ = window;
            @panic("not implemented yet");
        }
        pub fn get_desktop_data(window: abi.Window) [*]align(16) u8 {
            _ = window;
            @panic("not implemented yet");
        }
        pub fn post_window_event(
            window: abi.Window,
            event_type: abi.WindowEvent.Type,
            event: abi.WindowEvent,
        ) error{SystemResources} {
            _ = window;
            _ = event_type;
            _ = event;
            @panic("not implemented yet");
        }
    };

    pub const random = struct {
        pub fn get_soft_random(data: []u8) void {
            ashet.random.get_random_bytes(data);
        }
    };
};