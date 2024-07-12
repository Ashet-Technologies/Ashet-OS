const std = @import("std");
const ashet = @import("../main.zig");

/// Encodes the different types of system resources.
/// TODO: Move to ABI
pub const Type = enum {
    //
};

/// This is the ABI-public version of a system resource.
pub const Handle = *opaque {}; // ashet.abi.SystemResource;

/// This is the kernel-internal abstraction over system resources.
pub const SystemResource = struct {
    type: Type,
    vtable: *const VTable,

    /// Number of processes this resource is referenced by.
    owners: std.DoublyLinkedList(void) = .{},

    pub fn cast(src: *SystemResource, comptime Resource: type) error{BadCast}!*Resource {
        const expected_type = Resource.system_resource_type;
        if (src.type != expected_type)
            return error.BadCast;
        return @alignCast(@fieldParentPtr(Resource, "system_resource"));
    }

    pub fn retain(src: *SystemResource) void {
        src.refcount += 1;
    }

    pub fn release(src: *SystemResource) void {
        src.refcount -|= 1;
        if (src.refcount == 0) {
            src.destroy();
        }
    }

    /// Immediatly destroys the system resource.
    pub fn destroy(src: *SystemResource) void {
        var it = src.owners.first;
        while (it) |node| {
            it = node.next;
            node.data.remove_resource(src);
        }
        src.vtable.destroy(src);
        src.* = undefined;
    }

    pub const VTable = struct {
        destroy: *const fn (*SystemResource) void,
    };
};

pub const Owner = std.DoublyLinkedList(*ashet.multi_tasking.Process).Node;

