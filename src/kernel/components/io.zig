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
    data: Data,

    const Data = extern union {
        padding: [6]usize,
    };

    pub fn get(ptr: *IOP) *KernelData {
        return @ptrCast(*KernelData, &ptr.kernel_data);
    }
};

comptime {
    // assert that KernelData can alias to the erased data structure
    const ErasedData = std.meta.fieldInfo(IOP, .kernel_data).field_type;
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
}

pub fn scheduleAndAwait(start_queue: ?*IOP, wait: WaitIO) ?*IOP {
    const thread = ashet.scheduler.Thread.current() orelse @panic("scheduleAndAwait called in a non-thread context!");
    const process = thread.process orelse @panic("scheduleAndAwait called in a non-process context!");
    const context: *Context = &process.io_context;

    var queue = start_queue;
    while (queue) |event| {
        // advance the queue as the first step, so we can now destroy and
        // restructeventure the linked list properties of our current event
        queue = event.next;

        const data = KernelData.get(event);
        data.* = KernelData{
            .context = context,
            .data = undefined,
        };

        logger.debug("dispatching i/o: {s}", .{@tagName(event.type)});

        context.pending += 1;
        switch (event.type) {
            .tcp_bind => ashet.network.tcp.bind(ashet.abi.IOP.cast(abi.tcp.Bind, event)),
            .tcp_connect => ashet.network.tcp.connect(ashet.abi.IOP.cast(abi.tcp.Connect, event)),
            .tcp_send => ashet.network.tcp.send(ashet.abi.IOP.cast(abi.tcp.Send, event)),
            .tcp_receive => ashet.network.tcp.receive(ashet.abi.IOP.cast(abi.tcp.Receive, event)),

            .udp_bind => unreachable,
            .udp_connect => unreachable,
            .udp_disconnect => unreachable,
            .udp_send => unreachable,
            .udp_send_to => unreachable,
            .udp_receive_from => unreachable,
        }
    }

    switch (wait) {
        .dont_block => {}, // just do nothing here :)
        .wait_one => while (context.completed.len == 0) {
            ashet.scheduler.yield();
        },
        .wait_all => while (context.pending > 0) {
            ashet.scheduler.yield();
        },
    }

    return context.completed.flush();
}

pub fn cancel(event: *ashet.abi.IOP) void {
    logger.warn("cancel event of tyype {}", .{event.type});
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

    pub fn flush(eq: *EventQueue) ?*IOP {
        const result = eq.head;
        eq.* = .{};
        return result;
    }
};
