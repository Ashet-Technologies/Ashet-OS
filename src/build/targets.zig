const std = @import("std");

const kernel_targets = @import("../kernel/port/targets.zig");

pub fn getPlatformSpec(platform: Platform) *const PlatformSpec {
    return switch (platform) {
        .hosted => comptime &PlatformSpec{
            .source_file = "src/kernel/port/platform/hosted.zig",
        },
    };
}
