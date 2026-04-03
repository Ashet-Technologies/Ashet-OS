const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "VideoControl: write non-zero enables flush" {
    var vctrl = emu.VideoControl{};
    try std.testing.expect(!vctrl.isFlushRequested());

    try helpers.testPeripheralAccess(vctrl.peripheral(), &.{
        helpers.Access.init(0x00, .write32, 1),
    });

    try std.testing.expect(vctrl.isFlushRequested());
}

test "VideoControl: write zero disables flush" {
    var vctrl = emu.VideoControl{};

    try helpers.testPeripheralAccess(vctrl.peripheral(), &.{
        helpers.Access.init(0x00, .write32, 1),
        helpers.Access.init(0x00, .write32, 0),
    });

    try std.testing.expect(!vctrl.isFlushRequested());
}

test "VideoControl: ackFlush clears flag" {
    var vctrl = emu.VideoControl{};

    try helpers.testPeripheralAccess(vctrl.peripheral(), &.{
        helpers.Access.init(0x00, .write32, 1),
    });

    try std.testing.expect(vctrl.isFlushRequested());
    vctrl.ackFlush();
    try std.testing.expect(!vctrl.isFlushRequested());
}

test "VideoControl: reads return Unmapped" {
    var vctrl = emu.VideoControl{};

    try helpers.testPeripheralAccess(vctrl.peripheral(), &.{
        helpers.Access.init(0x00, .read8, error.Unmapped),
        helpers.Access.init(0x00, .read16, error.Unmapped),
        helpers.Access.init(0x00, .read32, error.Unmapped),
    });
}

test "VideoControl: non-u32 write at offset 0 returns InvalidSize" {
    var vctrl = emu.VideoControl{};

    try helpers.testPeripheralAccess(vctrl.peripheral(), &.{
        helpers.Access.init(0x00, .write8, error.InvalidSize),
        helpers.Access.init(0x00, .write16, error.InvalidSize),
    });
}

test "VideoControl: write at non-zero offset returns Unmapped" {
    var vctrl = emu.VideoControl{};

    try helpers.testPeripheralAccess(vctrl.peripheral(), &.{
        helpers.Access.init(0x04, .write32, error.Unmapped),
    });
}
