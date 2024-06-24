const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("virtio", .{
        .root_source_file = b.path("src/virtio.zig"),
    });
}
