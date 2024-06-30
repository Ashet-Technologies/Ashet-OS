const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("ashet-std", .{
        .root_source_file = b.path("src/std.zig"),
    });
}
