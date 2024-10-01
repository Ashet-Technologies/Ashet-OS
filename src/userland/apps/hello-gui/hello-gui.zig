const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;

pub fn main() !void {
    std.log.info("Hello, GUI!", .{});
    defer std.log.info("Good bye, GUI!", .{});

    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv_len = ashet.userland.process.get_arguments(null, &argv_buffer);
    const argv = argv_buffer[0..argv_len];

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    std.log.info("using desktop {}", .{desktop});

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Hello GUI",
            .min_size = Size.new(100, 100),
            .max_size = Size.new(300, 200),
            .initial_size = Size.new(200, 150),
        },
    );
    defer window.release();

    std.log.info("created window: {}", .{window});

    while (true) {
        const event_res = try ashet.overlapped.performOne(ashet.abi.gui.GetWindowEvent, .{
            .window = window,
        });

        switch (event_res.event.event_type) {
            .widget_notify,
            .key_press,
            .key_release,
            .mouse_enter,
            .mouse_leave,
            .mouse_motion,
            .mouse_button_press,
            .mouse_button_release,
            .window_close,
            .window_minimize,
            .window_restore,
            .window_moving,
            .window_moved,
            .window_resizing,
            .window_resized,
            => {
                std.log.info("unhandled ui event: {}", .{event_res.event.event_type});
            },
        }
    }
}
