const std = @import("std");

const BitmapConverter = @This();

builder: *std.Build,
converter: *std.Build.Step.Compile,

pub fn init(b: *std.Build) BitmapConverter {
    const zig_args_module = b.dependency("args", .{}).module("args");
    const zigimg = b.dependency("zigimg", .{}).module("zigimg");

    const tool_mkicon = b.addExecutable(.{
        .name = "tool_mkicon",
        .root_source_file = b.path("tools/mkicon.zig"),
        .target = b.graph.host,
    });
    tool_mkicon.root_module.addImport("zigimg", zigimg);
    tool_mkicon.root_module.addImport("ashet-abi", b.modules.get("ashet-abi").?);
    tool_mkicon.root_module.addImport("args", zig_args_module);

    return BitmapConverter{
        .builder = b,
        .converter = tool_mkicon,
    };
}

pub const Options = struct {
    palette: Palette = .{ .sized = 15 },
    geometry: ?[2]u32 = null,

    const Palette = union(enum) {
        predefined: std.Build.LazyPath,
        sized: u8,
    };
};

pub fn convert(conv: BitmapConverter, source: std.Build.LazyPath, basename: []const u8, options: Options) std.Build.LazyPath {
    const mkicon = conv.builder.addRunArtifact(conv.converter);

    mkicon.addFileArg(source);

    switch (options.palette) {
        .predefined => |palette| {
            mkicon.addArg("--palette");
            mkicon.addFileArg(palette);
        },
        .sized => |size| {
            mkicon.addArg("--color-count");
            mkicon.addArg(conv.builder.fmt("{d}", .{size}));
        },
    }
    if (options.geometry) |geometry| {
        mkicon.addArg("--geometry");
        mkicon.addArg(conv.builder.fmt("{}x{}", .{ geometry[0], geometry[1] }));
    }

    mkicon.addArg("-o");
    const result = mkicon.addOutputFileArg(basename);

    return result;
}
