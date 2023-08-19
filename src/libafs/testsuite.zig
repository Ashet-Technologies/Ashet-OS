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
            return @as(*BD, @ptrCast(@alignCast(@alignOf(BD), ctx)));
        }

        fn getBlockCount(ctx: *anyopaque) u32 {
            return fromCtx(ctx).blocks.len;
        }
        fn writeBlock(ctx: *anyopaque, offset: u32, block: *const Block) !void {
            // std.debug.print("write block {}:\n", .{offset});
            dumpBlock(block);
            const bd = fromCtx(ctx);
            bd.blocks[offset] = block.*;
        }

        fn readBlock(ctx: *anyopaque, offset: u32, block: *Block) !void {
            // std.debug.print("read block {}\n", .{offset});
            const bd = fromCtx(ctx);
            block.* = bd.blocks[offset];
            dumpBlock(block);
        }

        fn dumpBlock(block: *const Block) void {
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
            _ = block;
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

test "iterate empty root directory" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    var iter = try fs.iterate(root);
    try std.testing.expectEqual(@as(?afs.Entry, null), try iter.next());
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

test "create single new file" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    _ = try fs.createFile(root, "system.dat", 1337);
}

test "create a lot of new files" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    var name_buf: [32]u8 = undefined;

    for (0..1024) |index| {
        const name = try std.fmt.bufPrint(&name_buf, "file-{}.dat", .{index});
        errdefer std.debug.print("Failed to create file {s}!\n", .{name});

        _ = try fs.createFile(root, name, 1337);
    }
}

test "iterate root directory with a single file" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    _ = try fs.createFile(root, "system.dat", 1337);

    var iter = try fs.iterate(root);

    const first = (try iter.next()) orelse return error.MissingEntry;

    try std.testing.expectEqualStrings("system.dat", first.name());
    try std.testing.expectEqual(afs.Entry.Type.file, first.handle);

    try std.testing.expectEqual(@as(?afs.Entry, null), try iter.next());
}

test "create duplicate file check" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    _ = try fs.createFile(root, "system.dat", 1337);
    _ = try fs.createFile(root, "magic.dat", 1337);
    try std.testing.expectError(error.FileAlreadyExists, fs.createDirectory(root, "system.dat", 1337));
    try std.testing.expectError(error.FileAlreadyExists, fs.createFile(root, "system.dat", 1337));
    try std.testing.expectError(error.FileAlreadyExists, fs.createDirectory(root, "magic.dat", 1337));
    try std.testing.expectError(error.FileAlreadyExists, fs.createFile(root, "magic.dat", 1337));
}

test "iterate root directory with several files" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    _ = try fs.createFile(root, "system.dat", 1337);
    _ = try fs.createDirectory(root, "bin", 1337);
    _ = try fs.createFile(root, "kernel.exe", 1337);

    var iter = try fs.iterate(root);

    // HACK: abuse implicit property: the order of elements will be the creation order

    {
        const entry = (try iter.next()) orelse return error.MissingEntry;
        try std.testing.expectEqualStrings("system.dat", entry.name());
        try std.testing.expectEqual(afs.Entry.Type.file, entry.handle);
    }
    {
        const entry = (try iter.next()) orelse return error.MissingEntry;
        try std.testing.expectEqualStrings("bin", entry.name());
        try std.testing.expectEqual(afs.Entry.Type.directory, entry.handle);
    }
    {
        const entry = (try iter.next()) orelse return error.MissingEntry;
        try std.testing.expectEqualStrings("kernel.exe", entry.name());
        try std.testing.expectEqual(afs.Entry.Type.file, entry.handle);
    }

    try std.testing.expectEqual(@as(?afs.Entry, null), try iter.next());
}

test "iterate over a lot of new files" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    var name_buf: [32]u8 = undefined;

    for (0..1024) |index| {
        const name = try std.fmt.bufPrint(&name_buf, "file-{}.dat", .{index});
        errdefer std.debug.print("Failed to create file {s}!\n", .{name});

        _ = try fs.createFile(root, name, 1337);
    }

    var iter = try fs.iterate(root);
    var count: usize = 0;
    while (try iter.next()) |entry| {
        try std.testing.expect(std.mem.startsWith(u8, entry.name(), "file-"));
        try std.testing.expect(std.mem.endsWith(u8, entry.name(), ".dat"));
        try std.testing.expectEqual(afs.Entry.Type.file, entry.handle);
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 1024), count);
}

test "increase file size several times" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    const file = try fs.createFile(root, "system.dat", 1337);

    try fs.resizeFile(file, 0); // NO-OP
    try fs.resizeFile(file, 100); // Allocate single block
    try fs.resizeFile(file, 512); // Still keep the single block active
    try fs.resizeFile(file, 513); // Resize to two blocks
    try fs.resizeFile(file, 117 * 512); // Resize to "all refs in ObjectBlock used"
    try fs.resizeFile(file, 117 * 512 + 1); // Resize to "all refs in ObjectBlock used" and another block
    try fs.resizeFile(file, (117 + 127) * 512); // Resize to "all refs of ObjectBlock and first RefListBlock" used
    try fs.resizeFile(file, (117 + 127) * 512 + 1); // Resize to "all refs of ObjectBlock and first RefListBlock, second RefListBlock has one entry used."
    try fs.resizeFile(file, 1 << 19); // Just resize to a realistic, but large size (512k)
}

