const std = @import("std");
const shimizu_build = @import("shimizu");
const abiBuild = @import("ashet-abi");
const regz = @import("regz");
const Platform = abiBuild.Platform;

pub const Machine = @import("port/machine_id.zig").MachineID;

fn create_embedded_resource(b: *std.Build, path: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(path),
    });
}

pub fn build(b: *std.Build) void {
    // Options:
    const machine_id = b.option(Machine, "machine", "Selects the machine for which the kernel should be built.") orelse @panic("-Dmachine required!");
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
    const validate_mode = b.option(bool, "no-emit-bin", "Disables installing the kernel and makes the build way quicker.") orelse false;

    // Target configuration:
    const platform_id = machine_id.get_platform();

    const machine_config = machine_info_map.get(machine_id);
    const platform_config = platform_info_map.get(platform_id);

    const kernel_target = b.resolveTargetQuery(machine_config.target);

    // Dependencies:
    const abi_dep = b.dependency("ashet-abi", .{});
    const virtio_dep = b.dependency("virtio", .{});
    const ashet_fs_dep = b.dependency("ashet_fs", .{});
    const ashet_std_dep = b.dependency("ashet_std", .{});
    const args_dep = b.dependency("args", .{});
    const network_dep = b.dependency("network", .{});
    const vnc_dep = b.dependency("vnc", .{});
    const lwip_dep = b.dependency("lwip", .{ .target = kernel_target, .optimize = .ReleaseSafe });
    const libc_dep = b.dependency("foundation-libc", .{
        .target = kernel_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const zfat_dep = b.dependency("zfat", .{
        .@"no-libc" = true,
        .target = kernel_target,
        .optimize = optimize,
        .max_long_name_len = @as(u8, 121),
        .code_page = .us,
        .@"volume-count" = @as(u8, 8),
        .@"static-rtc" = @as([]const u8, "2022-07-10"), // TODO: Fix this
        .mkfs = true,
    });
    const libashetos_dep = b.dependency("libashetos", .{
        .target = platform_id,
    });
    const agp_dep = b.dependency("agp", .{});
    const agp_swrast_dep = b.dependency("agp_swrast", .{});
    const turtlefont_dep = b.dependency("turtlefont", .{});
    const ashex_dep = b.dependency("ashex", .{});
    const xcvt_dep = b.dependency("xcvt", .{});
    const shimizu_dep = b.dependency("shimizu", .{});
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_protocols_dep = b.dependency("wayland-protocols", .{});

    const wayland_unstable_dir = shimizu_build.generateProtocolZig(shimizu_dep.builder, shimizu_dep.artifact("shimizu-scanner"), .{
        .output_directory_name = "wayland-unstable",
        .source_files = &.{
            wayland_protocols_dep.path("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"),
        },
        .interface_versions = &.{
            .{ .interface = "zxdg_decoration_manager_v1", .version = 1 },
        },
        .imports = &.{
            .{ .file = wayland_dep.path("protocol/wayland.xml"), .import_string = "@import(\"core\")" },
            .{ .file = wayland_protocols_dep.path("stable/xdg-shell/xdg-shell.xml"), .import_string = "@import(\"wayland-protocols\").xdg_shell" },
        },
    });
    const wayland_unstable_module = b.addModule("wayland-unstable", .{
        .root_source_file = wayland_unstable_dir.output_directory.?.path(b, "root.zig"),
        .target = kernel_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wire", .module = shimizu_dep.module("wire") },
            .{ .name = "core", .module = shimizu_dep.module("core") },
            .{ .name = "wayland-protocols", .module = shimizu_dep.module("wayland-protocols") },
        },
    });

    const zigx_dep = b.dependency("zigx", .{});

    // Modules:

    const abi_mod = abi_dep.module("ashet-abi");
    const abi_impl_mod = abi_dep.module("ashet-abi-provider");
    const virtio_mod = virtio_dep.module("virtio");
    const ashet_fs_mod = ashet_fs_dep.module("ashet-fs");
    const ashet_std_mod = ashet_std_dep.module("ashet-std");
    const args_mod = args_dep.module("args");
    const network_mod = network_dep.module("network");
    const vnc_mod = vnc_dep.module("vnc");
    const zfat_mod = zfat_dep.module("zfat");
    const lwip_mod = lwip_dep.module("lwip");
    const ashetos_mod = libashetos_dep.module("ashet");
    const agp_mod = agp_dep.module("agp");
    const agp_swrast_mod = agp_swrast_dep.module("agp-swrast");
    const turtlefont_mod = turtlefont_dep.module("turtlefont");
    const ashex_mod = ashex_dep.module("ashex");
    const xcvt_mod = xcvt_dep.module("cvt");
    const shimizu_mod = shimizu_dep.module("shimizu");
    const wayland_protocols_mod = shimizu_dep.module("wayland-protocols");
    const zig_mod = zigx_dep.module("x");

    // Build:

    const machine_info_module = blk: {
        const machine_info = renderMachineInfo(
            b,
            machine_id,
            platform_id,
        ) catch @panic("out of memory!");

        const write_file_step = b.addWriteFile("machine-info.zig", machine_info);

        const module = b.createModule(.{
            .root_source_file = .{
                .generated = .{
                    .file = &write_file_step.generated_directory,
                    .sub_path = write_file_step.files.items[0].sub_path,
                },
            },
        });

        break :blk module;
    };

    const kernel_mod = b.createModule(.{
        .target = kernel_target,
        .optimize = optimize,
        .root_source_file = b.path("main.zig"),
        .imports = &.{
            .{ .name = "machine-info", .module = machine_info_module },
            .{ .name = "ashet-abi", .module = abi_mod },
            .{ .name = "ashet-abi-impl", .module = abi_impl_mod },
            .{ .name = "ashet-std", .module = ashet_std_mod },
            .{ .name = "virtio", .module = virtio_mod },
            .{ .name = "ashet-fs", .module = ashet_fs_mod },
            .{ .name = "args", .module = args_mod },
            .{ .name = "fatfs", .module = zfat_mod },
            .{ .name = "vnc", .module = vnc_mod },
            .{ .name = "ashet", .module = ashetos_mod },
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "agp-swrast", .module = agp_swrast_mod },
            .{ .name = "turtlefont", .module = turtlefont_mod },
            .{ .name = "ashex", .module = ashex_mod },
            .{ .name = "cvt", .module = xcvt_mod },

            // only required on hosted instances:
            .{ .name = "network", .module = network_mod },
            .{ .name = "x11", .module = zig_mod },
            // .{ .name = "sdl", .module = options.modules.sd
        },
    });

    kernel_mod.addImport("lwip", lwip_mod);
    kernel_mod.addIncludePath(b.path("components/network/include"));
    lwip_mod.addIncludePath(b.path("components/network/include"));
    for (lwip_mod.include_dirs.items) |dir| {
        kernel_mod.include_dirs.append(b.allocator, dir) catch @panic("out of memory");
    }

    if (machine_id == .@"arm-ashet-hc") {
        const regz_dep = b.dependency("regz", .{
            .optimize = .ReleaseSafe,
        });

        const regz_exe = regz_dep.artifact("regz");

        const regz_run = b.addRunArtifact(regz_exe);

        regz_run.addArg("--microzig");
        regz_run.addArg("--format");
        regz_run.addArg("svd");

        regz_run.addArg("--output_path"); // Write to a file
        const rp2350_register_file = regz_run.addOutputFileArg("rp2350.zig");

        {
            const patches = @import("port/machine/arm/ashet-hc/patches/rp2350_arm.zig").patches;

            if (patches.len > 0) {
                // write patches to file
                const patch_ndjson = serialize_patches(
                    b,
                    patches,
                );
                const write_file_step = b.addWriteFiles();
                const patch_file = write_file_step.add(
                    "patch.ndjson",
                    patch_ndjson,
                );

                regz_run.addArg("--patch_path");
                regz_run.addFileArg(patch_file);
            }
        }

        regz_run.addFileArg(b.path("port/machine/arm/ashet-hc/rp2350.svd"));

        const microzig_shim_mod = b.createModule(.{
            .root_source_file = b.path("utils/microzig-shim.zig"),
            .imports = &.{
                .{ .name = "kernel", .module = kernel_mod },
            },
        });

        const rp2350_mod = b.createModule(.{
            .root_source_file = rp2350_register_file,
            .imports = &.{
                .{ .name = "microzig", .module = microzig_shim_mod },
            },
        });

        kernel_mod.addImport("rp2350", rp2350_mod);

        const hal_dep = b.dependency("rp2xxx-hal", .{});

        const hal_mod = b.createModule(.{
            .root_source_file = hal_dep.path("hal.zig"),
            .imports = &.{
                .{ .name = "microzig", .module = microzig_shim_mod },
            },
        });

        microzig_shim_mod.addImport("rp2350-chip", rp2350_mod);
        microzig_shim_mod.addImport("rp2350-hal", hal_mod);

        kernel_mod.addImport("rp2350-hal", hal_mod);
    }

    const start_file = if (machine_id.is_hosted())
        b.path("port/platform/startup/hosted.zig")
    else
        b.path("port/platform/startup/generic.zig");

    const kernel_exe = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = start_file,
        .target = kernel_target,
        .optimize = optimize,
    });

    if (machine_id == .@"arm-ashet-hc" and optimize == .Debug) {
        std.debug.print("arm-ashet-hc has no C sanitization enabled in Debug mode!\nSee https://github.com/ziglang/zig/issues/23052 and https://github.com/ziglang/zig/issues/23216 for more details!\n", .{});
        kernel_exe.root_module.sanitize_c = false;
    }

    if (kernel_target.result.cpu.arch.isThumb()) {
        // Disable LTO on arm as it fails hard on the linker:
        kernel_exe.want_lto = false;
    }

    kernel_exe.step.dependOn(machine_info_module.root_source_file.?.generated.file.step);
    kernel_exe.root_module.addImport("kernel", kernel_mod);

    // TODO(fqu): kernel_exe.root_module.code_model = .small;
    kernel_exe.bundle_compiler_rt = true;
    // kernel_exe.rdynamic = true; // Prevent the compiler from garbage collecting exported symbols
    kernel_exe.root_module.single_threaded = !machine_id.is_hosted();
    kernel_exe.root_module.omit_frame_pointer = false;
    kernel_exe.root_module.strip = false; // never strip debug info
    if (optimize == .Debug) {
        // we always want frame pointers in debug build!
        kernel_exe.root_module.omit_frame_pointer = false;
    }

    kernel_exe.setLinkerScript(b.path(machine_config.linker_script));

    // for (options.platforms.include_paths.get(machine_spec.platform).items) |path| {
    //     kernel_exe.addSystemIncludePath(path);
    // }

    _ = platform_config;

    if (machine_id.is_hosted()) {
        // kernel_mod.linkSystemLibrary("sdl2", .{
        //     .use_pkg_config = .force,
        //     .search_strategy = .mode_first,
        // });

        kernel_mod.addImport("shimizu", shimizu_mod);
        kernel_mod.addImport("wayland-protocols", wayland_protocols_mod);
        kernel_mod.addImport("wayland-unstable", wayland_unstable_module);

        kernel_exe.linkage = .static;
        kernel_exe.linkLibC();
    } else {
        const libc = libc_dep.artifact("foundation");

        lwip_mod.addIncludePath(libc.getEmittedIncludeTree());
        zfat_mod.addIncludePath(libc.getEmittedIncludeTree());

        kernel_exe.linkLibrary(libc);
    }

    if (validate_mode) {
        b.getInstallStep().dependOn(&kernel_exe.step);
    } else {
        b.installArtifact(kernel_exe);
    }
}

