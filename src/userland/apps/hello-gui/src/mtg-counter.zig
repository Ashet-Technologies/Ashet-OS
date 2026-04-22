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

    const inc_button = try ashet.gui.widgets.Button.create(window);
    defer inc_button.destroy();

    const count_label = try ashet.gui.widgets.Label.create(window);
    defer count_label.destroy();

    const dec_button = try ashet.gui.widgets.Button.create(window);
    defer dec_button.destroy();

    _ = try inc_button.place(.{ .x = 42, .y = 22, .width = 30, .height = 18 });
    _ = try count_label.place(.{ .x = 10, .y = 10, .width = 62, .height = 8 });
    _ = try dec_button.place(.{ .x = 10, .y = 22, .width = 30, .height = 18 });

    try inc_button.set_text("+");
    try dec_button.set_text("-");

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

                if (inc_button.eql(notify.widget)) {
                    counter +|= 1;
                    try set_label_int(count_label, counter);
                } else if (dec_button.eql(notify.widget)) {
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

fn set_label_int(label: *ashet.gui.widgets.Label, number: i32) !void {
    var buffer: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{}", .{number}) catch unreachable;
    try label.set_text(text);
}
