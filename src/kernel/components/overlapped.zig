const std = @import("std");
const hal = @import("hal");
const abi = ashet.abi;
const ashet = @import("../main.zig");
const astd = @import("ashet-std");
const logger = std.log.scoped(.overlapped);

pub const ARC = ashet.abi.ARC;
const WaitIO = ashet.abi.WaitIO;

const work_queue_count = 1;
var next_work_queue: usize = 0;
var work_queues: [work_queue_count]WorkQueue = undefined;

pub fn initialize() !void {
    var buffer: [32]u8 = undefined;
    for (&work_queues, 0..) |*wq, index| {
        const thread = try ashet.scheduler.Thread.spawn(background_worker_loop, wq, .{});

        try thread.setName(try std.fmt.bufPrint(&buffer, "background{}", .{index}));

        wq.* = WorkQueue{ .wakeup_thread = thread };

        thread.start() catch unreachable;

        thread.detach();
    }
}

/// Returns the current thread and async scheduling context.
fn get_context() struct { *ashet.scheduler.Thread, *Context } {
    const thread = ashet.scheduler.Thread.current() orelse @panic("schedule_and_await called in a non-thread context!");
    const context: *Context = &thread.process_link.data.process.async_context;
    return .{ thread, context };
}

const AsyncHandler = struct {
    call: *const fn (*AsyncCall) void,

    pub fn todo(comptime msg: []const u8) AsyncHandler {
        const Wrap = struct {
            fn call(_call: *AsyncCall) void {
                _ = _call;
                @panic(msg ++ " is not implemented yet!");
            }
        };
        return .{
            .call = &Wrap.call,
        };
    }

    pub fn wrap(comptime func: anytype) AsyncHandler {
        const F = @TypeOf(func);

        const fun_info = @typeInfo(F).Fn;

        std.debug.assert(fun_info.return_type == void);
        std.debug.assert(fun_info.is_var_args == false);
        std.debug.assert(fun_info.is_generic == false);

        const Wrap = switch (fun_info.params.len) {
            1 => struct {
                const call = func;
            },

            2 => struct {
                const Inputs = fun_info.params[1].type.?;
                const Generic = Inputs.Overlapped;
                comptime {
                    std.debug.assert(@typeInfo(Inputs) == .Struct);
                }

                const original: fn (*AsyncCall, Inputs) void = func;

                fn call(_call: *AsyncCall) void {
                    const generic = _call.arc.cast(Generic);
                    return original(_call, generic.inputs);
                }
            },

            else => @compileError("invalid arguments"),
        };

        return AsyncHandler{
            .call = &Wrap.call,
        };
    }
};

