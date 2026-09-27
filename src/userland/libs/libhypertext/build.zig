const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run libhypertext unit tests");
    const run_step = b.step("run", "Run the hypertext rendering test project");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ashet_dep = b.dependency("AshetOS", .{ .module_only = true });
    const hyperdoc_dep = b.dependency("hyperdoc", .{});
    const demosuite_dep = b.dependency("agp_demosuite", .{ .target = target, .optimize = optimize });
    const args_dep = b.dependency("args", .{});

    const ashet_mod = ashet_dep.module("ashet");
    const hyperdoc_mod = hyperdoc_dep.module("hyperdoc");

    const hypertext_mod = b.addModule("hypertext", .{
        .root_source_file = b.path("src/hypertext.zig"),
        .imports = &.{
            .{ .name = "ashet", .module = ashet_mod },
            .{ .name = "hyperdoc", .module = hyperdoc_mod },
        },
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/hypertext.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ashet", .module = ashet_mod },
                .{ .name = "hyperdoc", .module = hyperdoc_mod },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const render = b.addExecutable(.{
        .name = "hdoc-render",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/hdoc-render.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "hypertext", .module = hypertext_mod },
                .{ .name = "agp-demosuite", .module = demosuite_dep.module("agp-demosuite") },
                .{ .name = "args", .module = args_dep.module("args") },
            },
        }),
    });
    b.installArtifact(render);

    const run = b.addRunArtifact(render);
    if (b.args) |args| run.addArgs(args);
    run_step.dependOn(&run.step);
}