test "write basic data (no verify)" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    const file = try fs.createFile(root, "system.dat", 1337);

    try std.testing.expectEqual(@as(usize, 0), try fs.writeData(file, 0, "Hello, World!"));

    try fs.resizeFile(file, 10);

    try std.testing.expectEqual(@as(usize, 10), try fs.writeData(file, 0, "Hello, World!"));

    try std.testing.expectEqual(@as(usize, 5), try fs.writeData(file, 5, "Hello, World!"));

    try fs.resizeFile(file, 10_000);

    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 0, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 100, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 1000, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 512, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 2048, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 10), try fs.writeData(file, 9990, "Hello, World!"));
}

fn scrambleData(buf: []u8) void {
    @memset(buf, 0xAA);
}

test "write-read basic data" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    var buffer: [32]u8 = undefined;

    const root = fs.getRootDir();

    const file = try fs.createFile(root, "system.dat", 1337);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 0), try fs.writeData(file, 0, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 0), try fs.readData(file, 0, &buffer));

    try fs.resizeFile(file, 10);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 10), try fs.writeData(file, 0, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 10), try fs.readData(file, 0, &buffer));
    try std.testing.expectEqualStrings("Hello, Wor", buffer[0..10]);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 5), try fs.writeData(file, 5, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 5), try fs.readData(file, 5, &buffer));
    try std.testing.expectEqualStrings("Hello", buffer[0..5]);

    try fs.resizeFile(file, 10_000);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 0, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.readData(file, 0, buffer[0..13]));
    try std.testing.expectEqualStrings("Hello, World!", buffer[0..13]);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 100, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.readData(file, 100, buffer[0..13]));
    try std.testing.expectEqualStrings("Hello, World!", buffer[0..13]);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 1000, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.readData(file, 1000, buffer[0..13]));
    try std.testing.expectEqualStrings("Hello, World!", buffer[0..13]);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 512, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.readData(file, 512, buffer[0..13]));
    try std.testing.expectEqualStrings("Hello, World!", buffer[0..13]);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 13), try fs.writeData(file, 2048, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 13), try fs.readData(file, 2048, buffer[0..13]));
    try std.testing.expectEqualStrings("Hello, World!", buffer[0..13]);

    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 10), try fs.writeData(file, 9990, "Hello, World!"));
    try std.testing.expectEqual(@as(usize, 10), try fs.readData(file, 9990, buffer[0..13]));
    try std.testing.expectEqualStrings("Hello, Wor", buffer[0..10]);
}

test "overwrite portions of data" {
    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    var buffer: [30]u8 = undefined;

    const root = fs.getRootDir();

    const file = try fs.createFile(root, "system.dat", 1337);

    // std.debug.print("resize...\n", .{});
    try fs.resizeFile(file, 1 << 19); // make it big enough

    // std.debug.print("write 300:\n", .{});
    try std.testing.expectEqual(@as(usize, 30), try fs.writeData(file, 300, "012345678901234567890123456789"));
    try std.testing.expectEqual(@as(usize, 10), try fs.writeData(file, 310, "abcdefghij"));

    // std.debug.print("write (1 << 16):\n", .{});
    try std.testing.expectEqual(@as(usize, 30), try fs.writeData(file, (1 << 16) + 300, "012345678901234567890123456789"));
    try std.testing.expectEqual(@as(usize, 10), try fs.writeData(file, (1 << 16) + 310, "abcdefghij"));

    // std.debug.print("write (1 << 18):\n", .{});
    try std.testing.expectEqual(@as(usize, 30), try fs.writeData(file, (1 << 18) + 300, "012345678901234567890123456789"));
    try std.testing.expectEqual(@as(usize, 10), try fs.writeData(file, (1 << 18) + 310, "abcdefghij"));

    // std.debug.print("verify 300:\n", .{});
    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 30), try fs.readData(file, 300, buffer[0..30]));
    try std.testing.expectEqualStrings("0123456789abcdefghij0123456789", buffer[0..30]);

    // std.debug.print("verify (1 << 16):\n", .{});
    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 30), try fs.readData(file, (1 << 16) + 300, buffer[0..30]));
    try std.testing.expectEqualStrings("0123456789abcdefghij0123456789", buffer[0..30]);

    // std.debug.print("verify (1 << 18):\n", .{});
    scrambleData(&buffer);
    try std.testing.expectEqual(@as(usize, 30), try fs.readData(file, (1 << 18) + 300, buffer[0..30]));
    try std.testing.expectEqualStrings("0123456789abcdefghij0123456789", buffer[0..30]);
}

test "huge sequential data" {
    const large_buffer = try std.testing.allocator.alloc(u8, 1 << 19);
    defer std.testing.allocator.free(large_buffer);

    const validate_buffer = try std.testing.allocator.alloc(u8, large_buffer.len);
    defer std.testing.allocator.free(validate_buffer);

    var rng = std.rand.DefaultPrng.init(1337);
    rng.random().bytes(large_buffer);

    var bd = makeEmptyFs();
    var fs = try FileSystem.init(bd.interface());

    const root = fs.getRootDir();

    const file = try fs.createFile(root, "system.dat", 1337);

    try fs.resizeFile(file, large_buffer.len);
    try std.testing.expectEqual(@as(usize, large_buffer.len), try fs.writeData(file, 0, large_buffer));

    scrambleData(validate_buffer);
    try std.testing.expectEqual(@as(usize, validate_buffer.len), try fs.readData(file, 0, validate_buffer));
    try std.testing.expectEqualSlices(u8, large_buffer, validate_buffer);
}
