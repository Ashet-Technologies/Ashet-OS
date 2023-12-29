const std = @import("std");

const FatFS = @import("zfat");

const ashet_com = @import("os-common.zig");
const ashet_lwip = @import("lwip.zig");

const machines = @import("../kernel/machine/all.zig");
const MachineSpec = machines.MachineSpec;

pub const KernelOptions = struct {
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    fatfs_config: FatFS.Config,
    machine_spec: MachineSpec,
    modules: ashet_com.Modules,
    system_assets: *std.Build.Module,
};

fn writeMachineSpec(writer: anytype, machine_spec: MachineSpec) !void {
    try writer.writeAll("//! This is a machine-generated description of the Ashet OS target machine.\n\n");

    try writer.print("pub const machine = @import(\"root\").machines.all.{};\n", .{
        std.zig.fmtId(machine_spec.machine_id),
    });
    try writer.print("pub const platform = @import(\"root\").platforms.all.{};\n", .{
        std.zig.fmtId(machine_spec.platform.platform_id),
    });

    try writer.print("pub const machine_name = \"{}\";\n", .{
        std.zig.fmtEscapes(machine_spec.name),
    });
    try writer.print("pub const platform_name = \"{}\";\n", .{
        std.zig.fmtEscapes(machine_spec.platform.name),
    });
}

pub fn create(b: *std.Build, options: KernelOptions) *std.Build.Step.Compile {
    const cguana_dep = b.anonymousDependency("vendor/ziglibc", @import("../../vendor/ziglibc/build.zig"), .{
        .target = options.target,
        .optimize = .ReleaseSafe,

        .static = true,
        .dynamic = false,
        .start = .none,
        .trace = false,

        .cstd = true,
        .posix = false,
        .gnu = false,
        .linux = false,
    });

    const ashet_libc = cguana_dep.artifact("cguana");

    const machine_pkg = b.addWriteFile("machine.zig", blk: {
        var stream = std.ArrayList(u8).init(b.allocator);
        defer stream.deinit();

        writeMachineSpec(stream.writer(), options.machine_spec) catch @panic("out of memory!");

        break :blk stream.toOwnedSlice() catch @panic("out of memory");
    });

    const kernel_exe = b.addExecutable(.{
        .name = "ashet-os",
        .root_source_file = .{ .path = "src/kernel/main.zig" },
        .target = options.target,
        .optimize = options.optimize,
    });

    kernel_exe.code_model = .small;
    kernel_exe.bundle_compiler_rt = true;
    kernel_exe.rdynamic = true; // Prevent the compiler from garbage collecting exported symbols
    kernel_exe.single_threaded = true;
    kernel_exe.omit_frame_pointer = false;
    kernel_exe.strip = false; // never strip debug info
    if (options.optimize == .Debug) {
        // we always want frame pointers in debug build!
        kernel_exe.omit_frame_pointer = false;
    }

    kernel_exe.addModule("system-assets", options.system_assets);
    kernel_exe.addModule("ashet-abi", options.modules.ashet_abi);
    kernel_exe.addModule("ashet-std", options.modules.ashet_std);
    kernel_exe.addModule("ashet", options.modules.libashet);
    kernel_exe.addModule("ashet-gui", options.modules.ashet_gui);
    kernel_exe.addModule("virtio", options.modules.virtio);
    kernel_exe.addModule("ashet-fs", options.modules.libashetfs);
    kernel_exe.addModule("args", options.modules.args);
    kernel_exe.addAnonymousModule("machine", .{
        .source_file = machine_pkg.files.items[0].getFileSource(),
    });
    kernel_exe.addModule("fatfs", options.modules.fatfs);
    kernel_exe.setLinkerScriptPath(.{ .path = options.machine_spec.linker_script });

    kernel_exe.addSystemIncludePath(.{ .path = "vendor/ziglibc/inc/libc" });

    FatFS.link(kernel_exe, options.fatfs_config);

    kernel_exe.linkLibrary(ashet_libc);

    {
        const lwip = ashet_lwip.create(b, kernel_exe.target, .ReleaseSafe);
        lwip.is_linking_libc = false;
        lwip.strip = false;
        lwip.addSystemIncludePath(.{ .path = "vendor/ziglibc/inc/libc" });
        kernel_exe.linkLibrary(lwip);
        ashet_lwip.setup(kernel_exe);
    }

    return kernel_exe;
}
