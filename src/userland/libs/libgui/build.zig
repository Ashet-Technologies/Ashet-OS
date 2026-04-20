const std = @import("std");

pub fn build(b: *std.Build) void {
    const ashet_dep = b.dependency("AshetOS", .{ .module_only = true });
    const ashet_mod = ashet_dep.module("ashet");
    const test_step = b.step("test", "Runs libgui tests");

    _ = b.addModule("gui", .{
        .root_source_file = b.path("src/libgui.zig"),
        .imports = &.{
            .{ .name = "ashet", .module = ashet_mod },
            // .{ .name = "text-editor", .module = texteditor_mod },
        },
    });

    const parser_exe = b.addExecutable(.{
        .name = "widget-def-parser",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("tools/widget-def-parser.zig"),
        }),
    });
    b.installArtifact(parser_exe);

    const generate_json = b.addRunArtifact(parser_exe);
    generate_json.addFileArg(b.path("src/standard-widgets.def"));
    const widget_json = generate_json.addPrefixedOutputFileArg("--output=", "standard-widgets.json");

    b.addNamedLazyPath("standard-widgets.json", widget_json);

    const install_json = b.addInstallFile(widget_json, "standard-widgets.json");
    b.getInstallStep().dependOn(&install_json.step);

    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("tools/widget-def-parser.zig"),
        }),
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    test_step.dependOn(&run_parser_tests.step);
}
