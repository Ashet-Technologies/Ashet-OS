const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Runs libgui tests");

    _ = b.addModule("gui", .{
        .root_source_file = b.path("src/libgui.zig"),
        .imports = &.{
            // .{ .name = "text-editor", .module = texteditor_mod },
        },
    });

    const widget_model_mod = b.addModule("widgets-model", .{
        .root_source_file = b.path("tools/widget-def-model.zig"),
    });

    const parser_mod = b.createModule(.{
        .target = b.graph.host,
        .optimize = .Debug,
        .root_source_file = b.path("tools/widget-def-parser.zig"),
        .imports = &.{
            .{ .name = "widget-model", .module = widget_model_mod },
        },
    });

    const parser_exe = b.addExecutable(.{
        .name = "widget-def-parser",
        .root_module = parser_mod,
    });
    b.installArtifact(parser_exe);

    const generate_json = b.addRunArtifact(parser_exe);
    generate_json.addFileArg(b.path("src/standard-widgets.def"));
    const widget_json = generate_json.addPrefixedOutputFileArg("--output=", "standard-widgets.json");

    b.addNamedLazyPath("standard-widgets.json", widget_json);

    const install_json = b.addInstallFile(widget_json, "standard-widgets.json");
    b.getInstallStep().dependOn(&install_json.step);

    const parser_tests = b.addTest(.{
        .root_module = parser_mod,
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    test_step.dependOn(&run_parser_tests.step);
}
