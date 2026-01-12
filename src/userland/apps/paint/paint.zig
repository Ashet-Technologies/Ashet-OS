const std = @import("std");
const ashet = @import("ashet");

pub const std_options = ashet.core.std_options;

const Point = ashet.abi.Point;
const Color = ashet.abi.Color;

const color_size = 6;
const color_per_row = 8;
const color_per_column = @divExact(256, color_per_row);

pub fn main() !void {
    var draw_color: Color = .white;

    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = try ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    std.log.info("using desktop {f}", .{desktop});

    const draw_window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Dragon Craft - Image",
            .min_size = ashet.abi.Size.new(64, 64),
            .max_size = ashet.abi.Size.new(800, 480),
            .initial_size = ashet.abi.Size.new(200, 150),
        },
    );
    defer draw_window.destroy_now();

    const palette_window_size: ashet.abi.Size = .new(
        color_per_row * color_size,
        color_per_column * color_size,
    );
    const palette_window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Palette",
            .min_size = palette_window_size,
            .max_size = palette_window_size,
            .initial_size = palette_window_size,
            .popup = true,
        },
    );
    defer palette_window.destroy_now();

    const draw_framebuffer = try ashet.graphics.create_window_framebuffer(draw_window);
    defer draw_framebuffer.release();

    const palette_framebuffer = try ashet.graphics.create_window_framebuffer(palette_window);
    defer palette_framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    try command_queue.clear(ashet.graphics.Color.from_rgb(0, 0, 0));
    try command_queue.submit(draw_framebuffer, .{});

    try render_palette(&command_queue, palette_framebuffer, draw_color);

    var get_draw_event: ashet.gui.GetWindowEvent = .init(draw_window);
    var get_palette_event: ashet.gui.GetWindowEvent = .init(palette_window);

    try ashet.overlapped.schedule(&get_draw_event.arc);
    try ashet.overlapped.schedule(&get_palette_event.arc);
    try command_queue.submit(draw_framebuffer, .{});

    var painting: bool = false;
    var mouse_prev: Point = undefined;
    app_loop: while (true) {
        const events = try ashet.overlapped.await_events(.{
            .draw = &get_draw_event,
            .palette = &get_palette_event,
        });

        if (events.contains(.draw)) {
            const event = try get_draw_event.get_output();
            try ashet.overlapped.schedule(&get_draw_event.arc);

            switch (event.event_type) {
                .key_press => {
                    update_color_from_key(event.keyboard, &draw_color);
                    try render_palette(&command_queue, palette_framebuffer, draw_color);
                },
                .mouse_button_press => switch (event.mouse.button) {
                    .left => {
                        painting = true;
                        mouse_prev = Point.new(event.mouse.x, event.mouse.y);
                        // std.log.info("start painting at {}", .{mouse_prev});
                    },

                    .nav_previous => {
                        draw_color = .from_u8(dec_row(draw_color.to_u8()));
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },
                    .nav_next => {
                        draw_color = .from_u8(inc_row(draw_color.to_u8()));
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },

                    .wheel_down => {
                        draw_color = .from_u8(draw_color.to_u8() -% color_per_row);
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },
                    .wheel_up => {
                        draw_color = .from_u8(draw_color.to_u8() +% color_per_row);
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },

                    else => {},
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
                        draw_color,
                    );

                    try command_queue.submit(draw_framebuffer, .{});
                },
                .window_close => break :app_loop,
                else => {},
            }
        }
        if (events.contains(.palette)) {
            const event = try get_palette_event.get_output();
            try ashet.overlapped.schedule(&get_palette_event.arc);

            switch (event.event_type) {
                .key_press => {
                    update_color_from_key(event.keyboard, &draw_color);
                    try render_palette(&command_queue, palette_framebuffer, draw_color);
                },
                .mouse_button_press => switch (event.mouse.button) {
                    .left => {
                        const x: u8 = @intCast(@divFloor(event.mouse.x, color_size));
                        const y: u8 = @intCast(@divFloor(event.mouse.y, color_size));

                        draw_color = .from_u8(color_per_row * y + x);

                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },

                    .nav_previous => {
                        draw_color = .from_u8(dec_row(draw_color.to_u8()));
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },
                    .nav_next => {
                        draw_color = .from_u8(inc_row(draw_color.to_u8()));
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },

                    .wheel_down => {
                        draw_color = .from_u8(draw_color.to_u8() -% color_per_row);
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },
                    .wheel_up => {
                        draw_color = .from_u8(draw_color.to_u8() +% color_per_row);
                        try render_palette(&command_queue, palette_framebuffer, draw_color);
                    },

                    else => {},
                },
                else => {},
            }
        }
    }
}

fn update_color_from_key(event: ashet.abi.KeyboardEvent, color: *Color) void {
    const src = color.to_u8();

    const dst = switch (event.usage) {
        .up_arrow => src -% color_per_row,
        .down_arrow => src +% color_per_row,
        .left_arrow => dec_row(src),
        .right_arrow => inc_row(src),
        .page_up => src -% 8 * color_per_row,
        .page_down => src +% 8 * color_per_row,
        else => src,
    };

    color.* = .from_u8(dst);
}

fn render_palette(cq: *ashet.graphics.CommandQueue, fb: ashet.graphics.Framebuffer, selection: Color) !void {
    for (0..256) |index| {
        const color: Color = .from_u8(@intCast(index));
        const x: u15 = @intCast(index % color_per_row);
        const y: u15 = @intCast(index / color_per_row);

        const rect: ashet.abi.Rectangle = .{
            .x = color_size * x,
            .y = color_size * y,
            .width = color_size,
            .height = color_size,
        };

        try cq.fill_rect(rect, color);

        if (color == selection) {
            const outline: Color = if (is_bright(color))
                .black
            else
                .white;

            try cq.draw_rect(rect, outline);
        }
    }

    try cq.submit(fb, .{});
}

fn is_bright(color: Color) bool {
    const rgb = color.to_rgb888();
    return (@as(u16, rgb.r) + rgb.g + rgb.b) > (3 * 255 / 2);
}

fn inc_row(in: u8) u8 {
    var c: ColorRowCol = @bitCast(in);
    c.row +%= 1;
    return @bitCast(c);
}

fn dec_row(in: u8) u8 {
    var c: ColorRowCol = @bitCast(in);
    c.row -%= 1;
    return @bitCast(c);
}

const ColorRowCol = packed struct(u8) {
    const Row = std.meta.Int(.unsigned, std.math.log2_int(u8, color_per_row));
    const Column = std.meta.Int(.unsigned, std.math.log2_int(u8, color_per_column));

    row: Row,
    column: Column,
};
