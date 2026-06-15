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

var list_box: *ashet.gui.widgets.ListBox = undefined;
var current_dir: ashet.fs.Directory = undefined;

fn change_dir(new_path: []const u8) !void {
    std.debug.assert(!std.mem.endsWith(u8, new_path, "/"));

    var next_dir = try current_dir.openDir(new_path);
    errdefer next_dir.close();

    // We're using a in-place scheme for fetching and updating:
    // We first append to the new list, then we copy the new items into the old
    // ones, and finally resize to the new length.
    //
    // This gives us trivial error recover, and doesn't use more memory than
    // allocating a new list and freeing the old one.
    {
        const old_count = current_directory_list.items.len;
        errdefer current_directory_list.shrinkRetainingCapacity(old_count);

        try next_dir.reset();

        while (try next_dir.next()) |item| {
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

        const total_count = current_directory_list.items.len;
        const new_count = total_count - old_count;

        errdefer @compileError("We must succeed in the current block, otherwise we corrupt memory");

        std.mem.copyForwards(
            ashet.fs.FileInfo,
            current_directory_list.items[0..new_count],
            current_directory_list.items[old_count..total_count],
        );

        current_directory_list.shrinkRetainingCapacity(new_count);

        current_dir.close();
        current_dir = next_dir;
    }

    // Setup the new list:
    try list_box.set_list(
        current_directory_list.items.len + 2,
        &get_item_callback,
        null,
        -1,
    );
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
            .initial_size = .new(200, 150),
            .max_size = .new(800, 480),
        },
    );
    defer window.destroy_now();

    const path_box = try ashet.gui.widgets.TextBox.create(window);
    defer path_box.destroy();

    const go_button = try ashet.gui.widgets.Button.create(window);
    defer go_button.destroy();

    list_box = try ashet.gui.widgets.ListBox.create(window);
    defer list_box.destroy();

    _ = try path_box.place(.{ .x = 5, .y = 5, .width = 170, .height = 15 });
    _ = try go_button.place(.{ .x = 180, .y = 5, .width = 15, .height = 15 });
    _ = try list_box.place(.{ .x = 5, .y = 25, .width = 190, .height = 120 });

    try go_button.set_text("→");
    try path_box.set_text("SYS:/");

    current_dir = try .openDrive(.system, ".");
    defer current_dir.close();

    try change_dir(".");

    const Router = ashet.gui.EventRouter(struct {
        path_box: *ashet.gui.widgets.TextBox,
        go_button: *ashet.gui.widgets.Button,
        list_box: *ashet.gui.widgets.ListBox,
    });

    const router: Router = .init(.{
        .path_box = path_box,
        .go_button = go_button,
        .list_box = list_box,
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

                if (router.match(&notify)) |event_pos| {
                    switch (event_pos) {
                        .go_button => |evt| {
                            _ = evt;
                        },
                        .path_box => |evt| {
                            _ = evt;
                        },
                        .list_box => |evt| {
                            switch (evt) {
                                .item_clicked => |clicked| {
                                    const index = clicked.index;
                                    std.log.info("clicked item: {}", .{index});

                                    switch (index) {
                                        0 => {}, // clicked on "."
                                        1 => {
                                            //  clicked on ".."
                                            std.log.info("selected ..", .{});

                                            try change_dir("..");
                                        },

                                        else => if (index - 2 < current_directory_list.items.len) {
                                            // clicked on regular file or path
                                            const info = current_directory_list.items[index - 2];

                                            if (info.attributes.directory) {
                                                const name = info.getName();
                                                std.debug.assert(std.mem.endsWith(u8, name, "/"));
                                                try change_dir(name[0 .. name.len - 1]);
                                            }
                                        },
                                    }
                                },
                                .selected_item_changed => |data| {
                                    const index = try list_box.get_selected_item();

                                    std.log.info("selected from event: {}", .{data.index});
                                    std.log.info("selected from control: {}", .{index});

                                    // TODO: Render the cached file info
                                },
                            }
                        },
                    }
                }
            },

            else => {},
        }
    }
}