const async_call_handlers = std.EnumArray(ashet.abi.ARC_Type, AsyncHandler).init(.{
    .clock_timer = AsyncHandler.wrap(ashet.time.schedule_timer),
    .datetime_alarm = AsyncHandler.wrap(ashet.time.schedule_alarm),

    .process_spawn = AsyncHandler.wrap(ashet.multi_tasking.spawn_overlapped),

    .random_get_strict_random = AsyncHandler.todo("random_get_strict_random"),

    .network_tcp_bind = AsyncHandler.wrap(ashet.network.tcp.bind),
    .network_tcp_connect = AsyncHandler.wrap(ashet.network.tcp.connect),
    .network_tcp_send = AsyncHandler.wrap(ashet.network.tcp.send),
    .network_tcp_receive = AsyncHandler.wrap(ashet.network.tcp.receive),

    .network_udp_bind = AsyncHandler.wrap(ashet.network.udp.bind),
    .network_udp_connect = AsyncHandler.wrap(ashet.network.udp.connect),
    .network_udp_disconnect = AsyncHandler.wrap(ashet.network.udp.disconnect),
    .network_udp_send = AsyncHandler.wrap(ashet.network.udp.send),
    .network_udp_send_to = AsyncHandler.wrap(ashet.network.udp.sendTo),
    .network_udp_receive_from = AsyncHandler.wrap(ashet.network.udp.receiveFrom),

    .input_get_event = AsyncHandler.wrap(ashet.input.schedule_get_event),

    .fs_sync = AsyncHandler.wrap(ashet.filesystem.sync),
    .fs_get_filesystem_info = AsyncHandler.wrap(ashet.filesystem.getFilesystemInfo),
    .fs_open_drive = AsyncHandler.wrap(ashet.filesystem.openDrive),
    .fs_open_dir = AsyncHandler.wrap(ashet.filesystem.openDir),
    .fs_close_dir = AsyncHandler.wrap(ashet.filesystem.closeDir),
    .fs_reset_dir_enumeration = AsyncHandler.wrap(ashet.filesystem.resetDirEnumeration),
    .fs_enumerate_dir = AsyncHandler.wrap(ashet.filesystem.enumerateDir),
    .fs_delete = AsyncHandler.wrap(ashet.filesystem.delete),
    .fs_mk_dir = AsyncHandler.wrap(ashet.filesystem.mkdir),
    .fs_stat_entry = AsyncHandler.wrap(ashet.filesystem.statEntry),
    .fs_near_move = AsyncHandler.wrap(ashet.filesystem.nearMove),
    .fs_far_move = AsyncHandler.wrap(ashet.filesystem.farMove),
    .fs_copy = AsyncHandler.wrap(ashet.filesystem.copy),
    .fs_open_file = AsyncHandler.wrap(ashet.filesystem.openFile),
    .fs_close_file = AsyncHandler.wrap(ashet.filesystem.closeFile),
    .fs_flush_file = AsyncHandler.wrap(ashet.filesystem.flushFile),
    .fs_read = AsyncHandler.wrap(ashet.filesystem.read),
    .fs_write = AsyncHandler.wrap(ashet.filesystem.write),
    .fs_stat_file = AsyncHandler.wrap(ashet.filesystem.statFile),
    .fs_resize = AsyncHandler.wrap(ashet.filesystem.resize),

    .pipe_write = AsyncHandler.todo("pipe_write"),
    .pipe_read = AsyncHandler.todo("pipe_read"),

    .sync_wait_for_event = AsyncHandler.todo("sync_wait_for_event"),
    .sync_lock = AsyncHandler.todo("sync_lock"),

    .gui_show_message_box = AsyncHandler.todo("gui_show_message_box"),
    .gui_get_window_event = AsyncHandler.wrap(ashet.gui.schedule_get_window_event),

    .draw_render = AsyncHandler.wrap(ashet.graphics.render_async),
});

/// Schedules a new overlapped event from the current thread context.
pub fn schedule(event: *ARC) error{ SystemResources, AlreadyScheduled }!void {
    const thread, const context = get_context();
    return schedule_with_context(thread.get_process(), context, event);
}

/// Schedules a new overlapped event from the given thread and context.
pub fn schedule_with_context(resource_owner: *ashet.multi_tasking.Process, context: *Context, event: *ARC) error{ SystemResources, AlreadyScheduled }!void {
    const call = try AsyncCall.create(
        context,
        event,
        resource_owner,
        ashet.scheduler.Thread.current().?,
    );
    errdefer call.destroy();

    logger.debug("dispatching {s} from {}", .{ @tagName(event.type), resource_owner });

    context.in_flight.append(&call.owner_link);

    const handler = async_call_handlers.get(event.type);
    handler.call(call);
}

pub fn await_completion(completed: []*ARC, options: ashet.abi.Await_Options) error{Unscheduled}!usize {
    _, const context = get_context();
    return await_completion_with_context(context, completed, options);
}

