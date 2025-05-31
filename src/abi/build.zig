const std = @import("std");

const ports = @import("src/platforms.zig");

pub const Platform = ports.Platform;

const AbiConverter = @import("abi_mapper").Converter;

pub fn build(b: *std.Build) void {
    const debug = b.step("debug", "Installs the generated ABI V2 files");

    const regenerate_step = b.step("regenerate", "Regenerates the ABI JSON description");

    // generate and export the new v2 module:
    const abi_mapper_dep = b.dependency("abi_mapper", .{});
    const abi_mapper = AbiConverter{
        .b = b,
        .executable = abi_mapper_dep.artifact("abi-mapper"),
    };

    // Re-export the "abi-schema" module:
    const abi_schema_mod = abi_mapper_dep.module("abi-schema");
    b.modules.putNoClobber("abi-schema", abi_schema_mod) catch @panic("out of memory");

    const render_exe = b.addExecutable(.{
        .name = "render-abi-file",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("utility/render.zig"),
            .imports = &.{.{ .name = "abi-schema", .module = abi_schema_mod }},
        }),
    });

    b.installArtifact(render_exe);

    const abi_v2_def = b.path("src/abi.zabi");

    const abi_code = abi_mapper.convert_abi_file(abi_v2_def, .definition);
    const provider_code = abi_mapper.convert_abi_file(abi_v2_def, .kernel);
    const consumer_code = abi_mapper.convert_abi_file(abi_v2_def, .userland);
    const abi_json = abi_mapper.get_json_dump(abi_v2_def);

    const abi_mod = b.addModule("ashet-abi", .{
        .root_source_file = abi_code,
    });
    abi_mod.addAnonymousImport("async_running_call", .{
        .root_source_file = b.path("src/async_running_call.zig"),
    });
    abi_mod.addAnonymousImport("error_set", .{
        .root_source_file = b.path("src/error_set.zig"),
    });
    abi_mod.addAnonymousImport("platforms", .{
        .root_source_file = b.path("src/platforms.zig"),
    });

    _ = b.addModule("ashet-abi-provider", .{
        .root_source_file = provider_code,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });

    _ = b.addModule("ashet-abi-consumer", .{
        .root_source_file = consumer_code,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });

    _ = b.addModule("ashet-abi.json", .{
        .root_source_file = abi_json,
    });

    debug.dependOn(&b.addInstallFile(abi_code, "abi.zig").step);
    debug.dependOn(&b.addInstallFile(provider_code, "provider.zig").step);
    debug.dependOn(&b.addInstallFile(consumer_code, "consumer.zig").step);

    const update_sources = b.addUpdateSourceFiles();

    update_sources.addCopyFileToSource(abi_json, "src/ashet-abi.json");

    regenerate_step.dependOn(&update_sources.step);
}
