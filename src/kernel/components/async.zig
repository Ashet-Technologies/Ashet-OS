const std = @import("std");
const hal = @import("hal");
const abi = ashet.abi;
const ashet = @import("../main.zig");
const astd = @import("ashet-std");
const logger = std.log.scoped(.io);

pub const ARC = ashet.abi.ARC;
const WaitIO = ashet.abi.WaitIO;

const KernelData = struct {
    context: *Context,
    thread: *ashet.scheduler.Thread,
    // data: Data,

    /// This node is linked into one of the linked lists inside `Context`.
    owner_node: EventQueueNode = .{ .data = {} },

    /// This node is linked into interior lists of kernel components that handle this async call.
    schedule_node: EventQueueNode = .{ .data = {} },

    flags: Flags,

    // const Data = extern union {
    //     padding: [4]usize,
    // };

    const Flags = packed struct(usize) {
        resume_on_completed: bool,
        padding: @Type(.{ .Int = .{ .bits = @bitSizeOf(usize) - 1, .signedness = .unsigned } }) = 0,
    };

    /// Casts the opaque kernel data into the actual instance.
    pub fn get(ptr: *ARC) *KernelData {
        return @as(*KernelData, @ptrCast(&ptr.kernel_data));
    }

    /// Returns the ARC for the provided kernel data pointer.
    pub fn get_arc(ptr: *KernelData) *ARC {
        return @fieldParentPtr("kernel_data", ptr);
    }
};

/// Returns the thread that scheduled the ARC.
pub fn get_thread(arc: *ARC) *ashet.scheduler.Thread {
    return KernelData.get(arc).thread;
}

/// Returns the process that scheduled the ARC.
pub fn get_process(arc: *ARC) *ashet.multi_tasking.Process {
    return get_thread(arc).process_link.data.process;
}

comptime {
    // assert that KernelData can alias to the erased data structure
    const ErasedData = std.meta.fieldInfo(ARC, .kernel_data).type;
    std.debug.assert(@sizeOf(KernelData) == @sizeOf(ErasedData));
    std.debug.assert(@alignOf(KernelData) <= @alignOf(ErasedData));
}

/// Management context for async running calls.
pub const Context = struct {
    /// List of all in-flight elements
    in_flight: EventQueue = .{},

    /// List of all completed elements.
    completed: EventQueue = .{},
};

/// Completes the `event` element and moves it from the in_flight queue into the completed queue.
pub fn finalize(event: *ARC) void {
    const data = KernelData.get(event);

    std.debug.assert(data.schedule_node.prev == null);
    std.debug.assert(data.schedule_node.next == null);

    std.debug.assert(node_in_queue(data.context.in_flight, &data.owner_node));
    defer std.debug.assert(node_in_queue(data.context.completed, &data.owner_node));

    data.context.in_flight.remove(&data.owner_node);
    data.context.completed.append(&data.owner_node);

    // We finished an event, resume the thread if its waiting for I/O:
    if (data.flags.resume_on_completed) {
        data.thread.@"resume"();
    }
}

/// Finalizes the `generic` ARC with the `err` error code.
pub fn finalize_with_error(generic: anytype, err: anyerror) void {
    if (!comptime ARC.is_arc(@TypeOf(generic.*)))
        @compileError("finalize_with_error requires an ARC instance!");
    generic.outputs = undefined; // explicitly kill the content here in debug kernels
    generic.set_error(astd.mapToUnexpected(@TypeOf(generic.*).Error, err));
    finalize(&generic.arc);
}

/// Finalizes the `generic` ARC with the `outputs` result.
pub fn finalize_with_result(generic: anytype, outputs: @TypeOf(generic.*).Outputs) void {
    if (!comptime ARC.is_arc(@TypeOf(generic.*)))
        @compileError("finalize_with_result requires an ARC instance!");
    generic.outputs = outputs;
    generic.set_ok();
    finalize(&generic.arc);
}

var kernel_context: Context = .{};

