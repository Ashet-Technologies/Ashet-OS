const std = @import("std");

const ashet_abi = @import("abi");

pub const Target = ashet_abi.ApplicationTarget;

pub fn standardTargetOption(b: *std.Build) Target {
    return b.option(Target, "target", "Sets the machine to build for") orelse @panic("-Dtarget required!");
}

pub fn addExecutable(b: *std.Build, options: ExecutableOptions) *std.Build.Step.Compile {
    const zig_target = options.target.resolve(b);

    const exe = b.addExecutable(.{
        .name = options.name,
        .target = zig_target,
        .root_source_file = options.root_source_file,
        .version = options.version,
        .optimize = options.optimize,
        .code_model = options.code_model,
        .linkage = .dynamic,
        .max_rss = options.max_rss,
        .link_libc = options.link_libc,
        .single_threaded = true, // AshetOS doesn't support multithreading in a modern sense
        .pic = true, // which need PIC code
        .strip = options.strip orelse false, // Do not strip, not even in release modes.
        .unwind_tables = options.unwind_tables,
        .omit_frame_pointer = options.omit_frame_pointer orelse false, // do not emit frame pointer by default
        .sanitize_thread = false,
        .error_tracing = options.error_tracing,
        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .zig_lib_dir = options.zig_lib_dir,
        .win32_manifest = null,
    });

    exe.pie = true; // AshetOS requires PIE executables

    return exe;
}

pub fn build(b: *std.Build) void {
    // Options:
    const ashet_target = standardTargetOption(b);

    // Dependencies:
    const abi_dep = b.dependency("abi", .{});
    const std_dep = b.dependency("std", .{});

    // Modules:

    const abi_mod = abi_dep.module("ashet-abi");
    const std_mod = std_dep.module("ashet-std");

    // Build:

    const target = ashet_target.resolve(b);

    const libsyscall = b.addSharedLibrary(.{
        .name = "AshetOS",
        .target = target,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("libsyscall.zig"),
    });
    libsyscall.root_module.addImport("abi", abi_mod);
    b.installArtifact(libsyscall);

    _ = b.addModule("ashet", .{
        .root_source_file = b.path("libashet.zig"),
        .imports = &.{
            .{ .name = "ashet-abi", .module = abi_mod },
            .{ .name = "ashet-std", .module = std_mod },
        },
    });

    b.installLibFile("application.ld", "application.ld");
}

// Keep synchronized with std.Build.ExecutableOptions!
pub const ExecutableOptions = struct {
    name: []const u8,
    target: Target,
    root_source_file: ?std.Build.LazyPath = null,
    version: ?std.SemanticVersion = null,
    optimize: std.builtin.OptimizeMode = .Debug,
    code_model: std.builtin.CodeModel = .small,
    max_rss: usize = 0,
    link_libc: ?bool = null,
    strip: ?bool = null,
    unwind_tables: ?bool = null,
    omit_frame_pointer: ?bool = null,
    error_tracing: ?bool = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?std.Build.LazyPath = null,
};
