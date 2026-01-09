const std = @import("std");
const kernel = @import("kernel");

pub const chip = struct {
    const regz = @import("rp2350-chip");

    pub const peripherals = regz.peripherals;

    pub const types = regz.types;
};

pub const mmio = struct {
    pub fn Mmio(comptime Reg: type) type {
        return kernel.utils.mmio.MmioRegister(Reg, .{});
    }
};

pub const interrupt = struct {
    pub const Handler = kernel.platform.profile.FunctionPointer;

    pub fn unhandled() callconv(.c) void {
        @panic("unhandled unknown interrupt");
    }
};

pub const config = struct {
    pub const chip_name = "RP2350";

    pub const cpu_name = "cortex_m33";

    pub const ram_image = false;
};

pub const options = struct {
    pub const hal = struct {
        pub const bootmeta = struct {
            pub const image_def_exe_security = .secure;
            pub const next_block = null;
        };
        pub const use_dcp = true;
    };
    pub const cpu = struct {
        pub const enable_fpu = false;
    };
};

pub const board = struct {
    pub const xosc_freq = 12_000_000; // Hz
};

pub const hal = @import("rp2350-hal");

pub const drivers = struct {
    pub const base = struct {
        pub const I2C_Device = struct {
            pub const Error = error{
                DeviceNotPresent,
                NoAcknowledge,
                Timeout,
                NoData,
                TargetAddressReserved,
                UnknownAbort,
            };

            pub const Address = enum(u7) {
                _,

                pub fn new(in: u7) Address {
                    return @enumFromInt(in);
                }

                pub fn check_reserved(addr: Address) !void {
                    _ = addr; // TODO(0.15.2): Implement this?
                }
            };
        };
        //
    };

    pub const time = struct {
        pub const Absolute = kernel.time.Instant;

        pub const Duration = enum(u64) {
            _,

            pub fn from_us(us: u64) Duration {
                return @enumFromInt(us);
            }

            pub fn from_ms(ms: u64) Duration {
                return from_us(1000 * ms);
            }
        };

        pub const Deadline = struct {
            pub const no_deadline: Deadline = .{ .deadline = null };

            deadline: ?Absolute,
            pub fn init_relative(instant: kernel.time.Instant, timeout: ?Duration) Deadline {
                return .{
                    .deadline = if (timeout) |t| instant.add_ms(@intFromEnum(t)) else null,
                };
            }

            pub fn check(deadline: Deadline, now: Absolute) !void {
                if (deadline.deadline) |end| {
                    if (end.less_or_equal(now))
                        return error.Timeout;
                }
            }

            pub fn is_reached_by(deadline: Deadline, now: Absolute) bool {
                if (deadline.deadline) |end| {
                    return end.less_or_equal(now);
                }
                return false;
            }
        };

        pub fn make_timeout_us(instant: kernel.time.Instant, us: u64) Deadline {
            return .init_relative(instant, .from_us(us));
        }
    };
};

