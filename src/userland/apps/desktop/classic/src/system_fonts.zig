const std = @import("std");
const ashet = @import("ashet");
const logger = std.log.scoped(.system_fonts);

var arena: std.heap.ArenaAllocator = undefined;

var fonts: std.StringArrayHashMap([]const u8) = undefined;

pub fn load() !void {
    arena = std.heap.ArenaAllocator.init(ashet.memory.allocator);
    errdefer arena.deinit();

    fonts = std.StringArrayHashMap([]const u8).init(arena.allocator());
    errdefer fonts.deinit();

    var font_dir = try ashet.fs.Directory.openDrive(.system, "system/fonts");
    defer font_dir.close();

    while (try font_dir.next()) |ent| {
        if (ent.attributes.directory)
            continue;
        const file_name = ent.getName();
        if (!std.mem.endsWith(u8, file_name, ".font") or file_name.len <= 5)
            continue;

        var file = try font_dir.openFile(file_name, .read_only, .open_existing);
        defer file.close();

        loadAndAddFont(&file, file_name[0 .. file_name.len - 5]) catch |err| {
            logger.err("failed to load font {s}: {s}", .{
                file_name,
                @errorName(err),
            });
        };
    }

    logger.info("available system fonts:", .{});
    for (fonts.keys()) |name| {
        logger.info("- {s}", .{name});
    }
}

pub fn get(font_name: []const u8) error{FileNotFound}![]const u8 {
    return fonts.get(font_name) orelse return error.FileNotFound;
}

fn loadAndAddFont(file: *ashet.fs.File, name: []const u8) !void {
    const name_dupe = try arena.allocator().dupe(u8, name);
    errdefer arena.allocator().free(name_dupe);

    const stat = try file.stat();

    if (stat.size > 1_000_000) // hard limit: 1 MB
        return error.OutOfMemory;

    const buffer = try arena.allocator().alloc(u8, @as(u32, @intCast(stat.size)));
    errdefer arena.allocator().free(buffer);

    const len = try file.read(0, buffer);
    if (len != buffer.len)
        return error.UnexpectedEndOfFile;

    try fonts.putNoClobber(name_dupe, buffer);
}
