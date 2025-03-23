const std = @import("std");

const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");

const model = @import("model.zig");

// const content_dir = @import("build_options").content_dir;
const window_title = "zig-gamedev: minimal zgpu glfw opengl3";

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    try glfw.init();
    defer glfw.terminate();

    // Change current working directory to where the executable is located.
    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.posix.chdir(path) catch {};
    }

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);

    const glfw_window = try glfw.Window.create(800, 500, window_title, null);
    defer glfw_window.destroy();
    glfw_window.setSizeLimits(400, 400, -1, -1);

    glfw.makeContextCurrent(glfw_window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    const gl = zopengl.bindings;

    zgui.init(allocator);
    defer zgui.deinit();

    const scale_factor = scale_factor: {
        const scale = glfw_window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    // _ = zgui.io.addFontFromFile(
    //     content_dir ++ "Roboto-Medium.ttf",
    //     std.math.floor(16.0 * scale_factor),
    // );

    zgui.getStyle().scaleAllSizes(scale_factor);

    zgui.backend.init(glfw_window);
    defer zgui.backend.deinit();

    var window: model.Window = .{};
    defer window.widgets.deinit(allocator);

    try window.widgets.append(allocator, .{
        .class = &classes[0],
        .anchor = .top_left,
        .bounds = .new(.new(10, 10), .new(100, 50)),
    });

    var maybe_selected_widget_index: ?usize = 0;
    var editor: EditorOptions = .{};

    _ = &maybe_selected_widget_index;

    while (!glfw_window.shouldClose()) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = glfw_window.getFramebufferSize();

        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        // Set the starting window position and size to custom values
        zgui.setNextWindowPos(.{ .x = 20.0, .y = 20.0, .cond = .first_use_ever });
        zgui.setNextWindowSize(.{ .w = -1.0, .h = -1.0, .cond = .first_use_ever });

        if (zgui.beginMainMenuBar()) {
            if (zgui.beginMenu("File", true)) {
                defer zgui.endMenu();

                _ = zgui.menuItem("Restore", .{});
                _ = zgui.menuItem("Save", .{});
                zgui.separator();
                if (zgui.menuItem("Close", .{})) {
                    break;
                }
            }

            defer zgui.endMainMenuBar();
        }

        if (zgui.begin("Options", .{})) {
            _ = zgui.checkbox("Show Grid", .{ .v = &editor.render_grid });
            _ = zgui.checkbox("Snap To Grid", .{ .v = &editor.snap_to_grid });
            _ = zgui.inputInt("Grid Size", .{
                .v = &editor.grid_size,
                .step = 1,
                .step_fast = 10,
            });
            editor.grid_size = @max(1, @min(256, editor.grid_size));
        }
        zgui.end();

        if (zgui.begin("Toolbox", .{})) {
            for (classes) |*class| {
                if (zgui.button(class.name, .{ .w = 100 })) {
                    std.debug.print("Button pressed\n", .{});
                }
                if (zgui.beginDragDropSource(.{})) {
                    defer zgui.endDragDropSource();

                    _ = zgui.setDragDropPayload("WIDGET-CLASS", std.mem.asBytes(class), .once);
                }
            }
        }
        zgui.end();

        if (zgui.begin("Window", .{})) {
            const mouse_pos = zgui.getMousePos();
            const base = zgui.getCursorScreenPos();
            const draw = zgui.getWindowDrawList();

            const clicked = zgui.invisibleButton("Window Preview", .{
                .w = @floatFromInt(window.design_size.width),
                .h = @floatFromInt(window.design_size.height),
            });

            if (clicked) {
                std.debug.print("clicked\n", .{});
            }
            if (zgui.isItemActive()) {
                std.debug.print("{any}\n", .{zgui.getMouseDragDelta(.left, .{})});
            }

            draw.addRectFilled(.{
                .pmin = base,
                .pmax = .{
                    base[0] + @as(f32, @floatFromInt(window.design_size.width)),
                    base[1] + @as(f32, @floatFromInt(window.design_size.height)),
                },
                .col = 0xFFCCCCCC,
            });

            if (editor.render_grid) {
                //
            }

            for (window.widgets.items) |widget| {
                paintWidget(draw, base, widget);
            }

            if (zgui.beginDragDropTarget()) {
                defer zgui.endDragDropTarget();

                const pos: model.Point = editor.snap_pos(.new(
                    @intFromFloat(mouse_pos[0] - base[0]),
                    @intFromFloat(mouse_pos[1] - base[1]),
                ));

                if (zgui.getDragDropPayload()) |payload| {
                    if (payload.isDataType("WIDGET-CLASS")) {
                        const payload_ptr: [*]const u8 = @ptrCast(payload.data.?);
                        const payload_slice: []const u8 = payload_ptr[0..@intCast(payload.data_size)];
                        const class: *const model.Class = @alignCast(std.mem.bytesAsValue(model.Class, payload_slice));
                        const new: model.Widget = .{
                            .class = class,
                            .bounds = .new(pos, class.default_size),
                            .anchor = .top_left,
                        };

                        paintWidget(draw, base, new);
                    }
                }

                if (zgui.acceptDragDropPayload("WIDGET-CLASS", .{})) |payload| {
                    const payload_ptr: [*]const u8 = @ptrCast(payload.data.?);
                    const payload_slice: []const u8 = payload_ptr[0..@intCast(payload.data_size)];
                    const class: *const model.Class = @alignCast(std.mem.bytesAsValue(model.Class, payload_slice));
                    const new: model.Widget = .{
                        .class = class,
                        .bounds = .new(pos, class.default_size),
                        .anchor = .top_left,
                    };
                    try window.widgets.append(allocator, new);
                    std.debug.print("hello drop {s}\n", .{class.name});
                }
            }
        }
        zgui.end();

        if (maybe_selected_widget_index) |index| {
            const selected_widget = &window.widgets.items[index];

            if (zgui.begin("Properties", .{})) {
                zgui.textUnformatted("Geometry");

                var pos: [2]i32 = .{ selected_widget.bounds.x, selected_widget.bounds.y };
                var size: [2]i32 = .{ selected_widget.bounds.width, selected_widget.bounds.height };

                if (zgui.inputInt2("Position", .{ .v = &pos })) {
                    selected_widget.bounds.x = @intCast(std.math.clamp(pos[0], std.math.minInt(i16), std.math.maxInt(i16)));
                    selected_widget.bounds.y = @intCast(std.math.clamp(pos[1], std.math.minInt(i16), std.math.maxInt(i16)));
                }
                if (zgui.inputInt2("Size", .{ .v = &size })) {
                    selected_widget.bounds.width = @intCast(std.math.clamp(size[0], std.math.minInt(u15), std.math.maxInt(u15)));
                    selected_widget.bounds.height = @intCast(std.math.clamp(size[1], std.math.minInt(u15), std.math.maxInt(u15)));
                }

                if (zgui.beginTable("Position##position", .{ .column = 3 })) {
                    defer zgui.endTable();

                    zgui.tableNextRow(.{});

                    _ = zgui.tableSetColumnIndex(1);
                    if (zgui.arrowButton("##move-up", .{ .dir = .up }))
                        selected_widget.bounds.y -|= 1;

                    zgui.tableNextRow(.{});

                    _ = zgui.tableSetColumnIndex(0);
                    if (zgui.arrowButton("##move-left", .{ .dir = .left }))
                        selected_widget.bounds.x -|= 1;
                    _ = zgui.tableSetColumnIndex(2);
                    if (zgui.arrowButton("##move-right", .{ .dir = .right }))
                        selected_widget.bounds.x +|= 1;
                    (0);
                    if (zgui.arrowButton("##move-left", .{ .dir = .left }))
                        selected_widget.bounds.x -|= 1;
                    _ = zgui.tableSetColumnIndex(2);
                    if (zgui.arrowButton("##move-right", .{ .dir = .right }))
                        selected_widget.bounds.x +|= 1;

                    zgui.tableNextRow(.{});

                    _ = zgui.tableSetColumnIndex(1);
                    if (zgui.arrowButton("##move-down", .{ .dir = .down }))
                        selected_widget.bounds.y +|= 1;
                }

                zgui.textUnformatted("Anchor");

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

                _ = zgui.checkbox("Visible", .{ .v = &selected_widget.visible });
            }
            zgui.end();
        }

        zgui.backend.draw();

        glfw_window.swapBuffers();
    }
}

