const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.multitasking);

var initialized: bool = false;
var current_screen_idx: usize = 0;

pub fn initialize() void {
    // We initialize the first process ad-hoc in selectScreen
    initialized = false;
}

// pub fn selectScreen(screen: Screen) !void {
//     const new_screen_idx = screen.resolveToIndex();

//     if (initialized) {
//         // only perform transition into background
//         // when we have at least called selectScreen() once.

//         if (new_screen_idx == current_screen_idx)
//             return;

//         if (foreground_processes[current_screen_idx]) |old_proc| {
//             old_proc.save();
//         }
//     }
//     initialized = true;

//     const new_proc: *Process = foreground_processes[new_screen_idx] orelse blk: {
//         // Start new process with splash screen when we didn't have any process here yet

//         const req_pages = ashet.memory.getRequiredPages(@sizeOf(Process));

//         const base_page = try ashet.memory.allocPages(req_pages);
//         errdefer ashet.memory.freePages(base_page, req_pages);

//         const process: *Process = @ptrCast(*Process, ashet.memory.pageToPtr(base_page));

//         process.* = Process{
//             .master_thread = undefined,
//         };

//         process.master_thread = try ashet.scheduler.Thread.spawn(ashet.splash_screen.run, null, .{
//             .stack_size = 512 * 1024,
//             .process = process,
//         });
//         errdefer process.master_thread.kill();

//         // just format the name directly into the debug_info of the thread
//         var name_buf: [64]u8 = undefined;
//         const name = try std.fmt.bufPrint(&name_buf, "main screen {d}", .{new_screen_idx});
//         try process.master_thread.setName(name);

//         try process.master_thread.start();
//         process.master_thread.detach();

//         foreground_processes[new_screen_idx] = process;

//         break :blk process;
//     };

//     new_proc.restore();
//     current_screen_idx = new_screen_idx;
// }

// pub fn handOff(screen: Screen, main_thread: *ashet.scheduler.Thread) !void {
//     const screen_idx = screen.resolveToIndex() orelse return error.InvalidScreen;

//     const process = foreground_processes[screen_idx] orelse return error.NoProcess;

//     process.master_thread = main_thread;
// }

/// The process in this variable is the only process able to control the screen.
/// If `null`, the regular desktop UI is active.
pub var exclusive_video_controller: ?*Process = null;

pub const Process = struct {
    master_thread: *ashet.scheduler.Thread,

    pub fn kill(proc: *Process) void {
        if (exclusive_video_controller == proc) {
            exclusive_video_controller = null;
        }
        proc.master_thread.kill();
        proc.* = undefined;
    }

    pub fn save(proc: *Process) void {
        _ = proc;
    }

    pub fn restore(proc: *const Process) void {
        _ = proc;
    }

    pub fn isExclusiveVideoController(proc: *Process) bool {
        return (exclusive_video_controller == proc);
    }
};
