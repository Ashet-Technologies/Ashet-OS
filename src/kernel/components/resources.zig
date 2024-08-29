const std = @import("std");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.resources);

/// Encodes the different types of system resources.
pub const TypeId = ashet.abi.SystemResource.Type;

/// This is the ABI-public version of a system resource.
pub const Handle = ashet.abi.SystemResource;

/// Resolves the resource `handle` for the `owner` process into a pointer to
/// `Resource`.
pub fn resolve(
    comptime Resource: type,
    owner: *ashet.multi_tasking.Process,
    handle: Handle,
) error{ Gone, InvalidHandle, GenerationMismatch, TypeMismatch }!*Resource {
    const link = try owner.resources.resolve(handle);
    std.debug.assert(owner == link.data.process);
    const resource = link.data.resource;
    return resource.cast(Resource) catch return error.TypeMismatch;
}

/// This is the kernel-internal abstraction over system resources.
pub const SystemResource = struct {
    type: TypeId,

    /// Number of processes this resource is referenced by.
    owners: std.DoublyLinkedList(Ownership) = .{},

    pub fn cast(src: *SystemResource, comptime Resource: type) error{BadCast}!*Resource {
        const expected_type = instanceTypeId(Resource);
        if (src.type != expected_type)
            return error.BadCast;
        return @alignCast(@fieldParentPtr("system_resource", src));
    }

    pub fn add_owner(src: *SystemResource, owner: *OwnershipNode) void {
        std.debug.assert(owner.data.resource == src);
        logger.debug("add process 0x{X:0>8} to resource 0x{X:0>8} of type {s}", .{
            @intFromPtr(owner.data.process),
            @intFromPtr(src),
            @tagName(src.type),
        });
        src.owners.append(owner);
    }

    pub fn remove_owner(src: *SystemResource, owner: *OwnershipNode) void {
        std.debug.assert(owner.data.resource == src);
        logger.debug("remove process 0x{X:0>8} from resource 0x{X:0>8} of type {s}", .{
            @intFromPtr(owner.data.process),
            @intFromPtr(src),
            @tagName(src.type),
        });
        src.owners.remove(owner);
        if (src.owners.len == 0) {
            src.destroy();
        }
    }

    /// Destroys the resource
    pub fn destroy(src: *SystemResource) void {
        logger.debug("destroy 0x{X:0>8} of type {s}", .{
            @intFromPtr(src),
            @tagName(src.type),
        });
        src.unlink();
        switch (src.type) {
            inline else => |type_id| {
                const instance = src.cast(ashet.resources.InstanceType(type_id)) catch unreachable;
                instance.destroy();
            },

            // Threads need special handling
            .thread => {
                const instance = src.cast(ashet.scheduler.Thread) catch unreachable;
                instance.kill();
            },

            // video outputs are non-destroyed resources, they will exist until system exit.
            .video_output => {},
        }
    }

    /// Removes all references from owning processes.
    fn unlink(src: *SystemResource) void {
        var it = src.owners.first;
        while (it) |node| {
            it = node.next;
            node.data.process.resources.free_by_ownership(node) catch |err| switch (err) {
                error.DoubleFree => {
                    // this is fine, as unlink() might result from a process dropping a resource
                },
                error.NotOwned => unreachable, // kernel implementation bug
            };
        }
    }

    pub fn format(src: *const SystemResource, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("SystemResource(0x{X:0>8}, type={s}, owners={d})", .{
            @intFromPtr(src),
            @tagName(src.type),
            src.owners.len,
        });
    }
};

/// Link between a process and a resource.
pub const Ownership = struct {
    process: *ashet.multi_tasking.Process,
    resource: *SystemResource,
    handle: Handle,
};

pub const OwnershipNode = std.DoublyLinkedList(Ownership).Node;

