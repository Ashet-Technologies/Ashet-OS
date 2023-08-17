const std = @import("std");
const virtio = @import("virtio.zig");

const page_size = std.mem.page_size;

const VIRTIO_F_EVENT_IDX = 1;
const VIRTQ_AVAIL_F_NO_INTERRUPT = 1;
const VIRTQ_USED_F_NO_NOTIFY = 1;
const VQUF_NO_NOTIFY = 1;

/// A configurable-size virtio queue. Is used to communicate with
/// virtio devices.
pub fn VirtQ(comptime queue_size: comptime_int) type {
    return extern struct {
        const Queue = @This();

        pub const size = queue_size;

        descriptors: [queue_size]Descriptor align(page_size),
        avail: Ring(AvailItem, queue_size) align(2),
        used: Ring(UsedItem, queue_size) align(page_size),

        regs: *volatile virtio.ControlRegs,
        queue_index: u16,

        desc_i: u16 = 0,
        avail_i: u16 = 0,
        used_i: u16 = 0,

        pub fn init(vq: *Queue, queue_index: u16, regs: *volatile virtio.ControlRegs) error{ AlreadyInUse, TooSmall }!void {
            vq.* = Queue{
                .queue_index = queue_index,
                .regs = regs,

                .descriptors = std.mem.zeroes([queue_size]Descriptor),
                .avail = std.mem.zeroes(Ring(AvailItem, queue_size)),
                .used = std.mem.zeroes(Ring(UsedItem, queue_size)),
            };

            const legacy = regs.isLegacy();

            regs.queue_sel = queue_index;

            if ((legacy and regs.legacy_queue_pfn != 0) or (!legacy and regs.queue_ready != 0)) {
                return error.AlreadyInUse;
            }

            if (regs.queue_num_max < queue_size) {
                return error.TooSmall;
            }

            regs.queue_num = queue_size;

            vq.avail.flags = VIRTQ_AVAIL_F_NO_INTERRUPT;

            if (legacy) {
                regs.legacy_queue_align = page_size;
                regs.legacy_queue_pfn = @intFromPtr(vq) / page_size;
            } else {
                const vq_desc = @as(u64, @intFromPtr(&vq.descriptors));
                regs.queue_desc_lo = @truncate(u32, (vq_desc >> 0));
                regs.queue_desc_hi = @truncate(u32, (vq_desc >> 32));

                const vq_avail = @as(u64, @intFromPtr(&vq.avail));
                regs.queue_avail_lo = @truncate(u32, (vq_avail >> 0));
                regs.queue_avail_hi = @truncate(u32, (vq_avail >> 32));

                const vq_used = @as(u64, @intFromPtr(&vq.used));
                regs.queue_used_lo = @truncate(u32, (vq_used >> 0));
                regs.queue_used_hi = @truncate(u32, (vq_used >> 32));
            }
        }

        pub const DescriptorAccess = enum { read, write };

        pub fn pushDescriptor(vq: *Queue, comptime T: type, ptr: *T, access: DescriptorAccess, first: bool, last: bool) void {
            return vq.pushDescriptorRaw(@ptrCast(*anyopaque, ptr), @sizeOf(T), access, first, last);
        }

        fn flagIf(value: bool, flag: u16) u16 {
            return @intFromBool(value) * flag;
        }

        pub fn pushDescriptorRaw(vq: *Queue, ptr: *anyopaque, length: usize, access: DescriptorAccess, first: bool, last: bool) void {
            const next_i = vq.desc_i +% 1;

            const desc_i = vq.desc_i % queue_size;

            vq.descriptors[desc_i] = Descriptor{
                .addr = @intFromPtr(ptr),
                .len = length,
                .flags = flagIf(!last, Descriptor.F_NEXT) | flagIf((access == .write), Descriptor.F_WRITE),
                .next = flagIf(!last, next_i % queue_size),
            };

            if (first) {
                vq.avail.ring[vq.avail_i % queue_size] = desc_i;
                vq.avail_i +%= 1;
            }

            vq.desc_i = next_i;
        }

        pub fn exec(vq: *Queue) void {
            volatileWrite(&vq.avail.idx, vq.avail_i);
            if ((volatileRead(&vq.used.flags) & VQUF_NO_NOTIFY) == 0) {
                vq.regs.queue_notify = vq.queue_index;
            }
        }

        pub fn waitUsed(vq: *Queue) u16 {
            const next = vq.used_i;
            while (volatileRead(&vq.used.idx) == vq.used_i) {
                memorySideEffects();
            }
            vq.used_i = volatileRead(&vq.used.idx);
            return next;
        }

        pub fn singlePollUsed(vq: *Queue) ?u16 {
            const next = vq.used_i;
            if (volatileRead(&vq.used.idx) == vq.used_i) {
                return null;
            }
            vq.used_i += 1;
            return next;
        }

        pub fn waitSettled(vq: *Queue) void {
            while (volatileRead(&vq.used.idx) != vq.avail_i) {
                memorySideEffects();
            }
            vq.used_i = volatileRead(&vq.used.idx);
        }
    };
}

pub const Descriptor = extern struct {
    /// This marks a buffer as continuing via the next field.
    const F_NEXT: u16 = 1;
    /// This marks a buffer as device write-only (otherwise device read-only).
    const F_WRITE: u16 = 2;
    /// This means the buffer contains a list of buffer descriptors.
    const F_INDIRECT: u16 = 4;

    /// Address (guest-physical).
    addr: u64,
    /// Length.
    len: u32,
    /// The flags as indicated above.
    flags: u16,
    /// Next field if flags & NEXT
    next: u16,
};

pub fn Ring(comptime Item: type, comptime queue_size: comptime_int) type {
    return extern struct {
        flags: u16,
        idx: u16,
        ring: [queue_size]Item,
        event: u16, // Only if VIRTIO_F_EVENT_IDX
    };
}

pub const AvailItem = u16;

pub const UsedItem = extern struct {
    id: u32,
    len: u32,
};

fn volatileWrite(ptr: *volatile u16, value: u16) void {
    ptr.* = value;
}

fn volatileRead(ptr: *volatile u16) u16 {
    return ptr.*;
}

inline fn memorySideEffects() void {
    asm volatile ("" ::: "memory");
}
