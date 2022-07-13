const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.@"splash screen");

const Icon = extern struct {
    pub const width = 64;
    pub const height = 64;

    bitmap: [width * height]u8,
    palette: [15]u16,

    pub fn load(stream: anytype) !Icon {
        var icon: Icon = undefined;

        try stream.readNoEof(&icon.bitmap);
        try stream.readNoEof(std.mem.sliceAsBytes(&icon.palette));

        return icon;
    }
};

const default_icon = blk: {
    const data = @embedFile("../data/generic-app.icon");
    var fbs = std.io.fixedBufferStream(&data);
    break :blk Icon.load(fbs.reader()) catch unreachable;
};

const App = struct {
    name: [32]u8,
    icon: Icon,
};

pub fn run(task_ptr: ?*anyopaque) callconv(.C) u32 {
    const task = @ptrCast(*ashet.multi_tasking.Task, @alignCast(@alignOf(ashet.multi_tasking.Task), task_ptr orelse @panic("splash_screen.run requires a pointer to a task as an argument.")));

    SplashScreen.run(task) catch |err| {
        std.log.err("splash screen failed with {}", .{err});
        return 1;
    };

    return 0;
}

const SplashScreen = struct {
    task: *ashet.multi_tasking.Task,
    apps: std.BoundedArray(App, 15) = .{},

    fn run(task: *ashet.multi_tasking.Task) !void {
        var screen = SplashScreen{ .task = task };

        logger.info("starting splash screen for screen {}", .{task.screen_id});

        var dir = try ashet.filesystem.openDir("SYS:/apps");
        defer ashet.filesystem.closeDir(dir);

        while (try ashet.filesystem.next(dir)) |ent| {
            const app = screen.apps.addOne() catch {
                logger.warn("The system can only handle {} apps right now, but more are installed.", .{screen.apps.len});
                break;
            };

            {
                const name = ent.getName();
                std.mem.set(u8, &app.name, 0);
                std.mem.copy(u8, &app.name, name[0..std.math.min(name.len, app.name.len)]);
            }

            var path_buffer: [ashet.abi.max_path]u8 = undefined;

            const icon_path = try std.fmt.bufPrint(&path_buffer, "SYS:/apps/{s}/icon", .{ent.getName()});

            if (ashet.filesystem.open(icon_path, .read_only, .open_existing)) |icon_handle| {
                defer ashet.filesystem.close(icon_handle);

                app.icon = try Icon.load(ashet.filesystem.fileReader(icon_handle));
            } else |_| {
                std.log.warn("Application {s} does not have an icon. Using default.", .{ent.getName()});
                app.icon.bitmap = undefined;
            }
        }

        for (screen.apps.slice()) |app, index| {
            logger.info("app[{}]: {s}", .{ index, std.mem.sliceTo(&app.name, 0) });
        }

        ashet.video.setMode(.graphics);
        ashet.video.setResolution(400, 300);

        screen.fullPaint();

        while (true) {
            // if (true)
            //     @panic("pre");
            ashet.scheduler.yield();
        }
    }

    fn fullPaint(screen: SplashScreen) void {
        const Layout = struct {
            const Pos = struct { row: usize, col: usize };
            const Point = struct { x: usize, y: usize };
            pub const padding_h = 8;
            pub const padding_v = 8;

            rows: u16, // 1 ... 3
            cols: u16, // 1 ... 5

            fn slot(src: @This(), index: usize) Pos {
                return Pos{
                    .col = @truncate(u16, index % src.cols),
                    .row = @truncate(u16, index / src.cols),
                };
            }

            // l,r,t,b
            fn pos(src: @This(), index: usize) Point {
                const logical_pos = src.slot(index);

                const offset_x = (400 - Icon.width * src.cols - padding_h * (src.cols - 1)) / 2;
                const offset_y = (300 - Icon.height * src.rows - padding_v * (src.rows - 1)) / 2;

                const dx = offset_x + (Icon.width + padding_h) * logical_pos.col;
                const dy = offset_y + (Icon.height + padding_v) * logical_pos.row;

                return Point{
                    .x = dx,
                    .y = dy,
                };
            }
        };

        const layout: Layout = switch (screen.apps.len) {
            0, 1 => Layout{ .rows = 1, .cols = 1 },
            2 => Layout{ .rows = 1, .cols = 2 },
            3 => Layout{ .rows = 1, .cols = 3 },
            4 => Layout{ .rows = 1, .cols = 4 },
            5, 6 => Layout{ .rows = 2, .cols = 3 },
            7, 8 => Layout{ .rows = 2, .cols = 4 },
            9 => Layout{ .rows = 3, .cols = 3 },
            10, 11, 12 => Layout{ .rows = 3, .cols = 4 },
            13, 14, 15 => Layout{ .rows = 3, .cols = 5 },
            else => @panic("too many apps, implement scrolling!"),
        };

        const vmem = ashet.video.memory[0 .. 400 * 300];
        const palette = ashet.video.palette;

        std.mem.set(u8, vmem, 15);

        for (screen.apps.slice()) |app, index| {
            const target_pos = layout.pos(index);

            const palette_base = @truncate(u8, 16 * (index + 1));

            for (app.icon.palette) |color, offset| {
                palette[palette_base + offset + 1] = color;
            }

            var y: usize = 0;
            while (y < Icon.height) : (y += 1) {
                var x: usize = 0;
                while (x < Icon.width) : (x += 1) {
                    const src = app.icon.bitmap[Icon.width * y + x];
                    const idx = 400 * (target_pos.y + y) + target_pos.x + x;
                    if (src != 0) {
                        vmem[idx] = palette_base + src;
                    }
                }
            }
        }
    }
};

pub fn startApp(app_name: []const u8) !void {
    _ = app_name;

    // Start "init" process
    {
        const app_file = "PF0:/apps/shell/code";
        const stat = try ashet.filesystem.stat(app_file);

        const proc_byte_size = stat.size;

        const process_memory = @as([]align(ashet.memory.page_size) u8, @intToPtr([*]align(ashet.memory.page_size) u8, 0x80800000)[0..std.mem.alignForward(proc_byte_size, ashet.memory.page_size)]);

        const app_pages = ashet.memory.ptrToPage(process_memory.ptr) orelse unreachable;
        const proc_size = ashet.memory.getRequiredPages(process_memory.len);

        {
            var i: usize = 0;
            while (i < proc_size) : (i += 1) {
                if (!ashet.memory.isFree(app_pages + i)) {
                    @panic("app memory is not free");
                }
            }
            i = 0;
            while (i < proc_size) : (i += 1) {
                ashet.memory.markUsed(app_pages + i);
            }
        }

        {
            var file = try ashet.filesystem.open(app_file, .read_only, .open_existing);
            defer ashet.filesystem.close(file);

            const len = try ashet.filesystem.read(file, process_memory[0..proc_byte_size]);
            if (len != proc_byte_size)
                @panic("could not read all bytes on one go!");
        }

        const thread = try ashet.scheduler.Thread.spawn(@ptrCast(ashet.scheduler.ThreadFunction, process_memory.ptr), null, null);
        errdefer thread.kill();

        try thread.start();
    }
}