const PlatformConfig = struct {
    source_file: []const u8,
};

const MachineConfig = struct {
    target: std.Target.Query,

    linker_script: []const u8,
    source_file: []const u8,
};

fn constructTargetQuery(spec: std.Target.Query) std.Target.Query {
    var base: std.Target.Query = spec;

    if (base.os_tag == null) {
        std.debug.assert(base.dynamic_linker.len == 0);
        std.debug.assert(base.ofmt == null);
        base.os_tag = .freestanding;
        base.ofmt = .elf;
    } else {
        std.debug.assert(base.os_tag != .freestanding);
        // We're in a hosted environment, explicit os is set
    }

    return base;
}

const platform_info_map = std.EnumArray(Platform, PlatformConfig).init(.{
    .x86 = .{
        .source_file = "port/platform/x86.zig",
    },
    .arm = .{
        .source_file = "port/platform/arm.zig",
    },
    .rv32 = .{
        .source_file = "port/platform/riscv.zig",
    },
});

const machine_info_map = std.EnumArray(Machine, MachineConfig).init(.{
    .@"x86-pc-generic" = .{
        .target = constructTargetQuery(generic_x86),

        .source_file = "port/machine/x86/pc-generic/pc-generic.zig",
        .linker_script = "port/machine/x86/pc-generic/linker.ld",
    },

    .@"rv32-qemu-virt" = .{
        .target = constructTargetQuery(generic_rv32),

        .source_file = "port/machine/rv32/qemu-virt/rv32-qemu-virt.zig",
        .linker_script = "port/machine/rv32/qemu-virt/linker.ld",
    },

    .@"arm-ashet-vhc" = .{
        .target = constructTargetQuery(arm_cortex_m33),

        .source_file = "port/machine/arm/ashet-vhc/ashet-vhc.zig",
        .linker_script = "port/machine/arm/ashet-vhc/linker.ld",
    },

    .@"arm-ashet-hc" = .{
        .target = constructTargetQuery(arm_cortex_m33),

        .source_file = "port/machine/arm/ashet-hc/ashet-hc.zig",
        .linker_script = "port/machine/arm/ashet-hc/linker.ld",
    },

    .@"arm-qemu-virt" = .{
        .target = constructTargetQuery(generic_arm),

        .source_file = "port/machine/arm/qemu-virt/qemu-virt.zig",
        .linker_script = "port/machine/arm/qemu-virt/linker.ld",
    },

    .@"x86-hosted-linux" = .{
        .target = constructTargetQuery(.{
            .cpu_arch = .x86,
            .os_tag = .linux,
            .abi = .musl,
            .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
        }),

        .source_file = "port/machine/x86/hosted-linux/hosted-linux.zig",
        .linker_script = "port/machine/x86/hosted-linux/linker.ld",
    },

    .@"x86-hosted-windows" = .{
        .target = constructTargetQuery(.{
            .cpu_arch = .x86,
            .os_tag = .windows,
            .abi = .gnu,
            .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
        }),

        .source_file = "port/machine/x86/hosted-windows/hosted-windows.zig",
        .linker_script = "port/machine/x86/hosted-windows/linker.ld",
    },
});

