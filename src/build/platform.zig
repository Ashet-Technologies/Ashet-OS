const std = @import("std");
const foundation_libc = @import("../../vendor/foundation-libc/build.zig");
const ashet_lwip = @import("lwip.zig");

const build_targets = @import("targets.zig");

pub fn PlatformMap(comptime T: type) type {
    return std.enums.EnumMap(build_targets.Platform, T);
}

pub const PlatformData = struct {
    libc: PlatformMap(*std.Build.CompileStep) = .{},
    lwip: PlatformMap(*std.Build.CompileStep) = .{},
    modules: PlatformMap(*std.Build.Module) = .{},
};

pub fn init(b: *std.Build) PlatformData {
     const foundation_dep = b.anonymousDependency("vendor/foundation-libc", foundation_libc, .{});

    var data = PlatformData{};

    for (std.enums.values(build_targets.Platform)) |platform| {
        const platform_spec = build_targets.getPlatformSpec(platform);

        data.libc.put(platform, foundation_libc.createLibrary(
            foundation_dep.builder,
            platform_spec.target,
            .ReleaseSafe,
        ));

        data.modules.put(platform, b.createModule(.{
            .source_file = .{ .path = platform_spec.source_file },
        }));

        {
            const lwip = ashet_lwip.create(b, platform_spec.target, .ReleaseSafe);
            lwip.is_linking_libc = false;
            lwip.strip = false;
            lwip.addSystemIncludePath(.{ .path = "vendor/ziglibc/inc/libc" });
            data.lwip.put(platform, lwip);
        }
    }

    return data;
}
