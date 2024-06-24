const std = @import("std");

pub fn build(b: *std.Build) void {
    const args_mod = b.dependency("args", .{}).module("args");
    const abi_mod = b.dependency("abi", .{}).module("ashet-abi");

    const zigimg_mod = b.dependency("zigimg", .{}).module("zigimg");

    const exe = b.addExecutable(.{
        .name = "mkicon",
        .root_source_file = b.path("mkicon.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    exe.root_module.addImport("zigimg", zigimg_mod);
    exe.root_module.addImport("ashet-abi", abi_mod);
    exe.root_module.addImport("args", args_mod);
    b.installArtifact(exe);
}

pub const ConvertOptions = struct {
    palette: Palette = .{ .sized = 15 },
    geometry: ?[2]u32 = null,

    const Palette = union(enum) {
        predefined: std.Build.LazyPath,
        sized: u8,
    };
};

pub const Converter = struct {
    builder: *std.Build,
    exe: *std.Build.Step.Compile,

    pub fn create(builder: *std.Build, dep: *std.Build.Dependency) Converter {
        const exe = dep.artifact("mkicon");

        return Converter{
            .exe = exe,
            .builder = builder,
        };
    }

    pub fn convert(conv: Converter, source: std.Build.LazyPath, basename: []const u8, options: ConvertOptions) std.Build.LazyPath {
        const mkicon = conv.builder.addRunArtifact(conv.exe);

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
};