pub const utilities = struct {
    /// A helper class that allows operating on a slice of slices
    /// with similar operations to those of a slice.
    pub fn SliceVector(comptime Slice: type) type {
        const type_info = @typeInfo(Slice);
        if (type_info != .pointer)
            @compileError("Slice must have a slice type!");
        if (type_info.pointer.size != .slice)
            @compileError("Slice must have a slice type!");

        const item_ptr_info: std.builtin.Type = .{
            .pointer = .{
                .alignment = @min(type_info.pointer.alignment, @alignOf(type_info.pointer.child)),
                .size = .one,
                .child = type_info.pointer.child,
                .address_space = type_info.pointer.address_space,
                .is_const = type_info.pointer.is_const,
                .is_volatile = type_info.pointer.is_volatile,
                .is_allowzero = type_info.pointer.is_allowzero,
                .sentinel_ptr = null,
            },
        };

        return struct {
            const Vector = @This();

            pub const Item = type_info.pointer.child;
            pub const ItemPtr = @Type(item_ptr_info);

            /// The slice of slices. The first and the last slice of this slice must
            /// be non-empty or the slice-of-slices must be empty.
            ///
            /// Use `init()` to ensure this.
            slices: []const Slice,

            /// Initializes a new vector with the given slice of slices.
            /// Optimizes the `slices` array by removing all empty slices from the start and the end.
            pub fn init(slices: []const Slice) Vector {
                var view = slices;

                // trim start:
                while (view.len > 0) {
                    if (view[0].len > 0)
                        break;
                    view = view[1..];
                }

                // trail end:
                while (view.len > 0) {
                    if (view[view.len - 1].len > 0)
                        break;
                    view = view[0 .. view.len - 1];
                }

                if (view.len > 0) {
                    std.debug.assert(view[0].len > 0);
                    std.debug.assert(view[view.len - 1].len > 0);
                }

                return .{ .slices = view };
            }

            /// Returns the total length of all contained slices.
            pub fn size(vec: Vector) usize {
                var len: usize = 0;
                for (vec.slices) |slice| {
                    len += slice.len;
                }
                return len;
            }

            ///
            /// Returns the element at `index`.
            ///
            /// NOTE: Will iterate over the contained slices.
            pub fn at(vec: Vector, index: usize) Item {
                var offset: usize = 0;
                for (vec.slices) |slice| {
                    const rel = index - offset;
                    if (rel < slice.len)
                        return slice[rel];
                    offset += slice.len;
                }
                @panic("index out of bounds");
            }

            /// Returns an iterator for the slices.
            pub fn iterator(vec: Vector) Iterator {
                return .{ .slices = vec.slices };
            }

            pub const Iterator = struct {
                slices: []const Slice,
                slice_index: usize = 0,
                slice_offset: usize = 0,
                element_index: usize = 0,

                // Advances the iterator by a single element.
                pub fn next_element(iter: *Iterator) ?Element {
                    const ptr = iter.next_element_ptr() orelse return null;
                    return .{
                        .last = ptr.last,
                        .first = ptr.first,
                        .index = ptr.index,
                        .value = ptr.value_ptr.*,
                    };
                }

                // Advances the iterator by a single element.
                pub fn next_element_ptr(iter: *Iterator) ?ElementPtr {
                    if (iter.slice_index >= iter.slices.len)
                        return null;

                    var current_slice = iter.slices[iter.slice_index];
                    std.debug.assert(iter.slice_offset < current_slice.len);

                    const first = (iter.slice_index == 0) and (iter.slice_offset == 0);
                    const last = (iter.slice_index == (iter.slices.len - 1)) and (iter.slice_offset == (iter.slices[iter.slices.len - 1].len - 1));

                    const element: ElementPtr = .{
                        .first = first,
                        .last = last,
                        .index = iter.element_index,
                        .value_ptr = &current_slice[iter.slice_offset],
                    };

                    iter.element_index += 1;
                    iter.slice_offset += 1;
                    while (iter.slice_offset >= current_slice.len) {
                        iter.slice_offset = 0;
                        iter.slice_index += 1;

                        if (iter.slice_index >= iter.slices.len) {
                            break;
                        }
                        current_slice = iter.slices[iter.slice_index];
                    }

                    return element;
                }

                /// Returns the next available chunk of data.
                ///
                /// If `max_length` is given, that chunk never exceeds `max_length` elements.
                pub fn next_chunk(iter: *Iterator, max_length: ?usize) ?Slice {
                    if (iter.slice_index >= iter.slices.len)
                        return null;

                    var current_slice = iter.slices[iter.slice_index];
                    std.debug.assert(iter.slice_offset < current_slice.len);

                    const rest = current_slice[iter.slice_offset..];

                    const chunk: Slice = if (max_length) |limit|
                        rest[0..@min(rest.len, limit)]
                    else
                        rest;

                    iter.slice_offset += chunk.len;
                    std.debug.assert(iter.slice_offset <= current_slice.len);

                    while (iter.slice_offset == current_slice.len) {
                        iter.slice_offset = 0;
                        iter.slice_index += 1;
                        if (iter.slice_index >= iter.slices.len)
                            break;
                        current_slice = iter.slices[iter.slice_index];
                    }

                    return chunk;
                }

                pub const Element = struct {
                    first: bool,
                    last: bool,
                    index: usize,
                    value: Item,
                };

                pub const ElementPtr = struct {
                    first: bool,
                    last: bool,
                    index: usize,
                    value_ptr: ItemPtr,
                };
            };
        };
    }
};

