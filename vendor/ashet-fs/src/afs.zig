//!
//! Ashet File System
//!

const std = @import("std");
const logger = std.log.scoped(.ashet_fs);

fn asBytes(ptr: anytype) *[512]u8 {
    const T = @TypeOf(ptr.*);
    if (@sizeOf(T) != 512) @compileError("Invalid object size");
    return @as(*[512]u8, @ptrCast(ptr));
}

fn asConstBytes(ptr: anytype) *const [512]u8 {
    const T = @TypeOf(ptr.*);
    if (@sizeOf(T) != 512) @compileError("Invalid object size");
    return @as(*const [512]u8, @ptrCast(ptr));
}

fn bytesAsValue(comptime T: type, bytes: *align(@alignOf(T)) [@sizeOf(T)]u8) *T {
    return @as(*T, @ptrCast(bytes));
}

fn makeZeroPaddedString(str: []const u8, comptime len: comptime_int) [len]u8 {
    var buf = std.mem.zeroes([len]u8);
    std.mem.copyForwards(u8, &buf, str);
    return buf;
}

pub const magic_number: [32]u8 = .{
    0x2c, 0xcd, 0xbe, 0xe2, 0xca, 0xd9, 0x99, 0xa7, 0x65, 0xe7, 0x57, 0x31, 0x6b, 0x1c, 0xe1, 0x2b,
    0xb5, 0xac, 0x9d, 0x13, 0x76, 0xa4, 0x54, 0x69, 0xfc, 0x57, 0x29, 0xa8, 0xc9, 0x3b, 0xef, 0x62,
};

pub const Block = [512]u8;

/// A global block that provides 512 empty bytes. Required to clear freshly allocated blocks
const zero_block = std.mem.zeroes(Block);

pub const BlockDevice = struct {
    pub const IoError = error{
        WriteProtected,
        OperationTimeout,
        DeviceError,
    };

    pub const CompletedCallback = fn (*anyopaque, ?IoError) void;

    pub const VTable = struct {
        getBlockCountFn: *const fn (*anyopaque) u32,
        writeBlockFn: *const fn (*anyopaque, offset: u32, block: *const Block) IoError!void,
        readBlockFn: *const fn (*anyopaque, offset: u32, block: *Block) IoError!void,
    };

    object: *anyopaque,
    vtable: *const VTable,

    /// Returns the number of blocks in this block device.
    /// Support a maximum of 2 TB storage.
    pub fn getBlockCount(bd: BlockDevice) u32 {
        return bd.vtable.getBlockCountFn(bd.object);
    }

    /// Starts a write operation on the underlying block device. When done, will call `callback` with `callback_ctx` as the first argument, and
    /// an optional error state.
    /// NOTE: When the block device is non-blocking, `callback` is already invoked in this function! Design your code in a way that this won't
    /// affect your control flow.
    pub fn writeBlock(bd: BlockDevice, offset: u32, block: *const Block) IoError!void {
        try bd.vtable.writeBlockFn(bd.object, offset, block);
    }

    /// Starts a read operation on the underlying block device. When done, will call `callback` with `callback_ctx` as the first argument, and
    /// an optional error state.
    /// NOTE: When the block device is non-blocking, `callback` is already invoked in this function! Design your code in a way that this won't
    /// affect your control flow.
    pub fn readBlock(bd: BlockDevice, offset: u32, block: *Block) IoError!void {
        try bd.vtable.readBlockFn(bd.object, offset, block);
    }
};

pub const FileDataCache = struct {
    const CachedRefBlock = struct {
        next: u32,
        refs: []const u32,
    };

    const cache_size = 16;

    entry_valid: std.StaticBitSet(cache_size) = std.StaticBitSet(cache_size).initEmpty(),
    associated_file: [cache_size]FileHandle = undefined,
    associated_index: [cache_size]u32 = undefined,
    cached_refs: [cache_size][127]u32 = undefined,
    cached_ref_lens: [cache_size]usize = undefined,
    cached_nexts: [cache_size]u32 = undefined,

    fn cacheIndex(file: FileHandle, block_index: u32) usize {
        return (@intFromEnum(file) + block_index) % cache_size;
    }

    fn isHit(cache: *const FileDataCache, file: FileHandle, block_index: u32) ?usize {
        const index = cacheIndex(file, block_index);
        if (!cache.entry_valid.isSet(index))
            return null;
        if (cache.associated_file[index] != file)
            return null;
        if (cache.associated_index[index] != block_index)
            return null;
        return index;
    }

    fn fetchRefBlock(cache: *const FileDataCache, file: FileHandle, block_index: u32) ?CachedRefBlock {
        const index = cache.isHit(file, block_index) orelse {
            logger.debug("cache miss for {}+{}", .{
                @intFromEnum(file),
                block_index,
            });
            return null;
        };

        logger.debug("cache hit for {}+{}", .{
            @intFromEnum(file),
            block_index,
        });
        return CachedRefBlock{
            .next = cache.cached_nexts[index],
            .refs = cache.cached_refs[index][0..cache.cached_ref_lens[index]],
        };
    }

    fn putRefBlock(cache: *FileDataCache, file: FileHandle, block_index: u32, refs: []const u32, next_block: u32) void {
        const index = cacheIndex(file, block_index);

        cache.associated_file[index] = file;
        cache.associated_index[index] = block_index;

        std.mem.copyForwards(u32, &cache.cached_refs[index], refs);
        cache.cached_ref_lens[index] = refs.len;
        cache.cached_nexts[index] = next_block;

        cache.entry_valid.set(index);

        logger.debug("set cache({}) to {}+{}", .{
            index,
            @intFromEnum(file),
            block_index,
        });
    }
};

