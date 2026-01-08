const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const mqjs = b.dependency("mqjs", .{
        .target = target.resolve_target(b),
        .optimize = .ReleaseSafe,
    });

    const mqjs_mod = mqjs.module("mqjs");

    const app = sdk.addApp(.{
        .name = "hello-world",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("hello-world.zig"),
        .code_model = .default, // C code fails with clang error ".small not found"
        .link_libc = true,
    });

    app.exe.root_module.addImport("mqjs", mqjs_mod);

    sdk.installApp(app, .{});
}
