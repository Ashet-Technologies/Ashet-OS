const std = @import("std");
const foundation_libc = @import("../../vendor/foundation-libc/build.zig");
const ashet_lwip = @import("lwip.zig");

const build_targets = @import("targets.zig");

pub fn PlatformMap(comptime T: type) type {
    return std.enums.EnumArray(build_targets.Platform, T);
}

pub const PlatformData = struct {
    libsyscall: PlatformMap(*std.Build.CompileStep) = PlatformMap(*std.Build.CompileStep).initUndefined(),
    libc: PlatformMap(*std.Build.CompileStep) = PlatformMap(*std.Build.CompileStep).initUndefined(),
    lwip: PlatformMap(*std.Build.CompileStep) = PlatformMap(*std.Build.CompileStep).initUndefined(),
    modules: PlatformMap(*std.Build.Module) = PlatformMap(*std.Build.Module).initUndefined(),
    include_paths: PlatformMap(std.ArrayListUnmanaged(std.Build.LazyPath)) = PlatformMap(std.ArrayListUnmanaged(std.Build.LazyPath)).initFill(.{}),
};

pub fn init(b: *std.Build) PlatformData {
    const foundation_dep = b.anonymousDependency("vendor/foundation-libc", foundation_libc, .{});

    var data = PlatformData{};

    for (std.enums.values(build_targets.Platform)) |platform| {
        const platform_spec = build_targets.getPlatformSpec(platform);

        data.include_paths.getPtr(platform).append(b.allocator, .{
            .cwd_relative = b.pathFromRoot("vendor/foundation-libc/include"),
        }) catch @panic("out of memory");

        const libc = foundation_libc.createLibrary(
            foundation_dep.builder,
            platform_spec.target,
            .ReleaseSafe,
        );
        libc.single_threaded = true;
        data.libc.set(platform, libc);

        // data.modules.set(platform, b.createModule(.{
        //     .source_file = .{ .path = platform_spec.source_file },
        // }));

        {
            const lwip = ashet_lwip.create(b, platform_spec.target, .ReleaseSafe);
            lwip.is_linking_libc = false;
            lwip.strip = false;
            for (data.include_paths.get(platform).items) |path| {
                lwip.addSystemIncludePath(path);
            }
            data.lwip.set(platform, lwip);
        }

        const libsyscall = b.addSharedLibrary(.{
            .name = "syscall",
            .target = platform_spec.target,
            .optimize = .ReleaseSafe,
            .root_source_file = .{ .path = "src/abi/libsyscall.zig" },
        });

        const install_libsyscall = b.addInstallFileWithDir(
            libsyscall.getEmittedBin(),
            .{ .custom = b.fmt("lib/{s}", .{@tagName(platform)}) },
            "libsyscall.so",
        );

        b.getInstallStep().dependOn(&install_libsyscall.step);

        data.libsyscall.set(platform, libsyscall);
    }

    return data;
}
