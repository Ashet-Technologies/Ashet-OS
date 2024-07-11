const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.multitasking);

const ProcessList = std.DoublyLinkedList(void);
const ProcessNode = ProcessList.Node;

var process_list: ProcessList = .{};

var process_memory_pool: std.heap.MemoryPool(Process) = undefined;

/// The process in this variable is the only process able to control the screen.
/// If `null`, the regular desktop UI is active.
pub var exclusive_video_controller: ?*Process = null;

pub fn initialize() void {
    process_memory_pool = std.heap.MemoryPool(Process).init(ashet.memory.allocator);
}

pub fn processIterator() ProcessIterator {
    return ProcessIterator{ .current = process_list.first };
}

pub const ProcessIterator = struct {
    current: ?*ProcessNode,

    pub fn next(iter: *ProcessIterator) ?*Process {
        const current = iter.current orelse return null;
        iter.current = current.next;
        return @fieldParentPtr("list_item", current);
    }
};

pub const ProcessThreadList = std.DoublyLinkedList(struct {
    thread: *ashet.scheduler.Thread,
    process: *Process,
});

pub const Process = struct {
    /// Node inside `process_list`.
    list_item: ProcessNode = .{ .data = {} },

    /// The IO context for scheduling IOPs
    io_context: ashet.io.Context = .{},

    /// unfreeable process allocations
    memory_arena: std.heap.ArenaAllocator,

    /// All associated threads.
    threads: ProcessThreadList = .{},

    /// If true, the process will stay resident if the last thread of it dies.
    stay_resident: bool = false,

    /// Name of the process, displayed in kernel logs
    name: [:0]u8,

    /// Slice of where the executable was loaded in memory
    executable_memory: ?[]const u8 = null,

    resources: ashet.resources.HandlePool,

    pub const CreateOptions = struct {
        name: ?[]const u8 = null,
        stay_resident: bool = false,
    };
    pub fn create(options: CreateOptions) !*Process {
        const process: *Process = try process_memory_pool.create();
        errdefer process_memory_pool.destroy(process);

        process.* = Process{
            .memory_arena = std.heap.ArenaAllocator.init(ashet.memory.allocator),
            .name = undefined,
            .stay_resident = options.stay_resident,
        };
        errdefer process.memory_arena.deinit();

        process.name = if (options.name) |name|
            try process.memory_arena.allocator().dupeZ(u8, name)
        else
            try std.fmt.allocPrintZ(process.memory_arena.allocator(), "Process(0x{X:0>8})", .{@intFromPtr(process)});

        process_list.append(&process.list_item);
        errdefer process_list.remove(&process.list_item);

        return process;
    }

    pub const SpawnOptions = struct {
        stack_size: usize = 128 * 1024, // 128k
    };

    // pub fn spawn(name: []const u8, process_memory: []align(ashet.memory.page_size) u8, entry_point: ashet.abi.ThreadFunction, arg: ?*anyopaque, options: SpawnOptions) !*Process {

    // process.file_name = try process.memory_arena.allocator().dupeZ(u8, name);

    // process.master_thread = try ashet.scheduler.Thread.spawn(entry_point, arg, .{
    //     .stack_size = options.stack_size,
    //     .process = process,
    // });
    // errdefer process.master_thread.kill();

    // try process.master_thread.setName(name);

    // try process.master_thread.start();
    // process.master_thread.detach();

    // return process;
    // }

    pub fn kill(proc: *Process) void {
        process_list.remove(&proc.list_item);

        if (exclusive_video_controller == proc) {
            exclusive_video_controller = null;
        }

        // destroy all threads:
        while (proc.threads.popFirst()) |thread| {
            std.debug.assert(thread.data.process == proc);
            thread.data.thread.kill();
        }

        proc.memory_arena.deinit();

        process_memory_pool.destroy(proc);
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

    /// Returns a handle to a memory arena associated with the process.
    /// Memory allocated with this allocator cannot be freed.
    pub fn static_allocator(proc: *Process) std.mem.Allocator {
        return proc.memory_arena.allocator();
    }
};
