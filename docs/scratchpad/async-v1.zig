pub const Event = struct {
    completed: bool = false,
    cancelled: bool = false,
    tag: usize, // user specified data
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

/// Creates an event that will be completed after `timeout` nanoseconds.
pub fn timer(event: *Event, timeout: u64) void;

/// cancels the given event and will complete it as soon as possible.
pub fn cancel(event: *Event) void;

/// Suspends the current thread until `event` is completed.
pub fn waitForCompletion(event: *Event) void;

/// Suspends the current thread until all given `events` are completed.
pub fn waitForAll(events: []const *Event) void;

/// Suspends the current thread until at least one of the given `events` is completed.
/// Each completed event will have its corresponding bit in `bitmask` set.
/// This way, multiple events can be completed and trivially checked for completion.
/// `bitmask` must be at least `(events.len+31)/32` items long. Bits are LSB to MSB,
/// so `event[7]` will correspond to `(bitmask[0] & (1<<7))`, while `event[40]` will
/// correspond to `(bitmask[1] & (1<<8))`.
pub fn waitForAny(events: []const *Event, bitmask: []u32) void;

pub const fs = struct {
    const FileHandle = u32;

    pub const ReadEvent = struct {
        base: Event,
        bytes_read: usize,
        @"error": ?FileReadError,
    };

    pub const WriteEvent = struct {
        base: Event,
        bytes_written: usize,
        @"error": ?FileReadError,
    };

    pub const OpenEvent = struct {
        base: Event,
        size_bytes: usize,
        created: DateTime,
        modified: DateTime,
    };

    pub fn open(path: []const u8, event: *OpenEvent) !void;

    pub fn write(handle: FileHandle, event: *WriteEvent, data: []const u8) !void;
    pub fn read(handle: FileHandle, event: *ReadEvent, data: []u8) !void;
};

pub const tcp = struct {
    const Socket = u32;

    pub const SendEvent = struct {
        base: Event,
        bytes_sent: usize,
        @"error": SendError,
    };

    pub fn send(socket: Socket, event: *SendEvent, data: []const u8) !void;
};
