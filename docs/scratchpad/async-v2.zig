pub const Event = struct {
    tag: usize, // user specified data
    next: ?*Event,
    type: EventType,

    kernel_data: [16]usize = undefined, // internal data used by the kernel to store
};

pub const EventType = enum {
    timer,
    file_read,
    file_write,
    tcp_send,
    tcp_receive,
    udp_send,
    udp_receive,
};

/// Cancels the operation defined by `event`.
/// `event` has to be active right now.
/// Behaviour is undefined if the event wasn't started or is finished already.
pub fn cancel(event: *Event) void;

pub const WaitIO = enum {
    /// Don't wait for any I/O to complete.
    dont_block,

    /// Wait for at least one I/O to complete operation.
    wait_one,

    /// Wait until all scheduled I/O operations have completed.
    wait_all,
};

/// Starts new I/O operations and returns completed ones.
///
/// If `start_queue` is given, the kernel will schedule the events in the kernel.
/// All events in this queue must not be freed until they are returned by this function
/// at a later point.
///
/// The function will optionally block based on the `wait` parameter.
///
/// The return value is the HEAD element of a linked list of completed I/O events.
pub fn scheduleAndAwaitIO(start_queue: ?*Event, wait: WaitIO) ?*Event;

// Example I/O apis:

/// Creates an event that will be completed after `timeout` nanoseconds.
pub const TimerEvent = struct {
    base: Event,

    // input:
    timeout: u64,
};

pub const fs = struct {
    const FileHandle = u32;

    pub fn close(FileHandle) void;

    pub const OpenEvent = struct {
        base: Event,
        // inputs:
        path: []const u8,

        // outputs:
        handle: FileHandle,
        size_bytes: u64,
        created: DateTime,
        modified: DateTime,
    };

    pub const ReadEvent = struct {
        base: Event,

        // inputs:
        file: FileHandle,
        offset: u64,
        data: []u8,

        // outputs:
        bytes_read: usize = undefined,
        @"error": ?FileReadError = undefined,
    };

    pub const WriteEvent = struct {
        base: Event,

        // inputs:
        file: FileHandle,
        offset: u64,
        data: []const u8,

        // outputs:
        bytes_written: usize = undefined,
        @"error": ?FileReadError = undefined,
    };
};

pub const tcp = struct {
    const Socket = u32;

    pub fn create() !Socket;
    pub fn close(Socket) void;

    pub const BindEvent = struct {
        base: Event,

        // input:
        socket: Socket,

        // inout:
        bind_point: EndPoint,

        // outputs:
        @"error": ?SendError = undefined,
    };

    pub const ConnectEvent = struct {
        base: Event,

        // input:
        socket: Socket,
        target: EndPoint,

        // outputs:
        @"error": ?SendError = undefined,
    };

    pub const SendEvent = struct {
        base: Event,

        // input:
        socket: Socket,
        data: []const u8,

        // outputs:
        bytes_sent: usize = undefined,
        @"error": SendError = undefined,
    };

    pub const ReceiveEvent = struct {
        base: Event,

        // input:
        socket: Socket,
        buffer: []u8,

        // outputs:
        bytes_received: usize = undefined,
        @"error": ReceiveError = undefined,
    };
};
