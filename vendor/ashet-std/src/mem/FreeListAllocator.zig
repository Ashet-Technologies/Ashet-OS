const std = @import("std");
const builtin = @import("builtin");

const is_debug = (builtin.mode == .Debug);

const Allocator = std.mem.Allocator;

/// An allocator that splits a memory region into allocatable chunks.
pub const FreeListAllocator = struct {
    // [<-------------------------- Region ------------------------->]
    // [<- Chunk ->][<--- Chunk --->][<-Chunk->][<-Chunk->][<-Chunk->]
    //

    pub const Error = Allocator.Error;

    const base_align = @alignOf(usize);

    region: []align(base_align) u8,
    root: *Chunk,

    pub fn init(raw_region: []u8) FreeListAllocator {
        var allo = FreeListAllocator{
            .region = std.mem.alignInSlice(raw_region, base_align) orelse @panic("Pass enough memory to at least conform to basic alignment"),
            .root = undefined,
        };
        std.debug.assert(std.mem.isAligned(@intFromPtr(allo.region.ptr), base_align));
        std.debug.assert(std.mem.isAligned(allo.region.len, base_align));

        allo.root = Chunk.format(allo.region);

        return allo;
    }

    pub fn allocator(self: *FreeListAllocator) Allocator {
        return Allocator.init(self, alloc, resize, free);
    }

    fn alloc(fla: *FreeListAllocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Error![]u8 {
        _ = fla;
        _ = len;
        _ = ptr_align;
        _ = len_align;
        _ = ret_addr;
        @panic("not implemented yet");
    }

    fn resize(fla: *FreeListAllocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize {
        _ = fla;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        _ = new_len;
        _ = len_align;
        _ = ret_addr;
        @panic("not implemented yet");
    }

    fn free(fla: *FreeListAllocator, buf: []u8, buf_align: u29, ret_addr: usize) void {
        _ = fla;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        @panic("not implemented yet");
    }

    fn next(fla: *FreeListAllocator, chunk: *Chunk) ?*Chunk {
        const follower = @as(*Chunk, @ptrCast(@as([*]u8, @ptrCast(chunk)) + chunk.len));
        if (follower >= fla.region.ptr + fla.region.len)
            return null;
        return follower;
    }

    const Chunk = struct {
        len: usize,
        flags: Flags,

        pub fn format(region: []align(base_align) u8) *Chunk {
            std.debug.assert(region.len >= @sizeOf(Chunk));

            const chunk = @as(*Chunk, @ptrCast(region.ptr));
            chunk.* = Chunk{
                .len = region.len,
                .flags = .{ .free = true },
            };

            return chunk;
        }

        pub fn fromUserRegion(region: []u8) *Chunk {
            return @as(*Chunk, @ptrFromInt(@intFromPtr(region.ptr) - @sizeOf(Chunk)));
        }

        /// Returns the portion of memory in this chunk that is reserved for the user.
        pub fn userRegion(chunk: *Chunk) []u8 {
            const mem = @as([*]align(4) u8, @ptrCast(chunk));
            return mem[@sizeOf(Chunk)..chunk.len];
        }
    };

    const Flags = packed struct(u8) {
        free: bool,
        unused: u7 = 0,
    };
};

test "basic formatting" {
    const base_region = try std.testing.allocator.alloc(u8, 256 * 1024);
    defer std.testing.allocator.free(base_region);

    const fla = FreeListAllocator.init(base_region);

    _ = fla;
}

// test "test suite" {
//     const base_region = try std.testing.allocator.alloc(u8, 256 * 1024);
//     defer std.testing.allocator.free(base_region);

//     var fla = FreeListAllocator.init(base_region);

//     try runAllocatorTestSuite(fla.allocator());
// }

fn runAllocatorTestSuite(subject_to_test: std.mem.Allocator) !void {
    var validator = std.mem.validationWrap(subject_to_test);
    const allocator = validator.allocator();

    var random_source = std.rand.DefaultPrng.init(13091993);
    const rng = random_source.random();

    // First, perform some basic allocs
    {
        const bytes = try allocator.alloc(u8, 64);
        allocator.free(bytes);

        const smol = try allocator.create(u8);
        allocator.destroy(smol);

        const big = try allocator.create([256]u8);
        allocator.destroy(big);

        const uneven = try allocator.create([33]u8);
        allocator.destroy(uneven);
    }

    // Apply some basic pressure testing
    {
        //
        _ = rng;
    }
}
