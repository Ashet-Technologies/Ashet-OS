const std = @import("std");

const ports = @import("src/platforms.zig");

pub const Platform = ports.Platform;

const AbiConverter = @import("abi_mapper").Converter;

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Runs the unit tests for the ABI types");

    // generate and export the new v2 module:
    const abi_mapper_dep = b.dependency("abi_mapper", .{});
    const abi_mapper = AbiConverter{
        .b = b,
        .executable = abi_mapper_dep.artifact("abi-parser"),
    };

    // Re-export the "abi-schema" module:
    const abi_parser_mod = abi_mapper_dep.module("abi-parser");
    b.modules.putNoClobber("abi-parser", abi_parser_mod) catch @panic("out of memory");

    const render_zig_exe = b.addExecutable(.{
        .name = "render-abi-file",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("utility/render_zig_code.zig"),
            .imports = &.{.{ .name = "abi-parser", .module = abi_parser_mod }},
        }),
    });
    b.installArtifact(render_zig_exe);

    const render_docs_exe = b.addExecutable(.{
        .name = "render-docs",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("utility/render_html.zig"),
            .imports = &.{.{ .name = "abi-parser", .module = abi_parser_mod }},
        }),
    });
    b.installArtifact(render_docs_exe);

    const abi_json = blk: {
        const abi_v2_def = b.path("src/ashet.abi");
        const abi_id_db = b.path("db/abi-id-db.json");

        const new_abi_json = abi_mapper.get_json_dump(abi_id_db, abi_v2_def);

        break :blk new_abi_json;
    };

    const install_json = b.addInstallFile(abi_json, "ashet-abi.json");

    b.getInstallStep().dependOn(&install_json.step);

    const docs_html = blk: {
        const generate_core_abi = b.addRunArtifact(render_docs_exe);
        generate_core_abi.addFileArg(abi_json);
        break :blk generate_core_abi.addOutputFileArg("ashet-os.html");
    };

    const create_docs_dir = b.addWriteFiles();
    _ = create_docs_dir.addCopyFile(docs_html, "index.html");
    _ = create_docs_dir.addCopyFile(b.path("docs/style.css"), "style.css");

    const docs_dir = create_docs_dir.getDirectory();

    b.addNamedLazyPath("html-docs", docs_dir);

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = docs_dir,
        .install_dir = .prefix,
        .install_subdir = "docs",
    }).step);

    const abi_code = convert_abi_file(b, render_zig_exe, abi_json, b.path("src/ports/zig.abi.zpatch"), .definition);
    const provider_code = convert_abi_file(b, render_zig_exe, abi_json, null, .kernel);

    const abi_mod = b.addModule("ashet-abi", .{ .root_source_file = abi_code });
    abi_mod.addAnonymousImport("platforms", .{ .root_source_file = b.path("src/platforms.zig") });

    _ = b.addModule("ashet-abi-provider", .{
        .root_source_file = provider_code,
        .imports = &.{.{ .name = "abi", .module = abi_mod }},
    });

    _ = b.addModule("ashet-abi.json", .{ .root_source_file = abi_json });
    b.addNamedLazyPath("ashet-abi.json", abi_json);

    const check_abi_code = b.addSystemCommand(&.{ b.graph.zig_exe, "ast-check" });
    check_abi_code.addFileArg(abi_code);

    const check_provider_code = b.addSystemCommand(&.{ b.graph.zig_exe, "ast-check" });
    check_provider_code.addFileArg(provider_code);

    const install_abi_code = b.addInstallFileWithDir(abi_code, .{ .custom = "binding/zig" }, "abi.zig");
    install_abi_code.step.dependOn(&check_abi_code.step);

    const install_provider_code = b.addInstallFileWithDir(provider_code, .{ .custom = "binding/zig" }, "provider.zig");
    install_provider_code.step.dependOn(&check_provider_code.step);

    b.getInstallStep().dependOn(&install_abi_code.step);
    b.getInstallStep().dependOn(&install_provider_code.step);

    const abi_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/ports/tests.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });

    const abi_tests_exe = b.addTest(.{
        .root_module = abi_tests_mod,
    });

    const abi_tests_run = b.addRunArtifact(abi_tests_exe);
    test_step.dependOn(&abi_tests_run.step);
}

pub fn convert_abi_file(b: *std.Build, render: *std.Build.Step.Compile, input: std.Build.LazyPath, patch: ?std.Build.LazyPath, mode: enum { kernel, definition }) std.Build.LazyPath {
    const generate_core_abi = b.addRunArtifact(render);
    generate_core_abi.addArg(@tagName(mode));
    generate_core_abi.addFileArg(input);
    const abi_zig = generate_core_abi.addOutputFileArg(b.fmt("{s}.zig", .{@tagName(mode)}));
    if (patch) |p|
        generate_core_abi.addFileArg(p);
    return abi_zig;
}
