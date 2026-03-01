const std = @import("std");
const emu = @import("emulator");

test {
    var system: emu.System = .{
        .rom = &.{},
        .ram = &.{},
    };

    try system.step(10);
}
