const std = @import("std");

const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const args_parser = @import("args");

const model = @import("model.zig");

pub const CliOptions = struct {
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
    };
};

fn usage_fault(comptime fmt: []const u8, params: anytype) !noreturn {
    const stderr = std.io.getStdErr();
    try stderr.writer().print("gui-editor: " ++ fmt, params);
    std.process.exit(1);
}

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var cli = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli.deinit();

    const metadata = try model.load_metadata(allocator, @embedFile("widget-classes.json"));
    defer metadata.deinit();

    var window: model.Window = .{};
    defer window.deinit(allocator);

    const maybe_save_file_name: ?[]const u8 = switch (cli.positionals.len) {
        0 => null, // Default setup, this is fine
        1 => blk: {
            // Open provided file

            const file = try std.fs.cwd().openFile(cli.positionals[0], .{});
            defer file.close();

            window = try model.load_design(file.reader(), allocator, metadata);

            break :blk cli.positionals[0];
        },
        else => try usage_fault(
            "expects none or a single positional file, but {} were provided",
            .{cli.positionals.len},
        ),
    };

    _ = maybe_save_file_name;

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);
    glfw.windowHint(.wayland_app_id, "computer.ashet.os.gui_editor");

    const glfw_window = try glfw.Window.create(1200, 700, "Ashet GUI Designer", null);
    defer glfw_window.destroy();

    glfw_window.setSizeLimits(400, 400, -1, -1);

    glfw.makeContextCurrent(glfw_window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    const gl = zopengl.bindings;

    zgui.init(allocator);
    defer zgui.deinit();

    zgui.io.setIniFilename(null);

    zgui.backend.init(glfw_window);
    defer zgui.backend.deinit();

    zgui.io.setConfigFlags(.{
        .dock_enable = true,
        .dpi_enable_scale_viewport = true,
    });

    var maybe_selected_widget_index: ?usize = 0;
    var editor: EditorOptions = .{};

    var dock_layout_setup_done = false;

    var previously_window_clicked = false;
    var maybe_popup_widget: ?*model.Widget = null;

    const DragInfo = struct {
        widget: *model.Widget,
        start: model.Point,
    };

    var widget_drag: ?DragInfo = null;

    while (!glfw_window.shouldClose()) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = glfw_window.getFramebufferSize();
        const win_size = glfw_window.getSize();

        const scale_x: f32 = @as(f32, @floatFromInt(fb_size[0])) / @as(f32, @floatFromInt(win_size[0]));
        const scale_y: f32 = @as(f32, @floatFromInt(fb_size[1])) / @as(f32, @floatFromInt(win_size[1]));

        _ = .{ scale_x, scale_y };

        // std.debug.print("fb={any} win={any} {d};{d}\n", .{ fb_size, win_size, scale_x, scale_y });

        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]), scale_x, scale_y);

        const dockspace_id = zgui.DockSpaceOverViewport(0, zgui.getMainViewport(), .{ .auto_hide_tab_bar = true });

        if (!dock_layout_setup_done) {
            dock_layout_setup_done = true;

            var center_dockspace_id = dockspace_id;
            const left_id = zgui.dockBuilderSplitNode(dockspace_id, .left, 0.2, null, &center_dockspace_id);
            const right_id = zgui.dockBuilderSplitNode(center_dockspace_id, .right, 0.4, null, &center_dockspace_id);
            const options_id = zgui.dockBuilderSplitNode(center_dockspace_id, .up, 0.1, null, &center_dockspace_id);

            zgui.dockBuilderDockWindow("Toolbox", left_id);
            zgui.dockBuilderDockWindow("Properties", right_id);
            zgui.dockBuilderDockWindow("Window Designer", center_dockspace_id);
            zgui.dockBuilderDockWindow("Options", options_id);
            zgui.dockBuilderFinish(center_dockspace_id);
        }

        if (zgui.beginMainMenuBar()) {
            if (zgui.beginMenu("File", true)) {
                defer zgui.endMenu();

                _ = zgui.menuItem("Restore", .{});

                if (zgui.menuItem("Save", .{})) {
                    var result_file = try std.fs.cwd().atomicFile("current.gui.json", .{});
                    defer result_file.deinit();

                    try model.save_design(window, result_file.file.writer());

                    try result_file.finish();
                }

                zgui.separator();
                if (zgui.menuItem("Close", .{})) {
                    break;
                }
            }

            defer zgui.endMainMenuBar();
        }

        if (zgui.begin("Options", .{ .flags = .{ .always_auto_resize = true, .no_resize = true } })) {
            _ = zgui.checkbox("Show Grid", .{ .v = &editor.render_grid });

            zgui.sameLine(.{});
            _ = zgui.checkbox("Snap##SnapToGrid", .{ .v = &editor.snap_to_grid });
            zgui.sameLine(.{});

            zgui.textUnformatted("Grid Size");
            zgui.sameLine(.{});
            zgui.setNextItemWidth(80);
            _ = zgui.inputInt("##GridSize", .{
                .v = &editor.grid_size,
                .step = 1,
                .step_fast = 10,
            });
            editor.grid_size = @max(1, @min(256, editor.grid_size));
        }
        zgui.end();

        if (zgui.begin("Toolbox", .{ .flags = .{ .always_vertical_scrollbar = true } })) {
            const w = zgui.getContentRegionAvail()[0];

            for (metadata.get_class_names()) |class_name| {
                if (zgui.button(class_name, .{ .w = w })) {
                    std.debug.print("Button pressed\n", .{});
                }
                if (zgui.beginDragDropSource(.{})) {
                    defer zgui.endDragDropSource();

                    _ = zgui.setDragDropPayload(widget_class_tag, class_name[0 .. class_name.len + 1], .once);
                }
            }
        }
        zgui.end();

        if (zgui.begin("Window Designer", .{})) {
            const base = zgui.getCursorScreenPos();
            const draw = zgui.getWindowDrawList();

            const mouse_pos_raw = zgui.getMousePos();
            const mouse_pos: [2]f32 = .{ @max(0, mouse_pos_raw[0]), @max(0, mouse_pos_raw[1]) };

            const topleft = base;
            const bottomright: [2]f32 = .{
                topleft[0] + @as(f32, @floatFromInt(window.design_size.width)),
                topleft[1] + @as(f32, @floatFromInt(window.design_size.height)),
            };

            const pos: model.Point = .new(
                @intFromFloat(mouse_pos[0] - topleft[0]),
                @intFromFloat(mouse_pos[1] - topleft[1]),
            );

            const maybe_hovered_widget = window.widget_from_pos(pos);

            const is_window_clicked_raw = zgui.invisibleButton("Window Preview", .{
                .w = @floatFromInt(window.design_size.width),
                .h = @floatFromInt(window.design_size.height),
            });

            if (maybe_hovered_widget != null or maybe_popup_widget != null) {
                const maybe_target_widget: ?*model.Widget = if (maybe_popup_widget) |popup|
                    popup
                else if (maybe_hovered_widget) |tup|
                    tup[1]
                else
                    null;

                if (maybe_target_widget) |target_widget| {
                    if (zgui.beginPopupContextWindow()) {
                        defer zgui.endPopup();

                        maybe_popup_widget = target_widget;

                        _ = zgui.menuItem("Copy", .{});
                        _ = zgui.menuItem("Cut", .{});
                        _ = zgui.separator();
                        _ = zgui.menuItem("Snap position to grid", .{});
                        _ = zgui.menuItem("Shrink size to grid", .{});
                        _ = zgui.menuItem("Grow size to grid", .{});
                        _ = zgui.separator();
                        _ = zgui.menuItem("Bring to front", .{});
                        _ = zgui.menuItem("Send to back", .{});
                        _ = zgui.menuItem("Raise one layer", .{});
                        _ = zgui.menuItem("Lower one layer", .{});
                        _ = zgui.separator();
                        _ = zgui.menuItem("Delete", .{});
                    } else {
                        maybe_popup_widget = null;
                    }
                } else {
                    std.debug.assert(maybe_popup_widget == null);
                }
            }

            const is_window_pressed = zgui.isItemActive();
            defer previously_window_clicked = is_window_pressed;

            const mouse_down = is_window_pressed and !previously_window_clicked;
            const mouse_up = !is_window_pressed and previously_window_clicked;
            _ = mouse_down;

            const drag_fdx, const drag_fdy = zgui.getMouseDragDelta(.left, .{});

            const drag_dx: i16 = @intFromFloat(drag_fdx);
            const drag_dy: i16 = @intFromFloat(drag_fdy);

            const dragging = (widget_drag != null);
            const is_window_clicked = is_window_clicked_raw and !dragging;

            defer if (mouse_up) {
                widget_drag = null;
            };

            if (widget_drag) |drag| {
                const newpos = editor.snap_pos(.new(
                    drag.start.x +| drag_dx,
                    drag.start.y +| drag_dy,
                ));

                drag.widget.bounds.x = newpos.x;
                drag.widget.bounds.y = newpos.y;
            } else {
                // "Not dragging"
                if (is_window_clicked) {
                    if (maybe_hovered_widget) |_clicked_widget| {
                        const index, const clicked_window = _clicked_widget;
                        maybe_selected_widget_index = index;

                        std.debug.print("clicked {} => {}, {*}\n", .{ pos, index, clicked_window });
                    } else {
                        maybe_selected_widget_index = null;
                    }
                } else if (is_window_pressed) {
                    if (maybe_hovered_widget) |_hovered_widget| {
                        const index, const hovered_widget = _hovered_widget;

                        if (index == maybe_selected_widget_index and (drag_dx != 0 or drag_dy != 0)) {
                            widget_drag = .{
                                .widget = hovered_widget,
                                .start = hovered_widget.bounds.position(),
                            };
                        }
                    }
                }
            }

            draw.addRectFilled(.{
                .pmin = topleft,
                .pmax = bottomright,
                .col = 0xFFCCCCCC,
            });

            if (window.min_size.width > 0 and window.min_size.width < window.max_size.width and window.min_size.height > 0 and window.min_size.height < window.max_size.height) {
                const min_bottomright: [2]f32 = .{
                    topleft[0] + @as(f32, @floatFromInt(window.min_size.width)),
                    topleft[1] + @as(f32, @floatFromInt(window.min_size.height)),
                };
                draw.addRectFilled(.{
                    .pmin = topleft,
                    .pmax = min_bottomright,
                    .col = 0x10000000,
                });
            }

            if (editor.render_grid and editor.grid_size > 1) {
                const grid_increment: f32 = @floatFromInt(editor.grid_size);
                std.debug.assert(grid_increment > 0);

                var x: f32 = topleft[0];
                while (x < bottomright[0]) : (x += grid_increment) {
                    draw.addLine(.{
                        .p1 = .{ x, topleft[1] },
                        .p2 = .{ x, bottomright[1] },
                        .col = 0xFFAAAAAA,
                        .thickness = 1,
                    });
                }

                var y: f32 = topleft[1];
                while (y < bottomright[1]) : (y += grid_increment) {
                    draw.addLine(.{
                        .p1 = .{ topleft[0], y },
                        .p2 = .{ bottomright[0], y },
                        .col = 0xFFAAAAAA,
                        .thickness = 1,
                    });
                }
            }
            for (window.widgets.items, 0..) |widget, index| {
                paintWidget(draw, base, widget, maybe_selected_widget_index == index);
            }

            if (zgui.beginDragDropTarget()) {
                defer zgui.endDragDropTarget();

                if (zgui.getDragDropPayload()) |payload| {
                    if (widget_from_payload(metadata, editor, payload, pos)) |widget| {
                        paintWidget(draw, base, widget, false);
                    }
                }

                if (zgui.acceptDragDropPayload(widget_class_tag, .{})) |payload| {
                    if (widget_from_payload(metadata, editor, payload, pos)) |widget| {
                        try window.widgets.append(allocator, widget);
                        maybe_selected_widget_index = window.widgets.items.len - 1;
                        widget_drag = null;
                        std.debug.print("hello drop {s}\n", .{widget.class.name});
                    }
                }
            }

            if (maybe_selected_widget_index == null) {
                draw.addRect(.{
                    .pmin = .{ topleft[0] - 2, topleft[1] - 2 },
                    .pmax = .{ bottomright[0] + 2, bottomright[1] + 2 },
                    .col = 0xFF00FFFF,
                });
            }
        }
        zgui.end();

        zgui.setNextWindowSize(.{ .w = 300, .h = -1, .cond = .once });
        if (zgui.begin("Properties", .{})) {
            if (zgui.beginTable("##PropertiesTable", .{ .column = 2, .flags = .{} })) {
                defer zgui.endTable();

                zgui.tableSetupColumn("Key", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 100 });
                zgui.tableSetupColumn("Value", .{ .flags = .{ .width_stretch = true }, .init_width_or_height = -1 });

                const Utils = struct {
                    first: bool = true,

                    pub fn header(self: *@This(), name: [:0]const u8) void {
                        defer self.first = false;

                        if (!self.first) {
                            zgui.tableNextRow(.{ .min_row_height = 20 });
                        }
                        zgui.tableNextRow(.{ .row_flags = .{ .headers = true } });

                        _ = zgui.tableNextColumn();

                        zgui.textUnformatted(name);
                    }

                    pub fn beginField(self: @This(), name: [:0]const u8) void {
                        _ = self;

                        zgui.tableNextRow(.{});

                        _ = zgui.tableNextColumn();
                        zgui.textUnformatted(name);
                        _ = zgui.tableNextColumn();
                    }

                    pub fn sizeField(self: @This(), comptime display: [:0]const u8, value_ptr: anytype, min: anytype, max: anytype) void {
                        self.beginField(display);

                        zgui.beginDisabled(.{ .disabled = min >= max });
                        defer zgui.endDisabled();

                        var value: i32 = value_ptr.*;

                        _ = zgui.dragInt("##edit_" ++ display, .{ .v = &value });

                        zgui.sameLine(.{});
                        if (zgui.button("-##minus_" ++ display, .{})) {
                            value -|= 1;
                        }
                        zgui.sameLine(.{});

                        if (zgui.button("+##plus_" ++ display, .{})) {
                            value +|= 1;
                        }

                        value = std.math.clamp(value, min, max);

                        value_ptr.* = @intCast(value);
                    }
                };
                var utils: Utils = .{};

                if (maybe_selected_widget_index) |index| {
                    const selected_widget = &window.widgets.items[index];

                    utils.header("Widget");

                    utils.header("General");

                    // zgui.tableNextRow(.{});

                    {
                        utils.beginField("Class");

                        zgui.beginDisabled(.{ .disabled = true });
                        defer zgui.endDisabled();

                        var textinput: [256:0]u8 = @splat(0);
                        std.mem.copyForwards(u8, &textinput, selected_widget.class.name);
                        _ = zgui.inputText("##ClassName", .{ .buf = &textinput });
                    }

                    {
                        utils.beginField("Identifier");

                        var nameBuffer: [32:0]u8 = @splat(0);
                        _ = zgui.inputText("##name", .{
                            .buf = &nameBuffer,
                        });
                    }

                    utils.header("Geometry");

                    utils.sizeField("X", &selected_widget.bounds.x, std.math.minInt(i16), std.math.maxInt(i16));
                    utils.sizeField("Y", &selected_widget.bounds.y, std.math.minInt(i16), std.math.maxInt(i16));

                    utils.sizeField("Width", &selected_widget.bounds.width, selected_widget.class.min_size.width, selected_widget.class.max_size.width);
                    utils.sizeField("Height", &selected_widget.bounds.height, selected_widget.class.min_size.height, selected_widget.class.max_size.height);

                    utils.beginField("Anchor");

                    if (zgui.beginTable("Anchor##anchor", .{ .column = 3 })) {
                        defer zgui.endTable();

                        zgui.tableNextRow(.{});

                        _ = zgui.tableSetColumnIndex(1);
                        _ = zgui.checkbox("Top", .{ .v = &selected_widget.anchor.top });

                        zgui.tableNextRow(.{});

                        _ = zgui.tableSetColumnIndex(0);
                        _ = zgui.checkbox("Left", .{ .v = &selected_widget.anchor.left });
                        _ = zgui.tableSetColumnIndex(2);
                        _ = zgui.checkbox("Right", .{ .v = &selected_widget.anchor.right });

                        zgui.tableNextRow(.{});

                        _ = zgui.tableSetColumnIndex(1);
                        _ = zgui.checkbox("Bottom", .{ .v = &selected_widget.anchor.bottom });
                    }

                    utils.header("Visuals");

                    utils.beginField("Visible");
                    _ = zgui.checkbox("##Visible", .{ .v = &selected_widget.visible });

                    if (selected_widget.class.properties.count() > 0) {
                        utils.header("Widget Properties");

                        for (selected_widget.class.properties.keys(), selected_widget.class.properties.values()) |prop_name, prop_desc| {
                            const gop = try selected_widget.properties.getOrPut(allocator, prop_name);
                            if (!gop.found_existing) {
                                gop.value_ptr.* = prop_desc.default_value;
                            }

                            utils.beginField(prop_name);

                            var key_buf: [256]u8 = undefined;
                            const field_key = try std.fmt.bufPrintZ(&key_buf, "##userprop_{s}", .{prop_name});

                            switch (gop.value_ptr.*) {
                                .bool => |*data| _ = zgui.checkbox(field_key, .{ .v = data }),

                                .int => |*data| _ = zgui.inputInt(field_key, .{ .v = data }),
                                .float => |*data| _ = zgui.inputFloat(field_key, .{ .v = data }),
                                .string => |*data| {
                                    _ = zgui.inputText(field_key, .{ .buf = &data.data });
                                },
                                .color => |*data| {
                                    const rgb = data.to_rgb888();
                                    var rgbf: [3]f32 = .{
                                        @floatFromInt(rgb.r),
                                        @floatFromInt(rgb.g),
                                        @floatFromInt(rgb.b),
                                    };
                                    _ = zgui.colorEdit3(field_key, .{ .col = &rgbf });

                                    data.* = .from_rgbf(rgbf[0], rgbf[1], rgbf[2]);
                                },
                            }
                        }
                    }
                } else {
                    // Window/Design Properties
                    utils.header("Window");

                    utils.header("Geometry");

                    utils.sizeField("Min Width", &window.min_size.width, 0, window.max_size.width);
                    utils.sizeField("Min Height", &window.min_size.height, 0, window.max_size.height);

                    utils.sizeField("Max Width", &window.max_size.width, window.min_size.width, std.math.maxInt(u15));
                    utils.sizeField("Max Height", &window.max_size.height, window.min_size.height, std.math.maxInt(u15));

                    utils.sizeField("Design Width", &window.design_size.width, window.min_size.width, window.max_size.width);
                    utils.sizeField("Design Height", &window.design_size.height, window.min_size.height, window.max_size.height);
                }
            }

            zgui.end();
        }

        zgui.backend.draw();

        glfw_window.swapBuffers();
    }
    return 0;
}

