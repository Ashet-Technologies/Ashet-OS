const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const abi = ashet.abi;
const syscalls = ashet.userland;

// Some imports:
const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;

// Application logic:

const apps = @import("apps.zig");

const WindowList = std.DoublyLinkedList(void);
const WindowNode = WindowList.Node;

var active_windows: WindowList = .{};

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

    var render_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer render_queue.deinit();

    try render_queue.fill_rect(10, 10, 100, 50, ColorIndex.get(0));

    try render_queue.submit(video_fb, .{});

    // First ensure the image is displayed before continuing
    syscalls.process.thread.yield();

    // Do load available applications before we "open" the desktop:
    try apps.init();

    const desktop = try syscalls.gui.create_desktop("Classic", &.{
        .window_data_size = @sizeOf(WindowData),
        .handle_event = handle_desktop_event,
    });
    defer desktop.release();

    // const desktop_proc = try ashet.overlapped.performOne(abi.process.Spawn, .{
    //     .dir = apps_dir.dir,
    //     .path_ptr = "hello-gui/code",
    //     .path_len = 14,
    //     .argv_ptr = &[_]abi.SpawnProcessArg{
    //         abi.SpawnProcessArg.string("--desktop"),
    //         abi.SpawnProcessArg.resource(desktop.as_resource()),
    //     },
    //     .argv_len = 2,
    // });
    // desktop_proc.process.release(); // we're not interested in "holding" onto process

    var cursor: Point = Point.new(
        @intCast(fb_size.width / 2),
        @intCast(fb_size.height / 2),
    );

    var requires_repaint = true;

    while (true) {
        if (requires_repaint) {
            requires_repaint = false;

            const black = ColorIndex.get(0x0);
            const white = ColorIndex.get(0xF);

            try render_queue.clear(white);

            try render_queue.draw_line(
                cursor.x,
                cursor.y,
                cursor.x +| 10,
                cursor.y +| 5,
                black,
            );
            try render_queue.draw_line(
                cursor.x,
                cursor.y,
                cursor.x +| 5,
                cursor.y +| 10,
                black,
            );
            try render_queue.draw_line(
                cursor.x +| 10,
                cursor.y +| 5,
                cursor.x +| 5,
                cursor.y +| 10,
                black,
            );

            try render_queue.submit(video_fb, .{});
        }

        const event = try ashet.input.await_event();

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

            else => |evt| std.log.warn("unhandled input event: {}", .{evt}),
        }

        if (!cursor.eql(prev_cursor)) {
            requires_repaint = true;
        }
    }
}

fn handle_desktop_event(desktop: abi.Desktop, event: *const abi.DesktopEvent) callconv(.C) void {
    std.log.debug("handle desktop event of type {s}", .{@tagName(event.event_type)});
    switch (event.event_type) {
        .create_window => {
            const window = event.create_window.window;
            std.log.info("handle_desktop_event.create_window({})", .{window});

            const data = WindowData.from_handle(window);
            active_windows.append(&data.window_node);

            // TODO: Set up basic structure

            // TODO: Redraw invalidated desktop region
        },

        .destroy_window => {
            const window = event.create_window.window;
            std.log.info("handle_desktop_event.destroy_window({})", .{window});

            const data = WindowData.from_handle(window);
            active_windows.remove(&data.window_node);

            // TODO: Redraw invalidated desktop region
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

const WindowData = struct {
    window_node: WindowNode = .{ .data = {} },

    pub fn from_handle(handle: ashet.abi.Window) *WindowData {
        return @ptrCast(
            syscalls.gui.get_desktop_data(handle) catch @panic("kernel bug"),
        );
    }
};
