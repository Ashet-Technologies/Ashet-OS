//!
//! This file implements the splash screen application.
//! This application has more "rights" than a normal application,
//! as it can directly access any kernel state, but we still have
//! to use the system calls to access input and output, as the kernel
//! functions don't perform process filtering.
//!
//! Thus, for video memory and input events, we have to go through
//! libashet.
//!

const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");
const logger = std.log.scoped(.@"splash screen");
const libashet = @import("ashet");

pub fn run(_: ?*anyopaque) callconv(.C) u32 {
    const thread = ashet.scheduler.Thread.current() orelse {
        std.log.err("splash screen must be run in a thread.", .{});
        return 1;
    };

    const task = thread.process orelse {
        std.log.err("splash screen requires thread to be associated with a process.", .{});
        return 1;
    };

    SplashScreen.run(task) catch |err| {
        std.log.err("splash screen failed with {}", .{err});
        return 1;
    };

    return 0;
}

const SplashScreen = struct {
    task: *ashet.multi_tasking.Process,

    current_app: usize = 0,
    layout: Layout,

    fn run(task: *ashet.multi_tasking.Process) !void {
        var screen = SplashScreen{
            .task = task,
            .layout = undefined,
        };

        logger.info("starting splash screen for process {*}", .{task});

        screen.layout = Layout.get(screen.apps.len);

        libashet.video.setResolution(400, 300);

        screen.fullPaint();

        while (true) {
            while (libashet.input.getKeyboardEvent()) |event| {
                if (!event.pressed)
                    continue;
                var previous_app = screen.current_app;
                switch (event.key) {
                    .left => if (screen.current_app > 0) {
                        screen.current_app -= 1;
                    },

                    .right => if (screen.current_app + 1 < screen.apps.len) {
                        screen.current_app += 1;
                    },

                    .up => if (screen.current_app >= screen.layout.cols) {
                        screen.current_app -= screen.layout.cols;
                    },

                    .down => if (screen.current_app + screen.layout.cols < screen.apps.len) {
                        screen.current_app += screen.layout.cols;
                    },

                    .@"return", .kp_enter => {
                        // clear screen
                        const vmem = libashet.video.getVideoMemory()[0 .. 400 * 300];
                        std.mem.set(u8, vmem, 15);

                        // start application
                        try screen.startApp(screen.apps.slice()[screen.current_app]);
                        return;
                    },

                    else => {},
                }
                if (previous_app != screen.current_app) {
                    screen.paintSelection(previous_app, 0x0F);
                    screen.paintSelection(screen.current_app, 0x09);
                }
            }

            // if (true)
            //     @panic("pre");
            ashet.scheduler.yield();
        }
    }

    fn pixelIndex(x: usize, y: usize) usize {
        return 400 * y + x;
    }

    fn paintSelection(screen: SplashScreen, index: usize, color: u8) void {
        const vmem = libashet.video.getVideoMemory()[0 .. 400 * 300];

        const target_pos = screen.layout.pos(index);

        const x = target_pos.x;
        const y = target_pos.y;
        const h = Icon.height - 1;
        const w = Icon.width - 1;

        var i: usize = 0;
        while (i < 64) : (i += 1) {
            vmem[pixelIndex(x + i, y - 4)] = color; // top
            vmem[pixelIndex(x + i, y + h + 4)] = color; // bottom
            vmem[pixelIndex(x - 4, y + i)] = color; // left
            vmem[pixelIndex(x + w + 4, y + i)] = color; // right
        }

        i = 1; // 1...3
        while (i < 4) : (i += 1) {
            const j = 4 - i; // 3...1

            // top left
            vmem[pixelIndex(x - j, y - i)] = color;
            vmem[pixelIndex(x - j, y - i)] = color;
            vmem[pixelIndex(x - j, y - i)] = color;

            // top right
            vmem[pixelIndex(x + w + j, y - i)] = color;
            vmem[pixelIndex(x + w + j, y - i)] = color;
            vmem[pixelIndex(x + w + j, y - i)] = color;

            // bottom left
            vmem[pixelIndex(x - j, y + h + i)] = color;
            vmem[pixelIndex(x - j, y + h + i)] = color;
            vmem[pixelIndex(x - j, y + h + i)] = color;

            // bottom right
            vmem[pixelIndex(x + w + j, y + h + i)] = color;
            vmem[pixelIndex(x + w + j, y + h + i)] = color;
            vmem[pixelIndex(x + w + j, y + h + i)] = color;
        }
    }

    fn fullPaint(screen: SplashScreen) void {
        const vmem = libashet.video.getVideoMemory()[0 .. 400 * 300];
        const palette = libashet.video.getPaletteMemory();

        std.mem.set(u8, vmem, 15);

        for (screen.apps.slice(), 0..) |app, index| {
            const target_pos = screen.layout.pos(index);

            const palette_base = @truncate(u8, 16 * (index + 1));
            for (app.icon.palette, 0..) |color, offset| {
                palette[palette_base + offset + 1] = color;
            }

            var y: usize = 0;
            while (y < Icon.height) : (y += 1) {
                var x: usize = 0;
                while (x < Icon.width) : (x += 1) {
                    const src = app.icon.bitmap[Icon.width * y + x];
                    const idx = pixelIndex(target_pos.x + x, target_pos.y + y);
                    if (src != 0) {
                        vmem[idx] = palette_base + src;
                    }
                }
            }
        }

        screen.paintSelection(screen.current_app, 0x09);
    }

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

        fn get(count: usize) Layout {
            return switch (count) {
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
        }
    };
};
