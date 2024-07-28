const std = @import("std");

const ports = @import("v1/platforms.zig");

pub const Platform = ports.Platform;

const AbiConverter = @import("abi_mapper").Converter;

pub fn build(b: *std.Build) void {

    // export the legacy module:
    {
        _ = b.addModule("ashet-abi", .{
            .root_source_file = b.path("v1/abi.zig"),
        });
    }

    // generate and export the new v2 module:
    {
        const abi_mapper_dep = b.dependency("abi_mapper", .{});
        const abi_mapper = AbiConverter{
            .b = b,
            .executable = abi_mapper_dep.artifact("abi-mapper"),
        };

        const abi_v2_def = b.path("v2/abi.zabi");

        const generated_abi_code = abi_mapper.convert_abi_file(abi_v2_def, .definition);
        const generated_provider_code = abi_mapper.convert_abi_file(abi_v2_def, .kernel);
        const generated_consumer_code = abi_mapper.convert_abi_file(abi_v2_def, .userland);
        const generated_stubs_code = abi_mapper.convert_abi_file(abi_v2_def, .stubs);

        const compose_abi_package = b.addNamedWriteFiles("abi-package");

        const abi_code = compose_abi_package.addCopyFile(generated_abi_code, "abi.zig");
        const provider_code = compose_abi_package.addCopyFile(generated_provider_code, "provider.zig");
        const consumer_code = compose_abi_package.addCopyFile(generated_consumer_code, "consumer.zig");
        const stubs_code = compose_abi_package.addCopyFile(generated_stubs_code, "stubs.zig");
        _ = compose_abi_package.addCopyFile(b.path("v2/error_set.zig"), "error_set.zig");
        _ = compose_abi_package.addCopyFile(b.path("v2/iops.zig"), "iops.zig");

        const abi_mod = b.addModule("ashet-abi-v2", .{
            .root_source_file = abi_code,
        });

        _ = b.addModule("ashet-abi-v2-provider", .{
            .root_source_file = provider_code,
            .imports = &.{
                .{ .name = "abi", .module = abi_mod },
            },
        });

        _ = b.addModule("ashet-abi-v2-consumer", .{
            .root_source_file = consumer_code,
            .imports = &.{
                .{ .name = "abi", .module = abi_mod },
            },
        });

        _ = b.addModule("ashet-abi-v2-stubs", .{
            .root_source_file = stubs_code,
            .imports = &.{
                .{ .name = "abi", .module = abi_mod },
            },
        });
    }
}
