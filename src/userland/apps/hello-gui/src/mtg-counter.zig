const std = @import("std");
const ashet = @import("ashet");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

const UUID = ashet.abi.UUID;
const Size = ashet.abi.Size;
const Point = ashet.abi.Point;

pub fn main() !void {
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = try ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);
    defer desktop.release();
    std.log.info("using desktop {f}", .{desktop});

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "MTG Counter",
            .initial_size = Size.new(82, 50),
        },
    );
    defer window.destroy_now();
    std.log.info("created window: {f}", .{window});

    const inc_button = try ashet.gui.create_widget(window, ashet.gui.widgets.Button.uuid);
    defer inc_button.release();

    const count_label = try ashet.gui.create_widget(window, ashet.gui.widgets.Label.uuid);
    defer count_label.release();

    const dec_button = try ashet.gui.create_widget(window, ashet.gui.widgets.Button.uuid);
    defer dec_button.release();

    _ = try ashet.gui.place_widget(inc_button, .{ .x = 42, .y = 22, .width = 30, .height = 18 });
    _ = try ashet.gui.place_widget(count_label, .{ .x = 10, .y = 10, .width = 62, .height = 8 });
    _ = try ashet.gui.place_widget(dec_button, .{ .x = 10, .y = 22, .width = 30, .height = 18 });

    _ = try ashet.gui.control_widget(inc_button, ashet.gui.widgets.Button.set_text, .{
        @intFromPtr("+"),
        "+".len,
        0,
        0,
    });

    _ = try ashet.gui.control_widget(dec_button, ashet.gui.widgets.Button.set_text, .{
        @intFromPtr("-"),
        "-".len,
        0,
        0,
    });

    try set_label_int(count_label, 0);

    var counter: i32 = 0;

    std.log.info("created  {f} {f} {f}", .{
        inc_button,
        count_label,
        dec_button,
    });

    main_loop: while (true) {
        const event = try ashet.gui.get_window_event(window);

        switch (event) {
            .window_close => break :main_loop,

            .widget_notify => |notify| {
                std.log.info("widget notify widget={f}, type={}, data={{ {}, {}, {}, {} }}", .{
                    notify.widget,
                    notify.type,
                    notify.data[0],
                    notify.data[1],
                    notify.data[2],
                    notify.data[3],
                });

                if (notify.widget == inc_button) {
                    counter +|= 1;
                    try set_label_int(count_label, counter);
                } else if (notify.widget == dec_button) {
                    counter -|= 1;
                    try set_label_int(count_label, counter);
                } else {
                    std.log.err("unknown widget!?", .{});
                }
            },

            else => {},
        }
    }
}

fn set_label_int(label: ashet.gui.Widget, number: i32) !void {
    var buffer: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{}", .{number}) catch unreachable;

    _ = try ashet.gui.control_widget(label, ashet.gui.widgets.Label.set_text, .{
        @intFromPtr(text.ptr),
        text.len,
        0,
        0,
    });
}
