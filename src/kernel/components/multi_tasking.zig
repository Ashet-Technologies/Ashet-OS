const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.multitasking);

var initialized: bool = false;
var current_screen_idx: usize = 0;
var foreground_processes: [10]?*Process = [1]?*Process{null} ** 10;

pub const Screen = enum {
    current,

    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"10",

    pub fn resolveToIndex(screen: Screen) usize {
        return switch (screen) {
            .current => current_screen_idx,
            .@"1" => 0,
            .@"2" => 1,
            .@"3" => 2,
            .@"4" => 3,
            .@"5" => 4,
            .@"6" => 5,
            .@"7" => 6,
            .@"8" => 7,
            .@"9" => 8,
            .@"10" => 9,
        };
    }
};

pub fn initialize() void {
    // We initialize the first process ad-hoc in selectScreen
    initialized = false;
}

pub fn getForegroundProcess(screen: Screen) ?*Process {
    return foreground_processes[screen.resolveToIndex()];
}

pub fn selectScreen(screen: Screen) !void {
    const new_screen_idx = screen.resolveToIndex();

    if (initialized) {
        // only perform transition into background
        // when we have at least called selectScreen() once.

        if (new_screen_idx == current_screen_idx)
            return;

        if (foreground_processes[current_screen_idx]) |old_proc| {
            old_proc.save();
        }
    }
    initialized = true;

    const new_proc: *Process = foreground_processes[new_screen_idx] orelse blk: {
        // Start new process with splash screen when we didn't have any process here yet

        const req_pages = ashet.memory.getRequiredPages(@sizeOf(Process));

        const base_page = try ashet.memory.allocPages(req_pages);
        errdefer ashet.memory.freePages(base_page, req_pages);

        const process: *Process = @ptrCast(*Process, ashet.memory.pageToPtr(base_page));

        process.* = Process{
            .master_thread = undefined,
        };

        process.master_thread = try ashet.scheduler.Thread.spawn(ashet.splash_screen.run, null, .{
            .stack_size = 512 * 1024,
            .process = process,
        });
        errdefer process.master_thread.kill();

        // just format the name directly into the debug_info of the thread
        var name_buf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "main screen {d}", .{new_screen_idx});
        try process.master_thread.setName(name);

        try process.master_thread.start();
        process.master_thread.detach();

        foreground_processes[new_screen_idx] = process;

        break :blk process;
    };

    new_proc.restore();
    current_screen_idx = new_screen_idx;
}

pub fn handOff(screen: Screen, main_thread: *ashet.scheduler.Thread) !void {
    const screen_idx = screen.resolveToIndex() orelse return error.InvalidScreen;

    const process = foreground_processes[screen_idx] orelse return error.NoProcess;

    process.master_thread = main_thread;
}

pub const Process = struct {
    master_thread: *ashet.scheduler.Thread,

    // buffers for background storage
    video_buffer: [400 * 300]u8 align(4) = ashet.video.defaults.splash_screen ++ [1]u8{0x0F} ** (400 * 300 - 256 * 128),
    palette_buffer: [ashet.abi.palette_size]u16 = ashet.video.defaults.palette,
    video_mode: ashet.video.Mode = .graphics,
    resolution: ashet.video.Resolution = .{ .width = 256, .height = 128 },
    border_color: u8 = 0x0F,

    pub fn save(proc: *Process) void {
        proc.resolution = ashet.video.getResolution();
        proc.video_mode = ashet.video.getMode();
        proc.border_color = ashet.video.getBorder();

        std.mem.copy(u8, &proc.video_buffer, ashet.video.memory[0..proc.resolution.size()]);
        std.mem.copy(u16, &proc.palette_buffer, ashet.video.palette);
    }

    pub fn restore(proc: *const Process) void {
        ashet.video.setResolution(proc.resolution.width, proc.resolution.height);
        ashet.video.setMode(proc.video_mode);
        ashet.video.setBorder(proc.border_color);

        std.mem.copy(u8, ashet.video.memory, proc.video_buffer[0..proc.resolution.size()]);
        std.mem.copy(u16, ashet.video.palette, &proc.palette_buffer);

        ashet.video.flush();
    }
};
