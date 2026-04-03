const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "DebugOutput: write byte" {
    var buf: [16]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var dbg = emu.DebugOutput.init(&writer);

    try helpers.testPeripheralAccess(dbg.peripheral(), &.{
        helpers.Access.init(0x00, .write8, 'A'),
        helpers.Access.init(0x00, .write8, 'B'),
    });

    try std.testing.expectEqualStrings("AB", writer.buffered());
}

test "DebugOutput: reads return Unmapped" {
    var buf: [16]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var dbg = emu.DebugOutput.init(&writer);

    try helpers.testPeripheralAccess(dbg.peripheral(), &.{
        helpers.Access.init(0x00, .read8, error.Unmapped),
        helpers.Access.init(0x00, .read16, error.Unmapped),
        helpers.Access.init(0x00, .read32, error.Unmapped),
    });
}

test "DebugOutput: non-u8 writes at offset 0 return InvalidSize" {
    var buf: [16]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var dbg = emu.DebugOutput.init(&writer);

    try helpers.testPeripheralAccess(dbg.peripheral(), &.{
        helpers.Access.init(0x00, .write16, error.InvalidSize),
        helpers.Access.init(0x00, .write32, error.InvalidSize),
    });
}

test "DebugOutput: write at non-zero offset returns Unmapped" {
    var buf: [16]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    var dbg = emu.DebugOutput.init(&writer);

    try helpers.testPeripheralAccess(dbg.peripheral(), &.{
        helpers.Access.init(0x01, .write8, error.Unmapped),
        helpers.Access.init(0x10, .write16, error.Unmapped),
    });
}