pub fn schedule_and_await(start_queue: ?*ARC, options: abi.Schedule_And_Await_Options) ?*ARC {
    ashet.stackCheck();

    const thread = ashet.scheduler.Thread.current() orelse @panic("schedule_and_await called in a non-thread context!");
    const context: *Context = &thread.process_link.data.process.async_context;
    // const process = thread.process orelse @panic("scheduleAndAwait called in a non-process context!");

    // TODO: verify that start_queue has no loops

    var queue = start_queue;
    while (queue) |event| {
        // advance the queue as the first step, so we can now destroy and
        // restructeventure the linked list properties of our current event
        queue = event.next;
        std.debug.assert(queue != start_queue); // very basic sanity check

        const data = KernelData.get(event);
        data.* = KernelData{
            .context = context,
            .thread = thread,
            .flags = .{
                .resume_on_completed = (options.wait != .dont_block),
            },
        };

        logger.debug("dispatching i/o: {s}", .{@tagName(event.type)});

        // unhinge from queue, so we're able to finish the ARC immediatly.
        event.next = null;
        context.in_flight.append(&data.owner_node);

        switch (event.type) {
            .clock_timer => ashet.time.scheduleTimer(ARC.cast(abi.clock.Timer, event)),

            .process_spawn => @panic("not done yet"),

            .random_get_strict_random => @panic("not done yet"),

            .network_tcp_bind => ashet.network.tcp.bind(ARC.cast(abi.tcp.Bind, event)),
            .network_tcp_connect => ashet.network.tcp.connect(ARC.cast(abi.tcp.Connect, event)),
            .network_tcp_send => ashet.network.tcp.send(ARC.cast(abi.tcp.Send, event)),
            .network_tcp_receive => ashet.network.tcp.receive(ARC.cast(abi.tcp.Receive, event)),

            .network_udp_bind => ashet.network.udp.bind(ARC.cast(abi.udp.Bind, event)),
            .network_udp_connect => ashet.network.udp.connect(ARC.cast(abi.udp.Connect, event)),
            .network_udp_disconnect => ashet.network.udp.disconnect(ARC.cast(abi.udp.Disconnect, event)),
            .network_udp_send => ashet.network.udp.send(ARC.cast(abi.udp.Send, event)),
            .network_udp_send_to => ashet.network.udp.sendTo(ARC.cast(abi.udp.SendTo, event)),
            .network_udp_receive_from => ashet.network.udp.receiveFrom(ARC.cast(abi.udp.ReceiveFrom, event)),

            .input_get_event => ashet.input.getEventARC(ARC.cast(abi.input.GetEvent, event)),

            // fs api

            .fs_sync => ashet.filesystem.sync(ARC.cast(abi.fs.Sync, event)),
            .fs_get_filesystem_info => ashet.filesystem.getFilesystemInfo(ARC.cast(abi.fs.GetFilesystemInfo, event)),
            .fs_open_drive => ashet.filesystem.openDrive(ARC.cast(abi.fs.OpenDrive, event)),
            .fs_open_dir => ashet.filesystem.openDir(ARC.cast(abi.fs.OpenDir, event)),
            .fs_close_dir => ashet.filesystem.closeDir(ARC.cast(abi.fs.CloseDir, event)),
            .fs_reset_dir_enumeration => ashet.filesystem.resetDirEnumeration(ARC.cast(abi.fs.ResetDirEnumeration, event)),
            .fs_enumerate_dir => ashet.filesystem.enumerateDir(ARC.cast(abi.fs.EnumerateDir, event)),
            .fs_delete => ashet.filesystem.delete(ARC.cast(abi.fs.Delete, event)),
            .fs_mk_dir => ashet.filesystem.mkdir(ARC.cast(abi.fs.MkDir, event)),
            .fs_stat_entry => ashet.filesystem.statEntry(ARC.cast(abi.fs.StatEntry, event)),
            .fs_near_move => ashet.filesystem.nearMove(ARC.cast(abi.fs.NearMove, event)),
            .fs_far_move => ashet.filesystem.farMove(ARC.cast(abi.fs.FarMove, event)),
            .fs_copy => ashet.filesystem.copy(ARC.cast(abi.fs.Copy, event)),
            .fs_open_file => ashet.filesystem.openFile(ARC.cast(abi.fs.OpenFile, event)),
            .fs_close_file => ashet.filesystem.closeFile(ARC.cast(abi.fs.CloseFile, event)),
            .fs_flush_file => ashet.filesystem.flushFile(ARC.cast(abi.fs.FlushFile, event)),
            .fs_read => ashet.filesystem.read(ARC.cast(abi.fs.Read, event)),
            .fs_write => ashet.filesystem.write(ARC.cast(abi.fs.Write, event)),
            .fs_stat_file => ashet.filesystem.statFile(ARC.cast(abi.fs.StatFile, event)),
            .fs_resize => ashet.filesystem.resize(ARC.cast(abi.fs.Resize, event)),

            // .fs_delete => ashet.filesystem.delete(ARC.cast(abi.fs.Delete, event)),
            // .fs_mkdir => ashet.filesystem.mkdir(ARC.cast(abi.fs.MkDir, event)),
            // .fs_rename => ashet.filesystem.rename(ARC.cast(abi.fs.Rename, event)),
            // .fs_stat => ashet.filesystem.stat(ARC.cast(abi.fs.Stat, event)),

            // // file api
            // .fs_openFile => ashet.filesystem.open(ARC.cast(abi.fs.file.Open, event)),
            // .fs_read => ashet.filesystem.read(ARC.cast(abi.fs.file.Read, event)),
            // .fs_write => ashet.filesystem.write(ARC.cast(abi.fs.file.Write, event)),
            // .fs_seekTo => ashet.filesystem.seekTo(ARC.cast(abi.fs.file.SeekTo, event)),
            // .fs_flush => ashet.filesystem.flush(ARC.cast(abi.fs.file.Flush, event)),
            // .fs_close => ashet.filesystem.close(ARC.cast(abi.fs.file.Close, event)),

            // // dir api:
            // .fs_openDir => ashet.filesystem.openDir(ARC.cast(abi.fs.dir.Open, event)),
            // .fs_nextFile => ashet.filesystem.next(ARC.cast(abi.fs.dir.Next, event)),
            // .fs_closeDir => ashet.filesystem.closeDir(ARC.cast(abi.fs.dir.Close, event)),
        }
    }

    switch (options.wait) {
        .schedule_only => return null, // do nothing, and also don't flush the completed queue
        .dont_block => {}, // just do nothing here :)
        .wait_one => while (context.completed.len == 0) {
            thread.@"suspend"(); // we're waiting for completion, so we can remove ourselves from scheduling
        },
        .wait_all => while (context.pending > 0) {
            thread.@"suspend"(); // we're waiting for completion, so we can remove ourselves from scheduling
        },
    }

    return context.completed.flush();
}

