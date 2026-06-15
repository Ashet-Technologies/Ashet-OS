const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "Framebuffer: write and read back u8" {
    var fb = emu.Framebuffer{};

    try helpers.testPeripheralAccess(fb.peripheral(), &.{
        helpers.Access.init(0, .write8, 0xAB),
        helpers.Access.init(0, .read8, 0xAB),
    });
}

test "Framebuffer: write and read back u32" {
    var fb = emu.Framebuffer{};

    try helpers.testPeripheralAccess(fb.peripheral(), &.{
        helpers.Access.init(100, .write32, 0xDEADBEEF),
        helpers.Access.init(100, .read32, 0xDEADBEEF),
    });
}

test "Framebuffer: access at boundary returns Unmapped" {
    var fb = emu.Framebuffer{};

    try helpers.testPeripheralAccess(fb.peripheral(), &.{
        // Last valid byte
        helpers.Access.init(255_999, .write8, 0xFF),
        helpers.Access.init(255_999, .read8, 0xFF),
        // First invalid byte
        helpers.Access.init(256_000, .write8, error.Unmapped),
        helpers.Access.init(256_000, .read8, error.Unmapped),
    });
}

test "Framebuffer: host pixels reflect bus writes" {
    var fb = emu.Framebuffer{};

    try helpers.testPeripheralAccess(fb.peripheral(), &.{
        helpers.Access.init(42, .write8, 0x77),
    });

    try std.testing.expectEqual(@as(u8, 0x77), fb.pixels()[42]);
}