pub const HandlePool = struct {
    const grow_margin = 64; // always allocate 64 chunks at once

    allocator: std.mem.Allocator,

    bit_map: std.DynamicBitSetUnmanaged = .{},
    generations: std.ArrayListUnmanaged(EncodedHandle.Generation) = .{},
    owners: std.SegmentedList(Owner, grow_margin) = .{},

    pub fn init(allocator: std.mem.Allocator) HandlePool {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(pool: *HandlePool) void {
        pool.bit_map.deinit(pool.allocator);
        pool.generations.deinit(pool.allocator);
        pool.owners.deinit(pool.allocator);
        pool.* = undefined;
    }

    pub const AllocResult = struct {
        handle: Handle,
        owner: *Owner,
    };

    pub fn alloc(pool: *HandlePool, proc: *ashet.multi_tasking.Process) error{ OutOfMemory, OutOfHandles }!AllocResult {
        const raw_index = pool.bit_map.toggleFirstSet() orelse blk: {
            const original_len = pool.bit_map.capacity();

            errdefer pool.bit_map.resize(pool.allocator, original_len, true) catch unreachable;
            errdefer pool.owners.shrinkRetainingCapacity(original_len);
            errdefer pool.generations.shrinkRetainingCapacity(original_len);

            const new_len = @min(original_len + grow_margin, std.math.maxInt(EncodedHandle.Index) + 1);
            if (new_len == original_len)
                return error.OutOfHandles;

            try pool.bit_map.resize(pool.allocator, new_len, true);
            try pool.owners.growCapacity(pool.allocator, new_len);
            try pool.generations.resize(pool.allocator, new_len);

            // this is a bit weird, but whatever. the list doesn't offer a "resize"
            // capability:

            for (original_len..new_len) |_| {
                _ = pool.owners.addOne(pool.allocator) catch unreachable;
            }
            pool.owners.len = new_len;
            std.debug.assert(pool.owners.len == new_len);

            pool.bit_map.unset(original_len);

            break :blk original_len;
        };

        std.debug.assert(!pool.bit_map.isSet(raw_index));

        const generation_ptr = &pool.generations.items[raw_index];

        var encoded: EncodedHandle = .{
            .index = @intCast(raw_index),
            .generation = generation_ptr.*,
            .checksum = 0,
        };
        encoded.checksum = EncodedHandle.compute_checksum(
            encoded.index,
            encoded.generation,
        );

        const owner = pool.owners.uncheckedAt(raw_index);
        owner.* = .{
            .data = proc,
        };

        return .{
            .handle = @ptrFromInt(@as(usize, @bitCast(encoded))),
            .owner = owner,
        };
    }

    pub fn free(pool: *HandlePool, handle: Handle) error{ InvalidHandle, DoubleFree, GenerationMismatch }!void {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());

        const handle_bits: EncodedHandle = @bitCast(@intFromPtr(handle));

        handle_bits.validate_checksum() catch return error.InvalidHandle;
        if (handle_bits.index >= pool.bit_map.capacity())
            return error.InvalidHandle;

        const generation_ptr = &pool.generations.items[handle_bits.index];

        if (pool.generations.items[handle_bits.index] != handle_bits.generation)
            return error.GenerationMismatch;

        if (pool.bit_map.isSet(handle_bits.index))
            return error.DoubleFree;

        pool.bit_map.set(handle_bits.index);
        pool.owners.at(handle_bits.index).* = undefined;
        generation_ptr.* +%= 1;
    }

    pub fn resolve(pool: *HandlePool, handle: Handle) error{ InvalidHandle, GenerationMismatch, Gone }!*Owner {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());

        const handle_bits: EncodedHandle = @bitCast(@intFromPtr(handle));

        handle_bits.validate_checksum() catch return error.InvalidHandle;
        if (handle_bits.index >= pool.bit_map.capacity())
            return error.InvalidHandle;

        if (pool.generations.items[handle_bits.index] != handle_bits.generation)
            return error.GenerationMismatch;

        if (pool.bit_map.isSet(handle_bits.index))
            return error.Gone;

        return pool.owners.uncheckedAt(handle_bits.index);
    }

    /// We use a pretty complex encoding scheme for the
    /// handles.
    ///
    /// We split the handle into three sections:
    /// - generation
    /// - index
    /// - checksum
    ///
    /// The checksum is used to prevent accidential casting of a handle
    /// into index and generation.
    ///
    /// The generation is a second level safety measure which stores the
    /// number of times this specific index was allocated already.
    ///
    /// The index is an offset into our list of elements.
    pub const EncodedHandle = packed struct(usize) {
        const Checksum = u2;
        const Generation = u10;
        const Index: type = @Type(.{ .Int = .{
            .signedness = .unsigned,
            .bits = index_bits,
        } });

        const generation_bits = @bitSizeOf(Generation);
        const checksum_bits = @bitSizeOf(Checksum);
        const index_bits = @bitSizeOf(usize) - generation_bits - checksum_bits;

        index: Index,
        generation: Generation,
        checksum: Checksum,

        fn validate_checksum(h: EncodedHandle) error{ChecksumMismatch}!void {
            const expected = compute_checksum(h.index, h.generation);
            if (expected != h.checksum)
                return error.ChecksumMismatch;
        }

        /// Compute a Wyhash based checksum which is folded into `checksum_bits` bits by
        /// xoring it will all bit groups of the hash compute by Wyhash.
        fn compute_checksum(index: Index, generation: Generation) Checksum {
            var hasher = std.hash.Wyhash.init(0x8b3e_8737_cf7d_4c30);
            // Encode both index and generation as `usize`, so we can safely change them without anything breaking.
            hasher.update(std.mem.asBytes(&@as(usize, index)));
            hasher.update(std.mem.asBytes(&@as(usize, generation)));
            var final = hasher.final();
            var out: Checksum = 0;
            while (final != 0) {
                out ^= @truncate(final);
                final >>= checksum_bits;
            }
            return out;
        }
    };
};

test "HandlePool" {
    var p1: ashet.multi_tasking.Process = undefined;
    var p2: ashet.multi_tasking.Process = undefined;
    var p3: ashet.multi_tasking.Process = undefined;

    var pool = HandlePool.init(std.testing.allocator);
    defer pool.deinit();

    const h1 = try pool.alloc(&p1);
    const h2 = try pool.alloc(&p2);

    try std.testing.expect(h1.owner.data == &p1);
    try std.testing.expect(h2.owner.data == &p2);

    try std.testing.expect(try pool.resolve(h1.handle) == h1.owner);
    try std.testing.expect(try pool.resolve(h2.handle) == h2.owner);

    try pool.free(h1.handle);
    try std.testing.expectError(error.GenerationMismatch, pool.free(h1.handle));

    const h3 = try pool.alloc(&p3);

    try std.testing.expectError(error.GenerationMismatch, pool.resolve(h1.handle));
    try std.testing.expect(try pool.resolve(h2.handle) == h2.owner);
    try std.testing.expect(try pool.resolve(h3.handle) == h3.owner);

    try pool.free(h2.handle);
    try pool.free(h3.handle);

    try std.testing.expectError(error.GenerationMismatch, pool.free(h1.handle));
}