pub fn cancel(event: *ashet.abi.ARC) void {
    ashet.stackCheck();

    const thread = ashet.scheduler.Thread.current() orelse @panic("scheduleAndAwait called in a non-thread context!");
    const context: *Context = &thread.process_link.data.process.async_context;

    const data = KernelData.get(event);

    if (node_in_queue(context.completed, &data.owner_node)) {
        std.debug.assert(!node_in_queue(context.in_flight, &data.owner_node));
        std.debug.assert(data.schedule_node.prev == null);
        std.debug.assert(data.schedule_node.next == null);
        // We're already done
        context.completed.remove(&data.owner_node);
        return;
    } else if (node_in_queue(context.in_flight, &data.owner_node)) {
        std.debug.assert(node_in_queue(context.in_flight, &data.owner_node));
    }

    switch (event.type) {
        else => {
            logger.err("non-implemented cancel of type {}", .{event.type});
            @panic("unimplemented cancel!");
        },
    }
}

pub fn destroy(context: *Context) void {
    logger.err("io.destroy(Context) not implemented yet!", .{});
    _ = context;
}

const EventQueue = std.DoublyLinkedList(void);

const EventQueueNode = EventQueue.Node;

fn node_in_queue(q: EventQueue, n: *EventQueueNode) bool {
    var iter = q.first;
    return while (iter) |node| : (iter = node.next) {
        if (iter == n)
            break true;
    } else false;
}

/// A work queue for ARCs, meant for the use inside
/// subsystems that handle asynchronous calls.
pub const WorkQueue = struct {
    /// If this is set, the queue will wake up the thread
    /// so it can resume working on the queued tasks.
    wakeup_thread: ?*ashet.scheduler.Thread,

    queue: EventQueue = .{},

    /// Enqueues an ARC into
    pub fn enqueue(wq: *WorkQueue, arc: *ARC) void {
        const data = KernelData.get(arc);

        // Assert the node isn't accidently queued yet:
        std.debug.assert(data.schedule_node.prev == null);
        std.debug.assert(data.schedule_node.next == null);
        std.debug.assert(!wq.contains(arc));

        wq.queue.append(&data.schedule_node);

        if (wq.wakeup_thread) |thread| {
            // Wake up the optionally attached thread so work can be resumed:
            thread.@"resume"();
        }
    }

    /// Pops a single work item from the queue and returns it.
    /// Returns `null` if no work items are present.
    pub fn dequeue(wq: *WorkQueue) ?*ARC {
        const node = wq.queue.popFirst() orelse return null;
        const data: *KernelData = @fieldParentPtr("schedule_node", node);
        return data.get_arc();
    }

    /// Returns `true` if the `arc` is currently queued in this queue.
    pub fn contains(wq: WorkQueue, arc: *ARC) bool {
        return node_in_queue(wq.queue, &KernelData.get(arc).schedule_node);
    }
};