pub const cpu = struct {
    pub const peripherals = struct {
        pub const SCB = extern struct {
            VTOR: u32, // 0xE000ED08

            CPACR: mmio.Mmio(packed struct(u32) { // 0xE000ED88 TODO
                const Access = enum(u2) {
                    access_denied = 0b00, //  Access denied. Any attempted access generates a NOCP UsageFault.
                    privileged_access_only = 0b01, //  Privileged access only. An unprivileged access generates a NOCP UsageFault.
                    reserved = 0b10, //  Reserved.
                    full_access = 0b11, //  Full access.
                };
                CP0: Access,
                CP1: Access,
                CP2: Access,
                CP3: Access,
                CP4: Access,
                CP5: Access,
                CP6: Access,
                CP7: Access,
                RES0: u4,
                CP10: Access,
                CP11: Access,
                RES1: u8,
            }),
        };
        pub const scb: *volatile SCB = @ptrCast(kernel.platform.profile.peripherals.system_control_block.vtor);
    };

    pub const nop = kernel.platform.profile.nop;
    pub const sev = kernel.platform.profile.sev;
    pub const wfe = kernel.platform.profile.wfe;
};

pub const concurrency = struct {
    pub const AtomicStaticBitSetError = error{NoAvailableBit};

    /// Creates a statically sized BitSet type where operations are atomic.
    /// Useful for managing a fixed pool of resources or flags concurrently.
    /// `size` determines the number of bits available (0 to size-1).
    pub fn AtomicStaticBitSet(comptime size: usize) type {
        return struct {
            const Size = size;
            const BlockType = usize;
            const BlockNum = (size + @bitSizeOf(BlockType) - 1) / @bitSizeOf(BlockType);
            const Bit = std.math.Log2Int(BlockType);
            const Self = @This();

            blocks: [BlockNum]std.atomic.Value(BlockType) = .{std.atomic.Value(BlockType){ .raw = 0 }} ** BlockNum,

            /// Sets the bit at `bit_index` to 1.
            ///
            /// Returns:
            ///   `true` if the bit was successfully changed from 0 to 1 by this call.
            ///   `false` if the bit was already 1.
            pub inline fn set(self: *Self, bit_index: usize) bool {
                std.debug.assert(bit_index < Size);
                return self.blocks[block_index(bit_index)].bitSet(bit_offset(bit_index), .seq_cst) == 0;
            }

            /// Resets (clears) the bit at `bit_index` to 0.
            ///
            /// Returns:
            ///   `true` if the bit was successfully changed from 1 to 0 by this call.
            ///   `false` if the bit was already 0.
            pub inline fn reset(self: *Self, bit_index: usize) bool {
                std.debug.assert(bit_index < Size);
                return self.blocks[block_index(bit_index)].bitReset(bit_offset(bit_index), .seq_cst) == 1;
            }

            /// Tests the value of the bit at `bit_index` without modifying it.
            ///
            /// Returns:
            ///   `u1`: Returns 1 if the bit is set, 0 if the bit is clear.
            pub inline fn test_bit(self: *Self, bit_index: usize) u1 {
                std.debug.assert(bit_index < Size);
                const mask: BlockType = @as(BlockType, 1) << bit_offset(bit_index);
                return @intFromBool(self.blocks[block_index(bit_index)].load(.seq_cst) & mask != 0);
            }

            /// Finds the first available (0) bit, sets it to 1, and returns its index.
            ///
            /// Returns:
            ///   The `usize` index of the bit that was successfully found and set.
            ///   Returns `BitSetError.NoAvailableBit` if all bits were already set.
            pub inline fn set_first_available(self: *Self) AtomicStaticBitSetError!usize {
                for (0..Size) |bit_index| {
                    if (self.set(bit_index)) {
                        return bit_index;
                    }
                }
                return AtomicStaticBitSetError.NoAvailableBit;
            }

            inline fn block_index(bit_index: usize) usize {
                return bit_index / @bitSizeOf(BlockType);
            }

            inline fn bit_offset(bit_index: usize) Bit {
                return @truncate(bit_index % @bitSizeOf(BlockType));
            }
        };
    }
};

pub fn BoundedArray(comptime T: type, comptime buffer_capacity: usize) type {
    return BoundedArrayAligned(T, @alignOf(T), buffer_capacity);
}

