const std = @import("std");

const ashet_abi = @import("abi");
const mkicon = @import("mkicon");

/// Applications target *platforms*, not explicit targets
/// like Zig does.
/// We just use the Ashet OS platform here.
pub const Target = ashet_abi.Platform;

pub fn standardTargetOption(b: *std.Build) Target {
    return b.option(Target, "target", "Sets the machine to build for") orelse @panic("-Dtarget required!");
}

pub const ExportedApp = struct {
    target_path: []const u8,
    ashex_file: std.Build.LazyPath,
    elf_file: std.Build.LazyPath,
};

/// Returns the list of exported applications for the given dependency
pub fn getApplications(dep: *std.Build.Dependency) []const ExportedApp {
    const write_files = dep.namedWriteFiles(AshetSdk.exported_app_writefiles_key);
    const elf_files = dep.namedWriteFiles(AshetSdk.exported_elf_writefiles_key);

    const apps = dep.builder.allocator.alloc(ExportedApp, write_files.files.items.len) catch @panic("out of memory");

    for (apps, write_files.files.items) |*app, writefile| {
        app.* = .{
            .ashex_file = writefile.contents.copy,
            .elf_file = for (elf_files.files.items) |file| {
                if (std.mem.eql(u8, file.sub_path, writefile.sub_path))
                    break file.contents.copy;
            } else unreachable,
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
        .syscall_library = get_named_file(dep.namedWriteFiles("files"), "libAshetOS.a"),
        .mkicon_exe = dep.artifact("mkicon"),

        .desktop_icon_conv_options = .{
            .geometry = .{ 32, 32 },
        },

        .app_files = b.addNamedWriteFiles("ashet.app.files"),
    };
    return sdk;
}

pub const AshetSdk = struct {
    pub const exported_app_writefiles_key = "ashet-os:apps";
    pub const exported_elf_writefiles_key = "ashet-os:elves";

    // Public properties:

    ashex_tool_exe: *std.Build.Step.Compile,
    mkicon_exe: *std.Build.Step.Compile,

    syscall_library: std.Build.LazyPath,
    ashet_module: *std.Build.Module,
    linker_script: std.Build.LazyPath,
    desktop_icon_conv_options: mkicon.ConvertOptions,
    app_files: *std.Build.Step.WriteFile,

    // Internals:
    owning_builder: *std.Build,
    dependency: *std.Build.Dependency,

    published_apps: ?*std.Build.Step.WriteFile = null,
    published_elves: ?*std.Build.Step.WriteFile = null,

    pub fn install_file(sdk: *AshetSdk, file: []const u8, path: std.Build.LazyPath) void {
        std.debug.assert(std.mem.startsWith(u8, file, "/"));
        _ = sdk.app_files.addCopyFile(path, file[1..]);
    }

    pub fn addApp(sdk: *AshetSdk, options: ExecutableOptions) *AshetApp {
        const b = sdk.owning_builder;

        const zig_target: std.Build.ResolvedTarget = options.target.resolve_target(b);

        const file_name = b.fmt("{s}.ashex", .{options.name});

        const exe = b.addExecutable(.{
            .name = options.name,
            .target = zig_target,
            .root_source_file = options.root_source_file,
            .version = options.version,
            .optimize = options.optimize,
            .code_model = options.code_model,
            .linkage = .static, // AshetOS ELF executables are statically linked, as Ashex uses a non-standard dynamic linking procedure.
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

        // if (zig_target.result.cpu.arch.isThumb()) {
        //     // Disable LTO on arm as it fails hard
        //     exe.want_lto = false;
        // }

        exe.pie = true; // AshetOS requires PIE executables

        exe.addObjectFile(sdk.syscall_library);
        exe.setLinkerScript(sdk.linker_script);

        if (options.os_module_import) |os_module_import| {
            exe.root_module.addImport(os_module_import, sdk.ashet_module);
        }

        const convert_to_ashex = b.addRunArtifact(sdk.ashex_tool_exe);
        convert_to_ashex.addArg("convert");

        const maybe_icon_file: ?std.Build.LazyPath = switch (options.icon) {
            .none => null,
            .abm => |path| path,
            .convert => |raw_image| blk: {
                const converter: mkicon.Converter = .{
                    .builder = b,
                    .exe = sdk.mkicon_exe,
                };
                break :blk converter.convert(raw_image, b.fmt("{s}.abm", .{options.name}), sdk.desktop_icon_conv_options);
            },
        };

        if (maybe_icon_file) |icon_file| {
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
        if (sdk.published_elves == null) {
            sdk.published_elves = b.addNamedWriteFiles(exported_elf_writefiles_key);
        }

        _ = sdk.published_apps.?.addCopyFile(
            app.app_file,
            target_file_name,
        );
        _ = sdk.published_elves.?.addCopyFile(
            app.exe.getEmittedBin(),
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
    icon: IconSource = .none,

    root_source_file: ?std.Build.LazyPath = null,
    version: ?std.SemanticVersion = null,
    optimize: std.builtin.OptimizeMode = .Debug,
    code_model: std.builtin.CodeModel = .small,
    max_rss: usize = 0,
    link_libc: ?bool = null,
    strip: ?bool = null,
    unwind_tables: ?std.builtin.UnwindTables = null,
    omit_frame_pointer: ?bool = null,
    error_tracing: ?bool = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?std.Build.LazyPath = null,

    pub const IconSource = union(enum) {
        none,
        abm: std.Build.LazyPath,
        convert: std.Build.LazyPath,
    };
};

pub fn build(b: *std.Build) void {

    // Targets:
    const debug_step = b.step("debug", "Installs a debug executable for disassembly");

    // Options:
    const modules_only = b.option(bool, "module_only", "Only export the module") orelse false;
    const maybe_ashet_target = if (!modules_only) standardTargetOption(b) else null;

    // Dependencies:
    const abi_dep = b.dependency("abi", .{});
    const ashex_dep = b.dependency("ashex", .{});
    const mkicon_dep = b.dependency("mkicon", .{});
    const module_dep = b.dependency("libashet", .{});

    // Modules:

    const abi_json_mod = abi_dep.module("ashet-abi.json");
    const abi_parser_mod = abi_dep.module("abi-parser");

    const libashet_mod = module_dep.module("ashet");

    b.modules.put("ashet", libashet_mod) catch @panic("out of memory");

    const ashet_target = maybe_ashet_target orelse return;

    // External tooling:
    const ashet_exe_tool = ashex_dep.artifact("ashet-exe");
    b.installArtifact(ashet_exe_tool);

    const image_converter = mkicon_dep.artifact("mkicon");
    b.installArtifact(image_converter);

    // Build:

    const gen_binding_exe = b.addExecutable(.{
        .name = "gen_abi_binding",
        .target = b.graph.host,
        .optimize = .Debug,
        .root_source_file = b.path("src/gen-libsyscall.zig"),
    });
    gen_binding_exe.root_module.addImport("abi-parser", abi_parser_mod);

    const zig_binding = b.addRunArtifact(gen_binding_exe);
    zig_binding.addFileArg(abi_json_mod.root_source_file.?);
    zig_binding.addDirectoryArg(abi_dep.path("."));

    const lib_build_dir = zig_binding.addOutputDirectoryArg("binding-library");

    debug_step.dependOn(
        &b.addInstallDirectory(.{
            .source_dir = lib_build_dir,
            .install_dir = .{ .custom = "libsyscall.build" },
            .install_subdir = ".",
        }).step,
    );

    const target = ashet_target.resolve_target(b);

    const sub_build = b.addSystemCommand(&.{ b.graph.zig_exe, "build-lib" });

    sub_build.addArg("-static");
    sub_build.addArg("-fPIC");
    sub_build.addArg("-O");
    sub_build.addArg("ReleaseSmall");
    sub_build.addArg("--name");
    sub_build.addArg("libAshetOS");
    sub_build.addArg("-target");
    sub_build.addArg(target.query.zigTriple(b.allocator) catch @panic("oom"));
    sub_build.addArg("-mcpu");
    sub_build.addArg(target.query.serializeCpuAlloc(b.allocator) catch @panic("oom"));

    switch (ashet_target) {
        .arm => sub_build.addArg("-DPLATFORM_THUMB"),
        .rv32 => sub_build.addArg("-DPLATFORM_RISCV32"),
        .x86 => sub_build.addArg("-DPLATFORM_X86"),
    }

    sub_build.addPrefixedFileArg("@", lib_build_dir.path(b, "assembly-files.rsp"));

    const libsyscall_path = sub_build.addPrefixedOutputFileArg("-femit-bin=", "libAshetOS.a");

    const debug_exe = b.addExecutable(.{
        .name = b.fmt("libAshetOS.{s}", .{@tagName(ashet_target)}),
        .root_source_file = b.path("src/binding-test.zig"),
        .optimize = .ReleaseFast,
        .target = target,
        .pic = true,
        .linkage = .static,
    });
    debug_exe.pie = true;
    debug_exe.want_lto = false;
    debug_exe.link_gc_sections = false;
    debug_exe.addObjectFile(libsyscall_path);

    const install_debug_exe = b.addInstallArtifact(debug_exe, .{});
    debug_step.dependOn(&install_debug_exe.step);

    b.getInstallStep().dependOn(
        &b.addInstallFileWithDir(
            libsyscall_path,
            .lib,
            "libAshetOS.a",
        ).step,
    );
    b.installLibFile("application.ld", "application.ld");

    const exported_files = b.addNamedWriteFiles("files");
    _ = exported_files.addCopyFile(
        libsyscall_path,
        "libAshetOS.a",
    );
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
