const std = @import("std");
const foundation_libc = @import("foundation-libc");
const ashet_lwip = @import("lwip.zig");
const common = @import("os-common.zig");

const build_targets = @import("targets.zig");

pub fn PlatformMap(comptime T: type) type {
    return std.enums.EnumArray(build_targets.Platform, T);
}

pub const PlatformData = struct {
    libsyscall: PlatformMap(*std.Build.Step.Compile) = PlatformMap(*std.Build.Step.Compile).initUndefined(),
    libc: PlatformMap(*std.Build.Step.Compile) = PlatformMap(*std.Build.Step.Compile).initUndefined(),
    lwip: PlatformMap(*std.Build.Step.Compile) = PlatformMap(*std.Build.Step.Compile).initUndefined(),
    modules: PlatformMap(*std.Build.Module) = PlatformMap(*std.Build.Module).initUndefined(),
    include_paths: PlatformMap(std.ArrayListUnmanaged(std.Build.LazyPath)) = PlatformMap(std.ArrayListUnmanaged(std.Build.LazyPath)).initFill(.{}),
};

pub fn init(b: *std.Build, modules: common.Modules) PlatformData {
    var data = PlatformData{};

    for (std.enums.values(build_targets.Platform)) |platform| {
        const platform_spec = build_targets.getPlatformSpec(platform);

        const foundation_dep = b.dependency("foundation-libc", .{
            .target = b.resolveTargetQuery(platform_spec.target),
            .optimize = .ReleaseSafe,
            .single_threaded = true,
        });

        const libc = foundation_dep.artifact("foundation");
        data.include_paths.getPtr(platform).append(
            b.allocator,
            libc.getEmittedIncludeTree(),
        ) catch @panic("out of memory");
        data.libc.set(platform, libc);

        // data.modules.set(platform, b.createModule(.{
        //     .source_file = .{ .path = platform_spec.source_file },
        // }));

        {
            const target = b.resolveTargetQuery(platform_spec.target);
            const lwip = ashet_lwip.create(b, target, .ReleaseSafe);
            lwip.is_linking_libc = false;
            lwip.root_module.strip = false;
            for (data.include_paths.get(platform).items) |path| {
                lwip.addSystemIncludePath(path);
            }
            data.lwip.set(platform, lwip);
        }

        const libsyscall = b.addSharedLibrary(.{
            .name = "AshetOS",
            .target = b.resolveTargetQuery(platform_spec.target),
            .optimize = .ReleaseSafe,
            .root_source_file = b.path("src/abi/libsyscall.zig"),
        });
        libsyscall.root_module.addImport("abi", modules.ashet_abi);

        const install_libsyscall = b.addInstallFileWithDir(
            libsyscall.getEmittedBin(),
            .{ .custom = b.fmt("lib/{s}", .{@tagName(platform)}) },
            "libAshetOS.so",
        );

        b.getInstallStep().dependOn(&install_libsyscall.step);

        data.libsyscall.set(platform, libsyscall);
    }

    return data;
}
