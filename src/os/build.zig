const std = @import("std");
const AshetOS = @import("AshetOS");

const DiskBuildInterface = @import("disk-image-step").BuildInterface;
const kernel_package = @import("kernel");

const Machine = kernel_package.Machine;

const app_packages = [_][]const u8{
    "hello_world",
    "hello_gui",
    "gui_debugger",
    "clock",
    "paint",
    "init",
    "test_behaviour",
    "desktop_classic",
    "dungeon",
    // TODO: Include "wiki" again,
};

pub fn build(b: *std.Build) void {

    // Options:
    const machine = b.option(Machine, "machine", "What machine should AshetOS be built for?") orelse @panic("no machine defined!");
    const optimize_kernel = b.option(bool, "optimize-kernel", "Should the kernel be optimized?") orelse false;
    const optimize_apps = b.option(std.builtin.OptimizeMode, "optimize-apps", "Optimization mode for the applications") orelse .Debug;

    const platform = machine.get_platform();

    // Dependencies:

    const kernel_dep = b.dependency("kernel", .{
        .machine = machine,
        .release = optimize_kernel,
    });
    const assets_dep = b.dependency("assets", .{});
    const syslinux_dep = b.dependency("syslinux", .{ .release = true });

    const disk_image_dep = b.dependency("disk-image-step", .{ .release = true });

    // Build:

    const disk_image_tools = DiskBuildInterface.init(b, disk_image_dep);

    const machine_info = machine_info_map.get(machine);

    const kernel = kernel_dep.artifact("kernel");

    const kernel_elf = kernel.getEmittedBin();

    const result_files = b.addNamedWriteFiles("ashet-os");

    _ = result_files.addCopyFile(kernel_elf, "kernel.elf");

    // Phase 1: Target independent root fs:

    var rootfs = DiskBuildInterface.FileSystemBuilder.init(b);
    {
        // Add the rootfs part which is present on all deployments:
        rootfs.copyDirectory(b.path("../../rootfs/all-systems"), "/");

        // Add the rootfs part which is auto-generated during the build and contains converted files:
        const asset_source = assets_dep.namedWriteFiles("assets");
        rootfs.copyDirectory(asset_source.getDirectory(), "/");

        // Add the rootfs part which contains developer customizations:
        rootfs.copyDirectory(b.path("../../rootfs/dev"), "/");
    }

    // Phase 2: Platform dependent root fs

    for (app_packages) |dep_name| {

        // std.log.err("dep: {s}", .{dep_name});

        const app_dep = b.dependency(dep_name, .{
            .target = platform,
            .optimize = optimize_apps,
        });

        const install_files = app_dep.namedWriteFiles("ashet.app.files");
        for (install_files.files.items) |file| {
            _ = rootfs.copyFile(
                install_files.getDirectory().path(b, file.sub_path),
                b.fmt("/{s}", .{file.sub_path}),
            );
        }

        const app_list = AshetOS.getApplications(app_dep);

        for (app_list) |app| {
            // std.log.err("- {s}", .{app.target_path});

            const app_path = b.fmt("/apps/{s}", .{app.target_path});

            // Copy the file into the disk image:
            if (std.fs.path.dirnamePosix(app_path)) |dir| {
                rootfs.mkdir(dir);
            }
            rootfs.copyFile(app.ashex_file, app_path);

            // TODO(fqu): Add means to also export the applications ELF file:
            _ = result_files.addCopyFile(
                app.elf_file,
                b.fmt("apps/{s}.elf", .{
                    app.target_path[0 .. app.target_path.len - ".ashex".len],
                }),
            );
            _ = result_files.addCopyFile(
                app.ashex_file,
                b.fmt("apps/{s}", .{app.target_path}),
            );
        }
    }

    switch (platform) {
        else => {},
    }

    // Phase 3: Machine dependent root fs
    switch (machine) {
        .@"x86-pc-bios" => {
            rootfs.copyFile(kernel_elf, "/ashet-os");

            // Copy syslinux installation fikles
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/cmenu/libmenu/libmenu.c32"), "/syslinux/libmenu.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/gpllib/libgpl.c32"), "/syslinux/libgpl.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/hdt/hdt.c32"), "/syslinux/hdt.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/lib/libcom32.c32"), "/syslinux/libcom32.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/libutil/libutil.c32"), "/syslinux/libutil.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/mboot/mboot.c32"), "/syslinux/mboot.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/menu/menu.c32"), "/syslinux/menu.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/modules/poweroff.c32"), "/syslinux/poweroff.c32");
            rootfs.copyFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/modules/reboot.c32"), "/syslinux/reboot.c32");

            // Copy syslinux configuration files
            rootfs.copyFile(b.path("../../rootfs/pc-bios/syslinux/modules.alias"), "/syslinux/modules.alias");
            rootfs.copyFile(b.path("../../rootfs/pc-bios/syslinux/pci.ids"), "/syslinux/pci.ids");
            rootfs.copyFile(b.path("../../rootfs/pc-bios/syslinux/syslinux.cfg"), "/syslinux/syslinux.cfg");
        },

        else => {},
    }

    if (machine_info.rom_size) |rom_size| {
        const objcopy_kernel = b.addObjCopy(kernel_elf, .{
            .basename = "kernel.bin",
            .format = .bin,
            .pad_to = rom_size,
        });

        const kernel_bin = objcopy_kernel.getOutput();

        _ = result_files.addCopyFile(kernel_bin, "kernel.bin");

        const install_bin_file = b.addInstallFile(kernel_bin, "kernel.bin");
        b.getInstallStep().dependOn(&install_bin_file.step);
    }

    // Phase 4: Put all files in the rootfs into a named step as well:
    // MUST BE DONE BEFORE "rootfs.finalize()"!
    {
        const rootfs_files = b.addNamedWriteFiles("rootfs");

        for (rootfs.list.items) |item| {
            switch (item) {
                .empty_dir => |destination| {
                    _ = rootfs_files.addCopyDirectory(
                        b.path("empty-dir"),
                        destination,
                        .{
                            .exclude_extensions = &.{".gitignore"},
                        },
                    );
                },

                .copy_dir => |copy| {
                    _ = rootfs_files.addCopyDirectory(
                        copy.source,
                        copy.destination,
                        .{},
                    );
                },

                .copy_file => |copy| {
                    _ = rootfs_files.addCopyFile(
                        copy.source,
                        copy.destination,
                    );
                },

                .include_script => @panic("unsupported feature used!"),
            }
        }
    }

    // Phase 5: Create disk
    const disk_image = switch (machine) {
        .@"x86-pc-bios" => blk: {
            const raw_disk_file = disk_image_tools.createDisk(500 * DiskBuildInterface.MiB, .{
                .mbr_part_table = .{
                    .bootloader = &.{ .paste_file = syslinux_dep.path("vendor/syslinux-6.03/bios/mbr/mbr.bin") },
                    .partitions = .{
                        &.{
                            .type = .@"fat32-lba",
                            .bootable = true,
                            .data = .{ .vfat = .{
                                .format = .fat32,
                                .label = "AshetOS",
                                .tree = rootfs.finalize(),
                            } },
                        },
                        null,
                        null,
                        null,
                    },
                },
            });

            const syslinux_installer = syslinux_dep.artifact("syslinux");

            const install_syslinux = InstallSyslinuxStep.create(b, syslinux_installer, raw_disk_file);

            break :blk std.Build.LazyPath{ .generated = .{ .file = install_syslinux.output_file } };
        },

        else => disk_image_tools.createDisk(
            machine_info.disk_size,
            .{
                .vfat = .{
                    .label = "AshetOS",
                    .format = .fat16,
                    .tree = rootfs.finalize(),
                },
            },
        ),
    };

    _ = result_files.addCopyFile(disk_image, "disk.img");

    const install_disk_image = b.addInstallFile(disk_image, "disk.img");
    b.getInstallStep().dependOn(&install_disk_image.step);
}

