const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "BlockDevice: not present - writes to LBA/COMMAND ignored" {
    var blk = emu.BlockDevice.init(false, 0);

    // Writes to LBA and COMMAND are silently ignored (no error)
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x08, .write32, 42), // LBA
        helpers.Access.init(0x0C, .write32, 1), // COMMAND
    });

    // STATUS: not present, not busy
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 0), // present=0
    });
}

test "BlockDevice: not present - buffer access returns error" {
    var blk = emu.BlockDevice.init(false, 0);

    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x100, .read8, error.Unmapped),
        helpers.Access.init(0x100, .write8, error.Unmapped),
    });
}

test "BlockDevice: present - STATUS has present bit" {
    var blk = emu.BlockDevice.init(true, 100);

    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 1), // present=1, busy=0, error=0
        helpers.Access.init(0x04, .read32, 100), // SIZE = 100 blocks
    });
}

test "BlockDevice: present - can read/write buffer when idle" {
    var blk = emu.BlockDevice.init(true, 100);

    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x100, .write8, 0xAB),
        helpers.Access.init(0x100, .read8, 0xAB),
        helpers.Access.init(0x104, .write32, 0xDEADBEEF),
        helpers.Access.init(0x104, .read32, 0xDEADBEEF),
    });
}

test "BlockDevice: read command flow" {
    var blk = emu.BlockDevice.init(true, 100);

    // Set LBA and issue read command
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x08, .write32, 42), // LBA = 42
        helpers.Access.init(0x0C, .write32, 1), // COMMAND = read
    });

    // Should be busy now
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 3), // present=1, busy=1
    });

    // Buffer inaccessible while busy
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x100, .read8, error.Unmapped),
        helpers.Access.init(0x100, .write8, error.Unmapped),
    });

    // getPendingRequest returns once
    const req = blk.getPendingRequest();
    try std.testing.expect(req != null);
    try std.testing.expectEqual(false, req.?.is_write);
    try std.testing.expectEqual(@as(u32, 42), req.?.lba);
    try std.testing.expect(blk.getPendingRequest() == null); // second call returns null

    // Host fills buffer and completes
    blk.transferBuffer()[0] = 0xAA;
    try blk.complete(true);

    // Not busy anymore, no error
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 1), // present=1, busy=0, error=0
        helpers.Access.init(0x100, .read8, 0xAA), // buffer accessible
    });
}

test "BlockDevice: complete with error sets error flag" {
    var blk = emu.BlockDevice.init(true, 100);

    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x08, .write32, 0), // LBA
        helpers.Access.init(0x0C, .write32, 1), // COMMAND = read
    });

    _ = blk.getPendingRequest();
    try blk.complete(false); // error

    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 5), // present=1, busy=0, error=1
    });

    // Buffer inaccessible when error is set
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x100, .read8, error.Unmapped),
    });

    // Clear error
    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x0C, .write32, 3), // COMMAND = clear_error
    });

    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 1), // present=1, error cleared
    });
}

test "BlockDevice: complete with no pending request returns error" {
    var blk = emu.BlockDevice.init(true, 100);
    try std.testing.expectError(error.NoPendingRequest, blk.complete(true));
}

test "BlockDevice: write command snapshots LBA" {
    var blk = emu.BlockDevice.init(true, 100);

    try helpers.testPeripheralAccess(blk.peripheral(), &.{
        helpers.Access.init(0x08, .write32, 99), // LBA = 99
        helpers.Access.init(0x0C, .write32, 2), // COMMAND = write
    });

    const req = blk.getPendingRequest();
    try std.testing.expect(req != null);
    try std.testing.expect(req.?.is_write);
    try std.testing.expectEqual(@as(u32, 99), req.?.lba);
}