test "HandlePool Stress Test" {

    // test configuration:
    const repeat_count = 100; // number of test loops
    const loop_count = 10_000; // number of alloc/free/resolve calls per loop
    const free_chance = 0.7; // random free chance
    const alloc_chance = 0.8; // random alloc chance
    const retain_chance = 0.1; // accidently double-free percentage
    const fake_free_chance = 0.1; // chance for freeing random handles
    const fake_resolve_chance = 0.1; // chance for freeing random handles

    // test:

    var dummy: ashet.multi_tasking.Process = undefined;

    var rng_engine = std.rand.DefaultPrng.init(0x1337);
    const rng = rng_engine.random();

    for (0..repeat_count) |test_loop| {
        var pool = HandlePool.init(std.testing.allocator);
        defer pool.deinit();

        var alive_handles = std.ArrayList(Handle).init(std.testing.allocator);
        defer alive_handles.deinit();

        var retained_items = std.AutoHashMap(Handle, void).init(std.testing.allocator);
        defer retained_items.deinit();

        try alive_handles.ensureTotalCapacity(loop_count);

        var max_level: usize = 0;
        var alloc_count: usize = 0;
        var free_count: usize = 0;
        var fake_free_count: usize = 0;
        var fake_resolve_count: usize = 0;
        var retain_count: usize = 0;

        for (0..loop_count) |_| {
            if (alive_handles.items.len > 0 and rng.float(f32) < free_chance) {
                const index = rng.intRangeLessThan(usize, 0, alive_handles.items.len);

                const retain_item = rng.float(f32) < retain_chance;

                const handle = if (retain_item)
                    alive_handles.items[index]
                else
                    alive_handles.swapRemove(index);

                pool.free(handle) catch {
                    // this is fine in our scenario
                };

                if (retain_item) {
                    retain_count += 1;
                    try retained_items.put(handle, {});
                } else {
                    _ = retained_items.remove(handle);
                }

                free_count += 1;
            }

            if (rng.float(f32) < alloc_chance) {
                const res = try pool.alloc(&dummy);
                std.debug.assert(res.owner.data == &dummy);

                try alive_handles.append(res.handle);

                alloc_count += 1;
            }

            if (rng.float(f32) < fake_free_chance) {
                const handle: Handle = @ptrFromInt(rng.int(usize));

                if (pool.free(handle)) |_| {
                    const alive_index = std.mem.indexOfScalar(Handle, alive_handles.items, handle);
                    try std.testing.expect(alive_index != null);

                    _ = alive_handles.swapRemove(alive_index.?);
                    _ = retained_items.remove(handle);
                } else |_| {
                    // this is fine
                    fake_free_count += 1;
                }
            }

            if (rng.float(f32) < fake_resolve_chance) {
                const handle: Handle = @ptrFromInt(rng.int(usize));

                if (pool.resolve(handle)) |_| {
                    try std.testing.expect(std.mem.indexOfScalar(Handle, alive_handles.items, handle) != null);
                } else |_| {
                    // this is fine
                    fake_resolve_count += 1;
                }
            }

            if (alive_handles.items.len > 0) {
                const index = rng.intRangeLessThan(usize, 0, alive_handles.items.len);

                const handle = alive_handles.items[index];

                if (retained_items.get(handle) != null) {
                    try std.testing.expectEqual(@as(?*Owner, null), pool.resolve(handle) catch null);
                } else {
                    _ = try pool.resolve(handle);
                }
            }

            max_level = @max(max_level, alive_handles.items.len);
        }

        while (alive_handles.popOrNull()) |handle| {
            pool.free(handle) catch {
                // this is fine in our scenario
            };
        }

        std.debug.print("\ntest loop {}:\n", .{test_loop});
        std.debug.print("  max_level          = {}\n", .{max_level});
        std.debug.print("  alloc_count        = {}\n", .{alloc_count});
        std.debug.print("  free_count         = {}\n", .{free_count});
        std.debug.print("  retain_count       = {}\n", .{retain_count});
        std.debug.print("  fake_free_count    = {}\n", .{fake_free_count});
        std.debug.print("  fake_resolve_count = {}\n", .{fake_resolve_count});
    }
}
