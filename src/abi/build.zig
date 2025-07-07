const std = @import("std");

const ports = @import("src/platforms.zig");

pub const Platform = ports.Platform;

const AbiConverter = @import("abi_mapper").Converter;

pub fn build(b: *std.Build) void {
    const debug = b.step("debug", "Installs the generated ABI V2 files");

    _ = debug;

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

    b.getInstallStep().dependOn(
        &b.addInstallFileWithDir(docs_html, .{ .custom = "docs" }, "index.html").step,
    );
    b.getInstallStep().dependOn(
        &b.addInstallFileWithDir(b.path("docs/style.css"), .{ .custom = "docs" }, "style.css").step,
    );

    const abi_code = convert_abi_file(b, render_zig_exe, abi_json, .definition);
    const provider_code = convert_abi_file(b, render_zig_exe, abi_json, .kernel);
    // const consumer_code = convert_abi_file(b, render_zig_exe, abi_json, .userland);

    const abi_mod = b.addModule("ashet-abi", .{ .root_source_file = abi_code });
    // abi_mod.addAnonymousImport("async_running_call", .{ .root_source_file = b.path("src/async_running_call.zig") });
    // abi_mod.addAnonymousImport("error_set", .{ .root_source_file = b.path("src/error_set.zig") });
    // abi_mod.addAnonymousImport("platforms", .{ .root_source_file = b.path("src/platforms.zig") });

    _ = b.addModule("ashet-abi-provider", .{
        .root_source_file = provider_code,
        .imports = &.{.{ .name = "api", .module = abi_mod }},
    });

    // _ = b.addModule("ashet-abi-consumer", .{
    //     .root_source_file = consumer_code,
    //     .imports = &.{.{ .name = "abi", .module = abi_mod }},
    // });

    _ = b.addModule("ashet-abi.json", .{ .root_source_file = abi_json });

    const check_abi_code = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "ast-check",
    });
    check_abi_code.addFileArg(abi_code);

    const check_provider_code = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "ast-check",
    });
    check_provider_code.addFileArg(provider_code);

    const install_abi_code = b.addInstallFileWithDir(abi_code, .{ .custom = "binding/zig" }, "abi.zig");
    // install_abi_code.step.dependOn(&check_abi_code.step);

    const install_provider_code = b.addInstallFileWithDir(provider_code, .{ .custom = "binding/zig" }, "provider.zig");
    // install_provider_code.step.dependOn(&check_provider_code.step);

    b.getInstallStep().dependOn(&install_abi_code.step);
    b.getInstallStep().dependOn(&install_provider_code.step);

    // b.getInstallStep().dependOn(
    //     &b.addInstallFileWithDir(consumer_code, .{}, "consumer.zig").step,
    // );
}

pub fn convert_abi_file(b: *std.Build, render: *std.Build.Step.Compile, input: std.Build.LazyPath, mode: enum { userland, kernel, definition, stubs }) std.Build.LazyPath {
    const generate_core_abi = b.addRunArtifact(render);
    generate_core_abi.addArg(@tagName(mode));
    generate_core_abi.addFileArg(input);
    const abi_zig = generate_core_abi.addOutputFileArg(b.fmt("{s}.zig", .{@tagName(mode)}));
    return abi_zig;
}
