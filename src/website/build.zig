const std = @import("std");

const kernel_package = @import("kernel");

const Machine = kernel_package.Machine;

// - os.ashet.computer
//     - Landing Page: /
//         - Overview
//         - Links to sub pages
//     - Syscall Documentation: /syscalls
//     - Live Demo: /try
//         - Live Demo
//         - x86 Build
//         - x86 Disk Image
//         - x86.js Setup
//     - Kernel Documentation: /kernel
//         - Autodocs

pub fn build(b: *std.Build) void {
    const install_step = b.getInstallStep();

    const os_dep = b.dependency("os", .{
        .@"optimize-kernel" = true,
        .@"optimize-apps" = .ReleaseFast,
        .machine = Machine.@"x86-pc-generic",
    });

    const abi_dep = b.dependency("abi", .{});

    const hyperdoc_dep = b.dependency("hyperdoc", .{});

    const hyperdoc_mod = hyperdoc_dep.module("hyperdoc");

    const wiki_conv_exe = b.addExecutable(.{
        .name = "wiki-conv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wiki-conv.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "hyperdoc", .module = hyperdoc_mod },
            },
        }),
    });

    const conv_wiki_proc = b.addRunArtifact(wiki_conv_exe);
    conv_wiki_proc.addDirectoryArg(b.path("../../rootfs/all-systems/wiki"));
    const html_wiki_dir = conv_wiki_proc.addOutputDirectoryArg("wiki");

    const os_files = os_dep.namedWriteFiles("ashet-os");

    const disk_img = get_named_file(os_files, "disk.img");

    install_step.dependOn(&b.addInstallFile(disk_img, "try/images/livedemo.img").step);
    install_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = abi_dep.namedLazyPath("html-docs"),
        .install_dir = .prefix,
        .install_subdir = "syscalls",
    }).step);
    install_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = html_wiki_dir,
        .install_dir = .prefix,
        .install_subdir = "wiki",
    }).step);

    install_step.dependOn(&b.addInstallFile(b.path("www/CRT.png"), "try/img/crt.png").step);
    install_step.dependOn(&b.addInstallFile(b.path("www/try.html"), "try/index.html").step);

    install_step.dependOn(&b.addInstallFile(b.path("vendor/v86/libv86.js"), "try/v86/libv86.js").step);
    install_step.dependOn(&b.addInstallFile(b.path("vendor/v86/v86.wasm"), "try/v86/v86.wasm").step);
    install_step.dependOn(&b.addInstallFile(b.path("vendor/bios/seabios.bin"), "try/bios/seabios.bin").step);
    install_step.dependOn(&b.addInstallFile(b.path("vendor/bios/vgabios.bin"), "try/bios/vgabios.bin").step);
}

fn get_optional_named_file(write_files: *std.Build.Step.WriteFile, sub_path: []const u8) ?std.Build.LazyPath {
    for (write_files.files.items) |file| {
        if (path_eql(file.sub_path, sub_path))
            return .{
                .generated = .{
                    .file = &write_files.generated_directory,
                    .sub_path = file.sub_path,
                },
            };
    }
    return null;
}

fn get_named_file(write_files: *std.Build.Step.WriteFile, sub_path: []const u8) std.Build.LazyPath {
    if (get_optional_named_file(write_files, sub_path)) |path|
        return path;

    std.debug.print("missing file '{s}' in dependency '{s}:{s}'. available files are:\n", .{
        sub_path,
        std.mem.trimRight(u8, write_files.step.owner.dep_prefix, "."),
        write_files.step.name,
    });
    for (write_files.files.items) |file| {
        std.debug.print("- '{s}'\n", .{file.sub_path});
    }
    std.process.exit(1);
}

fn path_eql(lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len)
        return false;
    for (lhs, rhs) |l, r| {
        if (std.fs.path.isSep(l) and std.fs.path.isSep(r))
            continue;
        if (l != r)
            return false;
    }
    return true;
}