/// The AshetFS filesystem driver. Implements all supported operations on the file
/// system over a block device.
/// It's recommended to use a caching block device so not every small change will
/// create disk activity.
pub const FileSystem = struct {
    device: BlockDevice,

    version: u32,
    size: u64,

    root_directory: DirectoryHandle,

    pub fn init(bd: BlockDevice) !FileSystem {
        var fs = FileSystem{
            .device = bd,
            .version = undefined,
            .size = undefined,
            .root_directory = undefined,
        };

        var root_block: RootBlock = undefined;
        try bd.readBlock(0, asBytes(&root_block));

        if (!std.mem.eql(u8, &root_block.magic_identification_number, &magic_number))
            return error.NoFilesystem;

        if (root_block.size > bd.getBlockCount())
            return error.CorruptFileSystem;

        if (root_block.version != 1)
            return error.UnsupportedVersion;

        const bitmap_block_count = ((root_block.size + 4095) / 4096);

        fs.version = root_block.version;
        fs.size = root_block.size;
        fs.root_directory = @as(DirectoryHandle, @enumFromInt(bitmap_block_count + 1));

        return fs;
    }

    pub fn getRootDir(fs: FileSystem) DirectoryHandle {
        return fs.root_directory;
    }

    pub fn iterate(fs: *FileSystem, dir: DirectoryHandle) !Iterator {
        var iter = Iterator{
            .device = fs.device,
            .total_count = undefined,
            .ref_storage = undefined,
            .ref_index = @offsetOf(ObjectBlock, "refs") / @sizeOf(u32),
            .entry_index = 0,
        };

        try fs.device.readBlock(dir.blockNumber(), asBytes(&iter.ref_storage));

        const blocklist = @as(*align(4) ObjectBlock, @ptrCast(&iter.ref_storage));

        iter.total_count = blocklist.size / @sizeOf(Entry);

        return iter;
    }

    pub fn readMetaData(fs: *FileSystem, object: ObjectHandle) !MetaData {
        var block: ObjectBlock = undefined;

        try fs.device.readBlock(object.blockNumber(), asBytes(&block));

        return MetaData{
            .create_time = block.create_time,
            .modify_time = block.modify_time,
            .size = block.size,
            .flags = block.flags,
        };
    }

    pub fn updateMetaData(fs: *FileSystem, object: ObjectHandle, changeset: MetaDataChangeSet) !void {
        var block: ObjectBlock = undefined;

        try fs.device.readBlock(object.blockNumber(), asBytes(&block));

        if (changeset.create_time) |new_value| block.create_time = new_value;
        if (changeset.modify_time) |new_value| block.modify_time = new_value;
        if (changeset.flags) |new_value| block.flags = new_value;

        try fs.device.writeBlock(object.blockNumber(), asConstBytes(&block));
    }

    fn stringsEqualZ(lhs: []const u8, rhs: []const u8) bool {
        const lhs_strip = if (std.mem.indexOfScalar(u8, lhs, 0)) |i| lhs[0..i] else lhs;
        const rhs_strip = if (std.mem.indexOfScalar(u8, rhs, 0)) |i| rhs[0..i] else rhs;

        return std.mem.eql(u8, lhs_strip, rhs_strip);
    }

    // Allocates a new block on the file system and returns its number.
    fn allocBlock(fs: *FileSystem) !u32 {
        var current_bitmap_block: u32 = 1;

        // the root directy is always directly after the bitmap, so as soon as our
        // cursor is hitting the root dir, we're out of memory.
        while (current_bitmap_block != @intFromEnum(fs.root_directory)) : (current_bitmap_block += 1) {
            var buf: Block align(4) = undefined;
            try fs.device.readBlock(current_bitmap_block, &buf);

            const buf_slice = std.mem.bytesAsSlice(u32, &buf);

            const Bit = struct {
                offset: u32,
                bit: u5,
            };

            const bit: Bit = for (buf_slice, 0..) |*item, word_index| {
                if (item.* == 0xFFFF_FFFF) // early check
                    continue;

                break Bit{
                    .offset = @as(u32, @intCast(word_index)),
                    .bit = @as(u5, @intCast(@ctz(~item.*))),
                };
            } else continue;

            // std.debug.print("alloc block: {}.{}.{}\n", .{
            //     current_bitmap_block,
            //     bit.offset,
            //     bit.bit,
            // });

            buf_slice[bit.offset] |= (@as(u32, 1) << bit.bit);

            // write back the allocation
            try fs.device.writeBlock(current_bitmap_block, &buf);

            // compute the absolute block index
            return 4096 * (current_bitmap_block - 1) + 32 * bit.offset + bit.bit;
        }

        return error.DiskFull;
    }

    // Frees a previously allocated block.
    fn freeBlock(fs: *FileSystem, block: u32) !void {
        _ = fs;
        _ = block;
        @panic("unimplemented");
    }

    /// Creates a new entry in a directory and initializes the ObjectBlock with default values.
    /// Ensures the created object isn't duplicate by name
    fn createEntryInDir(fs: *FileSystem, dir: DirectoryHandle, name: []const u8, entry_type: Entry.Type, time_stamp: i128) !ObjectHandle {
        if (name.len > 120)
            return error.NameTooLong;

        var list_block_num: u32 = undefined;
        var list_buf: Block align(16) = undefined;

        var refs: []u32 = undefined;
        var ref_count: u32 = undefined;
        var next_ref_block: u32 = undefined;
        var entry_count: u32 = undefined;

        {
            const entries_per_block = @divExact(@sizeOf(Block), @sizeOf(Entry));

            list_block_num = dir.blockNumber();
            try fs.device.readBlock(list_block_num, &list_buf);

            const object_block = bytesAsValue(ObjectBlock, &list_buf);

            entry_count = std.math.cast(u32, object_block.size / @sizeOf(Entry)) orelse return error.CorruptFilesystem;

            ref_count = (entry_count + entries_per_block - 1) / entries_per_block;
            refs = &object_block.refs;
            next_ref_block = object_block.next;
        }

        const StorageTarget = struct {
            block: u32,
            index: u2,
        };

        var valid_slot: ?StorageTarget = null;

        search_loop: for (0..ref_count) |_| {
            std.debug.assert(entry_count > 0);
            if (refs.len == 0) {
                if (next_ref_block == 0)
                    return error.CorruptFileSystem;
                list_block_num = next_ref_block;
                try fs.device.readBlock(list_block_num, &list_buf);
                const ref_block: *RefListBlock = bytesAsValue(RefListBlock, &list_buf);
                refs = &ref_block.refs;
                next_ref_block = ref_block.next;
                if (refs.len == 0)
                    return error.CorruptFileSystem;
            }

            const current_data_block = refs[0];
            refs = refs[1..];

            var entry_buf: Block align(16) = undefined;
            try fs.device.readBlock(current_data_block, &entry_buf);
            const dir_data: *DirectoryDataBlock = bytesAsValue(DirectoryDataBlock, &entry_buf);

            for (&dir_data.entries, 0..) |entry, i| {
                //   T we used up all entries, but there are still entries left in our current segment
                //   |
                //   |                      T the current entry was freed at a previous point in time.
                //   v                      v
                if ((entry_count == 0 or entry.ref == 0) and valid_slot == null) {
                    valid_slot = StorageTarget{
                        .block = current_data_block,
                        .index = @as(u2, @intCast(i)),
                    };
                    if (entry_count == 0)
                        break :search_loop;
                }
                if (stringsEqualZ(&entry.name, name))
                    return error.FileAlreadyExists;

                entry_count -= 1;
            }
        }

        // std.debug.print("valid_slot     = {?}\n", .{valid_slot});
        // std.debug.print("refs           = {any}\n", .{refs});
        // std.debug.print("ref_count      = {}\n", .{ref_count});
        // std.debug.print("next_ref_block = {}\n", .{next_ref_block});
        // std.debug.print("entry_count    = {}\n", .{entry_count});

        const storage_slot = if (valid_slot) |slot| slot else blk: {
            // no free entry blocks are in the block ref chain,
            // so we need to allocate a new block into the chain.

            const slot = StorageTarget{
                .block = try fs.allocBlock(),
                .index = 0,
            };
            errdefer fs.freeBlock(slot.block) catch |err| {
                // TODO: What to do here?
                logger.err("failed to free block {}: {s}\nfile system garbage collection is required!", .{
                    slot.block,
                    @errorName(err),
                });
            };

            if (next_ref_block != 0)
                return error.CorruptFileSystem; // must be 0, otherwise something got inconsistent. this has to be the last page

            if (refs.len > 0) {
                // we still got some refs in our current list available
                // let's emplace ourselves there

                // mutate the data stored in `list_buf`. This is safe as we
                // will always write into the right place in the buffer, no matter
                // if it's an `ObjectBlock` or a `RefListBlock`.
                refs[0] = slot.block;

                // then write-back the block into the filesystem. we have now successfully emplaced ourselves
                try fs.device.writeBlock(list_block_num, &list_buf);
            } else {

                // we are at the total end of the block ref chain, we have to get a new ref list and put ourselves into the chain:

                const new_list_block = try fs.allocBlock();
                errdefer fs.freeBlock(new_list_block) catch |err| {
                    // TODO: What to do here?
                    logger.err("failed to free block {}: {s}\nfile system garbage collection is required!", .{
                        new_list_block,
                        @errorName(err),
                    });
                };

                // we can savely write the next block in the chain, no matter
                // if `list_buf` contains a `ObjectBlock` or `RefListBlock`.
                // the `next` field is always the last 4 bytes.
                std.mem.writeInt(u32, list_buf[508..512], new_list_block, .little);

                // write-back the changes to the fs.
                try fs.device.writeBlock(list_block_num, &list_buf);

                // TOOD: How to handle error failure after that, FS is potentially in an inconsistent state?!

                const new_list: *RefListBlock = bytesAsValue(RefListBlock, &list_buf);
                new_list.* = RefListBlock{
                    .refs = std.mem.zeroes([127]u32),
                    .next = 0,
                };
                new_list.refs[0] = slot.block;

                // Write the new block to disk. File system is now semi-consistent
                try fs.device.writeBlock(new_list_block, &list_buf);
            }

            // initialize new block
            const new_entry_block: *DirectoryDataBlock = bytesAsValue(DirectoryDataBlock, &list_buf);
            new_entry_block.* = DirectoryDataBlock{
                .entries = std.mem.zeroes([4]DirectoryEntry),
            };

            try fs.device.writeBlock(slot.block, &list_buf);

            break :blk slot;
        };

        // std.debug.print("storage_slot   = {}\n", .{storage_slot});

        // Prepare new object block for the created file
        const object_block = try fs.allocBlock();
        {
            const object: *ObjectBlock = bytesAsValue(ObjectBlock, &list_buf);
            object.* = ObjectBlock{
                .size = 0,
                .create_time = time_stamp,
                .modify_time = time_stamp,
                .flags = 0,
                .refs = std.mem.zeroes([116]u32),
                .next = 0,
            };
            try fs.device.writeBlock(object_block, &list_buf);
        }

        // std.debug.print("object_block   = {}\n", .{object_block});

        // Read-modify-write our entry for the new file:
        {
            try fs.device.readBlock(storage_slot.block, &list_buf);

            const entry_list: *DirectoryDataBlock = bytesAsValue(DirectoryDataBlock, &list_buf);

            entry_list.entries[storage_slot.index] = DirectoryEntry{
                .name = makeZeroPaddedString(name, 120),
                .type = switch (entry_type) {
                    .directory => 0,
                    .file => 1,
                },
                .ref = object_block,
            };

            try fs.device.writeBlock(storage_slot.block, &list_buf);
        }

        // Read-modify-write the original directory and increase its size
        {
            try fs.device.readBlock(dir.blockNumber(), &list_buf);

            const dir_data: *ObjectBlock = bytesAsValue(ObjectBlock, &list_buf);

            // Increment directory size by a single entry.
            dir_data.size += @sizeOf(Entry);

            try fs.device.writeBlock(dir.blockNumber(), &list_buf);
        }

        return @as(ObjectHandle, @enumFromInt(object_block));
    }

    pub fn createFile(fs: *FileSystem, dir: DirectoryHandle, name: []const u8, create_time: i128) !FileHandle {
        const file_handle = try fs.createEntryInDir(dir, name, .file, create_time);
        // file is already fully initialized with an empty object
        return file_handle.toFileHandle();
    }

    pub fn resizeFile(fs: *FileSystem, file: FileHandle, new_size: u64) !void {
        var storage_blob: Block align(16) = undefined;

        try fs.device.readBlock(file.blockNumber(), &storage_blob);

        const object: *ObjectBlock = bytesAsValue(ObjectBlock, &storage_blob);
        const old_block_count = std.math.cast(u32, (object.size + @sizeOf(Block) - 1) / @sizeOf(Block)) orelse return error.CorruptFilesystem;
        const new_block_count = std.math.cast(u32, (new_size + @sizeOf(Block) - 1) / @sizeOf(Block)) orelse return error.FileSize;

        object.size = new_size;
        try fs.device.writeBlock(file.blockNumber(), &storage_blob);

        // check if we still have the same number of blocks (small bump/shrink),
        // as no work is to be done here.
        if (old_block_count == new_block_count)
            return;

        // std.debug.print("resize from {} to {} blocks\n", .{ old_block_count, new_block_count });

        if (old_block_count < new_block_count) {
            var refs: []u32 = &object.refs;
            var refs_used: u64 = old_block_count;
            var current_block: u32 = file.blockNumber();

            const skip_forward_count = if (old_block_count > ObjectBlock.ref_count)
                // compute number of blocks we gotta skip.
                ((old_block_count -| ObjectBlock.ref_count) + RefListBlock.ref_count - 1) / RefListBlock.ref_count
            else
                // no blocks to skip, we're still on the first block
                0;

            // std.debug.print("  => skip {} blocks\n", .{skip_forward_count});

            for (0..skip_forward_count) |_| {
                const next_list = std.mem.readInt(u32, storage_blob[508..512], .little);
                if (next_list == 0)
                    return error.CorruptFilesystem;
                try fs.device.readBlock(next_list, &storage_blob);
                current_block = next_list;

                // std.debug.print("  consume {} refs => {}\n", .{ refs.len, refs_used });
                refs_used -= refs.len;
                refs = &bytesAsValue(RefListBlock, &storage_blob).refs;
            }
            // std.debug.print("  refs used: {} / {}\n", .{ refs_used, refs.len });
            std.debug.assert(refs_used <= refs.len);
            refs = refs[refs_used..];

            // std.debug.print("  refs used: {}\n", .{refs_used});
            // std.debug.print("  total ref len: {}\n", .{refs.len});

            const blocks_to_fill = new_block_count - old_block_count;

            for (0..blocks_to_fill) |_| {
                if (refs.len == 0) {
                    const next_ref_block = try fs.allocBlock();

                    try fs.device.writeBlock(next_ref_block, &zero_block);
                    std.mem.writeInt(u32, storage_blob[508..512], next_ref_block, .little);
                    try fs.device.writeBlock(current_block, &storage_blob);

                    current_block = next_ref_block;

                    refs = &bytesAsValue(RefListBlock, &storage_blob).refs;
                }
                refs[0] = try fs.allocBlock();
                try fs.device.writeBlock(refs[0], &zero_block);

                refs = refs[1..];
            }

            try fs.device.writeBlock(current_block, &storage_blob);
        } else {
            @panic("shrinking files not implemented yet!");
        }
    }

    const FileDataOffset = struct {
        refblock_index: u32,
        ref_index: u7,
        byte_offset: u9,
    };

    fn computeFileDataOffset(byte_addr: u64) FileDataOffset {
        const block_number = byte_addr / @sizeOf(Block);
        const byte_offset = @as(u9, @truncate(byte_addr));

        return if (block_number < ObjectBlock.ref_count)
            FileDataOffset{
                .refblock_index = 0, // object block
                .ref_index = @as(u7, @truncate(block_number)),
                .byte_offset = byte_offset,
            }
        else
            FileDataOffset{
                .refblock_index = @as(u32, @intCast(1 + (block_number - ObjectBlock.ref_count) / RefListBlock.ref_count)),
                .ref_index = @as(u7, @intCast((block_number - ObjectBlock.ref_count) % RefListBlock.ref_count)),
                .byte_offset = byte_offset,
            };
    }

    fn accessData(
        fs: *FileSystem,
        file: FileHandle,
        position: u64,
        comptime Accessor: type,
        data: Accessor.Slice,
        opt_cache: ?*FileDataCache,
    ) !usize {
        var storage_blob: Block align(16) = undefined;

        try fs.device.readBlock(file.blockNumber(), &storage_blob);

        const object = bytesAsValue(ObjectBlock, &storage_blob);

        const object_size = object.size;

        if (object_size == 0)
            return 0; // short-cut, we don't need to access any data at all

        const actual_len = @min(data.len, object_size -| position);

        var data_position = computeFileDataOffset(position);

        // std.debug.print("\ndata position: {}\n", .{data_position});

        var refs: []const u32 = &object.refs;
        var next_block = object.next;

        var cache_hit = false;
        if (opt_cache) |cache| {
            if (cache.fetchRefBlock(file, data_position.refblock_index)) |refblock| {
                next_block = refblock.next;
                refs = refblock.refs;
                cache_hit = true;
            }
        }

        if (!cache_hit) {
            var i: u32 = 0;
            while (i < data_position.refblock_index) : (i += 1) {
                try fs.device.readBlock(next_block, &storage_blob);
                const refblock = bytesAsValue(RefListBlock, &storage_blob);
                next_block = refblock.next;
                refs = &refblock.refs;
            }
            if (opt_cache) |cache| {
                cache.putRefBlock(file, i, refs, next_block);
            }
        }

        var offset: usize = 0;
        while (offset < actual_len) {
            const max_chunk_size = @min(@sizeOf(Block), actual_len - offset);
            std.debug.assert(max_chunk_size > 0);

            // std.debug.print("try reading {} bytes at ram={}/disk={} from block {}, max len {}...\n", .{
            //     max_chunk_size,
            //     offset,
            //     data_position.byte_offset,
            //     refs[data_position.ref_index],
            //     actual_len,
            // });
            const chunk_size = if (max_chunk_size == @sizeOf(Block) and data_position.byte_offset == 0) blk: {
                try Accessor.accessFull(fs.device, refs[data_position.ref_index], data[offset..][0..@sizeOf(Block)]);
                data_position.ref_index += 1;
                break :blk @sizeOf(Block);
            } else blk: {
                const chunk_size = @min(max_chunk_size, @as(usize, @sizeOf(Block)) - data_position.byte_offset);

                try Accessor.accessPartial(
                    fs.device,
                    refs[data_position.ref_index],
                    data_position.byte_offset,
                    data[offset .. offset + chunk_size],
                );

                data_position.ref_index += 1;
                data_position.byte_offset = 0;

                break :blk chunk_size;
            };
            std.debug.assert(chunk_size > 0);

            offset += chunk_size;

            if (data_position.ref_index == refs.len and offset != actual_len) {
                // end of the current ref section, reload the storage_blob and refresh the refs
                data_position.ref_index = 0;
                data_position.refblock_index += 1;

                try fs.device.readBlock(next_block, &storage_blob);
                const refblock = bytesAsValue(RefListBlock, &storage_blob);
                refs = &refblock.refs;
                next_block = refblock.next;

                if (opt_cache) |cache| {
                    cache.putRefBlock(file, data_position.refblock_index, refs, next_block);
                }
            }
        }

        return actual_len;
    }

    const WriteAccessor = struct {
        const Slice = []const u8;
        fn accessPartial(device: BlockDevice, block_address: u32, byte_offset: usize, slice: []const u8) !void {
            var buffer_block: Block = undefined;
            try device.readBlock(block_address, &buffer_block);
            std.mem.copyForwards(u8, buffer_block[byte_offset..], slice);
            try device.writeBlock(block_address, &buffer_block);
        }
        fn accessFull(device: BlockDevice, block_address: u32, block: *const [512]u8) !void {
            try device.writeBlock(block_address, block);
        }
    };

    pub fn writeData(fs: *FileSystem, file: FileHandle, position: u64, data: []const u8, cache: ?*FileDataCache) !usize {
        return fs.accessData(file, position, WriteAccessor, data, cache);
    }

    const ReadAccessor = struct {
        const Slice = []u8;
        fn accessPartial(device: BlockDevice, block_address: u32, byte_offset: usize, slice: []u8) !void {
            var buffer_block: Block = undefined;
            try device.readBlock(block_address, &buffer_block);
            std.mem.copyForwards(u8, slice, buffer_block[byte_offset..][0..slice.len]);
        }
        fn accessFull(device: BlockDevice, block_address: u32, block: *[512]u8) !void {
            try device.readBlock(block_address, block);
        }
    };

    pub fn readData(fs: *FileSystem, file: FileHandle, position: u64, data: []u8, cache: ?*FileDataCache) !usize {
        return fs.accessData(file, position, ReadAccessor, data, cache);
    }

    pub fn createDirectory(fs: *FileSystem, dir: DirectoryHandle, name: []const u8, create_time: i128) !DirectoryHandle {
        const dir_handle = try fs.createEntryInDir(dir, name, .directory, create_time);
        // directory is already fully initialized with an empty object
        return dir_handle.toDirectoryHandle();
    }

    pub fn renameEntry(fs: *FileSystem, dir: DirectoryHandle, current_name: []const u8, new_name: []const u8) !void {
        _ = fs;
        _ = dir;
        _ = current_name;
        _ = new_name;
    }

    pub fn moveEntry(fs: *FileSystem, src_dir: DirectoryHandle, src_name: []const u8, dst_dir: DirectoryHandle, dst_name: []const u8) !void {
        _ = fs;
        _ = src_dir;
        _ = src_name;
        _ = dst_dir;
        _ = dst_name;
    }

    pub fn deleteEntry(fs: *FileSystem, dir: DirectoryHandle, name: []const u8) !void {
        _ = fs;
        _ = dir;
        _ = name;
    }

    pub fn getEntry(fs: *FileSystem, dir: DirectoryHandle, name: []const u8) !Entry {
        var iter = try fs.iterate(dir);
        while (try iter.next()) |entry| {
            if (std.mem.eql(u8, name, entry.name()))
                return entry;
        }
        return error.FileNotFound;
    }

    pub const Iterator = struct {
        device: BlockDevice,
        total_count: u64,
        ref_storage: RefListBlock,
        ref_index: u8,
        entry_index: u2 = 0,

        pub fn next(iter: *Iterator) !?Entry {
            while (true) {
                if (iter.total_count == 0)
                    return null;

                // std.debug.print("total_count = {}\n", .{iter.total_count});
                // std.debug.print("ref_index   = {}\n", .{iter.ref_index});
                // std.debug.print("entry_index = {}\n", .{iter.entry_index});
                // std.debug.print("next        = {}\n", .{iter.ref_storage.next});

                var entry_list: DirectoryDataBlock = undefined;
                try iter.device.readBlock(iter.ref_storage.refs[iter.ref_index], asBytes(&entry_list));

                const raw_entry = entry_list.entries[iter.entry_index];

                const entry = Entry{
                    .name_buffer = raw_entry.name,
                    .handle = switch (raw_entry.type) {
                        0 => .{ .directory = @as(DirectoryHandle, @enumFromInt(raw_entry.ref)) },
                        1 => .{ .file = @as(FileHandle, @enumFromInt(raw_entry.ref)) },
                        else => return error.CorruptFilesystem,
                    },
                };

                // std.debug.print("result: {}\n", .{entry});

                iter.entry_index +%= 1;
                iter.total_count -= 1;

                if (iter.total_count > 0 and iter.entry_index == 0) {
                    iter.ref_index += 1;
                    if (iter.ref_index == iter.ref_storage.refs.len) {
                        if (iter.ref_storage.next == 0)
                            return error.CorruptFilesystem;
                        try iter.device.readBlock(iter.ref_storage.next, asBytes(&iter.ref_storage));
                        iter.ref_index = 0;
                    }
                }

                if (raw_entry.ref == 0) // entry was deleted
                    continue;
                return entry;
            }
        }
    };
};

