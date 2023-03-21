const std = @import("std");
const afs = @import("afs.zig");

const block_size = 512; // regular block size
const block_count = 2048; // 1 MB

const Block = [block_size]u8;

const BlockDevice = struct {
    blocks: [block_count]Block = undefined,
};

test {
    _ = afs;
    // var blockdev = BlockDevice{};

    // afs.format(blockdev.interface());
}