pub fn BoundedArrayAligned(
    comptime T: type,
    comptime alignment: u29,
    comptime buffer_capacity: usize,
) type {
    return struct {
        const Self = @This();
        buffer: [buffer_capacity]T align(alignment) = undefined,
        len: usize = 0,

        /// Set the actual length of the slice.
        /// Returns error.Overflow if it exceeds the length of the backing array.
        pub fn init(len: usize) error{Overflow}!Self {
            if (len > buffer_capacity) return error.Overflow;
            return Self{ .len = len };
        }

        /// View the internal array as a slice whose size was previously set.
        pub fn slice(self: anytype) switch (@TypeOf(&self.buffer)) {
            *align(alignment) [buffer_capacity]T => []align(alignment) T,
            *align(alignment) const [buffer_capacity]T => []align(alignment) const T,
            else => unreachable,
        } {
            return self.buffer[0..self.len];
        }

        /// View the internal array as a constant slice whose size was previously set.
        pub fn const_slice(self: *const Self) []align(alignment) const T {
            return self.slice();
        }

        /// Adjust the slice's length to `len`.
        /// Does not initialize added items if any.
        pub fn resize(self: *Self, len: usize) error{Overflow}!void {
            if (len > buffer_capacity) return error.Overflow;
            self.len = len;
        }

        /// Remove all elements from the slice.
        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        /// Copy the content of an existing slice.
        pub fn from_slice(m: []const T) error{Overflow}!Self {
            var list = try init(m.len);
            @memcpy(list.slice(), m);
            return list;
        }

        /// Return the element at index `i` of the slice.
        pub fn get(self: Self, i: usize) T {
            return self.const_slice()[i];
        }

        /// Set the value of the element at index `i` of the slice.
        pub fn set(self: *Self, i: usize, item: T) void {
            self.slice()[i] = item;
        }

        /// Return the maximum length of a slice.
        pub fn capacity(self: Self) usize {
            return self.buffer.len;
        }

        /// Check that the slice can hold at least `additional_count` items.
        pub fn ensure_unused_capacity(self: Self, additional_count: usize) error{Overflow}!void {
            if (self.len + additional_count > buffer_capacity) {
                return error.Overflow;
            }
        }

        /// Increase length by 1, returning a pointer to the new item.
        pub fn add_one(self: *Self) error{Overflow}!*T {
            try self.ensure_unused_capacity(1);
            return self.add_one_assume_capacity();
        }

        /// Increase length by 1, returning pointer to the new item.
        /// Asserts that there is space for the new item.
        pub fn add_one_assume_capacity(self: *Self) *T {
            std.debug.assert(self.len < buffer_capacity);
            self.len += 1;
            return &self.slice()[self.len - 1];
        }

        /// Resize the slice, adding `n` new elements, which have `undefined` values.
        /// The return value is a pointer to the array of uninitialized elements.
        pub fn add_many_as_array(self: *Self, comptime n: usize) error{Overflow}!*align(alignment) [n]T {
            const prev_len = self.len;
            try self.resize(self.len + n);
            return self.slice()[prev_len..][0..n];
        }

        /// Resize the slice, adding `n` new elements, which have `undefined` values.
        /// The return value is a slice pointing to the uninitialized elements.
        pub fn add_many_as_slice(self: *Self, n: usize) error{Overflow}![]align(alignment) T {
            const prev_len = self.len;
            try self.resize(self.len + n);
            return self.slice()[prev_len..][0..n];
        }

        /// Remove and return the last element from the slice, or return `null` if the slice is empty.
        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            const item = self.get(self.len - 1);
            self.len -= 1;
            return item;
        }

        /// Return a slice of only the extra capacity after items.
        /// This can be useful for writing directly into it.
        /// Note that such an operation must be followed up with a
        /// call to `resize()`
        pub fn unused_capacity_slice(self: *Self) []align(alignment) T {
            return self.buffer[self.len..];
        }

        /// Insert `item` at index `i` by moving `slice[n .. slice.len]` to make room.
        /// This operation is O(N).
        pub fn insert(
            self: *Self,
            i: usize,
            item: T,
        ) error{Overflow}!void {
            if (i > self.len) {
                return error.Overflow;
            }
            _ = try self.add_one();
            var s = self.slice();
            std.mem.copyBackwards(T, s[i + 1 .. s.len], s[i .. s.len - 1]);
            self.buffer[i] = item;
        }

        /// Insert slice `items` at index `i` by moving `slice[i .. slice.len]` to make room.
        /// This operation is O(N).
        pub fn insert_slice(self: *Self, i: usize, items: []const T) error{Overflow}!void {
            try self.ensure_unused_capacity(items.len);
            self.len += items.len;
            std.mem.copyBackwards(T, self.slice()[i + items.len .. self.len], self.const_slice()[i .. self.len - items.len]);
            @memcpy(self.slice()[i..][0..items.len], items);
        }

        /// Replace range of elements `slice[start..][0..len]` with `new_items`.
        /// Grows slice if `len < new_items.len`.
        /// Shrinks slice if `len > new_items.len`.
        pub fn replace_range(
            self: *Self,
            start: usize,
            len: usize,
            new_items: []const T,
        ) error{Overflow}!void {
            const after_range = start + len;
            var range = self.slice()[start..after_range];

            if (range.len == new_items.len) {
                @memcpy(range[0..new_items.len], new_items);
            } else if (range.len < new_items.len) {
                const first = new_items[0..range.len];
                const rest = new_items[range.len..];
                @memcpy(range[0..first.len], first);
                try self.insert_slice(after_range, rest);
            } else {
                @memcpy(range[0..new_items.len], new_items);
                const after_subrange = start + new_items.len;
                for (self.const_slice()[after_range..], 0..) |item, i| {
                    self.slice()[after_subrange..][i] = item;
                }
                self.len -= len - new_items.len;
            }
        }

        /// Extend the slice by 1 element.
        pub fn append(self: *Self, item: T) error{Overflow}!void {
            const new_item_ptr = try self.add_one();
            new_item_ptr.* = item;
        }

        /// Extend the slice by 1 element, asserting the capacity is already
        /// enough to store the new item.
        pub fn append_assume_capacity(self: *Self, item: T) void {
            const new_item_ptr = self.add_one_assume_capacity();
            new_item_ptr.* = item;
        }

        /// Remove the element at index `i`, shift elements after index
        /// `i` forward, and return the removed element.
        /// Asserts the slice has at least one item.
        /// This operation is O(N).
        pub fn ordered_remove(self: *Self, i: usize) T {
            const newlen = self.len - 1;
            if (newlen == i) return self.pop().?;
            const old_item = self.get(i);
            for (self.slice()[i..newlen], 0..) |*b, j| b.* = self.get(i + 1 + j);
            self.set(newlen, undefined);
            self.len = newlen;
            return old_item;
        }

        /// Remove the element at the specified index and return it.
        /// The empty slot is filled from the end of the slice.
        /// This operation is O(1).
        pub fn swap_remove(self: *Self, i: usize) T {
            if (self.len - 1 == i) return self.pop().?;
            const old_item = self.get(i);
            self.set(i, self.pop().?);
            return old_item;
        }

        /// Append the slice of items to the slice.
        pub fn append_slice(self: *Self, items: []const T) error{Overflow}!void {
            try self.ensure_unused_capacity(items.len);
            self.append_slice_assume_capacity(items);
        }

        /// Append the slice of items to the slice, asserting the capacity is already
        /// enough to store the new items.
        pub fn append_slice_assume_capacity(self: *Self, items: []const T) void {
            const old_len = self.len;
            self.len += items.len;
            @memcpy(self.slice()[old_len..][0..items.len], items);
        }

        /// Append a value to the slice `n` times.
        /// Allocates more memory as necessary.
        pub fn append_n_times(self: *Self, value: T, n: usize) error{Overflow}!void {
            const old_len = self.len;
            try self.resize(old_len + n);
            @memset(self.slice()[old_len..self.len], value);
        }

        /// Append a value to the slice `n` times.
        /// Asserts the capacity is enough.
        pub fn append_n_times_assume_capacity(self: *Self, value: T, n: usize) void {
            const old_len = self.len;
            self.len += n;
            std.debug.assert(self.len <= buffer_capacity);
            @memset(self.slice()[old_len..self.len], value);
        }

        pub const Writer = if (T != u8)
            @compileError("The Writer interface is only defined for BoundedArray(u8, ...) " ++
                "but the given type is BoundedArray(" ++ @typeName(T) ++ ", ...)")
        else
            struct {
                ba: *Self,
                interface: std.Io.Writer,
                //std.io.Writer(*Self, error{Overflow}, appendWrite);
            };

        /// Initializes a writer which will write into the array.
        pub fn writer(self: *Self) Writer {
            return .{
                .ba = self,
                .interface = .{
                    .vtable = &.{
                        .drain = drain,
                    },
                    .buffer = &.{},
                },
            };
        }

        fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
            _ = splat;
            const w: *Writer = @fieldParentPtr("interface", io_w);
            var ret: usize = 0;
            for (data) |d| {
                const n = w.ba.append_write(d) catch return error.WriteFailed;
                ret += n;
                if (n != d.len)
                    break;
            }

            return ret;
        }

        /// Same as `append_slice` except it returns the number of bytes written, which is always the same
        /// as `m.len`. The purpose of this function existing is to match `std.io.Writer` API.
        fn append_write(self: *Self, m: []const u8) error{Overflow}!usize {
            try self.append_slice(m);
            return m.len;
        }
    };
}
