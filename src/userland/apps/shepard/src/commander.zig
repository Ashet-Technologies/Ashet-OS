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

var current_directory_list: std.ArrayListUnmanaged(ashet.fs.FileInfo) = .empty;

fn get_item_callback(ctx: ?*anyopaque, index: usize, item: *ashet.gui.widgets.ListBox.Item) callconv(.c) void {
    _ = ctx;

    if (index == 0) {
        item.* = .new("./");
        return;
    }

    if (index == 1) {
        item.* = .new("../");
        return;
    }

    const list_index = index - 2;
    if (list_index >= current_directory_list.items.len) {
        item.* = .new("<out of range>");
        return;
    }

    item.* = .new(current_directory_list.items[list_index].getName());
}

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
            .initial_size = Size.new(200, 150),
        },
    );
    defer window.destroy_now();

    const path_box = try ashet.gui.create_widget(window, ashet.gui.widgets.TextBox.uuid);
    defer path_box.release();

    const go_button = try ashet.gui.create_widget(window, ashet.gui.widgets.Button.uuid);
    defer go_button.release();

    const list_box = try ashet.gui.create_widget(window, ashet.gui.widgets.ListBox.uuid);
    defer list_box.release();

    _ = try ashet.gui.place_widget(path_box, .{ .x = 5, .y = 5, .width = 170, .height = 15 });
    _ = try ashet.gui.place_widget(go_button, .{ .x = 180, .y = 5, .width = 15, .height = 15 });
    _ = try ashet.gui.place_widget(list_box, .{ .x = 5, .y = 25, .width = 190, .height = 120 });

    _ = try ashet.gui.control_widget(go_button, ashet.gui.widgets.Button.set_text, .{
        @intFromPtr("→"),
        "→".len,
        0,
        0,
    });

    _ = try ashet.gui.control_widget(path_box, ashet.gui.widgets.TextBox.set_text, .{
        @intFromPtr("SYS:/"),
        "SYS:/".len,
        0,
        0,
    });

    {
        var root_dir: ashet.fs.Directory = try .openDrive(.system, ".");
        defer root_dir.close();

        try root_dir.reset();

        while (try root_dir.next()) |item| {
            std.log.info("read file: {s}", .{item.getName()});

            // Append a / for directory entries
            var copy = item;
            if (copy.attributes.directory) {
                if (std.mem.indexOfScalar(u8, &copy.name, 0)) |index| {
                    @memset(copy.name[index..], 0);
                    copy.name[index] = '/';
                }
            }
            try current_directory_list.append(ashet.process.mem.allocator(), copy);
        }

        _ = try ashet.gui.control_widget(list_box, ashet.gui.widgets.ListBox.set_list, .{
            current_directory_list.items.len + 2,
            @intFromPtr(&get_item_callback),
            0,
            0, // ashet.gui.widgets.ListBox.set_list_clear_selection,
        });
    }

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
                } else if (notify.widget == path_box) {
                    //
                } else if (notify.widget == list_box) {
                    switch (notify.type) {
                        ashet.gui.widgets.ListBox.item_clicked => {
                            std.log.info("clicked item: {}", .{notify.data[0]});
                        },
                        ashet.gui.widgets.ListBox.selected_item_changed => {
                            const index = try ashet.gui.control_widget(
                                list_box,
                                ashet.gui.widgets.ListBox.get_selected_item,
                                .{ 0, 0, 0, 0 },
                            );

                            std.log.info("selected from event: {}", .{notify.data[0]});
                            std.log.info("selected from control: {}", .{index});

                            switch (index) {
                                0 => {}, // clicked on "."
                                1 => {
                                    //  clicked on ".."
                                    std.log.info("selected ..", .{});
                                },

                                else => if (index - 2 < current_directory_list.items.len) {
                                    // clicked on regular file or path

                                    std.log.info("selected {s}", .{
                                        current_directory_list.items[index - 2].getName(),
                                    });
                                },
                            }
                        },
                        else => {},
                    }
                }
            },

            else => {},
        }
    }
}
