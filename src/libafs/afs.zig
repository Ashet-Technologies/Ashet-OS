//!
//! Ashet File System
//!

const std = @import("std");

pub const Block = [512]u8;

pub const BlockDevice = struct {
    pub const IoError = error{
        WriteProtected,
        OperationTimeout,
    };

    pub const CompletedCallback = fn (*anyopaque, ?IoError) void;

    pub const VTable = struct {
        getBlockCountFn: *const fn (*anyopaque) u32,
        beginWriteBlockFn: *const fn (*anyopaque, offset: u32, block: *const Block, callback: *const CompletedCallback, callback_ctx: *anyopaque) void,
        beginReadBlockFn: *const fn (*anyopaque, offset: u32, block: *Block, callback: *const CompletedCallback, callback_ctx: *anyopaque) void,
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
    pub fn beginWriteBlock(bd: BlockDevice, offset: u32, block: *const Block, callback: *const CompletedCallback, callback_ctx: *anyopaque) void {
        bd.vtable.beginWriteBlockFn(bd.object, offset, block, callback, callback_ctx);
    }

    /// Starts a read operation on the underlying block device. When done, will call `callback` with `callback_ctx` as the first argument, and
    /// an optional error state.
    /// NOTE: When the block device is non-blocking, `callback` is already invoked in this function! Design your code in a way that this won't
    /// affect your control flow.
    pub fn beginReadBlock(bd: BlockDevice, offset: u32, block: *Block, callback: *const CompletedCallback, callback_ctx: *anyopaque) void {
        bd.vtable.beginReadBlockFn(bd.object, offset, block, callback, callback_ctx);
    }
};

pub const Formatter = struct {
    const Error = BlockDevice.IoError;

    buffer: Block,
    completed: bool = false,
    async_error: ?Error = null,

    fn setBuffer(fmt: *Formatter, data: anytype) void {
        if (@sizeOf(@TypeOf(data)) != @sizeOf(Block))
            @compileError("");
        std.mem.copy(u8, &fmt.buffer, &std.mem.asBytes(&data));
    }

    pub fn startFormat(fmt: *Formatter, bd: BlockDevice) Formatter {
        const len = bd.getBlockCount();

        _ = len;

        bd.beginWriteBlock(0, &fmt.buffer, formatBitmap, fmt);
    }

    pub fn isCompleted(fmt: *const Formatter) bool {
        return fmt.completed;
    }

    pub fn endFormat(fmt: *Formatter) Error!void {
        if (fmt.async_error) |err|
            return err;
    }

    fn fromCtx(ctx: *anyopaque, err: ?Error) ?*Formatter {
        const fmt = @ptrCast(*Formatter, @alignCast(@alignOf(Formatter), ctx));
        if (err) |e| {
            fmt.async_error = e;
            fmt.completed = true;
            return null;
        }
        return fmt;
    }

    // format sequence

    fn formatBitmap(ctx: *anyopaque, err: ?Error) void {
        const fmt = fromCtx(ctx, err) orelse return;

        _ = fmt;
    }
};

const RootBlock = extern struct {
    magic_identification_number: [32]u8 = .{
        0x2c, 0xcd, 0xbe, 0xe2, 0xca, 0xd9, 0x99, 0xa7, 0x65, 0xe7, 0x57, 0x31, 0x6b, 0x1c, 0xe1, 0x2b,
        0xb5, 0xac, 0x9d, 0x13, 0x76, 0xa4, 0x54, 0x69, 0xfc, 0x57, 0x29, 0xa8, 0xc9, 0x3b, 0xef, 0x62,
    },
    version: u32 = 1, // must be 1
    size: u32, // number of managed blocks including this

    padding: [472]u8, // fill up to 512
};

const ObjectBlock = extern struct {
    size: u32, // size of this object in bytes. for directories, this means the directory contains `size/sizeof(Entry)` elements.
    create_time: i128 align(4), // stores the date when this object was created, unix timestamp in nano seconds
    modify_time: i128 align(4), // stores the date when this object was last modified, unix timestamp in nano seconds
    flags: u32, // type-dependent bit field (file: bit 0 = read only; directory: none; all other bits are reserved=0)
    refs: [117]u32, // pointer to a type-dependent data block (FileDataBlock, DirectoryDataBlock)
    next: u32, // link to a RefListBlock to continue the refs listing. 0 is "end of chain"
};

const RefListBlock = extern struct {
    refs: [127]u32, // pointers to data blocks to list the entries
    next: u32, // pointer to the next RefListBlock or 0
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
