//!
//! Ashet File System
//!

const std = @import("std");
const logger = std.log.scoped(.ashet_fs);

const asBytes = std.mem.asBytes;

pub const magic_number: [32]u8 = .{
    0x2c, 0xcd, 0xbe, 0xe2, 0xca, 0xd9, 0x99, 0xa7, 0x65, 0xe7, 0x57, 0x31, 0x6b, 0x1c, 0xe1, 0x2b,
    0xb5, 0xac, 0x9d, 0x13, 0x76, 0xa4, 0x54, 0x69, 0xfc, 0x57, 0x29, 0xa8, 0xc9, 0x3b, 0xef, 0x62,
};

pub const Block = [512]u8;

pub const BlockDevice = struct {
    pub const IoError = error{
        WriteProtected,
        OperationTimeout,
    };

    pub const CompletedCallback = fn (*anyopaque, ?IoError) void;

    pub const VTable = struct {
        getBlockCountFn: *const fn (*anyopaque) u64,
        writeBlockFn: *const fn (*anyopaque, offset: u64, block: *const Block) IoError!void,
        readBlockFn: *const fn (*anyopaque, offset: u64, block: *Block) IoError!void,
    };

    object: *anyopaque,
    vtable: *const VTable,

    /// Returns the number of blocks in this block device.
    /// Support a maximum of 2 TB storage.
    pub fn getBlockCount(bd: BlockDevice) u64 {
        return bd.vtable.getBlockCountFn(bd.object);
    }

    /// Starts a write operation on the underlying block device. When done, will call `callback` with `callback_ctx` as the first argument, and
    /// an optional error state.
    /// NOTE: When the block device is non-blocking, `callback` is already invoked in this function! Design your code in a way that this won't
    /// affect your control flow.
    pub fn writeBlock(bd: BlockDevice, offset: u64, block: *const Block) IoError!void {
        try bd.vtable.writeBlockFn(bd.object, offset, block);
    }

    /// Starts a read operation on the underlying block device. When done, will call `callback` with `callback_ctx` as the first argument, and
    /// an optional error state.
    /// NOTE: When the block device is non-blocking, `callback` is already invoked in this function! Design your code in a way that this won't
    /// affect your control flow.
    pub fn readBlock(bd: BlockDevice, offset: u64, block: *Block) IoError!void {
        try bd.vtable.readBlockFn(bd.object, offset, block);
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
        fs.root_directory = @intToEnum(DirectoryHandle, bitmap_block_count + 1);

        return fs;
    }

    pub fn getRootDir(fs: FileSystem) DirectoryHandle {
        return fs.root_directory;
    }

    pub fn iterate(fs: *FileSystem, dir: DirectoryHandle) !Iterator {
        var iter = Iterator{
            .device = fs.device,
            .current_index = 0,
            .total_count = 0,
            .reflist = undefined,
        };

        try fs.device.readBlock(dir.blockNumber(), asBytes(&iter.reflist));

        const blocklist = @ptrCast(*align(4) ObjectBlock, &iter.reflist);

        // off by the initial offset as we alias the ObjectBlock into a RefListBlock,
        // using the equivalent part of the refs array.
        iter.current_index = iter.reflist.refs.len - blocklist.refs.len;
        iter.total_count = iter.current_index + blocklist.size / @sizeOf(Entry);

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

        try fs.device.writeBlock(object.blockNumber(), asBytes(&block));
    }

    pub fn createFile(fs: *FileSystem, dir: DirectoryHandle, name: []const u8) !FileHandle {
        _ = fs;
        _ = dir;
        _ = name;
    }
    pub fn resizeFile(fs: *FileSystem, file: FileHandle, new_size: u64) !void {
        _ = fs;
        _ = file;
        _ = new_size;
    }
    pub fn writeData(fs: *FileSystem, file: FileHandle, offset: u64, data: []const u8) !usize {
        _ = fs;
        _ = file;
        _ = offset;
        _ = data;
    }
    pub fn readData(fs: *FileSystem, file: FileHandle, offset: u64, data: []u8) !usize {
        _ = fs;
        _ = file;
        _ = offset;
        _ = data;
    }
    pub fn createDirectory(fs: *FileSystem, dir: DirectoryHandle, name: []const u8) !DirectoryHandle {
        _ = fs;
        _ = dir;
        _ = name;
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

    pub const Iterator = struct {
        device: BlockDevice,
        current_index: u64,
        total_count: u64,
        reflist: RefListBlock,

        pub fn next(iter: *Iterator) !?Entry {
            _ = iter;
            return null;
        }
    };
};

pub const Entry = struct {
    name_buffer: [120]u8,
    handle: union(enum) {
        file: FileHandle,
        directory: DirectoryHandle,
    },
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

pub const FileHandle = enum(u64) {
    _,
    pub fn object(h: FileHandle) ObjectHandle {
        return @intToEnum(ObjectHandle, @enumToInt(h));
    }

    pub fn blockNumber(h: FileHandle) u64 {
        return @enumToInt(h);
    }
};

pub const DirectoryHandle = enum(u64) {
    _,
    pub fn object(h: DirectoryHandle) ObjectHandle {
        return @intToEnum(ObjectHandle, @enumToInt(h));
    }

    pub fn blockNumber(h: DirectoryHandle) u64 {
        return @enumToInt(h);
    }
};
pub const ObjectHandle = enum(u64) {
    _,
    pub fn blockNumber(h: ObjectHandle) u64 {
        return @enumToInt(h);
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
        .block = @intCast(u32, page),
        .byte_offset = @intCast(u9, word_index),
        .bit_offset = @intCast(u3, word_bit),
    };
}

fn setBuffer(block: *Block, data: anytype) void {
    if (@sizeOf(@TypeOf(data)) != @sizeOf(Block))
        @compileError("Invalid size: " ++ @typeName(@TypeOf(data)) ++ " is not 512 byte large!");
    std.mem.copy(u8, block, asBytes(&data));
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
        std.mem.set(u8, &block, 0);

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

        try device.writeBlock(index, &block);
    }

    setBuffer(&block, ObjectBlock{
        .size = 0, // empty directory
        .create_time = init_time,
        .modify_time = init_time,
        .flags = 0,
        .refs = std.mem.zeroes([115]u32),
        .next = 0,
    });

    try device.writeBlock(bitmap_block_count + 1, &block);
}

const RootBlock = extern struct {
    magic_identification_number: [32]u8 = magic_number,
    version: u32 = 1, // must be 1
    size: u64 align(4), // number of managed blocks including this

    padding: [468]u8 = std.mem.zeroes([468]u8), // fill up to 512
};

const ObjectBlock = extern struct {
    size: u64 align(4), // size of this object in bytes. for directories, this means the directory contains `size/sizeof(Entry)` elements.
    create_time: i128 align(4), // stores the date when this object was created, unix timestamp in nano seconds
    modify_time: i128 align(4), // stores the date when this object was last modified, unix timestamp in nano seconds
    flags: u32, // type-dependent bit field (file: bit 0 = read only; directory: none; all other bits are reserved=0)
    refs: [115]u32, // pointer to a type-dependent data block (FileDataBlock, DirectoryDataBlock)
    next: u64 align(4), // link to a RefListBlock to continue the refs listing. 0 is "end of chain"
};

const RefListBlock = extern struct {
    refs: [126]u32, // pointers to data blocks to list the entries
    next: u64 align(4), // pointer to the next RefListBlock or 0
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