const DragDropPayload = @TypeOf(zgui.getDragDropPayload().?.*);

const widget_class_tag = "WIDGET-CLASS";

fn widget_from_payload(
    metadata: *const model.Metadata,
    options: EditorOptions,
    payload: *DragDropPayload,
    center: model.Point,
) ?model.Widget {
    if (!payload.isDataType(widget_class_tag))
        return null;

    const payload_ptr: [*]const u8 = @ptrCast(payload.data.?);
    const payload_slice: [:0]const u8 = payload_ptr[0..@intCast(payload.data_size - 1) :0];

    const class = metadata.class_by_name(payload_slice) orelse return null;

    const new: model.Widget = .{
        .class = class,
        .bounds = .new(
            options.snap_pos(.new(
                center.x -| @as(i16, @intCast(class.default_size.width / 2)),
                center.y -| @as(i16, @intCast(class.default_size.height / 2)),
            )),
            class.default_size,
        ),
        .anchor = .top_left,
    };

    return new;
}

fn paintWidget(draw: zgui.DrawList, base: [2]f32, widget: model.Widget, selected: bool) void {
    const x0: f32 = @floatFromInt(widget.bounds.x);
    const y0: f32 = @floatFromInt(widget.bounds.y);

    const x = base[0] + x0;
    const y = base[1] + y0;

    const w: f32 = @floatFromInt(widget.bounds.width);
    const h: f32 = @floatFromInt(widget.bounds.height);

    {
        draw.pushClipRect(.{
            .pmin = .{ x, y },
            .pmax = .{ x + w, y + h },
            .intersect_with_current = true,
        });
        defer draw.popClipRect();

        draw.addRectFilled(.{
            .pmin = .{ x, y },
            .pmax = .{ x + w, y + h },
            .col = 0xFFFFFFFF,
        });

        if (w > 4 and h > 2) {
            if (widget.anchor.left) {
                draw.addLine(.{
                    .p1 = .{ x + 1, y + 1 },
                    .p2 = .{ x + 1, y + h - 2 },
                    .col = 0xFF0088CC,
                    .thickness = 1,
                });
            }
            if (widget.anchor.right) {
                draw.addLine(.{
                    .p1 = .{ x + w - 2, y + 1 },
                    .p2 = .{ x + w - 2, y + h - 2 },
                    .col = 0xFF0088CC,
                    .thickness = 1,
                });
            }
        }

        if (w > 2 and h > 4) {
            if (widget.anchor.top) {
                draw.addLine(.{
                    .p1 = .{ x + 1, y + 1 },
                    .p2 = .{ x + w - 2, y + 1 },
                    .col = 0xFF0088CC,
                    .thickness = 1,
                });
            }
            if (widget.anchor.bottom) {
                draw.addLine(.{
                    .p1 = .{ x + 1, y + h - 2 },
                    .p2 = .{ x + w - 2, y + h - 2 },
                    .col = 0xFF0088CC,
                    .thickness = 1,
                });
            }
        }

        draw.addTextUnformatted(.{ x + 2, y + 2 }, 0xFF000000, widget.class.name);

        draw.addRect(.{
            .pmin = .{ x, y },
            .pmax = .{ x + w, y + h },
            .col = 0xFF000000,
        });
    }

    if (selected) {
        draw.addRect(.{
            .pmin = .{ x - 2, y - 2 },
            .pmax = .{ x + w + 2, y + h + 2 },
            .col = 0xFF00FFFF,
        });
    }
}

const EditorOptions = struct {
    grid_size: i32 = 10,

    render_grid: bool = true,
    snap_to_grid: bool = true,

    pub fn snap_pos(opts: EditorOptions, pos: model.Point) model.Point {
        return .new(opts.snap_value(pos.x), opts.snap_value(pos.y));
    }

    pub fn snap_value(opts: EditorOptions, value: anytype) @TypeOf(value) {
        const gs: u15 = @intCast(opts.grid_size);
        return if (opts.snap_to_grid)
            gs * @divFloor(value + gs / 2, gs)
        else
            value;
    }
};
