// ctx.createAshetApp("dungeon", "src/apps/dungeon/dungeon.zig", "artwork/apps/dungeon/dungeon.png", optimize, &.{});
// addBitmap(dungeon, bmpconv, "artwork/dungeon/floor.png", "src/apps/dungeon/data/floor.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-plain.png", "src/apps/dungeon/data/wall-plain.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-cobweb.png", "src/apps/dungeon/data/wall-cobweb.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-paper.png", "src/apps/dungeon/data/wall-paper.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-vines.png", "src/apps/dungeon/data/wall-vines.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-door.png", "src/apps/dungeon/data/wall-door.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-post-l.png", "src/apps/dungeon/data/wall-post-l.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-post-r.png", "src/apps/dungeon/data/wall-post-r.abm", .{ 32, 32 });
// addBitmap(dungeon, bmpconv, "artwork/dungeon/enforcer.png", "src/apps/dungeon/data/enforcer.abm", .{ 32, 60 });

const std = @import("std");
const AshetOS = @import("AshetOS");

pub fn build(b: *std.Build) void {
    const target = AshetOS.standardTargetOption(b);
    const optimize = b.standardOptimizeOption(.{});

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
}
