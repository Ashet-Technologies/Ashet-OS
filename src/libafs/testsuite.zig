const std = @import("std");
const afs = @import("afs.zig");

const block_size = 512; // regular block size

const FileSystem = afs.FileSystem;

const Block = [block_size]u8;

pub fn BlockDevice(comptime block_count: u32) type {
    return struct {
        const BD = @This();

        blocks: [block_count]Block = undefined,

        pub fn interface(bd: *BD) afs.BlockDevice {
            return afs.BlockDevice{
                .object = bd,
                .vtable = &vtable,
            };
        }

        fn fromCtx(ctx: *anyopaque) *BD {
            return @ptrCast(*BD, @alignCast(@alignOf(BD), ctx));
        }

        fn getBlockCount(ctx: *anyopaque) u64 {
            return fromCtx(ctx).blocks.len;
        }
        fn writeBlock(ctx: *anyopaque, offset: u64, block: *const Block) !void {
            std.debug.print("write block {}:\n", .{offset});

            // const rowlen = 16;
            // for (@bitCast([512 / rowlen][rowlen]u8, block.*), 0..) |row, i| {
            //     std.debug.print("{X:0>3}:", .{rowlen * i});
            //     for (row, 0..) |c, j| {
            //         if ((j % 4) == 0 and j != 0)
            //             std.debug.print(" ", .{});
            //         std.debug.print(" {X:0>2}", .{c});
            //     }
            //     std.debug.print(" |", .{});
            //     for (row) |c| {
            //         std.debug.print("{c}", .{if (std.ascii.isPrint(c)) c else '.'});
            //     }
            //     std.debug.print("|\n", .{});
            // }

            const bd = fromCtx(ctx);
            bd.blocks[offset] = block.*;
        }

        fn readBlock(ctx: *anyopaque, offset: u64, block: *Block) !void {
            std.debug.print("read block {}\n", .{offset});
            const bd = fromCtx(ctx);
            block.* = bd.blocks[offset];
        }

        const vtable = afs.BlockDevice.VTable{
            .getBlockCountFn = getBlockCount,
            .writeBlockFn = writeBlock,
            .readBlockFn = readBlock,
        };
    };
}

fn makeEmptyFs() BlockDevice(2048) {
    var blockdev = BlockDevice(2048){};
    {
        afs.format(blockdev.interface(), 1337) catch unreachable;
    }
    return blockdev;
}

test "format smol file system" {
    var blockdev = BlockDevice(2048){};

    const create_time = std.time.nanoTimestamp();

    try afs.format(blockdev.interface(), create_time);

    try std.testing.expectEqualSlices(
        u8,
        &afs.magic_number,
        blockdev.blocks[0][0..32],
    );
    try std.testing.expectEqual(@as(u32, 1), std.mem.readIntLittle(u32, blockdev.blocks[0][32..36]));
    try std.testing.expectEqual(@as(u64, blockdev.blocks.len), std.mem.readIntLittle(u64, blockdev.blocks[0][36..44]));

    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        blockdev.blocks[1][0..8],
    );

    for (blockdev.blocks[1][8..]) |item| {
        try std.testing.expectEqual(@as(u8, 0x00), item);
    }

    {
        const block = blockdev.blocks[2];

        try std.testing.expectEqual(@as(u64, 0), std.mem.readIntLittle(u64, block[0..8])); // empty size
        try std.testing.expectEqual(@as(i128, create_time), std.mem.readIntLittle(i128, block[8..24])); // same time stamp
        try std.testing.expectEqual(@as(i128, create_time), std.mem.readIntLittle(i128, block[24..40])); // same time stamp
        try std.testing.expectEqual(@as(u32, 0), std.mem.readIntLittle(u32, block[508..512])); // empty size
    }
}

test "init fs driver" {
    var bd = makeEmptyFs();

    var fs = try FileSystem.init(bd.interface());

    try std.testing.expectEqual(@as(u64, bd.blocks.len), fs.size);
    try std.testing.expectEqual(@as(u32, 1), fs.version);
}

test "iterate root directory" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    var iter = try fs.iterate(root);
    while (try iter.next()) |entry| {
        std.debug.print("- {}\n", .{entry});
    }
}

test "read metadata" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    var meta = try fs.readMetaData(root.object());
    try std.testing.expectEqual(@as(i128, 1337), meta.create_time);
    try std.testing.expectEqual(@as(i128, 1337), meta.modify_time);
    try std.testing.expectEqual(@as(u64, 0), meta.size);
    try std.testing.expectEqual(@as(u32, 0), meta.flags);
}

test "modify metadata" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    try fs.updateMetaData(root.object(), .{});
    {
        var meta = try fs.readMetaData(root.object());
        try std.testing.expectEqual(@as(i128, 1337), meta.create_time);
        try std.testing.expectEqual(@as(i128, 1337), meta.modify_time);
        try std.testing.expectEqual(@as(u64, 0), meta.size);
        try std.testing.expectEqual(@as(u32, 0), meta.flags);
    }

    try fs.updateMetaData(root.object(), .{ .create_time = 424242 });
    {
        var meta = try fs.readMetaData(root.object());
        try std.testing.expectEqual(@as(i128, 424242), meta.create_time);
        try std.testing.expectEqual(@as(i128, 1337), meta.modify_time);
        try std.testing.expectEqual(@as(u64, 0), meta.size);
        try std.testing.expectEqual(@as(u32, 0), meta.flags);
    }

    try fs.updateMetaData(root.object(), .{ .modify_time = 112233 });
    {
        var meta = try fs.readMetaData(root.object());
        try std.testing.expectEqual(@as(i128, 424242), meta.create_time);
        try std.testing.expectEqual(@as(i128, 112233), meta.modify_time);
        try std.testing.expectEqual(@as(u64, 0), meta.size);
        try std.testing.expectEqual(@as(u32, 0), meta.flags);
    }

    try fs.updateMetaData(root.object(), .{ .flags = 0xBEEFBABE });
    {
        var meta = try fs.readMetaData(root.object());
        try std.testing.expectEqual(@as(i128, 424242), meta.create_time);
        try std.testing.expectEqual(@as(i128, 112233), meta.modify_time);
        try std.testing.expectEqual(@as(u64, 0), meta.size);
        try std.testing.expectEqual(@as(u32, 0xBEEFBABE), meta.flags);
    }

    try fs.updateMetaData(root.object(), .{
        .create_time = 100,
        .modify_time = -10,
        .flags = 0xAABBCCDD,
    });
    {
        var meta = try fs.readMetaData(root.object());
        try std.testing.expectEqual(@as(i128, 100), meta.create_time);
        try std.testing.expectEqual(@as(i128, -10), meta.modify_time);
        try std.testing.expectEqual(@as(u64, 0), meta.size);
        try std.testing.expectEqual(@as(u32, 0xAABBCCDD), meta.flags);
    }
}
