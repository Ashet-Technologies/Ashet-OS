const std = @import("std");

const ports = @import("src/platforms.zig");

pub const Platform = ports.Platform;

pub fn build(b: *std.Build) void {
    _ = b.addModule("ashet-abi", .{
        .root_source_file = b.path("abi.zig"),
    });
}
