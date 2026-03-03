const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "Keyboard: push and pop key event" {
    var kbd = emu.Keyboard{};
    try std.testing.expect(kbd.pushKey(0x04, .down)); // 'a' down

    try helpers.testPeripheralAccess(kbd.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 1), // STATUS: non-empty
        helpers.Access.init(0x04, .read32, 0x80000004), // DATA: down + HID 0x04
        helpers.Access.init(0x00, .read32, 0), // STATUS: empty
        helpers.Access.init(0x04, .read32, 0), // DATA: empty returns 0
    });
}

test "Keyboard: FIFO capacity" {
    var kbd = emu.Keyboard{};
    // Fill with alternating down/up for different keys to avoid dedup
    var i: u16 = 0;
    while (i < emu.Keyboard.FIFO_SIZE) : (i += 1) {
        try std.testing.expect(kbd.pushKey(i, .down));
    }
    // 17th push: different key but FIFO full
    try std.testing.expect(!kbd.pushKey(0xFF, .down));
}

test "Keyboard: deduplication - same state discarded" {
    var kbd = emu.Keyboard{};
    try std.testing.expect(kbd.pushKey(0x04, .down));
    try std.testing.expect(kbd.pushKey(0x04, .down)); // duplicate, accepted but not enqueued

    try helpers.testPeripheralAccess(kbd.peripheral(), &.{
        helpers.Access.init(0x04, .read32, 0x80000004), // first event
        helpers.Access.init(0x00, .read32, 0), // STATUS: empty (second was deduped)
    });
}

test "Keyboard: different states enqueue separately" {
    var kbd = emu.Keyboard{};
    try std.testing.expect(kbd.pushKey(0x04, .down));
    try std.testing.expect(kbd.pushKey(0x04, .up));

    try helpers.testPeripheralAccess(kbd.peripheral(), &.{
        helpers.Access.init(0x04, .read32, 0x80000004), // down
        helpers.Access.init(0x04, .read32, 0x00000004), // up
        helpers.Access.init(0x00, .read32, 0), // empty
    });
}

test "Keyboard: writes return WriteProtected" {
    var kbd = emu.Keyboard{};

    try helpers.testPeripheralAccess(kbd.peripheral(), &.{
        helpers.Access.init(0x00, .write32, error.WriteProtected),
        helpers.Access.init(0x04, .write8, error.WriteProtected),
    });
}
