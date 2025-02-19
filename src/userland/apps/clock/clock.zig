const std = @import("std");
const ashet = @import("ashet");

const Color = ashet.abi.Color;
const Size = ashet.abi.Size;
const Point = ashet.abi.Point;

pub usingnamespace ashet.core;

const window_size = Size.new(47, 47);

pub fn main() !void {
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    std.log.info("using desktop {}", .{desktop});

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Clock",
            .min_size = window_size,
            .max_size = window_size,
            .initial_size = window_size,
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    try paint(&command_queue);
    try command_queue.submit(framebuffer, .{});

    var timer_iop = ashet.clock.Timer.new(.{ .timeout = next_full_second() });
    try ashet.overlapped.schedule(&timer_iop.arc);

    var get_event_iop = ashet.gui.GetWindowEvent.new(.{ .window = window });
    try ashet.overlapped.schedule(&get_event_iop.arc);

    app_loop: while (true) {
        var arc_buffer: [2]*ashet.overlapped.ARC = undefined;

        const completed = try ashet.overlapped.await_completion(&arc_buffer, .{
            .wait = .wait_one,
            .thread_affinity = .this_thread,
        });

        for (completed) |overlapped_event| {
            if (overlapped_event == &timer_iop.arc) {
                try timer_iop.check_error();

                try paint(&command_queue);
                try command_queue.submit(framebuffer, .{});

                timer_iop.inputs.timeout = next_full_second();
                try ashet.overlapped.schedule(&timer_iop.arc);
            } else if (overlapped_event == &get_event_iop.arc) {
                const event = try get_event_iop.get_output();
                switch (event.event_type) {
                    .window_close => break :app_loop,
                    else => {},
                }

                // reschedule the IOP to receive more events:
                try ashet.overlapped.schedule(&get_event_iop.arc);
            } else {
                unreachable;
            }
        }
    }
}

fn paint(q: *ashet.graphics.CommandQueue) !void {
    const now = ashet.datetime.now();

    const time = std.time.epoch.EpochSeconds{
        .secs = @as(u64, @intCast(@max(0, now.as_unix_timestamp_s()))),
    };

    const day_secs = time.getDaySeconds();

    const hour = day_secs.getHoursIntoDay();
    const minute = day_secs.getMinutesIntoHour();
    const seconds = day_secs.getSecondsIntoMinute();

    const background_color = ashet.graphics.known_colors.dark_red;

    try q.clear(background_color);

    for (clock_face.pixels[0 .. clock_face.width * clock_face.height], 0..) |color, i| {
        const x = @as(i16, @intCast(i % clock_face.width));
        const y = @as(i16, @intCast(i / clock_face.width));
        comptime std.debug.assert(clock_face.has_transparency);
        if (!color.eql(clock_face.transparency_key)) {
            try q.set_pixel(Point.new(1 + x, 1 + y), color);
            try q.set_pixel(Point.new(1 + x, 45 - y), color);
            try q.set_pixel(Point.new(45 - x, 1 + y), color);
            try q.set_pixel(Point.new(45 - x, 45 - y), color);
        }
    }

    const H = struct {
        const digit = Color.black;
        // const shadow = ColorIndex.get(10);
        const highlight = Color.red;
    };

    const Digit = struct {
        pos: u15,
        limit: u15,
        color: ashet.graphics.Color,
        len: f32,
    };

    const digits = [3]Digit{
        .{ .pos = minute + 60 * (@as(u15, hour) % 12), .limit = 12 * 60, .color = H.digit, .len = 9 },
        .{ .pos = minute, .limit = 60, .color = H.digit, .len = 16 },
        .{ .pos = seconds, .limit = 60, .color = H.highlight, .len = 19 },
    };

    for (digits) |digit| {
        const cx = @as(i16, @intCast(window_size.width / 2));
        const cy = @as(i16, @intCast(window_size.height / 2));

        const angle = std.math.tau * @as(f32, @floatFromInt(digit.pos)) / @as(f32, @floatFromInt(digit.limit));

        const dx = @as(i16, @intFromFloat(digit.len * @sin(angle)));
        const dy = -@as(i16, @intFromFloat(digit.len * @cos(angle)));

        try q.draw_line(
            Point.new(cx, cy),
            Point.new(cx + dx, cy + dy),
            digit.color,
        );
    }
}

const clock_face_palette = .{
    .@"0" = Color.black,
    .F = Color.white,
};

pub const clock_face = ashet.graphics.embed_comptime_bitmap(clock_face_palette,
    \\..................00000
    \\...............000FFFFF
    \\.............00FFFFFF00
    \\...........00FFFFFFFF00
    \\.........00FFFFFFFFFF00
    \\........0FFFFFFFFFFFFFF
    \\.......0FFF00FFFFFFFFFF
    \\......0FFFF00FFFFFFFFFF
    \\.....0FFFFFFFFFFFFFFFFF
    \\....0FFFFFFFFFFFFFFFFFF
    \\....0FFFFFFFFFFFFFFFFFF
    \\...0FFFFFFFFFFFFFFFFFFF
    \\...0FFFFFFFFFFFFFFFFFFF
    \\..0FF00FFFFFFFFFFFFFFFF
    \\..0FF00FFFFFFFFFFFFFFFF
    \\.0FFFFFFFFFFFFFFFFFFFFF
    \\.0FFFFFFFFFFFFFFFFFFFFF
    \\.0FFFFFFFFFFFFFFFFFFFFF
    \\0FFFFFFFFFFFFFFFFFFFFFF
    \\0FFFFFFFFFFFFFFFFFFFFFF
    \\0FFFFFFFFFFFFFFFFFFFFFF
    \\0F000FFFFFFFFFFFFFFFFFF
    \\0F000FFFFFFFFFFFFFFFFFF
);

/// Computes the monotonic time of the next full second.
///
/// This is done by computing the delta of the current RTC clock to the
/// next full second and then returning the absolute time of monotonic clock +
/// time delta.
fn next_full_second() ashet.clock.Absolute {
    const ms_per_s = std.time.ms_per_s;

    const now = ashet.datetime.now();

    const ms_in_current_s: u64 = @intCast(@mod(now.as_unix_timestamp_ms(), ms_per_s));

    const monotonic_now = ashet.clock.monotonic();
    const increment = ashet.clock.Duration.from_ms(ms_per_s - ms_in_current_s);
    const next_update = monotonic_now.increment_by(increment);
    // std.log.info("{} {} {}", .{
    //     monotonic_now,
    //     increment,
    //     next_update,
    // });
    return next_update;
}
