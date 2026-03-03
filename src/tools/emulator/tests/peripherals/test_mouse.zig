const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "Mouse: setState and read registers" {
    var mouse = emu.Mouse{};
    mouse.setState(100, 200, 0x01);

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 100),
        helpers.Access.init(0x04, .read32, 200),
        helpers.Access.init(0x08, .read32, 0x01),
    });
}

test "Mouse: negative coordinates clamped to 0" {
    var mouse = emu.Mouse{};
    mouse.setState(-5, -10, 0);

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 0),
        helpers.Access.init(0x04, .read32, 0),
    });
}

test "Mouse: coordinates clamped to screen bounds" {
    var mouse = emu.Mouse{};
    mouse.setState(1000, 500, 0);

    try helpers.testPeripheralAccess(mouse.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 639),
        helpers.Access.init(0x04, .read32, 399),
    });
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
