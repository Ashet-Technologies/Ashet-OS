const std = @import("std");

const ashet_abi = @import("abi");

/// Applications target *platforms*, not explicit targets
/// like Zig does.
/// We just use the Ashet OS platform here.
pub const Target = ashet_abi.Platform;

pub fn standardTargetOption(b: *std.Build) Target {
    return b.option(Target, "target", "Sets the machine to build for") orelse @panic("-Dtarget required!");
}

pub const ExportedApp = struct {
    target_path: []const u8,
    file: std.Build.LazyPath,
};

/// Returns the list of exported applications for the given dependency
pub fn getApplications(dep: *std.Build.Dependency) []const ExportedApp {
    const write_files = dep.namedWriteFiles(AshetSdk.exported_app_writefiles_key);

    const apps = dep.builder.allocator.alloc(ExportedApp, write_files.files.items.len) catch @panic("out of memory");

    for (apps, write_files.files.items) |*app, writefile| {
        app.* = .{
            .file = writefile.contents.copy,
            .target_path = writefile.sub_path,
        };
    }

    return apps;
}

pub fn init(b: *std.Build, dependency_name: []const u8, args: struct {
    target: Target,
}) *AshetSdk {
    const dep = b.dependency(dependency_name, args);
    const sdk = b.allocator.create(AshetSdk) catch @panic("out of memory");
    sdk.* = .{
        .owning_builder = b,
        .dependency = dep,

        .ashex_tool_exe = dep.artifact("ashet-exe"),
        .ashet_module = dep.module("ashet"),
        .linker_script = dep.path("application.ld"),
        .syscall_library = dep.artifact("AshetOS"),
    };
    return sdk;
}

pub const AshetSdk = struct {
    pub const exported_app_writefiles_key = "ashet-os:apps";

    // Public properties:

    ashex_tool_exe: *std.Build.Step.Compile,

    syscall_library: *std.Build.Step.Compile,
    ashet_module: *std.Build.Module,
    linker_script: std.Build.LazyPath,

    // Internals:
    owning_builder: *std.Build,
    dependency: *std.Build.Dependency,

    published_apps: ?*std.Build.Step.WriteFile = null,

    pub fn addApp(sdk: *AshetSdk, options: ExecutableOptions) *AshetApp {
        const b = sdk.owning_builder;

        const zig_target = options.target.resolve_target(b);

        const file_name = b.fmt("{s}.ashex", .{options.name});

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

        exe.linkLibrary(sdk.syscall_library);
        exe.setLinkerScript(sdk.linker_script);

        if (options.os_module_import) |os_module_import| {
            exe.root_module.addImport(os_module_import, sdk.ashet_module);
        }

        const convert_to_ashex = b.addRunArtifact(sdk.ashex_tool_exe);

        if (options.icon_file) |icon_file| {
            convert_to_ashex.addPrefixedFileArg("--icon=", icon_file);
        }

        const ashex_file = convert_to_ashex.addPrefixedOutputFileArg("--output=", file_name);

        convert_to_ashex.addFileArg(exe.getEmittedBin());

        const app = sdk.owning_builder.allocator.create(AshetApp) catch @panic("out of memory");
        app.* = AshetApp{
            .exe = exe,
            .app_file = ashex_file,
            .file_name = file_name,
        };
        return app;
    }

    pub fn installApp(sdk: *AshetSdk, app: *AshetApp, options: InstallAppOptions) void {
        const target_file_name = if (options.sub_folder) |sub_folder|
            std.mem.join(
                sdk.owning_builder.allocator,
                "/",
                &.{
                    std.mem.trim(u8, sub_folder, "/"),
                    app.file_name,
                },
            ) catch @panic("out of memory")
        else
            app.file_name;

        const b = sdk.owning_builder;

        if (sdk.published_apps == null) {
            sdk.published_apps = b.addNamedWriteFiles(exported_app_writefiles_key);
        }

        const target_step = sdk.published_apps.?;
        _ = target_step.addCopyFile(
            app.app_file,
            target_file_name,
        );

        b.installArtifact(app.exe);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            app.app_file,
            .{ .custom = "apps" },
            target_file_name,
        ).step);
    }
};

pub const InstallAppOptions = struct {
    sub_folder: ?[]const u8 = null,
};

pub const AshetApp = struct {
    file_name: []const u8,
    exe: *std.Build.Step.Compile,
    app_file: std.Build.LazyPath,
};

// Keep synchronized with std.Build.ExecutableOptions!
pub const ExecutableOptions = struct {
    /// Defines the name of the executable file
    name: []const u8,

    /// Specifies for which AshetOS platform the executable will be
    /// compiled.
    target: Target,

    /// If given, the AshetOS module will be imported with this name
    /// on the root module of the executable
    os_module_import: ?[]const u8 = "ashet",

    /// If given, will embed the provided file into the generated application
    icon_file: ?std.Build.LazyPath = null,

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

pub fn build(b: *std.Build) void {
    // Options:
    const ashet_target = standardTargetOption(b);

    // Dependencies:
    const abi_dep = b.dependency("abi", .{});
    const std_dep = b.dependency("std", .{});
    const agp_dep = b.dependency("agp", .{});
    const ashex_dep = b.dependency("ashex", .{});

    // Modules:

    const std_mod = std_dep.module("ashet-std");
    const agp_mod = agp_dep.module("agp");

    const abi_mod = abi_dep.module("ashet-abi");
    const abi_access_mod = abi_dep.module("ashet-abi-consumer");
    const abi_stubs_mod = abi_dep.module("ashet-abi-stubs");

    // External tooling:

    const ashet_exe_tool = ashex_dep.artifact("ashet-exe");
    b.installArtifact(ashet_exe_tool);

    // Build:

    const target = ashet_target.resolve_target(b);

    const libsyscall = b.addSharedLibrary(.{
        .name = "AshetOS",
        .target = target,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/libsyscall.zig"),
    });
    libsyscall.root_module.addImport("abi", abi_mod);
    libsyscall.root_module.addImport("stubs", abi_stubs_mod);
    b.installArtifact(libsyscall);

    _ = b.addModule("ashet", .{
        .root_source_file = b.path("src/libashet.zig"),
        .imports = &.{
            .{ .name = "agp", .module = agp_mod },
            .{ .name = "ashet-std", .module = std_mod },
            .{ .name = "ashet-abi", .module = abi_mod },
            .{ .name = "ashet-abi-access", .module = abi_access_mod },
        },
    });

    b.installLibFile("application.ld", "application.ld");
}
