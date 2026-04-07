const std = @import("std");
const ashet = @import("ashet");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;

const next_image_interval: ashet.clock.Duration = .from_ms(3500);

const fixed_size: Size = .new(600, 350);

const State = struct {
    pictures: []const ashet.graphics.Framebuffer,
    index: usize = 0,

    cq: *ashet.graphics.CommandQueue,
    fb: ashet.graphics.Framebuffer,

    fn next(state: *State) void {
        state.index += 1;
        if (state.index >= state.pictures.len) {
            state.index = 0;
        }
    }
};

pub fn main() !void {
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = try ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    var pictures: std.ArrayList(ashet.graphics.Framebuffer) = .empty;
    defer pictures.deinit(ashet.process.mem.allocator());

    {
        var dir = try ashet.fs.Directory.openDrive(.system, "data/slideshow");
        defer dir.close();

        while (try dir.next()) |entry| {
            if (!std.mem.eql(u8, std.fs.path.extension(entry.getName()), ".abm")) {
                std.log.warn("skipping {s}...", .{entry.getName()});
                continue;
            }

            std.log.info("loading {s}...", .{entry.getName()});

            var file = try dir.openFile(entry.getName(), .read_only, .open_existing);
            defer file.close();

            const framebuffer = try ashet.graphics.load_texture_file(file);

            try pictures.append(ashet.process.mem.allocator(), framebuffer);
        }
    }

    if (pictures.items.len == 0)
        return;

    const desktop = try argv[1].value.resource.cast(.desktop);

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Slideshow",
            .min_size = fixed_size,
            .max_size = fixed_size,
            .initial_size = fixed_size,
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    var state: State = .{
        .index = 0,
        .pictures = pictures.items,
        .cq = &command_queue,
        .fb = framebuffer,
    };

    try paint(state);

    var next_image_time: ashet.abi.Absolute = ashet.clock.monotonic().increment_by(next_image_interval);

    var gui_event: ashet.abi.gui.GetWindowEvent = .init(window);
    var timer_event: ashet.abi.clock.Timer = .init(next_image_time);

    try ashet.overlapped.schedule(&gui_event.arc);
    try ashet.overlapped.schedule(&timer_event.arc);

    main_loop: while (true) {
        const which = try ashet.overlapped.await_events(.{
            .gui = &gui_event,
            .timer = &timer_event,
        });

        if (which.contains(.timer)) {
            next_image_time = ashet.clock.monotonic().increment_by(next_image_interval);

            timer_event = .init(next_image_time);
            try ashet.overlapped.schedule(&timer_event.arc);

            state.next();

            try paint(state);
        }

        if (which.contains(.gui)) {
            const event = try gui_event.get_output();
            switch (event.event_type) {
                .widget_notify,
                .mouse_enter,
                .mouse_leave,
                .window_minimize,
                .window_restore,
                .window_moving,
                .window_moved,
                .window_resizing,
                .window_resized,
                => {},

                .window_close => break :main_loop,

                .mouse_motion => {},

                .mouse_button_press => {
                    if (event.mouse.button == .left) {
                        state.next();
                        try paint(state);
                    }
                },

                .mouse_button_release => {},

                .key_press => {
                    if (event.keyboard.usage == .space) {
                        state.next();
                        try paint(state);
                    }
                },

                .key_release => {},
            }

            try ashet.overlapped.schedule(&gui_event.arc);
        }
    }
}

fn paint(state: State) !void {
    const picture = state.pictures[state.index];

    const size = try ashet.graphics.get_framebuffer_size(picture);

    const pos: Point = .new(
        @intCast(@as(i32, fixed_size.width) - size.width),
        @intCast(@as(i32, fixed_size.height) - size.height),
    );

    try state.cq.clear(ashet.graphics.known_colors.black);
    try state.cq.blit_framebuffer(pos, picture);
    try state.cq.submit(state.fb, .{});
}
