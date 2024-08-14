const std = @import("std");
const ashet = @import("../main.zig");
const libashet = @import("ashet");
const logger = std.log.scoped(.apps);

const loader = @import("loader.zig");

pub const AppID = struct {
    name: []const u8,

    fn getName(app: AppID) []const u8 {
        return app.name;
    }
};

pub fn startApp(app: AppID) !void {
    var root_dir = try libashet.fs.Directory.openDrive(.system, "apps");
    defer root_dir.close();

    var app_dir = try root_dir.openDir(app.getName());
    defer app_dir.close();

    var file = try app_dir.openFile("code", .read_only, .open_existing);
    defer file.close();

    const process = try ashet.multi_tasking.Process.create(.{
        .stay_resident = false,
        .name = app.getName(),
    });
    errdefer process.kill();

    const loaded = try loader.load(&file, process.static_allocator(), .elf);

    process.executable_memory = loaded.process_memory;

    const thread = try ashet.scheduler.Thread.spawn(
        @as(ashet.scheduler.ThreadFunction, @ptrFromInt(loaded.entry_point)),
        null,
        .{ .process = process, .stack_size = 64 * 1024 },
    );
    errdefer thread.kill();

    try thread.setName(app.getName());

    try thread.start();

    thread.detach();
}

// pub fn startAppBinary(app: AppID) !void {
//     var path_buffer: [ashet.abi.max_path]u8 = undefined;
//     const app_path = try std.fmt.bufPrint(&path_buffer, "SYS:/apps/{s}/code", .{app.getName()});

//     const stat = try ashet.filesystem.stat(app_path);

//     const proc_byte_size = stat.size;
//     const proc_page_size = std.mem.alignForward(proc_byte_size, ashet.memory.page_size);
//     const proc_page_count = ashet.memory.getRequiredPages(proc_page_size);

//     const app_pages = try ashet.memory.allocPages(proc_page_count);
//     errdefer ashet.memory.freePages(app_pages, proc_page_count);

//     const process_memory = @as([*]align(ashet.memory.page_size) u8, @ptrCast(ashet.memory.pageToPtr(app_pages)))[0..proc_page_size];

//     logger.info("process {s} will be loaded at {*} with {d} bytes size ({d} pages at {d})", .{
//         app.getName(),
//         process_memory,
//         proc_page_size,
//         proc_page_count,
//         app_pages,
//     });

//     {
//         const file = try ashet.filesystem.open(app_path, .read_only, .open_existing);
//         defer ashet.filesystem.close(file);

//         const len = try ashet.filesystem.read(file, process_memory[0..proc_byte_size]);
//         if (len != proc_byte_size)
//             @panic("could not read all bytes on one go!");
//     }

//     try spawnApp(app, process_memory, @intFromPtr(process_memory.ptr));
// }
