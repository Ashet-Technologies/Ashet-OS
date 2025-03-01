const std = @import("std");
const ashet = @import("../main.zig");

pub const SharedMemory = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    const alignment = 16;

    system_resource: ashet.resources.SystemResource = .{ .type = .shared_memory },
    buffer: []align(alignment) u8,

    pub fn create(size: usize) !*SharedMemory {
        const shm = try ashet.memory.type_pool(SharedMemory).alloc();
        errdefer ashet.memory.type_pool(SharedMemory).free(shm);

        shm.* = .{
            .buffer = try ashet.memory.allocator.alignedAlloc(u8, alignment, size),
        };

        return shm;
    }

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(shm: *SharedMemory) void {
        ashet.memory.allocator.free(shm.buffer);
        shm.* = undefined;
        ashet.memory.type_pool(SharedMemory).free(shm);
    }
};
