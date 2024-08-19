const std = @import("std");

const ports = @import("src/platforms.zig");

pub const Platform = ports.Platform;

const AbiConverter = @import("abi_mapper").Converter;

pub fn build(b: *std.Build) void {
    const debug = b.step("debug", "Installs the generated ABI V2 files");

    // generate and export the new v2 module:
    const abi_mapper_dep = b.dependency("abi_mapper", .{});
    const abi_mapper = AbiConverter{
        .b = b,
        .executable = abi_mapper_dep.artifact("abi-mapper"),
    };

    const abi_v2_def = b.path("src/abi.zabi");

    const abi_code = abi_mapper.convert_abi_file(abi_v2_def, .definition);
    const provider_code = abi_mapper.convert_abi_file(abi_v2_def, .kernel);
    const consumer_code = abi_mapper.convert_abi_file(abi_v2_def, .userland);
    const stubs_code = abi_mapper.convert_abi_file(abi_v2_def, .stubs);

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

    _ = b.addModule("ashet-abi-stubs", .{
        .root_source_file = stubs_code,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });

    debug.dependOn(&b.addInstallFile(abi_code, "abi.zig").step);
    debug.dependOn(&b.addInstallFile(provider_code, "provider.zig").step);
    debug.dependOn(&b.addInstallFile(consumer_code, "consumer.zig").step);
    debug.dependOn(&b.addInstallFile(stubs_code, "stubs.zig").step);
}
