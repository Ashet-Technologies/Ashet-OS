const std = @import("std");
const hal = @import("hal");
const libashet = @import("ashet");
const astd = @import("ashet-std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.multitasking);
const loader = @import("loader.zig");

const ProcessList = std.DoublyLinkedList(void);
const ProcessNode = ProcessList.Node;
const ExitCode = ashet.abi.ExitCode;

var process_list: ProcessList = .{};

/// The process in this variable is the only process able to control the screen.
/// If `null`, the regular desktop UI is active.
pub var exclusive_video_controller: ?*Process = null;

var initialized = false;

var kernel_process: *Process = undefined;

pub fn initialize() void {
    kernel_process = Process.create(.{
        .name = "<kernel>",
        .stay_resident = true,
    }) catch @panic("could not create kernel process: out of memory");
    initialized = true;
}

pub fn spawn_blocking(
    proc_name: []const u8,
    file: *libashet.fs.File,
    argv: []const ashet.abi.SpawnProcessArg,
) !*Process {
    const process = try ashet.multi_tasking.Process.create(.{
        .stay_resident = false,
        .name = proc_name,
    });
    errdefer process.kill(.killed);

    // TODO: Process argv!

    _ = argv;

    const loaded = try loader.load(file, process.static_allocator(), .elf);

    process.executable_memory = loaded.process_memory;

    const thread = try ashet.scheduler.Thread.spawn(
        @as(ashet.scheduler.ThreadFunction, @ptrFromInt(loaded.entry_point)),
        null,
        .{ .process = process, .stack_size = 64 * 1024 },
    );
    errdefer thread.kill();

    try thread.setName(proc_name);

    thread.start() catch |err| switch (err) {
        error.AlreadyStarted => unreachable,
    };

    thread.detach();

    return process;
}

pub fn spawn_overlapped(call: *ashet.overlapped.AsyncCall) void {
    logger.debug("spawn_overlapped()", .{});
    ashet.overlapped.enqueue_background_task(
        call,
        ashet.overlapped.create_handler(ashet.abi.process.Spawn, spawn_background),
    );
}

fn spawn_background(context: *ashet.overlapped.Context, call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.process.Spawn.Inputs) ashet.abi.process.Spawn.Error!ashet.abi.process.Spawn.Outputs {
    var open_file = ashet.abi.fs.OpenFile.new(.{
        .dir = inputs.dir,
        .path_ptr = inputs.path_ptr,
        .path_len = inputs.path_len,
        .access = .read_only,
        .mode = .open_existing,
    });

    logger.debug("spawn_background().schedule_with_context", .{});
    ashet.overlapped.schedule_with_context(
        call.resource_owner,
        context,
        &open_file.arc,
    ) catch |err| return switch (err) {
        error.AlreadyScheduled => unreachable,
        error.SystemResources => |e| e,
    };

    logger.debug("spawn_background().await_completion_with_context", .{});
    var completed: [1]*ashet.abi.ARC = .{&open_file.arc};
    const count = ashet.overlapped.await_completion_with_context(
        context,
        &completed,
        .{
            .thread_affinity = .all_threads,
            .wait = .wait_one,
            // TODO(fqu): .preselected = true,
        },
    ) catch |err| return switch (err) {
        error.Unscheduled => unreachable,
    };
    std.debug.assert(count == 1);
    std.debug.assert(completed[0] == &open_file.arc);

    open_file.check_error() catch |err| return switch (err) {
        error.WriteProtected,
        error.FileAlreadyExists,
        error.NoSpaceLeft,
        error.Unexpected,
        error.Exists,
        => unreachable,

        error.SystemFdQuotaExceeded => error.SystemResources,

        else => |e| e,
    };

    logger.debug("spawn_background().resolve", .{});
    const kernel_file_handle = ashet.resources.resolve(
        ashet.filesystem.File,
        call.resource_owner,
        open_file.outputs.handle.as_resource(),
    ) catch @panic("unrecoverage resource leak");
    defer kernel_file_handle.system_resource.destroy();

    // var file = dir.openFile(inputs.path_ptr[0..inputs.path_len], .read_only, .open_existing) catch |err| return switch (err) {
    //     error.InvalidPath,
    //     error.DiskError,
    //     error.InvalidHandle,
    //     error.SystemResources,
    //     error.FileNotFound,
    //     => |e| e,

    //     error.SystemFdQuotaExceeded => error.SystemResources,

    //     error.WriteProtected,
    //     error.FileAlreadyExists,
    //     error.NoSpaceLeft,
    //     error.Unexpected,
    //     error.Exists,
    //     => unreachable,
    // };
    // defer file.close();

    var file_handle: libashet.fs.File = .{
        .handle = open_file.outputs.handle,
        .offset = 0,
    };

    logger.debug("spawn_background().spawn_blockiong", .{});
    var proc = spawn_blocking(
        "<new>",
        &file_handle,
        inputs.argv_ptr[0..inputs.argv_len],
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.SystemResources,

        error.SystemResources,
        error.DiskError,
        error.InvalidHandle,
        => |e| e,

        error.EndOfStream,
        error.InvalidElfMagic,
        error.InvalidElfVersion,
        error.InvalidElfEndian,
        error.InvalidElfClass,
        error.InvalidEndian,
        error.InvalidBitSize,
        error.InvalidMachine,
        error.NoCode,
        error.BadExecutable,
        error.InvalidPltRel,
        error.MissingSymbol,
        error.UnsupportedRelocation,
        error.UnalignedProgramHeader,
        error.Overflow,
        => error.BadExecutable,

        error.Unexpected,
        => unreachable,
    };
    errdefer proc.kill(.killed);

    logger.debug("spawn_background().assign_new_resource", .{});
    const handle = try call.resource_owner.assign_new_resource(&proc.system_resource);

    return .{
        .process = handle.unsafe_cast(.process),
    };
}

/// Gets the handle to the kernel process.
pub fn get_kernel_process() *Process {
    std.debug.assert(initialized);
    return kernel_process;
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
    const debug_line_buffer_length = 64;
    const DebugLogBuffers = std.EnumArray(ashet.abi.LogLevel, astd.LineBuffer(debug_line_buffer_length));

    system_resource: ashet.resources.SystemResource = .{ .type = .process },

    /// Node inside `process_list`.
    list_item: ProcessNode = .{ .data = {} },

    /// The IO context for scheduling IOPs
    async_context: ashet.overlapped.Context = .{},

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

    /// If not null, the process was terminated is now zombie process.
    /// Zombies exist as handles, but do not own any data anymore
    exit_code: ?ExitCode = null,

    resources: ashet.resources.HandlePool,

    debug_outputs: DebugLogBuffers = DebugLogBuffers.initFill(.{}),

    pub const CreateOptions = struct {
        name: ?[]const u8 = null,
        stay_resident: bool = false,
    };

    pub fn create(options: CreateOptions) !*Process {
        const process: *Process = try ashet.memory.type_pool(Process).alloc();
        errdefer ashet.memory.type_pool(Process).free(process);

        process.* = Process{
            .memory_arena = std.heap.ArenaAllocator.init(ashet.memory.allocator),
            .name = undefined,
            .stay_resident = options.stay_resident,
            .resources = undefined,
        };
        errdefer process.memory_arena.deinit();

        process.resources = ashet.resources.HandlePool.init(process.memory_arena.allocator());
        errdefer process.resources.deinit();

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

    pub fn is_zombie(proc: Process) bool {
        return (proc.exit_code != null);
    }

    /// Kills the process, stops all threads, and releases of its resources.
    pub fn kill(proc: *Process, exit_code: ExitCode) void {
        std.debug.assert(!proc.is_zombie());

        process_list.remove(&proc.list_item);

        if (exclusive_video_controller == proc) {
            exclusive_video_controller = null;
        }

        // TODO: remove when threads are a resource!
        // destroy all threads:
        while (proc.threads.popFirst()) |thread| {
            std.debug.assert(thread.data.process == proc);
            thread.data.thread.kill();
        }

        // Drop all resource ownerships:
        {
            var iter = proc.resources.iterator();
            while (iter.next()) |item| {
                const res = item.ownership.data.resource;
                res.remove_owner(item.ownership);
                proc.resources.free_by_index(item.index) catch unreachable; // all resources we can reach here are valid
            }
            proc.resources.deinit();
        }

        proc.memory_arena.deinit();

        proc.exit_code = exit_code;
    }

    /// Kills the thread and deletes it afterwards. This will invalidate all resource handles!
    pub fn destroy(proc: *Process) void {
        if (!proc.is_zombie()) {
            proc.kill(ExitCode.killed);
        }
        ashet.memory.type_pool(Process).free(proc);
    }

    pub fn save(proc: *Process) void {
        std.debug.assert(!proc.is_zombie());
        // TODO
    }

    pub fn restore(proc: *const Process) void {
        std.debug.assert(!proc.is_zombie());
        // TODO
    }

    pub fn isExclusiveVideoController(proc: *Process) bool {
        std.debug.assert(!proc.is_zombie());
        return (exclusive_video_controller == proc);
    }

    /// Returns a handle to a memory arena associated with the process.
    /// Memory allocated with this allocator cannot be freed.
    pub fn static_allocator(proc: *Process) std.mem.Allocator {
        std.debug.assert(!proc.is_zombie());
        return proc.memory_arena.allocator();
    }

    /// Returns a handle to a general purpose allocator associated with the process.
    pub fn dynamic_allocator(proc: *Process) std.mem.Allocator {
        std.debug.assert(!proc.is_zombie());
        // TODO(fqu): Actually implemenet this!
        return proc.memory_arena.allocator();
    }

    /// Assigns this process the system resource `res` and returns the handle.
    pub fn assign_new_resource(proc: *Process, res: *ashet.resources.SystemResource) error{SystemResources}!ashet.abi.SystemResource {
        const info = proc.resources.alloc() catch return error.SystemResources;
        errdefer proc.resources.free_by_handle(info.handle) catch unreachable;

        info.ownership.* = .{
            .data = .{
                .process = proc,
                .resource = res,
            },
        };
        res.add_owner(info.ownership);

        return info.handle;
    }

    pub fn format(proc: *const Process, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Thread(0x{X:0>8}, \"{}\")", .{ @intFromPtr(proc), std.zig.fmtEscapes(proc.name) });
    }

    pub fn write_log(proc: *Process, log_level: ashet.abi.LogLevel, text: []const u8) void {
        const output = proc.debug_outputs.getPtr(log_level);

        const process_logger = std.log.scoped(.process);

        var offset: usize = 0;
        while (offset < text.len) {
            const consumed, const maybe_text = output.append(text[offset..]);
            offset += consumed;
            if (maybe_text) |log_line| {
                switch (log_level) {
                    .critical => process_logger.err("{s}: CRITICAL: {s}", .{ proc.name, log_line }),
                    .err => process_logger.err("{s}: {s}", .{ proc.name, log_line }),
                    .warn => process_logger.warn("{s}: {s}", .{ proc.name, log_line }),
                    .notice => process_logger.info("{s}: {s}", .{ proc.name, log_line }),
                    .debug => process_logger.debug("{s}: {s}", .{ proc.name, log_line }),
                }
            }
        }
    }
};
