const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const logger = std.log.scoped(.desktop);
const abi = ashet.abi;
const syscalls = ashet.userland;

// Some imports:
const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;

// Application logic:

const icons = @import("icons.zig");
const apps = @import("apps.zig");
const themes = @import("theme.zig");

const WindowManager = @import("WindowManager.zig");
const DamageTracking = @import("DamageTracking.zig");

var window_manager: WindowManager = undefined;

pub fn main() !void {
    std.log.info("classic desktop startup...", .{});
    const video_output = try syscalls.video.acquire(.primary);
    defer video_output.release();

    const video_fb = try syscalls.draw.create_video_framebuffer(video_output);
    defer video_fb.release();

    const screen_size = try syscalls.video.get_resolution(video_output);

    std.log.info("primary video output has a resolution of {}x{}", .{
        screen_size.width,
        screen_size.height,
    });

    const fb_size = try syscalls.draw.get_framebuffer_size(video_fb);
    std.log.info("video output framebuffer has a resolution of {}x{}", .{
        fb_size.width,
        fb_size.height,
    });

    const vmem = try syscalls.video.get_video_memory(video_output);
    std.log.info("video memory: base=0x{X:0>8}, stride={}, width={}, height={}", .{
        @intFromPtr(vmem.base),
        vmem.stride,
        vmem.width,
        vmem.height,
    });

    // Load nice pattern:
    var scanline: [*]abi.ColorIndex = vmem.base;
    for (0..vmem.height) |y| {
        for (scanline[0..vmem.width], 0..) |*pixel, x| {
            pixel.* = @enumFromInt(@as(u4, @truncate(x ^ y)));
        }
        scanline += vmem.stride;
    }

    // Let the rest of the system continue to boot:
    syscalls.process.thread.yield();

    const default_font = try ashet.graphics.get_system_font("sans-6");
    defer default_font.release();

    const current_theme = themes.Theme{
        .title_font = default_font,
        .dark = ashet.graphics.known_colors.dark_gray,
        .active_window = .{
            .border = ashet.graphics.known_colors.dark_blue,
            .font = ashet.graphics.known_colors.white,
            .title = ashet.graphics.known_colors.blue,
        },
        .inactive_window = .{
            .border = ashet.graphics.known_colors.dim_gray,
            .font = ashet.graphics.known_colors.bright_gray,
            .title = ashet.graphics.known_colors.dark_gray,
        },
        .desktop_color = ashet.graphics.known_colors.teal,
        .window_fill = ashet.graphics.known_colors.gray,
    };

    var render_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer render_queue.deinit();

    try render_queue.fill_rect(.{ .x = 10, .y = 10, .width = 100, .height = 50 }, ColorIndex.get(0));

    try render_queue.submit(video_fb, .{});

    // First ensure the image is displayed before continuing
    syscalls.process.thread.yield();

    // Do load available applications before we "open" the desktop:
    try apps.init();

    var damage_tracking = DamageTracking.init(
        Rectangle.new(Point.zero, fb_size),
    );

    window_manager = WindowManager.init(&damage_tracking);
    defer window_manager.deinit();

    const desktop = try syscalls.gui.create_desktop("Classic", &.{
        .window_data_size = @sizeOf(WindowManager.Window),
        .handle_event = handle_desktop_event,
    });
    defer desktop.release();

    var apps_dir = try ashet.fs.Directory.openDrive(.system, "apps");
    defer apps_dir.close();

    var cursor: Point = Point.new(
        @intCast(fb_size.width / 2),
        @intCast(fb_size.height / 2),
    );

    damage_tracking.invalidate_screen();

    var selected_app_icon: ?usize = null;
    var last_click_pos: ashet.abi.Point = ashet.abi.Point.zero;
    var last_click_time: ashet.clock.Absolute = .system_start;

    while (true) {
        if (damage_tracking.is_tainted()) {
            defer damage_tracking.clear();

            const black = ColorIndex.get(0x0);
            // const blue = ColorIndex.get(0x2);
            const red = ColorIndex.get(0x4);

            // try render_queue.clear(window_manager.current_theme.desktop_color);

            for (damage_tracking.tainted_regions()) |rect| {
                try render_queue.fill_rect(rect, current_theme.desktop_color);
            }

            // Draw desktop:
            {
                var iter = apps.iterate(fb_size);

                while (iter.next()) |desktop_icon| {
                    try render_queue.blit_framebuffer(
                        desktop_icon.bounds.corner(.top_left),
                        desktop_icon.icon,
                    );

                    if (selected_app_icon == desktop_icon.index) {
                        try render_queue.draw_rect(
                            desktop_icon.bounds.grow(2),
                            red,
                        );
                    } else {
                        try render_queue.draw_rect(
                            desktop_icon.bounds.grow(2),
                            black,
                        );
                    }

                    try render_queue.draw_text(
                        desktop_icon.bounds.corner(.bottom_left),
                        default_font,
                        black,
                        desktop_icon.app.get_display_name(),
                    );
                }
            }

            try window_manager.render(&render_queue, current_theme);

            try Cursor.paint(&render_queue, cursor, black);

            try render_queue.submit(video_fb, .{});
        }

        const event = try ashet.input.await_event();

        // Update mouse cursor based off the event:
        {
            const prev_cursor = cursor;
            switch (event) {
                .mouse_abs_motion => |motion| {
                    cursor = Point.new(
                        @max(0, @min(@as(i16, @intCast(fb_size.width -| 1)), motion.x)),
                        @max(0, @min(@as(i16, @intCast(fb_size.height -| 1)), motion.y)),
                    );
                },
                .mouse_rel_motion => |motion| {
                    cursor = Point.new(
                        @max(0, @min(@as(i16, @intCast(fb_size.width -| 1)), cursor.x +| motion.dx)),
                        @max(0, @min(@as(i16, @intCast(fb_size.height -| 1)), cursor.y +| motion.dy)),
                    );
                },

                else => {},
            }

            if (!cursor.eql(prev_cursor)) {
                damage_tracking.invalidate_region(Rectangle{
                    .x = prev_cursor.x,
                    .y = prev_cursor.y,
                    .width = Cursor.width,
                    .height = Cursor.height,
                });
                damage_tracking.invalidate_region(Rectangle{
                    .x = cursor.x,
                    .y = cursor.y,
                    .width = Cursor.width,
                    .height = Cursor.height,
                });
            }
        }

        const was_handled = try window_manager.handle_event(cursor, event);
        try window_manager.handle_after_events();
        if (!was_handled) {
            switch (event) {
                .key_press, .key_release => {},

                .mouse_abs_motion, .mouse_rel_motion => {},

                .mouse_button_press => |data| handle_event: {
                    if (data.button != .left)
                        break :handle_event;

                    const previous_icon = selected_app_icon;
                    defer if (previous_icon != selected_app_icon) {
                        // Forward event to "desktop"
                        logger.debug("changed app selection from {?} to {?}", .{
                            previous_icon,
                            selected_app_icon,
                        });
                        // if (previous_icon) |previous| {
                        //     damage_tracking.invalidate_region(
                        //         previous.bounds.grow(8),
                        //     );
                        // }

                        // if (selected_app_icon) |current| {
                        //     damage_tracking.invalidate_region(
                        //         current.bounds.grow(8),
                        //     );
                        // }
                    };

                    const app = apps.app_from_point(fb_size, cursor) orelse {
                        // User clicked onto the backdrop, not an application icon.
                        // This means we have to deselect the application.

                        // Reset the last click time to system start so the user
                        // won't be able to trigger an accidential double click:
                        last_click_time = .system_start;

                        selected_app_icon = null;
                        break :handle_event;
                    };

                    const now = ashet.clock.monotonic();
                    defer last_click_time = now;

                    if (selected_app_icon == app.index) double_click_handler: {
                        // We clicked the same app again, let's see if it was a double click:

                        const pixel_since_last_click = cursor.manhattenDistance(last_click_pos);
                        logger.debug("pixel since: {}", .{pixel_since_last_click});
                        if (pixel_since_last_click > 4) {
                            // too much jitter
                            break :double_click_handler;
                        }

                        const ms_since_last_click = now.time_since(last_click_time).to_ms();
                        logger.debug("time since: {}", .{ms_since_last_click});
                        if (ms_since_last_click > 250) {
                            // too slow
                            break :double_click_handler;
                        }

                        // Start app:

                        var path_buffer: [256]u8 = undefined;

                        const path = try std.fmt.bufPrint(&path_buffer, "{s}/code", .{app.app.get_disk_name()});

                        const maybe_app = ashet.overlapped.performOne(abi.process.Spawn, .{
                            .dir = apps_dir.handle,
                            .path_ptr = path.ptr,
                            .path_len = path.len,
                            .argv_ptr = &[_]abi.SpawnProcessArg{
                                abi.SpawnProcessArg.string("--desktop"),
                                abi.SpawnProcessArg.resource(desktop.as_resource()),
                            },
                            .argv_len = 2,
                        });
                        if (maybe_app) |app_proc| {
                            app_proc.process.release(); // we're not interested in "holding" onto process
                        } else |err| {
                            logger.err("failed to start application {s}: {s}", .{
                                app.app.get_disk_name(),
                                @errorName(err),
                            });
                        }
                    }

                    last_click_pos = cursor;

                    selected_app_icon = app.index;
                    damage_tracking.invalidate_region(
                        app.bounds.grow(8),
                    );
                },

                .mouse_button_release => {},
            }
        }
    }
}

