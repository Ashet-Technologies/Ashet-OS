const std = @import("std");
const kernel = @import("kernel");

pub const chip = struct {
    const regz = @import("rp2350-chip");

    pub const peripherals = regz.devices.RP2350.peripherals;

    pub const types = regz.types;
};

pub const mmio = struct {
    pub fn Mmio(comptime Reg: type) type {
        return kernel.utils.mmio.MmioRegister(Reg, .{});
    }
};

pub const interrupt = struct {
    pub const Handler = kernel.platform.profile.FunctionPointer;

    fn unhandled() callconv(.C) void {
        @panic("unhandled unknown interrupt");
    }
};

pub const config = struct {
    pub const chip_name = "RP2350";

    pub const cpu_name = "cortex_m33";
};

pub const board = struct {
    pub const xosc_freq = 12_000_000; // Hz
};

pub const hal = @import("rp2350-hal");

pub const drivers = struct {
    pub const time = struct {
        pub const Absolute = kernel.time.Instant;
        pub const Duration = u64;

        pub const Deadline = struct {
            deadline: ?Absolute,
            pub fn init_relative(instant: kernel.time.Instant, timeout: ?Duration) Deadline {
                return .{
                    .deadline = if (timeout) |t| instant.add_ms(t) else null,
                };
            }

            pub fn check(deadline: Deadline, now: Absolute) !void {
                if (deadline.deadline) |end| {
                    if (end.less_or_equal(now))
                        return error.Timeout;
                }
            }
        };
    };
};

pub const utilities = struct {
    /// A helper class that allows operating on a slice of slices
    /// with similar operations to those of a slice.
    pub fn Slice_Vector(comptime Slice: type) type {
        const type_info = @typeInfo(Slice);
        if (type_info != .Pointer)
            @compileError("Slice must have a slice type!");
        if (type_info.Pointer.size != .Slice)
            @compileError("Slice must have a slice type!");

        const item_ptr_info: std.builtin.Type = .{
            .Pointer = .{
                .alignment = @min(type_info.Pointer.alignment, @alignOf(type_info.Pointer.child)),
                .size = .One,
                .child = type_info.Pointer.child,
                .address_space = type_info.Pointer.address_space,
                .is_const = type_info.Pointer.is_const,
                .is_volatile = type_info.Pointer.is_volatile,
                .is_allowzero = type_info.Pointer.is_allowzero,
                .sentinel = null,
            },
        };

        return struct {
            const Vector = @This();

            pub const Item = type_info.Pointer.child;
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
