const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;

pub fn main() !void {
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv_len = ashet.userland.process.get_arguments(null, &argv_buffer);
    const argv = argv_buffer[0..argv_len];

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    const font = try ashet.graphics.get_system_font("mono-8");

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "GUI Debugger",
            .min_size = Size.new(100, 100),
            .max_size = Size.new(300, 200),
            .initial_size = Size.new(200, 150),
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    var redraw_needed = true;
    var last_key_event: ?ashet.abi.KeyboardEvent = null;
    var last_mouse_event: ?ashet.abi.MouseEvent = null;

    main_loop: while (true) {
        if (redraw_needed) {
            try paint(
                &command_queue,
                framebuffer,
                font,
                last_key_event,
                last_mouse_event,
            );
        }

        const event_res = try ashet.overlapped.performOne(ashet.abi.gui.GetWindowEvent, .{
            .window = window,
        });

        const event = &event_res.event;
        switch (event.event_type) {
            .widget_notify,
            .mouse_enter,
            .mouse_leave,
            .window_minimize,
            .window_restore,
            .window_moving,
            .window_moved,
            => {
                std.log.info("unhandled ui event: {}", .{event.event_type});
            },

            .window_close => break :main_loop,

            .window_resizing,
            .window_resized,
            => {
                redraw_needed = true;
            },

            .mouse_motion => {
                last_mouse_event = event.mouse;
                redraw_needed = true;

                std.log.info("mouse motion at ({}, {})", .{
                    event.mouse.x,
                    event.mouse.y,
                });
            },

            .mouse_button_press, .mouse_button_release => {
                last_mouse_event = event.mouse;
                redraw_needed = true;

                std.log.info("mouse {s} at ({}, {}) of button {s}", .{
                    @tagName(event.event_type)["mouse_button_".len..],
                    event.mouse.x,
                    event.mouse.y,
                    @tagName(event.mouse.button),
                });
            },

            .key_press, .key_release => {
                last_key_event = event.keyboard;
                redraw_needed = true;

                std.log.info("key {s}: pressed={}, scancode={}, key={s}, text='{?}'", .{
                    @tagName(event.event_type)["key_".len..],
                    event.keyboard.pressed,
                    event.keyboard.scancode,
                    @tagName(event.keyboard.key),
                    if (event.keyboard.text) |str|
                        std.unicode.fmtUtf8(std.mem.sliceTo(str, 0))
                    else
                        null,
                });
            },
        }
    }
}

const TablePrinter = struct {
    const header_color = ashet.abi.Color.from_rgb(0xFF, 0x00, 0x00);
    const label_color = ashet.abi.Color.from_rgb(0x00, 0xFF, 0x00);
    const value_color = ashet.abi.Color.from_rgb(0x00, 0x00, 0xFF);
    const line_color = label_color;

    q: *ashet.graphics.CommandQueue,
    font: ashet.graphics.Font,
    anchor: Point,
    width: u15,

    fn header(tp: *TablePrinter, name: []const u8) !void {
        try tp.line(header_color, name);
    }

    fn hr(tp: *TablePrinter) !void {
        try tp.q.draw_horizontal_line(tp.anchor.move_by(0, 1), tp.width, line_color);
        try tp.advance(3);
    }

    fn row(tp: *TablePrinter, name: []const u8) !void {
        try tp.line(label_color, name);
    }

    fn property(tp: *TablePrinter, name: []const u8, comptime fmt: []const u8, args: anytype) !void {
        var buffer: [256]u8 = undefined;
        const value: []const u8 = try std.fmt.bufPrint(&buffer, fmt, args);

        try tp.q.draw_text(tp.anchor, tp.font, label_color, name);
        try tp.advance(8);
        try tp.q.draw_text(tp.anchor.move_by(tp.width / 2, 0), tp.font, value_color, value);
        std.log.info("{} {} '{}' '{}'", .{ tp.anchor, tp.anchor.move_by(tp.width / 2, 0), std.zig.fmtEscapes(name), std.zig.fmtEscapes(value) });
        try tp.advance(8);
    }

    fn line(tp: *TablePrinter, color: ashet.abi.Color, text: []const u8) !void {
        try tp.q.draw_text(tp.anchor, tp.font, color, text);
        try tp.advance(8);
    }

    fn advance(tp: *TablePrinter, h: u15) !void {
        tp.anchor.y += h;
    }
};

fn paint(
    q: *ashet.graphics.CommandQueue,
    fb: ashet.graphics.Framebuffer,
    font: ashet.graphics.Font,
    maybe_key_event: ?ashet.abi.KeyboardEvent,
    maybe_mouse_event: ?ashet.abi.MouseEvent,
) !void {
    try q.clear(ashet.graphics.known_colors.brown);

    var mouse_table: TablePrinter = .{
        .q = q,
        .anchor = Point.new(10, 10),
        .font = font,
        .width = 80,
    };

    try mouse_table.header("Mouse Event");
    try mouse_table.hr();
    if (maybe_mouse_event) |mouse_event| {
        try mouse_table.property("type", "{s}", .{@tagName(mouse_event.event_type.window)});
        try mouse_table.property("abs", "{d}/{d}", .{ mouse_event.x, mouse_event.y });
        try mouse_table.property("rel", "{d}/{d}", .{ mouse_event.dx, mouse_event.dy });
        try mouse_table.property("button", "{s}", .{@tagName(mouse_event.button)});
    } else {
        try mouse_table.row("<none>");
    }

    var key_table: TablePrinter = .{
        .q = q,
        .anchor = Point.new(100, 10),
        .font = font,
        .width = 80,
    };
    try key_table.header("Keyboard Event");
    try key_table.hr();
    if (maybe_key_event) |key_event| {
        _ = key_event;
    } else {
        try key_table.row("<none>");
    }

    try q.submit(fb, .{});
}