pub fn await_completion_with_context(context: *Context, completed: []*ARC, options: ashet.abi.Await_Options) error{Unscheduled}!usize {
    // We always have to resume the thread calling this function.
    // Everything else doesn't make sense at all:
    const thread = ashet.scheduler.Thread.current().?;

    const filter_thread = switch (options.thread_affinity) {
        .this_thread => thread,
        .all_threads => null,
    };

    var awaiter_node = AwaiterNode{
        .data = .{
            .resume_thread = thread,
            .filter_thread = filter_thread,
        },
    };

    // unset the whole array:
    for (completed) |*arc| {
        arc.* = undefined;
    }

    logger.debug("await completion from {?}", .{filter_thread});

    var count: usize = 0;
    gather_loop: while (count < completed.len) {
        if (pop_with_threadaffinity(&context.completed, filter_thread)) |node| {
            // we have a completed call, fill the queue:
            const call = AsyncCall.from_owner_link(node);
            std.debug.assert(call.work_link.next == null);
            std.debug.assert(call.work_link.prev == null);

            completed[count] = call.arc;
            count += 1;

            logger.debug("returning {s} to userland from {}", .{ @tagName(call.arc.type), thread });

            call.destroy();
        } else {
            // we don't have anything completed yet, so check how
            // the user wants us to proceed:
            switch (options.wait) {
                // we never block, we just immediatly return:
                .dont_block => break :gather_loop,

                // check if we found at least a single return value:
                .wait_one => if (count > 0)
                    break :gather_loop,

                // Check if we have completed all in-flight tasks:
                .wait_all => if (count_with_threadaffinity(context.in_flight, filter_thread) == 0)
                    break :gather_loop,
            }

            logger.debug("suspend {} and wait for completion...", .{thread});

            {
                context.awaiters.append(&awaiter_node);
                defer context.awaiters.remove(&awaiter_node);

                // suspend and wait to be woken up again, in the hope that we've completed events:
                thread.@"suspend"();
            }

            logger.debug("resumed {} from awaiting completion", .{thread});
        }
    }
    logger.debug("await yielded {} items", .{count});

    return count;
}

pub fn cancel(arc: *ARC) error{
    Unscheduled,
    Completed,
}!void {
    _, const context = get_context();
    return cancel_with_context(arc, context);
}

pub fn cancel_with_context(arc: *ARC, context: *Context) error{
    Unscheduled,
    Completed,
}!void {
    const call, const queue_name = context.get_call_object(arc) orelse return error.Unscheduled;

    switch (queue_name) {
        .completed => {
            std.debug.assert(!node_in_queue(context.in_flight, &call.owner_link));
            std.debug.assert(call.work_link.prev == null);
            std.debug.assert(call.work_link.next == null);
            // We're already done
            context.completed.remove(&call.owner_link);
            return error.Completed;
        },
        .in_flight => {
            if (call.cancel_fn) |cancel_fn| {
                context.in_flight.remove(&call.owner_link);
                cancel_fn(call);
            } else {
                // TODO: Implement actual cancelling of events
                logger.err("non-implemented cancel of type {}", .{arc.type});
                @panic("AshetOS has no idea how to cancel this!");
            }
        },
    }
}

pub fn destroy(context: *Context) void {
    logger.err("io.destroy(Context) not implemented yet!", .{});
    _ = context;
}

