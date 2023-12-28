const std = @import("std");

const BitmapConverter = @This();

builder: *std.Build,
converter: *std.Build.CompileStep,

pub fn init(builder: *std.Build) BitmapConverter {
    const zig_args_module = builder.dependency("args", .{}).module("args");
    const zigimg = builder.dependency("zigimg", .{}).module("zigimg");

    const tool_mkicon = builder.addExecutable(.{ .name = "tool_mkicon", .root_source_file = .{ .path = "tools/mkicon.zig" } });
    tool_mkicon.addModule("zigimg", zigimg);
    tool_mkicon.addModule("ashet-abi", builder.modules.get("ashet-abi").?);
    tool_mkicon.addModule("args", zig_args_module);

    return BitmapConverter{
        .builder = builder,
        .converter = tool_mkicon,
    };
}

pub const Options = struct {
    palette: Palette = .{ .sized = 15 },
    geometry: ?[2]u32 = null,

    const Palette = union(enum) {
        predefined: []const u8,
        sized: u8,
    };
};

pub fn convert(conv: BitmapConverter, source: std.Build.FileSource, basename: []const u8, options: Options) std.Build.FileSource {
    const mkicon = conv.builder.addRunArtifact(conv.converter);

    mkicon.addFileSourceArg(source);

    switch (options.palette) {
        .predefined => |palette| {
            mkicon.addArg("--palette");
            mkicon.addFileSourceArg(.{ .path = palette });
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
