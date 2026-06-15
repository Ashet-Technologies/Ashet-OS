const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "Timer: read MTIME_LO latches HI" {
    var timer = emu.Timer{};
    timer.setTime(0x0000_0002_0000_0001, 0);

    // Reading LO should return low word and latch high word
    try helpers.testPeripheralAccess(timer.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 0x0000_0001), // MTIME_LO
        helpers.Access.init(0x04, .read32, 0x0000_0002), // MTIME_HI (latched)
    });
}

test "Timer: read RTC_LO latches HI" {
    var timer = emu.Timer{};
    timer.setTime(0, 0x0000_0003_0000_0004);

    try helpers.testPeripheralAccess(timer.peripheral(), &.{
        helpers.Access.init(0x10, .read32, 0x0000_0004), // RTC_LO
        helpers.Access.init(0x14, .read32, 0x0000_0003), // RTC_HI (latched)
    });
}

test "Timer: setTime updates values" {
    var timer = emu.Timer{};
    timer.setTime(100, 200);

    try helpers.testPeripheralAccess(timer.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 100),
    });

    timer.setTime(999, 888);

    try helpers.testPeripheralAccess(timer.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 999),
    });
}

test "Timer: writes return WriteProtected" {
    var timer = emu.Timer{};

    try helpers.testPeripheralAccess(timer.peripheral(), &.{
        helpers.Access.init(0x00, .write32, error.WriteProtected),
        helpers.Access.init(0x04, .write8, error.WriteProtected),
    });
}

test "Timer: non-u32 reads return InvalidSize" {
    var timer = emu.Timer{};

    try helpers.testPeripheralAccess(timer.peripheral(), &.{
        helpers.Access.init(0x00, .read8, error.InvalidSize),
        helpers.Access.init(0x00, .read16, error.InvalidSize),
    });
}
