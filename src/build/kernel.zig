const std = @import("std");

const FatFS = @import("zfat");

const ashet_com = @import("os-common.zig");
const ashet_lwip = @import("lwip.zig");

const build_targets = @import("targets.zig");
const platforms = @import("platform.zig");

const ZfatConfig = @import("../../build.zig").ZfatConfig;

pub const KernelOptions = struct {
    optimize: std.builtin.OptimizeMode,
    fatfs_config: ZfatConfig,
    machine_spec: *const build_targets.MachineSpec,
    modules: ashet_com.Modules,
    system_assets: *std.Build.Module,
    platforms: platforms.PlatformData,
};

fn renderMachineInfo(
    b: *std.Build,
    machine_spec: *const build_targets.MachineSpec,
    platform_spec: *const build_targets.PlatformSpec,
) ![]const u8 {
    var stream = std.ArrayList(u8).init(b.allocator);
    defer stream.deinit();

    const writer = stream.writer();

    try writer.writeAll("//! This is a machine-generated description of the Ashet OS target machine.\n\n");

    try writer.print("pub const machine_id = .{};\n", .{
        std.zig.fmtId(machine_spec.machine_id),
    });
    try writer.print("pub const machine_name = \"{}\";\n", .{
        std.zig.fmtEscapes(machine_spec.name),
    });
    try writer.print("pub const platform_id = .{};\n", .{
        std.zig.fmtId(platform_spec.platform_id),
    });
    try writer.print("pub const platform_name = \"{}\";\n", .{
        std.zig.fmtEscapes(platform_spec.name),
    });

    return try stream.toOwnedSlice();
}

pub fn create(b: *std.Build, options: KernelOptions) *std.Build.Step.Compile {
    const machine_spec = options.machine_spec;
    const platform_spec = build_targets.getPlatformSpec(machine_spec.platform);

    const machine_info_module = blk: {
        const machine_info = renderMachineInfo(
            b,
            machine_spec,
            platform_spec,
        ) catch @panic("out of memory!");

        const write_file_step = b.addWriteFile("machine-info.zig", machine_info);

        const module = b.createModule(.{
            .root_source_file = write_file_step.files.items[0].getPath(),
        });

        break :blk module;
    };

    var bad_kernel_target = machine_spec.alt_target orelse platform_spec.target;
    bad_kernel_target.os_tag = .freestanding;

    const kernel_target = b.resolveTargetQuery(bad_kernel_target);

    const libc = options.platforms.libc.get(machine_spec.platform);

    const zfat = b.dependency("zfat", .{
        .@"no-libc" = true,
        .target = kernel_target,
        .optimize = options.optimize,
        .max_long_name_len = options.fatfs_config.max_long_name_len,
        .code_page = options.fatfs_config.code_page,
        .@"volume-count" = options.fatfs_config.volumes,
        .@"static-rtc" = options.fatfs_config.rtc,
        .mkfs = options.fatfs_config.mkfs,
    });

    const zfat_mod = zfat.module("zfat");

    zfat_mod.addIncludePath(libc.getEmittedIncludeTree());

    const kernel_mod = b.createModule(.{
        .target = kernel_target,
        .optimize = options.optimize,
        .root_source_file = b.path("src/kernel/main.zig"),
        .imports = &.{
            .{ .name = "machine-info", .module = machine_info_module },
            .{ .name = "system-assets", .module = options.system_assets },
            .{ .name = "ashet-abi", .module = options.modules.ashet_abi },
            .{ .name = "ashet-std", .module = options.modules.ashet_std },
            .{ .name = "ashet", .module = options.modules.libashet },
            .{ .name = "ashet-gui", .module = options.modules.ashet_gui },
            .{ .name = "virtio", .module = options.modules.virtio },
            .{ .name = "ashet-fs", .module = options.modules.libashetfs },
            .{ .name = "args", .module = options.modules.args },
            .{ .name = "fatfs", .module = zfat_mod },
            .{ .name = "args", .module = options.modules.args },
            .{ .name = "vnc", .module = options.modules.vnc },

            // only required on hosted instances:
            .{ .name = "network", .module = options.modules.network },
            // .{ .name = "sdl", .module = options.modules.sdl },
        },
    });
    // for (std.enums.values(build_targets.Platform)) |platform| {
    //     const mod = options.platforms.modules.get(platform);
    //     kernel_mod.dependencies.put(
    //         b.fmt("platform.{s}", .{@tagName(platform)}),
    //         mod,
    //     ) catch @panic("out of memory");
    // }

    const start_file: std.Build.LazyPath = machine_spec.start_file orelse
        platform_spec.start_file orelse
        b.path("src/kernel/port/platform/generic-startup.zig");

    const kernel_exe = b.addExecutable(.{
        .name = "ashet-os",
        .root_source_file = start_file,
        .target = kernel_target,
        .optimize = options.optimize,
    });

    kernel_exe.step.dependOn(machine_info_module.root_source_file.?.generated.file.step);

    kernel_exe.root_module.addImport("kernel", kernel_mod);

    // TODO(fqu): kernel_exe.root_module.code_model = .small;
    kernel_exe.bundle_compiler_rt = true;
    kernel_exe.rdynamic = true; // Prevent the compiler from garbage collecting exported symbols
    kernel_exe.root_module.single_threaded = (kernel_exe.rootModuleTarget().os.tag == .freestanding);
    kernel_exe.root_module.omit_frame_pointer = false;
    kernel_exe.root_module.strip = false; // never strip debug info
    if (options.optimize == .Debug) {
        // we always want frame pointers in debug build!
        kernel_exe.root_module.omit_frame_pointer = false;
    }

    kernel_exe.setLinkerScriptPath(b.path(options.machine_spec.linker_script));

    for (options.platforms.include_paths.get(machine_spec.platform).items) |path| {
        kernel_exe.addSystemIncludePath(path);
    }

    switch (options.machine_spec.platform) {
        .hosted => {
            kernel_mod.linkSystemLibrary("sdl2", .{
                .use_pkg_config = .force,
                .search_strategy = .mode_first,
            });
            kernel_exe.linkage = .dynamic;
            kernel_exe.linkLibC();
        },
        else => {},
    }

    kernel_exe.linkLibrary(libc);

    {
        const lwip = options.platforms.lwip.get(machine_spec.platform);
        kernel_exe.linkLibrary(lwip);
        ashet_lwip.setup(b, kernel_mod);
    }

    return kernel_exe;
}
