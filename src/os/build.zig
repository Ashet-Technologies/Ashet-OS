const std = @import("std");

const disk_image_step = @import("disk_image_step");
const kernel_package = @import("kernel");

const Machine = kernel_package.Machine;

pub fn build(b: *std.Build) void {
    // Options:
    const machine = b.option(Machine, "machine", "What machine should AshetOS be built for?") orelse @panic("no machine defined!");
    const optimize = b.standardOptimizeOption(.{});

    const platform = machine.get_platform();

    // Dependencies:

    const kernel_dep = b.dependency("kernel", .{ .machine = machine, .optimize = optimize });
    const assets_dep = b.dependency("assets", .{});
    const syslinux_dep = b.dependency("syslinux", .{});

    // Build:

    _ = platform;
    _ = kernel_dep;
    _ = assets_dep;
    _ = syslinux_dep;

    const disk_formatter = getDiskFormatter(machine_spec.disk_formatter);

    const disk_image = disk_formatter(b, kernel_file, &rootfs);

    const install_disk_image = b.addInstallFileWithDir(
        disk_image,
        .{ .custom = "disk" },
        b.fmt("{s}.img", .{machine_spec.machine_id}),
    );

    b.getInstallStep().dependOn(&install_disk_image.step);

    // TODO: Compile disk image for a single target here
}

const MachineDependentOsConfig = struct {
    //
};

const machine_info_map = std.EnumArray(Machine, MachineDependentOsConfig).init(.{
    .@"pc-bios" = .{
        .disk_formatter = "bios_pc",
        .rom_size = null,
    },
    .@"qemu-virt-rv32" = .{
        .disk_formatter = "rv32_virt",
        .rom_size = 0x0200_0000,
    },
    .@"qemu-virt-arm" = .{
        .disk_formatter = "arm_virt",
        .rom_size = 0x0400_0000,
    },
    .@"hosted-x86-linux" = .{
        .disk_formatter = "linux_pc",
        .rom_size = null,
    },
});

fn getDiskFormatter(name: []const u8) *const fn (*std.Build, std.Build.LazyPath, *disk_image_step.FileSystemBuilder) std.Build.LazyPath {
    inline for (comptime std.meta.declarations(disk_formatters)) |fmt_decl| {
        if (std.mem.eql(u8, fmt_decl.name, name)) {
            return @field(disk_formatters, fmt_decl.name);
        }
    }
    @panic("Machine has invalid disk formatter defined!");
}
pub fn generic_virt_formatter(b: *std.Build, kernel_file: std.Build.LazyPath, disk_content: *disk_image_step.FileSystemBuilder, disk_image_size: usize) std.Build.LazyPath {
    _ = kernel_file;

    const disk_image_dep = b.dependency("disk-image-step", .{});

    const disk = disk_image_step.initializeDisk(
        disk_image_dep,
        disk_image_size,
        .{
            .fs = disk_content.finalize(.{ .format = .fat16, .label = "AshetOS" }),
        },
    );

    return disk.getImageFile();
}

const disk_formatters = struct {
    pub fn rv32_virt(b: *std.Build, kernel_file: std.Build.LazyPath, disk_content: *disk_image_step.FileSystemBuilder) std.Build.LazyPath {
        return generic_virt_formatter(b, kernel_file, disk_content, 0x0200_0000);
    }

    pub fn arm_virt(b: *std.Build, kernel_file: std.Build.LazyPath, disk_content: *disk_image_step.FileSystemBuilder) std.Build.LazyPath {
        return generic_virt_formatter(b, kernel_file, disk_content, 0x0400_0000);
    }

    pub fn linux_pc(b: *std.Build, kernel_file: std.Build.LazyPath, disk_content: *disk_image_step.FileSystemBuilder) std.Build.LazyPath {
        return generic_virt_formatter(b, kernel_file, disk_content, 0x0400_0000);
    }

    pub fn bios_pc(b: *std.Build, kernel_file: std.Build.LazyPath, disk_content: *disk_image_step.FileSystemBuilder) std.Build.LazyPath {
        disk_content.addFile(kernel_file, "/ashet-os");

        disk_content.addFile(b.path("./rootfs-x86/syslinux/modules.alias"), "syslinux/modules.alias");
        disk_content.addFile(b.path("./rootfs-x86/syslinux/pci.ids"), "syslinux/pci.ids");
        disk_content.addFile(b.path("./rootfs-x86/syslinux/syslinux.cfg"), "syslinux/syslinux.cfg");

        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/cmenu/libmenu/libmenu.c32"), "syslinux/libmenu.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/gpllib/libgpl.c32"), "syslinux/libgpl.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/hdt/hdt.c32"), "syslinux/hdt.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/lib/libcom32.c32"), "syslinux/libcom32.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/libutil/libutil.c32"), "syslinux/libutil.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/mboot/mboot.c32"), "syslinux/mboot.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/menu/menu.c32"), "syslinux/menu.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/modules/poweroff.c32"), "syslinux/poweroff.c32");
        disk_content.addFile(b.path("./vendor/syslinux/vendor/syslinux-6.03/bios/com32/modules/reboot.c32"), "syslinux/reboot.c32");

        const disk_image_dep = b.dependency("disk-image-step", .{});

        const disk = disk_image_step.initializeDisk(disk_image_dep, 500 * disk_image_step.MiB, .{
            .mbr = .{
                .bootloader = @embedFile("./vendor/syslinux/vendor/syslinux-6.03/bios/mbr/mbr.bin").*,
                .partitions = .{
                    &.{
                        .type = .fat32_lba,
                        .bootable = true,
                        .size = 499 * disk_image_step.MiB,
                        .data = .{ .fs = disk_content.finalize(.{ .format = .fat32, .label = "AshetOS" }) },
                    },
                    null,
                    null,
                    null,
                },
            },
        });

        // const syslinux_dep = b.anonymousDependency("./vendor/syslinux/", syslinux_build_zig, .{
        //     .release = true,
        // });

        const syslinux_dep = b.dependency("syslinux", .{ .release = true });

        const syslinux_installer = syslinux_dep.artifact("syslinux");

        const raw_disk_file = disk.getImageFile();

        const install_syslinux = InstallSyslinuxStep.create(b, syslinux_installer, raw_disk_file);

        return .{ .generated = .{ .file = install_syslinux.output_file } };
    }
};

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