const generic_x86: std.Target.Query = .{
    .cpu_arch = .x86,
    .abi = .eabi,
    .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
    .cpu_features_add = std.Target.x86.featureSet(&.{
        .soft_float,
    }),
    .cpu_features_sub = std.Target.x86.featureSet(&.{
        .x87,
    }),
};

const generic_arm: std.Target.Query = .{
    .cpu_arch = .thumb,
    .abi = .eabi,
    .cpu_model = .{
        // .explicit = &std.Target.arm.cpu.cortex_a7, // this seems to be a pretty reasonable base line
        // .explicit = &std.Target.arm.cpu.generic,
        .explicit = &std.Target.arm.cpu.cortex_a7,
    },
    // .cpu_features_add = std.Target.arm.featureSet(&.{
    //     .v7a,
    // }),
    // .cpu_features_sub = std.Target.arm.featureSet(&.{
    //     .v7a, // this is stupid, but it keeps out all the neon stuff we don't wnat

    //     // drop everything FPU related:
    //     .neon,
    //     .neonfp,
    //     .neon_fpmovs,
    //     .fp64,
    //     .fpregs,
    //     .fpregs64,
    //     .vfp2,
    //     .vfp2sp,
    //     .vfp3,
    //     .vfp3d16,
    //     .vfp3d16sp,
    //     .vfp3sp,
    // }),
};

