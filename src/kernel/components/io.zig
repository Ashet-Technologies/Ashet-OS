const std = @import("std");
const hal = @import("hal");
const abi = ashet.abi;
const ashet = @import("../main.zig");
const astd = @import("ashet-std");
const logger = std.log.scoped(.io);

const IOP = ashet.abi.IOP;
const WaitIO = ashet.abi.WaitIO;

const KernelData = extern struct {
    context: *Context,
    thread: *ashet.scheduler.Thread,
    data: Data,
    flags: Flags,

    const Data = extern union {
        padding: [4]usize,
    };

    const Flags = packed struct(usize) {
        resume_on_completed: bool,
        padding: @Type(.{ .Int = .{ .bits = @bitSizeOf(usize) - 1, .signedness = .unsigned } }) = 0,
    };

    pub fn get(ptr: *IOP) *KernelData {
        return @as(*KernelData, @ptrCast(&ptr.kernel_data));
    }
};

comptime {
    // assert that KernelData can alias to the erased data structure
    const ErasedData = std.meta.fieldInfo(IOP, .kernel_data).type;
    std.debug.assert(@sizeOf(KernelData) == @sizeOf(ErasedData));
    std.debug.assert(@alignOf(KernelData) <= @alignOf(ErasedData));
}

pub const Context = struct {
    pending: usize = 0,
    completed: EventQueue = .{},
};

pub fn finalize(event: *IOP) void {
    const data = KernelData.get(event);
    data.context.completed.enqueue(event);
    data.context.pending -= 1;

    // We finished an event, resume the thread if its waiting for I/O:
    if (data.flags.resume_on_completed) {
        data.thread.@"resume"();
    }
}

pub fn finalizeWithError(generic: anytype, err: anyerror) void {
    if (!comptime IOP.isIOP(@TypeOf(generic.*)))
        @compileError("finalizeWithError requires an IOP instance!");
    generic.outputs = undefined; // explicitly kill the content here in debug kernels
    generic.setError(astd.mapToUnexpected(@TypeOf(generic.*).Error, err));
    finalize(&generic.iop);
}

pub fn finalizeWithResult(generic: anytype, outputs: @TypeOf(generic.*).Outputs) void {
    if (!comptime IOP.isIOP(@TypeOf(generic.*)))
        @compileError("finalizeWithError requires an IOP instance!");
    generic.outputs = outputs;
    generic.setOk();
    finalize(&generic.iop);
}

var kernel_context: Context = .{};

