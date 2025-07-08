const std = @import("std");
const hal = @import("hal");
const libashet = @import("ashet");
const astd = @import("ashet-std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.multitasking);
const loader = @import("loader.zig");

const ProcessList = astd.DoublyLinkedList(void, .{ .tag = opaque {} });
const ProcessNode = ProcessList.Node;
const ExitCode = ashet.abi.process.ExitCode;

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

/// Wraps a function call such that syscalls done from this call
/// are called from another process `context`.
pub fn call_inside_process(
    context: *Process,
    function: anytype,
    arguments: anytype,
) @TypeOf(@call(.auto, function, arguments)) {
    var ctx = ashet.syscalls.VirtualContextSwitch.enter(context);
    defer ctx.leave();

    return @call(.auto, function, arguments);
}

pub const SpawnBlockingError = error{
    Overflow,
    OutOfMemory,

    SystemResources,
    DiskError,
    InvalidHandle,
    EndOfStream,
    InvalidElfMagic,
    InvalidElfVersion,
    InvalidElfEndian,
    InvalidElfClass,
    InvalidEndian,
    InvalidBitSize,
    InvalidMachine,
    NoCode,
    BadExecutable,
    InvalidPltRel,
    MissingSymbol,
    UnsupportedRelocation,
    UnalignedProgramHeader,
    InvalidAshexExecutable,
    AshexMachineMismatch,
    AshexPlatformMismatch,
    AshexUnsupportedVersion,
    AshexNoData,
    AshexCorruptedFile,
    AshexUnsupportedSyscall,
    AshexInvalidRelocation,
    AshexInvalidSyscallIndex,
    Unexpected,
};

pub fn spawn_blocking(
    proc_name: []const u8,
    file: *libashet.fs.File,
    argv: []const ashet.abi.SpawnProcessArg,
) SpawnBlockingError!*Process {
    const process = try ashet.multi_tasking.Process.create(.{
        .stay_resident = false,
        .name = proc_name,
    });
    errdefer process.kill(.killed);

    // TODO: Process argv!

    _ = argv;

    const loaded = try loader.load(file, process.static_allocator(), .ashex);

    process.executable_memory = loaded.process_memory;

    logger.debug("loaded '{s}' to 0x{X:0>8}, entry point is 0x{X:0>8}", .{
        proc_name,
        @intFromPtr(loaded.process_memory.ptr),
        loaded.entry_point,
    });

    const thread = try ashet.scheduler.Thread.spawn(
        @as(ashet.scheduler.ThreadFunction, @ptrFromInt(loaded.entry_point)),
        null,
        .{ .process = process, .stack_size = 128 * 1024 },
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
    ashet.overlapped.enqueue_background_task(
        call,
        ashet.overlapped.create_handler(ashet.abi.process.Spawn, spawn_background),
    );
}

fn spawn_background(context: *ashet.overlapped.Context, call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.process.Spawn.Inputs) ashet.abi.process.Spawn.Error!ashet.abi.process.Spawn.Outputs {
    const exe_path = inputs.path_ptr[0..inputs.path_len];

    const raw_basename = std.fs.path.basenamePosix(exe_path);
    const exe_name = if (std.mem.eql(u8, raw_basename, "code"))
        std.fs.path.basenamePosix(std.fs.path.dirnamePosix(exe_path) orelse return error.InvalidPath)
    else
        raw_basename;

    logger.err("fix exe name computation: {s} => {s}", .{ raw_basename, exe_name });

    var open_file = ashet.abi.fs.OpenFile.new(.{
        .dir = inputs.dir,
        .path_ptr = exe_path.ptr,
        .path_len = exe_path.len,
        .access = .read_only,
        .mode = .open_existing,
    });

    ashet.overlapped.schedule_with_context(
        call.resource_owner,
        context,
        &open_file.arc,
    ) catch |err| return switch (err) {
        error.AlreadyScheduled => unreachable,
        error.SystemResources => |e| e,
    };

    var completed: [1]*ashet.abi.overlapped.ARC = .{&open_file.arc};
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

    const kernel_file_handle = ashet.resources.resolve(
        ashet.filesystem.File,
        call.resource_owner,
        open_file.outputs.handle.as_resource(),
    ) catch @panic("unrecoverage resource leak");
    defer ashet.resources.destroy(&kernel_file_handle.system_resource);

    const bg_process = ashet.scheduler.Thread.current().?.get_process();

    const local_resource_handle = try ashet.resources.add_to_process(bg_process, &kernel_file_handle.system_resource);
    defer ashet.resources.remove_from_process(bg_process, &kernel_file_handle.system_resource);

    var file_handle: libashet.fs.File = .{
        .handle = local_resource_handle.unsafe_cast(.file),
        .offset = 0,
    };

    const proc = spawn_blocking(
        exe_name,
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

        error.InvalidAshexExecutable,
        error.AshexMachineMismatch,
        error.AshexPlatformMismatch,
        error.AshexUnsupportedVersion,
        error.AshexNoData,
        error.AshexCorruptedFile,
        error.AshexUnsupportedSyscall,
        error.AshexInvalidRelocation,
        error.AshexInvalidSyscallIndex,
        => error.BadExecutable,

        error.Unexpected,
        => unreachable,
    };
    errdefer proc.kill(.killed);

    const argv_in = inputs.argv_ptr[0..inputs.argv_len];
    const argv_out = proc.static_allocator().alloc(SpawnProcessArg, argv_in.len) catch return error.SystemResources;
    for (argv_out, argv_in) |*out, in| {
        out.* = switch (in.type) {
            .string => .{
                .string = proc.static_allocator().dupe(u8, in.value.text.slice()) catch return error.SystemResources,
            },
            .resource => .{
                .resource = blk: {
                    const resource = ashet.resources.resolve_untyped(call.resource_owner, in.value.resource) catch return error.InvalidHandle;
                    break :blk try ashet.resources.add_to_process(proc, resource);
                },
            },
        };
    }

    proc.cli_arguments = argv_out;

    const handle = try ashet.resources.add_to_process(call.resource_owner, &proc.system_resource);

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

pub const ProcessThreadList = astd.DoublyLinkedList(struct {
    thread: *ashet.scheduler.Thread,
    process: *Process,
}, .{});

pub const SpawnProcessArg = union(ashet.abi.SpawnProcessArg.Type) {
    string: []const u8,
    resource: ashet.abi.SystemResource,
};

pub const Process = struct {
    const debug_line_buffer_length = 256;
    const DebugLogBuffers = std.EnumArray(ashet.abi.LogLevel, astd.LineBuffer(debug_line_buffer_length));

    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

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
    name: [:0]const u8,

    /// Slice of where the executable was loaded in memory
    executable_memory: ?[]const u8 = null,

    /// If not null, the process was terminated is now zombie process.
    /// Zombies exist as handles, but do not own any data anymore
    exit_code: ?ExitCode = null,

    /// Set of active resource handles.
    resource_handles: ashet.resources.HandlePool,

    debug_outputs: DebugLogBuffers = DebugLogBuffers.initFill(.{}),

    /// Stores the command-line arguments for the process.
    /// Memory is owned by `.memory_arena`, while resources are also
    /// assigned to this process. The resource handles won't necessarily be valid
    /// as the user is free to free them.
    cli_arguments: []const SpawnProcessArg = &.{},

    self_process_handle: ashet.abi.Process,

    pub const CreateOptions = struct {
        name: ?[]const u8 = null,
        stay_resident: bool = false,
    };

    pub fn create(options: CreateOptions) !*Process {
        const process: *Process = try ashet.memory.type_pool(Process).alloc();
        errdefer ashet.memory.type_pool(Process).free(process);

        process.* = Process{
            .memory_arena = std.heap.ArenaAllocator.init(ashet.memory.page_allocator),
            .name = undefined,
            .stay_resident = options.stay_resident,
            .resource_handles = undefined,
            .self_process_handle = undefined,
        };
        errdefer process.memory_arena.deinit();

        process.resource_handles = ashet.resources.HandlePool.init(process.memory_arena.allocator());
        errdefer process.resource_handles.deinit();

        process.name = if (options.name) |name|
            try process.memory_arena.allocator().dupeZ(u8, name)
        else
            try std.fmt.allocPrintZ(process.memory_arena.allocator(), "Process(0x{X:0>8})", .{@intFromPtr(process)});

        // we do actually own ourselves (*_*)
        const raw_handle = try ashet.resources.add_to_process(process, &process.system_resource);
        process.self_process_handle = raw_handle.unsafe_cast(.process);

        process_list.append(&process.list_item);
        errdefer process_list.remove(&process.list_item);

        logger.debug("create(\"{}\") => {}", .{
            std.zig.fmtEscapes(process.name),
            process,
        });

        return process;
    }

    /// Destroys the process resource and releases its memory.
    pub const destroy = Destructor.destroy;

    /// Kills the thread and deletes it afterwards. This will invalidate all resource handles!
    fn _internal_destroy(proc: *Process) void {
        logger.debug("destroy({})", .{proc});

        if (!proc.is_zombie()) {
            proc.kill(ExitCode.killed);
        }

        // TODO(fqu): Is that the right point?
        proc.resource_handles.deinit();
        proc.memory_arena.deinit();

        ashet.memory.type_pool(Process).free(proc);
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
        logger.debug("kill({}, {})", .{ proc, @intFromEnum(exit_code) });
        std.debug.assert(!proc.is_zombie());

        proc.exit_code = exit_code;
        process_list.remove(&proc.list_item);

        if (exclusive_video_controller == proc) {
            exclusive_video_controller = null;
        }

        // Destroy all currently scheduled overlapped calls:
        if (proc.async_context.in_flight.len > 0) {
            logger.warn("process has still {} in-flight overlapped operations", .{
                proc.async_context.in_flight.len,
            });

            while (proc.async_context.in_flight.len > 0) {
                const first = proc.async_context.in_flight.first.?;
                const call = ashet.overlapped.AsyncCall.from_owner_link(first);

                ashet.overlapped.cancel_with_context(call.arc, &proc.async_context) catch |err| {
                    logger.err("unexpected error {} from cancelling overlapped operation", .{err});
                    @panic("This is a kernel bug!");
                };
            }
        }

        // Destroy all threads attached to this process:
        {
            var iter = proc.threads.first;
            while (iter) |link| {
                // we have to advance before we remove the thread
                // from the list (implicitly by kill!)
                iter = link.next;

                std.debug.assert(link.data.process == proc);
                link.data.thread.kill();
            }
        }

        // Drop all resource ownerships. This might delete the process so it has to be last!
        ashet.resources.unlink_process(proc, true);
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

    pub fn format(proc: *const Process, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (proc.is_zombie()) {
            try writer.print("Process(0x{X:0>8}, \"{}\", <zombie>)", .{ @intFromPtr(proc), std.zig.fmtEscapes(proc.name) });
        } else {
            try writer.print("Process(0x{X:0>8}, \"{}\", base=0x{X:0>8})", .{
                @intFromPtr(proc),
                std.zig.fmtEscapes(proc.name),
                if (proc.executable_memory) |mem| @intFromPtr(mem.ptr) else 0,
            });
        }
    }

    pub fn write_log(proc: *Process, log_level: ashet.abi.LogLevel, text: []const u8) void {
        const output = proc.debug_outputs.getPtr(log_level);

        const process_logger = std.log.scoped(.userland);

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

pub fn debug_dump() void {
    logger.info("process list:", .{});
    var iter = process_list.first;
    while (iter) |proc_node| : (iter = proc_node.next) {
        const proc: *Process = @fieldParentPtr("list_item", proc_node);

        logger.info("- {}", .{proc});

        for (0..proc.resource_handles.bit_map.capacity()) |i| {
            if (proc.resource_handles.bit_map.isSet(i) == false) {
                const item = proc.resource_handles.owners.at(i);
                logger.info("  - {} => {}", .{
                    item.data.handle,
                    item.data.resource,
                });
            }
        }
    }
}
