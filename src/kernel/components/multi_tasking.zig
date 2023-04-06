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

/// The process in this variable is the only process able to control the screen.
/// If `null`, the regular desktop UI is active.
pub var exclusive_video_controller: ?*Process = null;

pub const Process = struct {
    master_thread: *ashet.scheduler.Thread,
    thread_count: usize = 0,
    process_memory: []align(ashet.memory.page_size) u8,
    io_context: ashet.io.Context = .{},

    memory_arena: std.heap.ArenaAllocator,

    pub const SpawnOptions = struct {
        stack_size: usize = 128 * 1024, // 128k
    };

    pub fn spawn(name: []const u8, process_memory: []align(ashet.memory.page_size) u8, entry_point: ashet.abi.ThreadFunction, arg: ?*anyopaque, options: SpawnOptions) !*Process {
        const process: *Process = try ashet.memory.allocator.create(Process);
        errdefer ashet.memory.allocator.destroy(process);

        process.* = Process{
            .master_thread = undefined,
            .process_memory = process_memory,
            .memory_arena = std.heap.ArenaAllocator.init(ashet.memory.allocator),
        };
        errdefer process.memory_arena.deinit();

        process.master_thread = try ashet.scheduler.Thread.spawn(entry_point, arg, .{
            .stack_size = options.stack_size,
            .process = process,
        });
        errdefer process.master_thread.kill();

        try process.master_thread.setName(name);

        try process.master_thread.start();
        process.master_thread.detach();

        return process;
    }

    pub fn kill(proc: *Process) void {
        if (exclusive_video_controller == proc) {
            exclusive_video_controller = null;
        }
        ashet.ui.destroyAllWindowsForProcess(proc);
        if (proc.thread_count > 0) {
            proc.master_thread.kill();
        }
        proc.memory_arena.deinit();

        ashet.memory.page_allocator.free(proc.process_memory);
        ashet.memory.allocator.destroy(proc);
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
