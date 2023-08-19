const std = @import("std");

pub fn HandleAllocator(comptime Handle: type, comptime Backing: type, comptime active_handle_limit: usize) type {
    return struct {
        const HAlloc = @This();

        const HandleType = std.meta.Tag(Handle);
        const HandleSet = std.bit_set.ArrayBitSet(u32, active_handle_limit);

        comptime {
            if (!std.math.isPowerOfTwo(active_handle_limit))
                @compileError("max_open_files must be a power of two!");
        }

        const handle_index_mask = active_handle_limit - 1;

        generations: [active_handle_limit]HandleType = std.mem.zeroes([active_handle_limit]HandleType),
        active_handles: HandleSet = HandleSet.initFull(),
        backings: [active_handle_limit]Backing = undefined,

        pub fn alloc(ha: *HAlloc) error{SystemResources}!Handle {
            if (ha.active_handles.toggleFirstSet()) |index| {
                while (true) {
                    const generation = ha.generations[index];
                    const numeric = generation *% active_handle_limit + index;

                    const handle = @as(Handle, @enumFromInt(numeric));
                    if (handle == .invalid) {
                        ha.generations[index] += 1;
                        continue;
                    }
                    return handle;
                }
            } else {
                return error.SystemResources;
            }
        }

        pub fn resolve(ha: *HAlloc, handle: Handle) !*Backing {
            const index = try ha.resolveIndex(handle);
            return &ha.backings[index];
        }

        pub fn resolveIndex(ha: *HAlloc, handle: Handle) error{InvalidHandle}!usize {
            const numeric = @intFromEnum(handle);

            const index = numeric & handle_index_mask;
            const generation = numeric / active_handle_limit;

            if (ha.generations[index] != generation)
                return error.InvalidHandle;

            return index;
        }

        pub fn handleToBackingUnsafe(ha: *HAlloc, handle: Handle) *Backing {
            return &ha.backings[handleToIndexUnsafe(handle)];
        }

        pub fn handleToIndexUnsafe(handle: Handle) usize {
            const numeric = @intFromEnum(handle);
            return @as(usize, numeric & handle_index_mask);
        }

        pub fn free(ha: *HAlloc, handle: Handle) void {
            const numeric = @intFromEnum(handle);

            const index = numeric & handle_index_mask;
            const generation = numeric / active_handle_limit;

            if (ha.generations[index] != generation) {
                std.log.err("free received invalid file handle: {}(index:{}, gen:{})", .{
                    numeric,
                    index,
                    generation,
                });
            } else {
                ha.active_handles.set(index);
                ha.generations[index] += 1;
            }
        }
    };
}
