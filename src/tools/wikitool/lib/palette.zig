const std = @import("std");
const zigimg = @import("zigimg");

pub fn loadPaletteFile(allocator: std.mem.Allocator, path: []const u8) ![]zigimg.color.Rgba32 {
    const palette_string = try std.fs.cwd().readFileAlloc(allocator, path, 1 << 20);
    defer allocator.free(palette_string);

    var palette = std.ArrayList(zigimg.color.Rgba32).init(allocator);
    defer palette.deinit();

    try palette.ensureTotalCapacity(256);

    var literator = std.mem.tokenizeSequence(u8, palette_string, "\r\n");

    const file_header = literator.next() orelse return error.InvalidFile;

    if (!std.mem.eql(u8, file_header, "GIMP Palette")) {
        return error.InvalidFile;
    }

    while (literator.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t"); // remove leading/trailing whitespace
        // if (std.mem.indexOfScalar(u8, trimmed, '\t')) |tab_index| { // remove the color name
        //     trimmed = std.mem.trim(u8, trimmed[0..tab_index], " ");
        // }

        if (std.mem.startsWith(u8, trimmed, "#"))
            continue;

        if (palette.items.len > 256) {
            return error.PaletteTooLarge;
        }

        var tups = std.mem.tokenizeAny(u8, trimmed, " \t");
        errdefer std.log.err("detected invalid line: '{}'\n", .{std.zig.fmtEscapes(trimmed)});

        const r = try std.fmt.parseInt(u8, tups.next() orelse return error.InvalidFile, 10);
        const g = try std.fmt.parseInt(u8, tups.next() orelse return error.InvalidFile, 10);
        const b = try std.fmt.parseInt(u8, tups.next() orelse return error.InvalidFile, 10);

        palette.appendAssumeCapacity(zigimg.color.Rgba32.initRgb(r, g, b));
    }

    return try palette.toOwnedSlice();
}