/// Manages allocation
pub const HandlePool = struct {
    const grow_margin = 64; // always allocate 64 chunks at once

    allocator: std.mem.Allocator,

    bit_map: std.DynamicBitSetUnmanaged = .{},
    generations: std.ArrayListUnmanaged(EncodedHandle.Generation) = .{},
    owners: std.SegmentedList(OwnershipNode, grow_margin) = .{},

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
        ownership: *OwnershipNode,
    };

    /// Allocates a new handle and returns both handle and the owner, with uninitialized `.data`
    pub fn alloc(pool: *HandlePool) error{ OutOfMemory, OutOfHandles }!AllocResult {
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

        const handle = pool.handle_from_index(raw_index);

        const owner = pool.owners.uncheckedAt(raw_index);
        owner.* = .{
            .data = undefined,
        };

        return .{
            .handle = handle,
            .ownership = owner,
        };
    }

    fn handle_from_index(pool: HandlePool, index: usize) Handle {
        const generation_ptr = &pool.generations.items[index];

        var encoded: EncodedHandle = .{
            .index = @intCast(index),
            .generation = generation_ptr.*,
            .checksum = 0,
        };
        encoded.checksum = EncodedHandle.compute_checksum(
            encoded.index,
            encoded.generation,
        );

        return @enumFromInt(@as(usize, @bitCast(encoded)));
    }

    pub fn index_from_handle(pool: *HandlePool, handle: Handle) error{ InvalidHandle, DoubleFree, GenerationMismatch }!usize {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());

        const handle_bits: EncodedHandle = @bitCast(@intFromEnum(handle));

        handle_bits.validate_checksum() catch return error.InvalidHandle;
        if (handle_bits.index >= pool.bit_map.capacity())
            return error.InvalidHandle;

        if (pool.generations.items[handle_bits.index] != handle_bits.generation)
            return error.GenerationMismatch;

        return handle_bits.index;
    }

    pub fn free_by_handle(pool: *HandlePool, handle: Handle) error{ InvalidHandle, DoubleFree, GenerationMismatch }!void {
        const index = try pool.index_from_handle(handle);

        pool.free_by_index(index) catch |err| switch (err) {
            error.OutOfBounds => unreachable,
            error.DoubleFree => |e| return e,
        };
    }

    pub fn free_by_ownership(pool: *HandlePool, ownership: *OwnershipNode) error{ NotOwned, DoubleFree }!void {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());

        var index: usize = 0;
        var iter = pool.owners.iterator(0);
        while (iter.next()) |owned_ownership| : (index += 1) {
            if (owned_ownership == ownership) {
                return pool.free_by_index(index) catch |err| switch (err) {
                    error.OutOfBounds => unreachable,
                    error.DoubleFree => |e| e,
                };
            }
        }
        return error.NotOwned;
    }

    pub fn free_by_index(pool: *HandlePool, index: usize) error{ OutOfBounds, DoubleFree }!void {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());

        if (index >= pool.bit_map.capacity())
            return error.OutOfBounds;

        if (pool.bit_map.isSet(index))
            return error.DoubleFree;

        pool.bit_map.set(index);
        pool.owners.at(index).* = undefined;
        pool.generations.items[index] +%= 1;
    }

    pub fn resolve(pool: *HandlePool, handle: Handle) error{ InvalidHandle, GenerationMismatch, Gone }!*OwnershipNode {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());

        const handle_bits: EncodedHandle = @bitCast(@intFromEnum(handle));

        handle_bits.validate_checksum() catch return error.InvalidHandle;
        if (handle_bits.index >= pool.bit_map.capacity())
            return error.InvalidHandle;

        if (pool.generations.items[handle_bits.index] != handle_bits.generation)
            return error.GenerationMismatch;

        if (pool.bit_map.isSet(handle_bits.index))
            return error.Gone;

        return pool.owners.uncheckedAt(handle_bits.index);
    }

    pub fn index_from_resource(pool: *HandlePool, resource: *SystemResource) ?usize {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());

        var index: usize = 0;
        var iter = pool.owners.iterator(0);
        while (iter.next()) |owned_ownership| : (index += 1) {
            if (owned_ownership.data.resource == resource) {
                return index;
            }
        }
        return null;
    }

    pub fn ownership_from_index(pool: *HandlePool, index: usize) *OwnershipNode {
        std.debug.assert(pool.generations.items.len == pool.bit_map.capacity());
        std.debug.assert(pool.owners.len == pool.bit_map.capacity());
        std.debug.assert(index < pool.owners.len);

        return pool.owners.at(index);
    }

    pub fn iterator(pool: HandlePool) Iterator {
        return .{ .pool = pool };
    }

    pub const Iterator = struct {
        pool: HandlePool,
        index: usize = 0,

        pub fn next(iter: *Iterator) ?IterationItem {
            const max_count = iter.pool.bit_map.capacity();

            while (iter.index < max_count and iter.pool.bit_map.isSet(iter.index)) {
                iter.index += 1;
            }
            if (iter.index >= max_count)
                return null;

            const index = iter.index;
            iter.index += 1;
            std.debug.assert(!iter.pool.bit_map.isSet(index));
            return .{
                .index = index,
                .ownership = iter.pool.owners.at(index),
            };
        }
    };

    pub const IterationItem = struct {
        index: usize,
        ownership: *OwnershipNode,
    };

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
    var pool = HandlePool.init(std.testing.allocator);
    defer pool.deinit();

    const h1 = try pool.alloc();
    const h2 = try pool.alloc();

    try std.testing.expect(try pool.resolve(h1.handle) == h1.ownership);
    try std.testing.expect(try pool.resolve(h2.handle) == h2.ownership);

    try pool.free_by_handle(h1.handle);
    try std.testing.expectError(error.GenerationMismatch, pool.free_by_handle(h1.handle));

    const h3 = try pool.alloc();

    try std.testing.expectError(error.GenerationMismatch, pool.resolve(h1.handle));
    try std.testing.expect(try pool.resolve(h2.handle) == h2.ownership);
    try std.testing.expect(try pool.resolve(h3.handle) == h3.ownership);

    try pool.free_by_handle(h2.handle);
    try pool.free_by_handle(h3.handle);

    try std.testing.expectError(error.GenerationMismatch, pool.free_by_handle(h1.handle));
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
    const iterate_chance = 0.1; // chance for iterating all handles

    // test:

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

                pool.free_by_handle(handle) catch {
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
                const res = try pool.alloc();

                try alive_handles.append(res.handle);

                alloc_count += 1;
            }

            if (rng.float(f32) < fake_free_chance) {
                const handle: Handle = @ptrFromInt(rng.int(usize));

                if (pool.free_by_handle(handle)) |_| {
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
            if (rng.float(f32) < iterate_chance) {
                var count: usize = 0;
                var iter = pool.iterator();
                while (iter.next()) |item| {
                    try std.testing.expect(!pool.bit_map.isSet(item.index));
                    count += 1;
                }
                try std.testing.expectEqual(iter.pool.bit_map.capacity() - iter.pool.bit_map.count(), count);
            }

            if (alive_handles.items.len > 0) {
                const index = rng.intRangeLessThan(usize, 0, alive_handles.items.len);

                const handle = alive_handles.items[index];

                if (retained_items.get(handle) != null) {
                    try std.testing.expectEqual(@as(?*OwnershipNode, null), pool.resolve(handle) catch null);
                } else {
                    _ = try pool.resolve(handle);
                }
            }

            max_level = @max(max_level, alive_handles.items.len);
        }

        while (alive_handles.popOrNull()) |handle| {
            pool.free_by_handle(handle) catch {
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

/// Maps `TypeId` to a concrete type.
pub fn InstanceType(comptime type_enum: TypeId) type {
    return switch (type_enum) {
        .shared_memory => ashet.shared_memory.SharedMemory,
        .pipe => ashet.pipes.Pipe,
        .service => ashet.ipc.Service,

        .process => ashet.multi_tasking.Process,
        .thread => ashet.scheduler.Thread,

        .sync_event => ashet.sync.SyncEvent,
        .mutex => ashet.sync.Mutex,

        .tcp_socket => ashet.network.tcp.Socket,
        .udp_socket => ashet.network.udp.Socket,

        .file => ashet.filesystem.File,
        .directory => ashet.filesystem.Directory,

        .video_output => ashet.video.Output,
        .framebuffer => ashet.graphics.Framebuffer,
        .font => ashet.graphics.Font,

        .window => ashet.gui.Window,
        .desktop => ashet.gui.Desktop,
        .widget => ashet.gui.Widget,
        .widget_type => ashet.gui.WidgetType,
    };
}

/// Maps a concrete type to it's `TypeId`
pub fn instanceTypeId(comptime T: type) TypeId {
    const result = comptime blk: {
        for (std.enums.values(TypeId)) |type_id| {
            if (InstanceType(type_id) == T)
                break :blk type_id;
        }
        @compileError(@typeName(T) ++ " is not a registered resource type!");
    };
    return result;
}

comptime {
    for (std.enums.values(TypeId)) |type_id| {
        const T = InstanceType(type_id);
        if (!@hasField(T, "system_resource"))
            @compileError(@typeName(T) ++ " is registered as a system resource, but has no field 'system_resource'!");
        const field = std.meta.fieldInfo(T, @field(std.meta.FieldEnum(T), "system_resource"));
        if (field.type != SystemResource)
            @compileError(@typeName(T) ++ ".system_resource is not a SystemResource!");
    }
}