pub const Entry = struct {
    name_buffer: [120]u8,
    handle: Handle,

    pub fn name(entry: *const Entry) []const u8 {
        return std.mem.sliceTo(&entry.name_buffer, 0);
    }

    pub const Type = enum { file, directory };

    pub const Handle = union(Type) {
        file: FileHandle,
        directory: DirectoryHandle,

        pub fn object(val: Handle) ObjectHandle {
            return switch (val) {
                inline else => |x| x.object(),
            };
        }
    };
};

pub const MetaData = struct {
    create_time: i128,
    modify_time: i128,
    size: u64,
    flags: u32,
};

pub const MetaDataChangeSet = struct {
    create_time: ?i128 = null,
    modify_time: ?i128 = null,
    flags: ?u32 = null,
};

pub const FileHandle = enum(u32) {
    _,
    pub fn object(h: FileHandle) ObjectHandle {
        return @as(ObjectHandle, @enumFromInt(@intFromEnum(h)));
    }

    pub fn blockNumber(h: FileHandle) u32 {
        return @intFromEnum(h);
    }
};

pub const DirectoryHandle = enum(u32) {
    _,
    pub fn object(h: DirectoryHandle) ObjectHandle {
        return @as(ObjectHandle, @enumFromInt(@intFromEnum(h)));
    }

    pub fn blockNumber(h: DirectoryHandle) u32 {
        return @intFromEnum(h);
    }
};
pub const ObjectHandle = enum(u32) {
    _,

    pub fn toFileHandle(h: ObjectHandle) FileHandle {
        return @as(FileHandle, @enumFromInt(@intFromEnum(h)));
    }
    pub fn toDirectoryHandle(h: ObjectHandle) DirectoryHandle {
        return @as(DirectoryHandle, @enumFromInt(@intFromEnum(h)));
    }

    pub fn blockNumber(h: ObjectHandle) u32 {
        return @intFromEnum(h);
    }
};