pub fn scheduleAndAwait(start_queue: ?*IOP, wait: WaitIO) ?*IOP {
    ashet.stackCheck();

    const thread = ashet.scheduler.Thread.current() orelse @panic("scheduleAndAwait called in a non-thread context!");
    const context: *Context = if (thread.process_link) |link|
        &link.data.process.io_context
    else
        &kernel_context; // kernel can also schedule I/Os
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
                .resume_on_completed = (wait != .dont_block),
            },
            .data = undefined,
        };

        logger.debug("dispatching i/o: {s}", .{@tagName(event.type)});

        // unhinge from queue, so we're able to finish the IOP immediatly.
        event.next = null;
        context.pending += 1;

        switch (event.type) {
            .timer => ashet.time.scheduleTimer(IOP.cast(abi.Timer, event)),

            .tcp_bind => ashet.network.tcp.bind(IOP.cast(abi.tcp.Bind, event)),
            .tcp_connect => ashet.network.tcp.connect(IOP.cast(abi.tcp.Connect, event)),
            .tcp_send => ashet.network.tcp.send(IOP.cast(abi.tcp.Send, event)),
            .tcp_receive => ashet.network.tcp.receive(IOP.cast(abi.tcp.Receive, event)),

            .udp_bind => ashet.network.udp.bind(IOP.cast(abi.udp.Bind, event)),
            .udp_connect => ashet.network.udp.connect(IOP.cast(abi.udp.Connect, event)),
            .udp_disconnect => ashet.network.udp.disconnect(IOP.cast(abi.udp.Disconnect, event)),
            .udp_send => ashet.network.udp.send(IOP.cast(abi.udp.Send, event)),
            .udp_send_to => ashet.network.udp.sendTo(IOP.cast(abi.udp.SendTo, event)),
            .udp_receive_from => ashet.network.udp.receiveFrom(IOP.cast(abi.udp.ReceiveFrom, event)),

            .input_get_event => ashet.input.getEventIOP(IOP.cast(abi.input.GetEvent, event)),

            .ui_get_event => @panic("deprecated iop"), // ashet.ui.getEvent(IOP.cast(abi.ui.GetEvent, event)),

            // fs api

            .fs_sync => ashet.filesystem.sync(IOP.cast(abi.fs.Sync, event)),
            .fs_get_filesystem_info => ashet.filesystem.getFilesystemInfo(IOP.cast(abi.fs.GetFilesystemInfo, event)),
            .fs_open_drive => ashet.filesystem.openDrive(IOP.cast(abi.fs.OpenDrive, event)),
            .fs_open_dir => ashet.filesystem.openDir(IOP.cast(abi.fs.OpenDir, event)),
            .fs_close_dir => ashet.filesystem.closeDir(IOP.cast(abi.fs.CloseDir, event)),
            .fs_reset_dir_enumeration => ashet.filesystem.resetDirEnumeration(IOP.cast(abi.fs.ResetDirEnumeration, event)),
            .fs_enumerate_dir => ashet.filesystem.enumerateDir(IOP.cast(abi.fs.EnumerateDir, event)),
            .fs_delete => ashet.filesystem.delete(IOP.cast(abi.fs.Delete, event)),
            .fs_mkdir => ashet.filesystem.mkdir(IOP.cast(abi.fs.MkDir, event)),
            .fs_stat_entry => ashet.filesystem.statEntry(IOP.cast(abi.fs.StatEntry, event)),
            .fs_near_move => ashet.filesystem.nearMove(IOP.cast(abi.fs.NearMove, event)),
            .fs_far_move => ashet.filesystem.farMove(IOP.cast(abi.fs.FarMove, event)),
            .fs_copy => ashet.filesystem.copy(IOP.cast(abi.fs.Copy, event)),
            .fs_open_file => ashet.filesystem.openFile(IOP.cast(abi.fs.OpenFile, event)),
            .fs_close_file => ashet.filesystem.closeFile(IOP.cast(abi.fs.CloseFile, event)),
            .fs_flush_file => ashet.filesystem.flushFile(IOP.cast(abi.fs.FlushFile, event)),
            .fs_read => ashet.filesystem.read(IOP.cast(abi.fs.Read, event)),
            .fs_write => ashet.filesystem.write(IOP.cast(abi.fs.Write, event)),
            .fs_stat_file => ashet.filesystem.statFile(IOP.cast(abi.fs.StatFile, event)),
            .fs_resize => ashet.filesystem.resize(IOP.cast(abi.fs.Resize, event)),

            // .fs_delete => ashet.filesystem.delete(IOP.cast(abi.fs.Delete, event)),
            // .fs_mkdir => ashet.filesystem.mkdir(IOP.cast(abi.fs.MkDir, event)),
            // .fs_rename => ashet.filesystem.rename(IOP.cast(abi.fs.Rename, event)),
            // .fs_stat => ashet.filesystem.stat(IOP.cast(abi.fs.Stat, event)),

            // // file api
            // .fs_openFile => ashet.filesystem.open(IOP.cast(abi.fs.file.Open, event)),
            // .fs_read => ashet.filesystem.read(IOP.cast(abi.fs.file.Read, event)),
            // .fs_write => ashet.filesystem.write(IOP.cast(abi.fs.file.Write, event)),
            // .fs_seekTo => ashet.filesystem.seekTo(IOP.cast(abi.fs.file.SeekTo, event)),
            // .fs_flush => ashet.filesystem.flush(IOP.cast(abi.fs.file.Flush, event)),
            // .fs_close => ashet.filesystem.close(IOP.cast(abi.fs.file.Close, event)),

            // // dir api:
            // .fs_openDir => ashet.filesystem.openDir(IOP.cast(abi.fs.dir.Open, event)),
            // .fs_nextFile => ashet.filesystem.next(IOP.cast(abi.fs.dir.Next, event)),
            // .fs_closeDir => ashet.filesystem.closeDir(IOP.cast(abi.fs.dir.Close, event)),
        }
    }

    switch (wait) {
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

pub fn cancel(event: *ashet.abi.IOP) void {
    ashet.stackCheck();

    const thread = ashet.scheduler.Thread.current() orelse @panic("scheduleAndAwait called in a non-thread context!");
    const context: *Context = if (thread.process_link) |link|
        &link.data.process.io_context
    else
        &kernel_context; // kernel can also schedule I/Os

    if (context.completed.remove(event))
        return;

    switch (event.type) {
        .ui_get_event => @panic("deprecated iop!"), //  ashet.ui.cancelGetEvent(IOP.cast(abi.ui.GetEvent, event)),

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

const EventQueue = struct {
    head: ?*IOP = null,
    tail: ?*IOP = null,
    len: usize = 0,

    pub fn enqueue(eq: *EventQueue, event: *IOP) void {
        eq.len += 1;

        event.next = null;
        if (eq.tail) |tail| {
            tail.next = event;
        } else {
            eq.head = event;
        }
        eq.tail = event;
    }

    pub fn dequeue(eq: *EventQueue) ?*IOP {
        const result = eq.head orelse return null;

        eq.len -= 1;
        eq.head = result.next;
        if (result.next == null) {
            eq.tail = null;
        }

        return result;
    }

    pub fn remove(eq: *EventQueue, event: *IOP) bool {
        if (eq.len == 0)
            return false;

        var iter = eq.head;
        var prev: ?*IOP = null;

        while (iter) |item| {
            iter = item.next;
            defer prev = item;

            if (item != event)
                continue;

            if (item == eq.head)
                eq.head = item.next;
            if (item == eq.tail)
                eq.tail = prev;

            if (prev) |p|
                p.next = item.next;
            item.next = null;

            eq.len -= 1;
            return true;
        }
        return false;
    }

    pub fn flush(eq: *EventQueue) ?*IOP {
        const result = eq.head;
        eq.* = .{};
        return result;
    }
};
