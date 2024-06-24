const std = @import("std");

pub const ApplicationTarget = enum {
    x86,
    arm,
    rv32,

    pub fn resolve(target: ApplicationTarget, b: *std.Build) std.Build.ResolvedTarget {
        return convertApplicationTarget(b, target);
    }
};

pub fn build(b: *std.Build) void {
    _ = b.addModule("ashet-abi", .{
        .root_source_file = b.path("abi.zig"),
    });
}

fn convertApplicationTarget(b: *std.Build, target: ApplicationTarget) std.Build.ResolvedTarget {
    const target_query = app_target_map.get(target);
    return b.resolveTargetQuery(target_query);
}

fn constructTargetQuery(spec: std.Target.Query) std.Target.Query {
    var base: std.Target.Query = spec;

    std.debug.assert(base.dynamic_linker.len == 0);
    std.debug.assert(base.os_tag == null);
    std.debug.assert(base.ofmt == null);

    base.dynamic_linker = std.Target.DynamicLinker.init("KERNEL:/runtime/dynamic-linker");
    base.os_tag = .other;
    base.ofmt = .elf;

    return base;
}

const app_target_map = std.EnumArray(ApplicationTarget, std.Target.Query).init(.{
    .x86 = constructTargetQuery(.{
        .cpu_arch = .x86,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
        .cpu_features_add = std.Target.x86.featureSet(&.{
            .soft_float,
        }),
        .cpu_features_sub = std.Target.x86.featureSet(&.{
            .x87,
        }),
    }),

    .arm = constructTargetQuery(.{
        .cpu_arch = .thumb,
        .abi = .eabi,
        .cpu_model = .{
            // .explicit = &std.Target.arm.cpu.cortex_a7, // this seems to be a pretty reasonable base line
            .explicit = &std.Target.arm.cpu.generic,
        },
        .cpu_features_add = std.Target.arm.featureSet(&.{
            .v7a,
        }),
        .cpu_features_sub = std.Target.arm.featureSet(&.{
            .v7a, // this is stupid, but it keeps out all the neon stuff we don't wnat

            // drop everything FPU related:
            .neon,
            .neonfp,
            .neon_fpmovs,
            .fp64,
            .fpregs,
            .fpregs64,
            .vfp2,
            .vfp2sp,
            .vfp3,
            .vfp3d16,
            .vfp3d16sp,
            .vfp3sp,
        }),
    }),

    .rv32 = constructTargetQuery(.{
        .cpu_arch = .riscv32,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = std.Target.riscv.featureSet(&[_]std.Target.riscv.Feature{
            .c,
            .m,
            .reserve_x4, // Don't allow LLVM to use the "tp" register. We want that for our own purposes
        }),
    }),
});