const BitmapLocation = struct {
    block: u32,
    byte_offset: u9,
    bit_offset: u3,
};

fn blockToBitPos(block_num: usize) BitmapLocation {
    const page = 1 + (block_num / 4096);
    const bit = block_num % 4096;
    const word_index = bit / 8;
    const word_bit = bit % 8;

    return BitmapLocation{
        .block = @as(u32, @intCast(page)),
        .byte_offset = @as(u9, @intCast(word_index)),
        .bit_offset = @as(u3, @intCast(word_bit)),
    };
}

fn setBuffer(block: *Block, data: anytype) void {
    if (@sizeOf(@TypeOf(data)) != @sizeOf(Block))
        @compileError("Invalid size: " ++ @typeName(@TypeOf(data)) ++ " is not 512 byte large!");
    std.mem.copyForwards(u8, block, asConstBytes(&data));
}

pub fn format(device: BlockDevice, init_time: i128) !void {
    const block_count = device.getBlockCount();
    logger.debug("start formatting with {} blocks", .{block_count});

    if (block_count < 32) {
        return error.DeviceTooSmall;
    }

    var block: Block = undefined;

    setBuffer(&block, RootBlock{
        .size = block_count,
    });
    try device.writeBlock(0, &block);

    const bitmap_block_count = ((block_count + 4095) / 4096);

    for (1..bitmap_block_count + 2) |index| {
        @memset(&block, 0);

        if (index == 1) {
            block[0] |= 0x01; // mark "root block" as allocated
        }

        // we have to mark all bits in the bitmap *and* the root directory
        // thus, we're counting from [1;bitmap_block_count+1] inclusive.
        for (1..bitmap_block_count + 2) |block_num| {
            const pos = blockToBitPos(block_num);
            if (pos.block == index) {
                block[pos.byte_offset] |= (@as(u8, 1) << pos.bit_offset);
            }
            if (pos.block > index)
                break;
        }

        try device.writeBlock(@as(u32, @intCast(index)), &block);
    }

    setBuffer(&block, ObjectBlock{
        .size = 0, // empty directory
        .create_time = init_time,
        .modify_time = init_time,
        .flags = 0,
        .refs = std.mem.zeroes([116]u32),
        .next = 0,
    });

    try device.writeBlock(bitmap_block_count + 1, &block);
}

