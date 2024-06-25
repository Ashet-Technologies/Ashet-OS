const std = @import("std");

const disk_image_step = @import("disk-image-step");
const kernel_package = @import("kernel");

const Machine = kernel_package.Machine;

pub fn build(b: *std.Build) void {
    // Options:
    const machine = b.option(Machine, "machine", "What machine should AshetOS be built for?") orelse @panic("no machine defined!");
    const optimize = b.standardOptimizeOption(.{});

    const platform = machine.get_platform();

    // Dependencies:

    const kernel_dep = b.dependency("kernel", .{
        .machine = machine,
        .release = (optimize != .Debug),
    });
    const assets_dep = b.dependency("assets", .{});
    const syslinux_dep = b.dependency("syslinux", .{ .release = true });

    const disk_image_dep = b.dependency("disk-image-step", .{});

    // Build:

    const machine_info = machine_info_map.get(machine);

    const kernel = kernel_dep.artifact("kernel");

    const kernel_elf = kernel.getEmittedBin();

    // TODO: add objcopy for kernel_bin file

    // Phase 1: Target independent root fs:

    var rootfs = disk_image_step.FileSystemBuilder.init(b);
    {
        rootfs.addDirectory(b.path("../../rootfs"), ".");

        const asset_source = assets_dep.namedWriteFiles("assets");
        rootfs.addDirectory(asset_source.getDirectory(), ".");
    }

    // Phase 2: Platform dependent root fs

    // TODO: Install applications here

    switch (platform) {
        else => {},
    }

    // Phase 3: Machine dependent root fs
    switch (machine) {
        .@"pc-bios" => {
            rootfs.addFile(kernel_elf, "/ashet-os");

            rootfs.addFile(b.path("../../rootfs-x86/syslinux/modules.alias"), "syslinux/modules.alias");
            rootfs.addFile(b.path("../../rootfs-x86/syslinux/pci.ids"), "syslinux/pci.ids");
            rootfs.addFile(b.path("../../rootfs-x86/syslinux/syslinux.cfg"), "syslinux/syslinux.cfg");

            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/cmenu/libmenu/libmenu.c32"), "syslinux/libmenu.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/gpllib/libgpl.c32"), "syslinux/libgpl.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/hdt/hdt.c32"), "syslinux/hdt.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/lib/libcom32.c32"), "syslinux/libcom32.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/libutil/libutil.c32"), "syslinux/libutil.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/mboot/mboot.c32"), "syslinux/mboot.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/menu/menu.c32"), "syslinux/menu.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/modules/poweroff.c32"), "syslinux/poweroff.c32");
            rootfs.addFile(syslinux_dep.path("vendor/syslinux-6.03/bios/com32/modules/reboot.c32"), "syslinux/reboot.c32");
        },

        else => {},
    }

    // Phase 4: Create disk

    const disk_image = switch (machine) {
        .@"pc-bios" => blk: {
            var bootloader_buffer: [440]u8 = undefined;
            const syslinux_bootloader = std.fs.cwd().readFile(
                syslinux_dep.path("vendor/syslinux-6.03/bios/mbr/mbr.bin").getPath(b),
                &bootloader_buffer,
            ) catch @panic("failed to load bootloader!");
            std.debug.assert(syslinux_bootloader.len == bootloader_buffer.len);

            const disk = disk_image_step.initializeDisk(disk_image_dep, 500 * disk_image_step.MiB, .{
                .mbr = .{
                    .bootloader = bootloader_buffer,
                    .partitions = .{
                        &.{
                            .type = .fat32_lba,
                            .bootable = true,
                            .size = 499 * disk_image_step.MiB,
                            .data = .{ .fs = rootfs.finalize(.{ .format = .fat32, .label = "AshetOS" }) },
                        },
                        null,
                        null,
                        null,
                    },
                },
            });

            const syslinux_installer = syslinux_dep.artifact("syslinux");

            const raw_disk_file = disk.getImageFile();

            const install_syslinux = InstallSyslinuxStep.create(b, syslinux_installer, raw_disk_file);

            break :blk std.Build.LazyPath{ .generated = .{ .file = install_syslinux.output_file } };
        },

        else => blk: {
            const disk = disk_image_step.initializeDisk(
                disk_image_dep,
                machine_info.disk_size,
                .{
                    .fs = rootfs.finalize(.{ .format = .fat16, .label = "AshetOS" }),
                },
            );

            break :blk disk.getImageFile();
        },
    };

    // TODO: consider using `b.fmt("{s}.img", .{machine_spec.machine_id})`, or move
    const install_disk_image = b.addInstallFile(disk_image, "disk.img");
    b.getInstallStep().dependOn(&install_disk_image.step);

    if (machine_info.rom_size) |rom_size| {
        const objcopy_kernel = b.addObjCopy(kernel_elf, .{
            .basename = "kernel.bin",
            .format = .bin,
            .pad_to = rom_size,
        });

        const install_bin_file = b.addInstallFile(objcopy_kernel.getOutput(), "kernel.bin");
        b.getInstallStep().dependOn(&install_bin_file.step);
    }
}

const MachineDependentOsConfig = struct {
    disk_size: usize,
    rom_size: ?usize,
};

const machine_info_map = std.EnumArray(Machine, MachineDependentOsConfig).init(.{
    .@"pc-bios" = .{
        .rom_size = null,
        .disk_size = 512 * disk_image_step.MiB,
    },
    .@"qemu-virt-rv32" = .{
        .disk_size = 0x0200_0000,
        .rom_size = 0x0200_0000,
    },
    .@"qemu-virt-arm" = .{
        .disk_size = 0x0400_0000,
        .rom_size = 0x0400_0000,
    },
    .@"hosted-x86-linux" = .{
        .disk_size = 0x0400_0000,
        .rom_size = null,
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

    fn make(step: *std.Build.Step, node: std.Progress.Node) !void {
        _ = node;

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
            "2048",
            "--install",
            "--directory",
            "syslinux", // path *inside* the image
            iss.output_file.path.?,
        });

        try step.writeManifest(&man);
    }
};
