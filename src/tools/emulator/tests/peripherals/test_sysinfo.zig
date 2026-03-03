const std = @import("std");
const emu = @import("emulator");
const helpers = @import("../test_helpers.zig");

test "SystemInfo: read RAM_SIZE" {
    var sysinfo = emu.SystemInfo.init(0x1000);

    try helpers.testPeripheralAccess(sysinfo.peripheral(), &.{
        helpers.Access.init(0x00, .read32, 0x1000),
    });
}

test "SystemInfo: writes return WriteProtected" {
    var sysinfo = emu.SystemInfo.init(0x1000);

    try helpers.testPeripheralAccess(sysinfo.peripheral(), &.{
        helpers.Access.init(0x00, .write8, error.WriteProtected),
        helpers.Access.init(0x00, .write16, error.WriteProtected),
        helpers.Access.init(0x00, .write32, error.WriteProtected),
    });
}

test "SystemInfo: non-u32 reads return InvalidSize" {
    var sysinfo = emu.SystemInfo.init(0x1000);

    try helpers.testPeripheralAccess(sysinfo.peripheral(), &.{
        helpers.Access.init(0x00, .read8, error.InvalidSize),
        helpers.Access.init(0x00, .read16, error.InvalidSize),
    });
}

test "SystemInfo: read at invalid offset returns Unmapped" {
    var sysinfo = emu.SystemInfo.init(0x1000);

    try helpers.testPeripheralAccess(sysinfo.peripheral(), &.{
        helpers.Access.init(0x04, .read32, error.Unmapped),
    });
}