const MachineDependentOsConfig = struct {
    disk_size: usize,
    rom_size: ?usize,
};

const machine_info_map = std.EnumArray(Machine, MachineDependentOsConfig).init(.{
    .@"x86-pc-bios" = .{
        .rom_size = null,
        .disk_size = 512 * DiskBuildInterface.MiB,
    },
    .@"rv32-qemu-virt" = .{
        .disk_size = 0x0200_0000,
        .rom_size = 0x0200_0000,
    },
    .@"arm-qemu-virt" = .{
        .disk_size = 0x0400_0000,
        .rom_size = 0x0400_0000,
    },
    .@"x86-hosted-linux" = .{
        .disk_size = 0x0400_0000,
        .rom_size = null,
    },
    .@"x86-hosted-windows" = .{
        .disk_size = 0x0400_0000,
        .rom_size = null,
    },
    .@"arm-ashet-vhc" = .{
        .disk_size = 0x0400_0000,
        .rom_size = null,
    },
    .@"arm-ashet-hc" = .{
        .disk_size = 0x0080_0000, // 4 MB, we store the disk inside the system image (upper half of the flash)
        .rom_size = 0x0080_0000, // 4 MB, we store the kernel inside the system image (lower half of the flash)
    },
});

const InstallSyslinuxStep = struct {
    step: std.Build.Step,
    output_file: *std.Build.GeneratedFile,
    input_file: std.Build.LazyPath,
    syslinux: *std.Build.Step.Compile,

    pub fn create(builder: *std.Build, syslinux: *std.Build.Step.Compile, input_file: std.Build.LazyPath) *InstallSyslinuxStep {
        const bundle = builder.allocator.create(InstallSyslinuxStep) catch @panic("oom");
        errdefer builder.allocator.destroy(bundle);

        const outfile = builder.allocator.create(std.Build.GeneratedFile) catch @panic("oom");
        errdefer builder.allocator.destroy(outfile);

        outfile.* = .{ .step = &bundle.step };

        bundle.* = InstallSyslinuxStep{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "install syslinux",
                .owner = builder,
                .makeFn = make,
                .first_ret_addr = null,
                .max_rss = 0,
            }),
            .syslinux = syslinux,
            .input_file = input_file,
            .output_file = outfile,
        };
        input_file.addStepDependencies(&bundle.step);
        bundle.step.dependOn(&syslinux.step);

        return bundle;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;

        const iss: *InstallSyslinuxStep = @fieldParentPtr("step", step);
        const b = step.owner;

        const disk_image = iss.input_file.getPath2(b, step);

        var man = b.graph.cache.obtain();
        defer man.deinit();

        _ = try man.addFile(disk_image, null);

        step.result_cached = try step.cacheHit(&man);
        const digest = man.final();

        const output_components = .{ "o", &digest, "disk.img" };
        const output_sub_path = b.pathJoin(&output_components);
        const output_sub_dir_path = std.fs.path.dirname(output_sub_path).?;
        b.cache_root.handle.makePath(output_sub_dir_path) catch |err| {
            return step.fail("unable to make path '{}{s}': {s}", .{
                b.cache_root, output_sub_dir_path, @errorName(err),
            });
        };

        iss.output_file.path = try b.cache_root.join(b.allocator, &output_components);

        if (step.result_cached)
            return;

        try std.fs.Dir.copyFile(
            b.cache_root.handle,
            disk_image,
            b.cache_root.handle,
            iss.output_file.path.?,
            .{},
        );

        _ = step.owner.run(&.{
            iss.syslinux.getEmittedBin().getPath2(iss.syslinux.step.owner, step),
            "--offset",
            "1048576",
            "--install",
            "--directory",
            "syslinux", // path *inside* the image
            iss.output_file.path.?,
        });

        try step.writeManifest(&man);
    }
};
