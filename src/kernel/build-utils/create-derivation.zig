const std = @import("std");

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const static_allocator = arena.allocator();

    const argv = try std.process.argsAlloc(static_allocator);

    if (argv.len < 3) {
        std.debug.print("usage: create-derivation --output=<dir> --source=<dir> {{ --patch=<file> }}\n", .{});
        return 1;
    }

    var output_dir: []const u8 = "";
    var source_dir: []const u8 = "";
    var patches: std.ArrayList([]const u8) = .empty;

    for (argv[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--output=")) {
            output_dir = std.mem.trimLeft(u8, arg[9..], " \t");
        } else if (std.mem.startsWith(u8, arg, "--source=")) {
            source_dir = std.mem.trimLeft(u8, arg[9..], " \t");
        } else if (std.mem.startsWith(u8, arg, "--patch=")) {
            const patch_file = std.mem.trimLeft(u8, arg[8..], " \t");
            try patches.append(static_allocator, patch_file);
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            return 1;
        }
    }
    if (source_dir.len == 0 or output_dir.len == 0) {
        std.debug.print("usage: create-derivation --output=<dir> --source=<dir> {{ --patch=<file> }}\n", .{});
        return 1;
    }

    var source = try std.fs.cwd().openDir(source_dir, .{ .iterate = true });
    defer source.close();

    var destination = try std.fs.cwd().makeOpenPath(output_dir, .{});
    defer destination.close();

    {
        var walker = try source.walk(static_allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            switch (entry.kind) {
                .file => try std.fs.Dir.copyFile(
                    source,
                    entry.path,
                    destination,
                    entry.path,
                    .{},
                ),
                .directory => try destination.makeDir(entry.path),
                else => @panic("unexpected file type!"),
            }
        }
    }

    for (patches.items) |patch_path| {
        const patch = try std.fs.cwd().readFileAlloc(static_allocator, patch_path, 1 << 25);
        if (!std.mem.startsWith(u8, patch, "//!")) {
            std.debug.print("Invalid patch file: {s}\n", .{patch_path});
            return 1;
        }

        const head_line_end = std.mem.indexOfScalar(u8, patch, '\n') orelse {
            std.debug.print("Invalid patch file: {s}\n", .{patch_path});
            return 1;
        };

        const header = std.mem.trim(u8, patch[3..head_line_end], " \t\r\n");

        var header_parser = std.mem.tokenizeScalar(u8, header, ' ');
        const target_file = header_parser.next().?;
        if (header_parser.next() != null) {
            std.debug.print("Invalid patch file: {s}\n", .{patch_path});
            return 1;
        }

        if (std.fs.path.dirnamePosix(target_file)) |directory| {
            try destination.makePath(directory);
        }

        const body = patch[head_line_end + 1 ..];

        try destination.writeFile(.{
            .sub_path = target_file,
            .data = body,
        });
    }

    return 0;
}