/// Kernel management object for an asynchronous system call.
///
/// This management object is created with `schedule_and_await` and is returned
/// by either `cancel` or also `schedule_and_await`.
pub const AsyncCall = struct {
    arc: *ARC,

    /// The scheduling context for this ARC. Controls awaiters and completion queue.
    context: *Context,

    /// Stores the process which owns created/referenced resource handles.
    resource_owner: *ashet.multi_tasking.Process,

    /// Stores the thread that scheduled this call
    scheduling_thread: *ashet.scheduler.Thread,

    /// Stored inside the `Context` type, can be used to list all
    /// async calls for a given process.
    owner_link: CallQueue.Node = .{ .data = {} },

    /// Stored inside a `WorkQueue` type. Is used to provide kernel subsystems
    /// a way to store their pending tasks.
    work_link: WorkQueue.Node = .{ .data = null },

    /// Function pointer to a function that cancels the async call
    /// after it has been fetched from its work_queue, but was not moved
    /// to the "completed" queue.
    cancel_fn: ?*const fn (*AsyncCall) void = null,

    /// A pointer to a context that can be used to bypass several lookups
    /// from `arc` to cancel the operation quickly.
    cancel_context: ?*anyopaque = null,

    // /// Returns the thread that scheduled the ARC.
    // pub fn get_thread(ac: *AsyncCall) *ashet.scheduler.Thread {
    //     return ac.thread;
    // }

    // /// Returns the process that scheduled the ARC.
    // pub fn get_process(ac: *AsyncCall) *ashet.multi_tasking.Process {
    //     return ac.thread.process_link.data.process;
    // }

    /// Finalizes the ARC with the provided `result` which is either an error or the outputs of the
    /// ARC.
    pub fn finalize(ac: *AsyncCall, comptime T: type, result: T.Error!T.Outputs) void {
        if (!comptime ARC.is_arc(T))
            @compileError("finalize_with_error requires an ARC instance!");

        const expected_type: ashet.abi.ARC_Type = T.arc_type;
        std.debug.assert(ac.arc.type == expected_type);
        if (result) |value| {
            const generic: *T = T.from_arc(ac.arc);
            generic.outputs = value;
            generic.set_ok();
            logger.debug("completing {s} with result", .{@tagName(ac.arc.type)});
        } else |err| {
            const generic: *T = T.from_arc(ac.arc);
            generic.outputs = undefined; // explicitly kill the content here in debug kernels
            generic.set_error(err);
            logger.debug("completing {s} with error {s}", .{ @tagName(ac.arc.type), @errorName(err) });
        }
        ac.finalize_unsafe();
    }

    /// Completes the `event` element and moves it from the in_flight queue into the completed queue.
    fn finalize_unsafe(ac: *AsyncCall) void {
        std.debug.assert(ac.work_link.prev == null);
        std.debug.assert(ac.work_link.next == null);

        std.debug.assert(node_in_queue(ac.context.in_flight, &ac.owner_link));
        defer std.debug.assert(node_in_queue(ac.context.completed, &ac.owner_link));

        ac.context.in_flight.remove(&ac.owner_link);
        ac.context.completed.append(&ac.owner_link);

        // When we finish an event, we have to ensure potential awaiters are woken up and resume
        // the processing:

        {
            var iter = ac.context.awaiters.first;
            while (iter) |node| : (iter = node.next) {
                if (node.data.filter_thread == null or node.data.filter_thread == ac.scheduling_thread) {
                    node.data.resume_thread.@"resume"();
                }
            }
        }
    }

    fn create(
        context: *Context,
        arc: *ARC,
        resource_owner: *ashet.multi_tasking.Process,
        scheduling_thread: *ashet.scheduler.Thread,
    ) error{SystemResources}!*AsyncCall {
        const item = ashet.memory.type_pool(AsyncCall).alloc() catch return error.SystemResources;
        item.* = AsyncCall{
            .context = context,
            .arc = arc,
            .resource_owner = resource_owner,
            .scheduling_thread = scheduling_thread,
        };
        return item;
    }

    /// Destroys the async call. Asserts that the call isn't in-flight anymore.
    fn destroy(call: *AsyncCall) void {

        // Check if the call isn't queued anymore:
        std.debug.assert(!node_in_queue(call.context.in_flight, &call.owner_link));
        std.debug.assert(!node_in_queue(call.context.completed, &call.owner_link));
        std.debug.assert(call.owner_link.prev == null);
        std.debug.assert(call.owner_link.next == null);
        std.debug.assert(call.work_link.prev == null);
        std.debug.assert(call.work_link.next == null);

        ashet.memory.type_pool(AsyncCall).free(call);
    }

    fn from_work_link(node: *WorkQueue.Node) *AsyncCall {
        return @fieldParentPtr("work_link", node);
    }

    pub fn from_owner_link(node: *CallQueue.Node) *AsyncCall {
        return @fieldParentPtr("owner_link", node);
    }
};

/// A structure that describes an active invocation of `await_completion_with_context`
/// and allows resuming that function.
const Awaiter = struct {
    /// Which thread must be resumed to complete?
    resume_thread: *ashet.scheduler.Thread,

    /// Which thread has scheduled the original async call?
    filter_thread: ?*ashet.scheduler.Thread,
};