const Cursor = struct {
    pub const width = 11;
    pub const height = 11;

    pub fn paint(q: *ashet.graphics.CommandQueue, point: Point, fg: ColorIndex) !void {
        const cursor_br = Point.new(point.x +| 10, point.y +| 5);
        const cursor_bl = Point.new(point.x +| 5, point.y +| 10);

        try q.draw_line(
            point,
            cursor_br,
            fg,
        );
        try q.draw_line(
            point,
            cursor_bl,
            fg,
        );
        try q.draw_line(
            cursor_br,
            cursor_bl,
            fg,
        );
    }
};

fn handle_desktop_event(desktop: abi.Desktop, event: *const abi.DesktopEvent) callconv(.C) void {
    std.log.debug("handle desktop event of type {s}", .{@tagName(event.event_type)});
    switch (event.event_type) {
        .create_window => {
            const window = event.create_window.window;
            std.log.info("handle_desktop_event.create_window({})", .{window});
            window_manager.create_window(window) catch |err| {
                logger.err("failed to handle window creation: {s}", .{@errorName(err)});
            };
        },

        .destroy_window => {
            const window = event.destroy_window.window;
            std.log.info("handle_desktop_event.destroy_window({})", .{window});

            window_manager.destroy_window(window);
        },

        .invalidate_window => {
            const window = event.invalidate_window.window;
            const area = event.invalidate_window.area;
            std.log.info("handle_desktop_event.invalidate_window({}, {})", .{ window, area });
        },

        .show_message_box => {
            std.log.info("handle_desktop_event.show_message_box(request_id=0x{X:0>4}, caption='{}', message='{}', icon={s}, buttons='{}')", .{
                @intFromEnum(event.show_message_box.request_id),
                std.zig.fmtEscapes(event.show_message_box.caption()),
                std.zig.fmtEscapes(event.show_message_box.message()),
                @tagName(event.show_message_box.icon),
                event.show_message_box.buttons,
            });

            // TODO: Implement message boxes
        },

        .show_notification => {
            std.log.info("handle_desktop_event.show_notification(message='{}', severity={s})", .{
                std.zig.fmtEscapes(event.show_notification.message()),
                @tagName(event.show_notification.severity),
            });

            // TODO: Implement notifications
        },

        _ => {
            std.log.info("handle_desktop_event(invalid event: {d})", .{@intFromEnum(event.event_type)});
        },
    }

    _ = desktop;
}
