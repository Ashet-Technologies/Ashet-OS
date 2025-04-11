// ctx.createAshetApp("dungeon", "src/apps/dungeon/dungeon.zig", "artwork/apps/dungeon/dungeon.png", optimize, &.{});

const mkicon = @import("mkicon");

const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

    const mkicon_dep = b.dependency("mkicon", .{ .release = true });

    const converter = mkicon.Converter.create(b, mkicon_dep);

    const texture_geom: mkicon.ConvertOptions = .{
        .geometry = .{ 32, 32 },
    };

    const sdk = AshetOS.init(b, "AshetOS", .{ .target = target });

    const app = sdk.addApp(.{
        .name = "dungeon",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/dungeon.zig"),
        .icon = .{
            .convert = b.path("../../../../assets/icons/apps/dungeon.png"),
        },
    });

    sdk.installApp(app, .{});

    sdk.install_file(
        "/apps/dungeon/data/floor.abm",
        converter.convert(b.path("../../../../assets/dungeon/floor.png"), "floor.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/wall-plain.abm",
        converter.convert(b.path("../../../../assets/dungeon/wall-plain.png"), "wall-plain.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/wall-cobweb.abm",
        converter.convert(b.path("../../../../assets/dungeon/wall-cobweb.png"), "wall-cobweb.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/wall-paper.abm",
        converter.convert(b.path("../../../../assets/dungeon/wall-paper.png"), "wall-paper.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/wall-vines.abm",
        converter.convert(b.path("../../../../assets/dungeon/wall-vines.png"), "wall-vines.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/wall-door.abm",
        converter.convert(b.path("../../../../assets/dungeon/wall-door.png"), "wall-door.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/wall-post-l.abm",
        converter.convert(b.path("../../../../assets/dungeon/wall-post-l.png"), "wall-post-l.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/wall-post-r.abm",
        converter.convert(b.path("../../../../assets/dungeon/wall-post-r.png"), "wall-post-r.abm", texture_geom),
    );
    sdk.install_file(
        "/apps/dungeon/data/enforcer.abm",
        converter.convert(b.path("../../../../assets/dungeon/enforcer.png"), "enforcer.abm", .{
            .geometry = .{ 32, 60 },
        }),
    );

    // files.addCopyFile("artwork/dungeon/floor.png", "src/apps/dungeon/data/floor.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/wall-plain.png", "src/apps/dungeon/data/wall-plain.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/wall-cobweb.png", "src/apps/dungeon/data/wall-cobweb.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/wall-paper.png", "src/apps/dungeon/data/wall-paper.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/wall-vines.png", "src/apps/dungeon/data/wall-vines.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/wall-door.png", "src/apps/dungeon/data/wall-door.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/wall-post-l.png", "src/apps/dungeon/data/wall-post-l.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/wall-post-r.png", "src/apps/dungeon/data/wall-post-r.abm", .{ 32, 32 });
    // files.addCopyFile("artwork/dungeon/enforcer.png", "src/apps/dungeon/data/enforcer.abm", .{ 32, 60 });
}
