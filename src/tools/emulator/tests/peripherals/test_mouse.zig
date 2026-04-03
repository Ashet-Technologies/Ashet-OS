const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "Mouse: push and pop pointing event" {
    var mouse = emu.Mouse{};
    try std.testing.expect(mouse.pushPointing(100, 200));

    // Event type 0b00 in bits [31:30], X=100 in bits [23:12], Y=200 in bits [11:0]
    const expected: u32 = (@as(u32, 100) << 12) | @as(u32, 200);

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 1), // STATUS: non-empty
        helpers.Access.init(0x04, .read32, expected),
        helpers.Access.init(0x00, .read32, 0), // STATUS: empty
        helpers.Access.init(0x04, .read32, 0), // DATA: empty returns 0
    });
}

test "Mouse: coordinates clamped to u12 max" {
    var mouse = emu.Mouse{};
    try std.testing.expect(mouse.pushPointing(5000, 5000));

    const expected: u32 = (@as(u32, 4095) << 12) | @as(u32, 4095);

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x04, .read32, expected),
    });
}

test "Mouse: negative coordinates clamped to 0" {
    var mouse = emu.Mouse{};
    try std.testing.expect(mouse.pushPointing(-5, -10));

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x04, .read32, 0), // both X and Y are 0
    });
}

test "Mouse: button down and up events" {
    var mouse = emu.Mouse{};
    try std.testing.expect(mouse.pushButtonDown(.left));
    try std.testing.expect(mouse.pushButtonUp(.left));

    // button_down = 0b01 << 30, button ID = 0 (left)
    const down_expected: u32 = @as(u32, 0b01) << 30 | 0;
    // button_up = 0b10 << 30, button ID = 0 (left)
    const up_expected: u32 = @as(u32, 0b10) << 30 | 0;

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x04, .read32, down_expected),
        helpers.Access.init(0x04, .read32, up_expected),
        helpers.Access.init(0x00, .read32, 0), // empty
    });
}

test "Mouse: different buttons" {
    var mouse = emu.Mouse{};
    try std.testing.expect(mouse.pushButtonDown(.right));
    try std.testing.expect(mouse.pushButtonDown(.middle));

    const right_expected: u32 = @as(u32, 0b01) << 30 | 1;
    const middle_expected: u32 = @as(u32, 0b01) << 30 | 2;

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x04, .read32, right_expected),
        helpers.Access.init(0x04, .read32, middle_expected),
    });
}

test "Mouse: deduplication of identical events" {
    var mouse = emu.Mouse{};
    try std.testing.expect(mouse.pushPointing(50, 60));
    try std.testing.expect(mouse.pushPointing(50, 60)); // duplicate, accepted but not enqueued

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x04, .read32, (@as(u32, 50) << 12) | 60),
        helpers.Access.init(0x00, .read32, 0), // only one event
    });
}

test "Mouse: FIFO capacity" {
    var mouse = emu.Mouse{};
    // Fill with unique pointing events
    var i: u12 = 0;
    while (i < emu.Mouse.FIFO_SIZE) : (i += 1) {
        try std.testing.expect(mouse.pushPointing(i, 0));
    }
    // Next push should fail
    try std.testing.expect(!mouse.pushPointing(4095, 4095));
}

test "Mouse: writes return WriteProtected" {
    var mouse = emu.Mouse{};

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x00, .write32, error.WriteProtected),
        helpers.Access.init(0x04, .write8, error.WriteProtected),
    });
}

test "Mouse: non-u32 reads return InvalidSize" {
    var mouse = emu.Mouse{};

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x00, .read8, error.InvalidSize),
        helpers.Access.init(0x00, .read16, error.InvalidSize),
    });
}