const RootBlock = extern struct {
    magic_identification_number: [32]u8 = magic_number,
    version: u32 = 1, // must be 1
    size: u32 align(4), // number of managed blocks including this

    padding: [472]u8 = std.mem.zeroes([472]u8), // fill up to 512
};

const ObjectBlock = extern struct {
    pub const ref_count = 116;

    size: u64 align(4), // size of this object in bytes. for directories, this means the directory contains `size/sizeof(Entry)` elements.
    create_time: i128 align(4), // stores the date when this object was created, unix timestamp in nano seconds
    modify_time: i128 align(4), // stores the date when this object was last modified, unix timestamp in nano seconds
    flags: u32, // type-dependent bit field (file: bit 0 = read only; directory: none; all other bits are reserved=0)
    refs: [ref_count]u32, // pointer to a type-dependent data block (FileDataBlock, DirectoryDataBlock)
    next: u32 align(4), // link to a RefListBlock to continue the refs listing. 0 is "end of chain"
};

const RefListBlock = extern struct {
    pub const ref_count = 127;

    refs: [ref_count]u32, // pointers to data blocks to list the entries
    next: u32 align(4), // pointer to the next RefListBlock or 0
};

const FileDataBlock = extern struct {
    @"opaque": [512]u8, // arbitrary file content, has no filesystem-defined meaning.
};

const DirectoryDataBlock = extern struct {
    entries: [4]DirectoryEntry, // two entries in the directory.
};

const DirectoryEntry = extern struct {
    type: u32, // the kind of this entry. 0 = directory, 1 = file, all other values are illegal
    ref: u32, // link to the associated ObjectBlock. if 0, the entry is deleted. this allows a panic recovery for accidentially deleted files.
    name: [120]u8, // zero-padded file name
};

comptime {
    const block_types = [_]type{
        RootBlock,
        ObjectBlock,
        RefListBlock,
        FileDataBlock,
        DirectoryDataBlock,
    };
    for (block_types) |t| {
        if (@sizeOf(t) != 512) @compileError(@typeName(t) ++ " is not 512 bytes large!");
    }
}
