const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const Point = ashet.abi.Point;

pub fn main() !void {
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = try ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    std.log.info("using desktop {}", .{desktop});

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Dragon Craft",
            .min_size = ashet.abi.Size.new(64, 64),
            .max_size = ashet.abi.Size.new(800, 480),
            .initial_size = ashet.abi.Size.new(200, 150),
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    try command_queue.clear(ashet.graphics.Color.from_rgb(0, 0, 0));

    try command_queue.submit(framebuffer, .{});

    var painting: bool = false;
    var mouse_prev: Point = undefined;
    app_loop: while (true) {
        const get_event = try ashet.overlapped.performOne(ashet.gui.GetWindowEvent, .{ .window = window });
        const event = &get_event.event;

        switch (event.event_type) {
            .mouse_button_press => if (event.mouse.button == .left) {
                painting = true;
                mouse_prev = Point.new(event.mouse.x, event.mouse.y);
                // std.log.info("start painting at {}", .{mouse_prev});
            },
            .mouse_button_release => if (event.mouse.button == .left) {
                painting = false;
                // std.log.info("stop painting at {}", .{mouse_prev});
            },
            .mouse_motion => if (painting) {
                const mouse_now = ashet.graphics.Point.new(event.mouse.x, event.mouse.y);
                defer mouse_prev = mouse_now;

                // std.log.info("paint from {} to {}", .{ mouse_prev, mouse_now });

                try command_queue.draw_line(
                    mouse_prev,
                    mouse_now,
                    ashet.graphics.Color.from_rgb(255, 255, 255),
                );

                try command_queue.submit(framebuffer, .{});
            },
            .window_close => break :app_loop,
            else => {},
        }
    }
}