const AwaiterList = std.DoublyLinkedList(Awaiter);
const AwaiterNode = AwaiterList.Node;

/// Management context for async running calls.
pub const Context = struct {
    /// List of all in-flight elements
    in_flight: CallQueue = .{},

    /// List of all completed elements.
    completed: CallQueue = .{},

    /// Number of active `await_completion` calls. If non-zero, the awaiting thread should
    /// be resumed.
    awaiters: AwaiterList = .{},

    pub const QueueName = enum { in_flight, completed };

    pub fn get_call_object(ctx: Context, arc: *ARC) ?struct { *AsyncCall, QueueName } {
        // Search the completion queue first, as we're interested primarily in those.
        {
            var it = ctx.completed.first;
            while (it) |node| : (it = node.next) {
                const call = AsyncCall.from_owner_link(node);
                if (call.arc == arc) {
                    std.debug.assert(!node_in_queue(ctx.in_flight, &call.owner_link));
                    return .{ call, .completed };
                }
            }
        }

        // Then search the in-flight queue:
        {
            var it = ctx.in_flight.first;
            while (it) |node| : (it = node.next) {
                const call = AsyncCall.from_owner_link(node);
                if (call.arc == arc) {
                    std.debug.assert(!node_in_queue(ctx.completed, &call.owner_link));
                    return .{ call, .in_flight };
                }
            }
        }

        return null;
    }
};

const CallQueue = std.DoublyLinkedList(void);

fn node_in_queue(q: CallQueue, n: *CallQueue.Node) bool {
    var iter = q.first;
    return while (iter) |node| : (iter = node.next) {
        if (iter == n)
            break true;
    } else false;
}

/// A work queue for ARCs, meant for the use inside
/// subsystems that handle asynchronous calls.
pub const WorkQueue = struct {
    const Backing = std.DoublyLinkedList(Item);

    pub const Item = ?*anyopaque;
    pub const Node = Backing.Node;

    /// If this is set, the queue will wake up the thread
    /// so it can resume working on the queued tasks.
    wakeup_thread: ?*ashet.scheduler.Thread,

    queue: Backing = .{},

    /// Returns the next-to-be-dequeued job.
    pub fn get_head(wq: WorkQueue) ?*AsyncCall {
        const node = wq.queue.first orelse return null;
        return AsyncCall.from_work_link(node);
    }

    /// Enqueues an ARC into
    pub fn enqueue(wq: *WorkQueue, arc: *AsyncCall, item: Item) void {
        std.debug.assert(arc.work_link.next == null);
        std.debug.assert(arc.work_link.prev == null);

        arc.work_link = .{ .data = item };

        wq.queue.append(&arc.work_link);

        if (wq.wakeup_thread) |thread| {
            // Wake up the optionally attached thread so work can be resumed:
            thread.@"resume"();
        }
    }

    /// Inserts an ARC into the WorkQueue based on a priority. The priority is determined
    /// by calling `comparer.lt(arc, node)`, with `node` being any node in the list.
    /// If `arc` is less than node, it will be scheduled before the first `node` that meets
    /// that requirement.
    pub fn priority_enqueue(wq: *WorkQueue, arc: *AsyncCall, item: Item, comparer: anytype) void {
        std.debug.assert(arc.work_link.next == null);
        std.debug.assert(arc.work_link.prev == null);

        arc.work_link = .{ .data = item };

        if (wq.queue.first != null) {
            var iter = wq.queue.first;

            while (iter) |node| : (iter = node.next) {
                // check if the new node is "more important" then
                // the one we're iterating. If so, insert the node
                // before the current node as it's higher priority:
                const point = AsyncCall.from_work_link(node);
                if (!comparer.lt(arc, point)) {
                    wq.queue.insertBefore(node, &arc.work_link);
                    break;
                }
            } else {
                // we did not break the while, so we reached the end,
                // so our node is the least priority task:
                wq.queue.append(&arc.work_link);
            }
        } else {
            std.debug.assert(wq.queue.len == 0);
            wq.queue.append(&arc.work_link);
        }

        if (wq.wakeup_thread) |thread| {
            // Wake up the optionally attached thread so work can be resumed:
            thread.@"resume"();
        }
    }

    /// Pops a single work item from the queue and returns it.
    /// Returns `null` if no work items are present.
    pub fn dequeue(wq: *WorkQueue) ?struct { *AsyncCall, Item } {
        const node = wq.queue.popFirst() orelse return null;
        node.next = null;
        node.prev = null;
        const call: *AsyncCall = @fieldParentPtr("work_link", node);
        return .{ call, node.data };
    }

    /// Returns `true` if the `arc` is currently queued in this queue.
    pub fn contains(wq: WorkQueue, arc: *AsyncCall) bool {
        return node_in_queue(wq.queue, &arc.work_link);
    }

    /// Removes a call from this queue.
    pub fn remove(wq: *WorkQueue, arc: *AsyncCall) bool {
        var iter = wq.queue.first;
        while (iter) |node| : (iter = node.next) {
            if (node == &arc.work_link) {
                wq.queue.remove(node);
                return true;
            }
        }
        return false;
    }
};

