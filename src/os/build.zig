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

    const disk_image_dep = b.dependency("disk-image-step", .{ .release = true });

    const limine_dep = b.dependency("zig_limine_install", .{ .target = b.graph.host, .optimize = .ReleaseSafe });

    // Build:

    const disk_image_tools = DiskBuildInterface.init(b, disk_image_dep);

    const machine_info = machine_info_map.get(machine);

    const kernel = kernel_dep.artifact("kernel");

    const kernel_exe = kernel.getEmittedBin();

    const result_files = b.addNamedWriteFiles("ashet-os");

    _ = result_files.addCopyFile(kernel_exe, machine.get_kernel_file_name());
    if (kernel.rootModuleTarget().ofmt == .coff) {
        _ = result_files.addCopyFile(kernel.getEmittedPdb(), "kernel.pdb");
    }

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

    if (machine_info.rom_size) |rom_size| {
        const objcopy_kernel = b.addObjCopy(kernel_exe, .{
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
            var esp_fs = DiskBuildInterface.FileSystemBuilder.init(b);
            // BIOS Setup
            esp_fs.copyFile(limine_dep.namedLazyPath("limine-bios.sys"), "/limine-bios.sys");

            // EFI Setup
            {
                esp_fs.mkdir("/EFI");
                esp_fs.mkdir("/EFI/BOOT");
                esp_fs.copyFile(limine_dep.namedLazyPath("limine").path(b, "BOOTX64.EFI"), "/EFI/BOOT/BOOTX64.EFI");
            }

            esp_fs.copyFile(b.path("../../rootfs/pc-bios/limine.conf"), "/limine.conf");
            esp_fs.copyFile(kernel_exe, "/ashet-os");

            const raw_disk_file = disk_image_tools.createDisk(40 * DiskBuildInterface.MiB, .{
                .gpt_part_table = .{
                    .partitions = &.{
                        .{
                            .type = .{ .name = .@"bios-boot" },
                            .name = "Legacy bootloader",
                            .size = 0x8000,
                            .offset = 0x5000,
                            .data = .empty,
                        },
                        .{
                            .type = .{ .name = .@"efi-system" },
                            .name = "EFI System Partition",
                            .offset = 0xD000,
                            .size = 2 * DiskBuildInterface.MiB,
                            .data = .{
                                .vfat = .{
                                    .format = .fat32,
                                    .label = "UEFI",
                                    .tree = esp_fs.finalize(),
                                },
                            },
                        },
                        .{
                            .type = .{ .guid = "1b279432-2c0a-4d6c-aa30-7edee4b7155f".* },
                            .name = "Ashet OS",
                            .offset = 0xD000,
                            // .size = 0x210_0000,
                            .data = .{
                                .vfat = .{
                                    .format = .fat32,
                                    .label = "AshetOS",
                                    .tree = rootfs.finalize(),
                                },
                            },
                        },
                    },
                },
            });

            const limine_install_exe = limine_dep.artifact("limine-install");

            const add_limine_to_image = b.addRunArtifact(limine_install_exe);
            add_limine_to_image.addArg("-i");
            add_limine_to_image.addFileArg(raw_disk_file);
            add_limine_to_image.addArg("-o");
            const disk_file = add_limine_to_image.addOutputFileArg("image.bin");
            add_limine_to_image.addArgs(&.{ "-p", "1" }); // set GPT partition index

            break :blk disk_file;
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

const InstallBootloaderStep = struct {
    step: std.Build.Step,
    output_file: *std.Build.GeneratedFile,
    input_file: std.Build.LazyPath,
    bootloader: std.Build.LazyPath,

    pub fn create(builder: *std.Build, bootloader: std.Build.LazyPath, input_file: std.Build.LazyPath) *InstallBootloaderStep {
        const bundle = builder.allocator.create(InstallBootloaderStep) catch @panic("oom");
        errdefer builder.allocator.destroy(bundle);

        const outfile = builder.allocator.create(std.Build.GeneratedFile) catch @panic("oom");
        errdefer builder.allocator.destroy(outfile);

        outfile.* = .{ .step = &bundle.step };

        bundle.* = InstallBootloaderStep{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "install bootloader",
                .owner = builder,
                .makeFn = make,
                .first_ret_addr = null,
                .max_rss = 0,
            }),
            .bootloader = bootloader,
            .input_file = input_file,
            .output_file = outfile,
        };
        input_file.addStepDependencies(&bundle.step);
        bootloader.addStepDependencies(&bundle.step);

        return bundle;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;

        const iss: *InstallBootloaderStep = @fieldParentPtr("step", step);
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
            iss.bootloader.getPath2(b, step),
            "bios-install",
            iss.output_file.path.?,
        });

        try step.writeManifest(&man);
    }
};
