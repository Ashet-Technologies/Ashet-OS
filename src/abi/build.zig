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

    // const render_exe = b.addExecutable(.{
    //     .name = "render-abi-file",
    //     .root_module = b.createModule(.{
    //         .target = b.graph.host,
    //         .optimize = .Debug,
    //         .root_source_file = b.path("utility/render.zig"),
    //         .imports = &.{.{ .name = "abi-parser", .module = abi_parser_mod }},
    //     }),
    // });

    // b.installArtifact(render_exe);

    const abi_json = blk: {
        const abi_v2_def = b.path("src/ashet.abi");
        const abi_id_db = b.path("db/abi-id-db.json");

        const new_abi_json = abi_mapper.get_json_dump(abi_id_db, abi_v2_def);

        break :blk new_abi_json;
    };

    const install_json = b.addInstallFile(abi_json, "ashet-abi.json");

    b.getInstallStep().dependOn(&install_json.step);

    // const abi_code = convert_abi_file(b, render_exe, abi_json, .definition);
    // const provider_code = convert_abi_file(b, render_exe, abi_json, .kernel);
    // const consumer_code = convert_abi_file(b, render_exe, abi_json, .userland);

    // const abi_mod = b.addModule("ashet-abi", .{ .root_source_file = abi_code });
    // abi_mod.addAnonymousImport("async_running_call", .{ .root_source_file = b.path("src/async_running_call.zig") });
    // abi_mod.addAnonymousImport("error_set", .{ .root_source_file = b.path("src/error_set.zig") });
    // abi_mod.addAnonymousImport("platforms", .{ .root_source_file = b.path("src/platforms.zig") });

    // _ = b.addModule("ashet-abi-provider", .{
    //     .root_source_file = provider_code,
    //     .imports = &.{.{ .name = "abi", .module = abi_mod }},
    // });

    // _ = b.addModule("ashet-abi-consumer", .{
    //     .root_source_file = consumer_code,
    //     .imports = &.{.{ .name = "abi", .module = abi_mod }},
    // });

    _ = b.addModule("ashet-abi.json", .{ .root_source_file = abi_json });

    // debug.dependOn(&b.addInstallFile(abi_code, "abi.zig").step);
    // debug.dependOn(&b.addInstallFile(provider_code, "provider.zig").step);
    // debug.dependOn(&b.addInstallFile(consumer_code, "consumer.zig").step);
}

pub fn convert_abi_file(b: *std.Build, render: *std.Build.Step.Compile, input: std.Build.LazyPath, mode: enum { userland, kernel, definition, stubs }) std.Build.LazyPath {
    const generate_core_abi = b.addRunArtifact(render);
    generate_core_abi.addArg(@tagName(mode));
    generate_core_abi.addFileArg(input);
    const abi_zig = generate_core_abi.addOutputFileArg(b.fmt("{s}.zig", .{@tagName(mode)}));
    return abi_zig;
}
