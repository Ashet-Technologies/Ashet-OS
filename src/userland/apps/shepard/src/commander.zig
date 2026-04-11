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

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Shepard",
            .initial_size = Size.new(82, 150),
        },
    );
    defer window.destroy_now();

    const path_box = try ashet.gui.create_widget(window, ashet.gui.widgets.TextBox.uuid);
    defer path_box.release();

    const go_button = try ashet.gui.create_widget(window, ashet.gui.widgets.ToolButton.uuid);
    defer go_button.release();

    const list_box = try ashet.gui.create_widget(window, ashet.gui.widgets.ListBox.uuid);
    defer list_box.release();

    _ = try ashet.gui.place_widget(path_box, .{ .x = 10, .y = 10, .width = 50, .height = 12 });
    _ = try ashet.gui.place_widget(go_button, .{ .x = 63, .y = 11, .width = 9, .height = 9 });
    _ = try ashet.gui.place_widget(list_box, .{ .x = 10, .y = 30, .width = 59, .height = 100 });

    // try ashet.gui.control_widget(inc_button, ashet.gui.widgets.Button.set_text, .{
    //     @intFromPtr("+"),
    //     "+".len,
    //     0,
    //     0,
    // });

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

                if (notify.widget == go_button) {
                    //
                }
            },

            else => {},
        }
    }
}