fn paintWidget(draw: zgui.DrawList, base: [2]f32, widget: model.Widget) void {
    const x0: f32 = @floatFromInt(widget.bounds.x);
    const y0: f32 = @floatFromInt(widget.bounds.y);

    const x = base[0] + x0;
    const y = base[1] + y0;

    const w: f32 = @floatFromInt(widget.bounds.width);
    const h: f32 = @floatFromInt(widget.bounds.height);

    draw.addRectFilled(.{
        .pmin = .{ x, y },
        .pmax = .{ x + w, y + h },
        .col = 0xFFFFFFFF,
    });
    draw.addTextUnformatted(.{ x + 2, y + 2 }, 0xFF000000, widget.class.name);
    draw.addRect(.{
        .pmin = .{ x, y },
        .pmax = .{ x + w, y + h },
        .col = 0xFF000000,
    });
}

const classes: []const model.Class = &.{
    .{ .name = "Frame" },
    .{ .name = "Label" },
    .{ .name = "Button" },
    .{ .name = "TextBox" },
    .{ .name = "Picture" },
};

const EditorOptions = struct {
    grid_size: i32 = 10,

    render_grid: bool = false,
    snap_to_grid: bool = false,

    pub fn snap_pos(opts: EditorOptions, pos: model.Point) model.Point {
        return .new(opts.snap_value(pos.x), opts.snap_value(pos.y));
    }

    pub fn snap_value(opts: EditorOptions, value: anytype) @TypeOf(value) {
        const gs: u15 = @intCast(opts.grid_size);
        return if (opts.snap_to_grid)
            gs * @divFloor(value, gs)
        else
            value;
    }
};