/// Handler for background workers.
pub const Background_Worker = fn (*Context, *AsyncCall) void;

/// Wraps an asynchronous call handler that takes input and returns a generic version.
pub fn create_handler(comptime Arc: type, comptime handler: fn (*Context, *AsyncCall, Arc.Inputs) Arc.Error!Arc.Outputs) *const Background_Worker {
    const Wrap = struct {
        fn wrapped(ctx: *Context, call: *AsyncCall) void {
            const cast = call.arc.cast(Arc);
            call.finalize(Arc, handler(ctx, call, cast.inputs));
        }
    };
    return Wrap.wrapped;
}

/// Queues `call` to be processed by `handler` in a background thread.
pub fn enqueue_background_task(call: *AsyncCall, handler: *const Background_Worker) void {
    const i = next_work_queue;
    next_work_queue += 1;
    if (next_work_queue >= work_queues.len) {
        next_work_queue = 0;
    }
    work_queues[i].enqueue(call, @constCast(handler));
}

fn background_worker_loop(context: ?*anyopaque) callconv(.C) u32 {
    const q: *WorkQueue = @ptrCast(@alignCast(context.?));

    logger.info("overlapped background worker ready.", .{});

    var overlapped_context = Context{};

    while (true) {
        while (q.dequeue()) |work_item| {
            const call, const ctx = work_item;

            const worker: *const Background_Worker = @ptrCast(ctx);

            logger.debug("execute overlapped call .{s}", .{@tagName(call.arc.type)});
            worker(&overlapped_context, call);
        }

        // go to sleep again until we're done.
        ashet.scheduler.Thread.current().?.@"suspend"();
    }
}

/// Pops the first element of the queue that belongs to `thread_filter` if set or any thread if `thread_filter` is null`.
fn pop_with_threadaffinity(queue: *CallQueue, thread_filter: ?*ashet.scheduler.Thread) ?*CallQueue.Node {
    const thread = thread_filter orelse return queue.popFirst();
    var iter = queue.first;
    while (iter) |node| : (iter = node.next) {
        const call = AsyncCall.from_owner_link(node);
        if (call.scheduling_thread == thread) {
            queue.remove(node);
            return node;
        }
    }
    return null;
}

/// Counts all elements in `queue` which belong to `thread_filter` if set or returns the total count if `thread_filter` is `null`.
fn count_with_threadaffinity(queue: CallQueue, thread_filter: ?*ashet.scheduler.Thread) usize {
    const thread = thread_filter orelse return queue.len;

    var count: usize = 0;
    var iter = queue.first;
    while (iter) |node| : (iter = node.next) {
        const call = AsyncCall.from_owner_link(node);
        if (call.scheduling_thread == thread) {
            count += 1;
        }
    }

    return 1;
}
