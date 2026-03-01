const std = @import("std");

/// A fully emulated system.
pub const System = struct {
    rom: []align(4) const u8,
    ram: []align(4) u8,

    pub fn step(system: *System, steps: usize) !void {
        //
        _ = system;
        _ = steps;
    }
};