const arm_cortex_m33: std.Target.Query = .{
    .cpu_arch = .thumb,
    .abi = .eabi,
    .cpu_model = .{
        .explicit = &std.Target.arm.cpu.cortex_m33,
    },
    .cpu_features_sub = std.Target.arm.featureSet(&.{
        // Disable GPU in kernel
        .slowfpvfmx,
        .slowfpvmlx,
    }),
};

const generic_rv32: std.Target.Query = .{
    .cpu_arch = .riscv32,
    .abi = .eabi,
    .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
    .cpu_features_add = std.Target.riscv.featureSet(&[_]std.Target.riscv.Feature{
        .i, // integer
        .m, // multiplication
        .c, // compressed
        .zbb, // bit instructions
        .zicsr, // control registers
        // .reserve_x4, // Don't allow LLVM to use the "tp" register. We want that for our own purposes
    }),
};

fn renderMachineInfo(
    b: *std.Build,
    machine_id: Machine,
    platform_id: Platform,
    // machine_spec: *const build_targets.MachineSpec,
    // platform_spec: *const build_targets.PlatformSpec,
) ![]const u8 {
    var stream = std.ArrayList(u8).init(b.allocator);
    defer stream.deinit();

    const writer = stream.writer();

    try writer.writeAll("//! This is a machine-generated description of the Ashet OS target machine.\n\n");

    try writer.print("pub const machine_id = .{};\n", .{
        std.zig.fmtId(@tagName(machine_id)),
    });
    try writer.print("pub const machine_name = \"{}\";\n", .{
        std.zig.fmtEscapes(machine_id.get_display_name()),
    });
    try writer.print("pub const platform_id = .{};\n", .{
        std.zig.fmtId(@tagName(platform_id)),
    });
    try writer.print("pub const platform_name = \"{}\";\n", .{
        std.zig.fmtEscapes(platform_id.get_display_name()),
    });

    return try stream.toOwnedSlice();
}

fn serialize_patches(b: *std.Build, patches: []const regz.patch.Patch) []const u8 {
    var buf = std.ArrayList(u8).init(b.allocator);

    for (patches) |patch| {
        std.json.stringify(patch, .{}, buf.writer()) catch @panic("OOM");
        buf.writer().writeByte('\n') catch @panic("OOM");
    }

    return buf.toOwnedSlice() catch @panic("OOM");
}
