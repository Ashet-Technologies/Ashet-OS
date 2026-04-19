const std = @import("std");

const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const args_parser = @import("args");
const agp = @import("agp");
const ashet = @import("ashet");
const agp_swrast = @import("agp-swrast");
const standard_widgets = @import("standard-widgets");

const gl = zopengl.bindings;

const Color = @import("ashet-abi").Color;
const model = @import("model.zig");

const CommandQueue = ashet.graphics.CommandQueue;
const Size = model.Size;
const Point = model.Point;
const Rectangle = model.Rectangle;
const Widget = model.Widget;
const Window = model.Window;
const Document = model.Document;
const Alignment = model.Alignment;

const PreviewTheme = standard_widgets.Theme;

const preview_texture_extent = 2048;

const preview_sans_6_font: ashet.graphics.Font = embed_preview_font(@embedFile("sans-6.font"), .{});
const preview_mono_8_font: ashet.graphics.Font = embed_preview_font(@embedFile("mono-8.font"), .{});

const preview_palette = blk: {
    @setEvalBranchQuota(8192);
    var palette: [256][4]u8 = undefined;
    for (&palette, 0..) |*entry, index| {
        const rgb = Color.to_rgb888(Color.from_u8(@intCast(index)));
        entry.* = .{ rgb.r, rgb.g, rgb.b, 0xFF };
    }
    break :blk palette;
};

const PreviewSurface = struct {
    texture: gl.Uint = 0,
    indexed_pixels: []Color = &.{},
    rgba_pixels: []u8 = &.{},
    used_size: Size = .new(0, 0),
    dirty: bool = true,

    fn ensureInitialized(surface: *PreviewSurface, allocator: std.mem.Allocator) !void {
        const pixel_count = preview_texture_extent * preview_texture_extent;

        if (surface.indexed_pixels.len == 0) {
            surface.indexed_pixels = try allocator.alloc(Color, pixel_count);
            @memset(surface.indexed_pixels, .black);
        }

        if (surface.rgba_pixels.len == 0) {
            surface.rgba_pixels = try allocator.alloc(u8, pixel_count * 4);
            @memset(surface.rgba_pixels, 0);
        }

        if (surface.texture == 0) {
            gl.genTextures(1, @ptrCast(&surface.texture));
            gl.bindTexture(gl.TEXTURE_2D, surface.texture);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texImage2D(
                gl.TEXTURE_2D,
                0,
                gl.RGBA8,
                preview_texture_extent,
                preview_texture_extent,
                0,
                gl.RGBA,
                gl.UNSIGNED_BYTE,
                @ptrCast(surface.rgba_pixels.ptr),
            );
        }
    }

    fn deinit(surface: *PreviewSurface, allocator: std.mem.Allocator) void {
        if (surface.texture != 0) {
            gl.deleteTextures(1, @ptrCast(&surface.texture));
            surface.texture = 0;
        }

        if (surface.rgba_pixels.len > 0) {
            allocator.free(surface.rgba_pixels);
            surface.rgba_pixels = &.{};
        }

        if (surface.indexed_pixels.len > 0) {
            allocator.free(surface.indexed_pixels);
            surface.indexed_pixels = &.{};
        }

        surface.used_size = .new(0, 0);
        surface.dirty = true;
    }

    fn clear(surface: *PreviewSurface, color: Color) void {
        const width: usize = surface.used_size.width;
        const height: usize = surface.used_size.height;

        for (0..height) |row| {
            const row_offset = row * preview_texture_extent;
            @memset(surface.indexed_pixels[row_offset .. row_offset + width], color);
        }
    }

    fn expandToRgba(surface: *PreviewSurface) void {
        const width: usize = surface.used_size.width;
        const height: usize = surface.used_size.height;

        for (0..height) |row| {
            const row_offset = row * preview_texture_extent;
            for (0..width) |col| {
                const pixel_offset = row_offset + col;
                const rgba_offset = pixel_offset * 4;
                const color = preview_palette[surface.indexed_pixels[pixel_offset].to_u8()];

                surface.rgba_pixels[rgba_offset + 0] = color[0];
                surface.rgba_pixels[rgba_offset + 1] = color[1];
                surface.rgba_pixels[rgba_offset + 2] = color[2];
                surface.rgba_pixels[rgba_offset + 3] = color[3];
            }
        }
    }

    fn upload(surface: *PreviewSurface) void {
        if (surface.used_size.width == 0 or surface.used_size.height == 0)
            return;

        surface.expandToRgba();

        gl.bindTexture(gl.TEXTURE_2D, surface.texture);
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.pixelStorei(gl.UNPACK_ROW_LENGTH, preview_texture_extent);
        gl.texSubImage2D(
            gl.TEXTURE_2D,
            0,
            0,
            0,
            @intCast(surface.used_size.width),
            @intCast(surface.used_size.height),
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            @ptrCast(surface.rgba_pixels.ptr),
        );
        gl.pixelStorei(gl.UNPACK_ROW_LENGTH, 0);
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 4);
    }
};

pub const CliOptions = struct {
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
    };
};

fn usage_fault(comptime fmt: []const u8, params: anytype) !noreturn {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    try stderr_writer.interface.print("gui-editor: " ++ fmt, params);
    try stderr_writer.interface.flush();
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

    const preview_theme = try standard_widgets.initialize_default_theme(load_preview_font);

    var document: Document = .{
        .allocator = allocator,
        .window = .{},
    };
    defer document.deinit();

    const maybe_save_file_name: ?[]const u8 = switch (cli.positionals.len) {
        0 => null, // Default setup, this is fine
        1 => blk: {
            // Open provided file

            const file = try std.fs.cwd().openFile(cli.positionals[0], .{});
            defer file.close();

            var file_buffer: [2048]u8 = undefined;
            var file_reader = file.reader(&file_buffer);

            document = try model.load_design(
                &file_reader.interface,
                document.allocator,
                metadata,
            );

            break :blk cli.positionals[0];
        },
        else => try usage_fault(
            "expects none or a single positional file, but {} were provided",
            .{cli.positionals.len},
        ),
    };

    var editor: Editor = .{
        .document = &document,
        .metadata = metadata,
        .allocator = allocator,
        .preview_theme = preview_theme,
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

    const glfw_window = try glfw.Window.create(1200, 700, "Ashet GUI Designer", null, null);
    defer glfw_window.destroy();

    glfw_window.setSizeLimits(400, 400, -1, -1);

    glfw.makeContextCurrent(glfw_window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    zgui.init(allocator);
    defer zgui.deinit();

    defer editor.deinit();

    zgui.io.setIniFilename(null);

    zgui.backend.init(glfw_window);
    defer zgui.backend.deinit();

    zgui.io.setConfigFlags(.{
        .dock_enable = true,
        .dpi_enable_scale_viewport = true,
    });

    while (!glfw_window.shouldClose()) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0, 0, 0, 1.0 });

        const fb_size = glfw_window.getFramebufferSize();
        const win_size = glfw_window.getSize();

        const scale_x: f32 = @as(f32, @floatFromInt(fb_size[0])) / @as(f32, @floatFromInt(win_size[0]));
        const scale_y: f32 = @as(f32, @floatFromInt(fb_size[1])) / @as(f32, @floatFromInt(win_size[1]));

        _ = .{ scale_x, scale_y };

        // std.debug.print("fb={any} win={any} {d};{d}\n", .{ fb_size, win_size, scale_x, scale_y });

        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));

        editor.handle_gui() catch |err| switch (err) {
            error.AppExit => break,
            else => |e| return e,
        };

        zgui.backend.draw();

        glfw_window.swapBuffers();
    }
    return 0;
}

pub const Editor = struct {
    const DragInfo = struct {
        widget: *model.Widget,
        start: model.Point,
    };

    allocator: std.mem.Allocator,

    // Editor Configuration
    options: EditorOptions = .{},
    dock_layout_setup_done: bool = false,

    // Current Document
    metadata: *const model.Metadata,
    document: *Document,
    preview_theme: *const PreviewTheme,

    // Current Editing State
    maybe_selected_widget_index: ?usize = null,

    previously_window_clicked: bool = false,
    maybe_popup_widget: ?model.WidgetRef = null,

    widget_drag: ?DragInfo = null,

    preview_surface: PreviewSurface = .{},
    preview_visible: bool = false,

    pub fn deinit(editor: *Editor) void {
        editor.preview_surface.deinit(editor.document.allocator);
    }

    pub fn handle_gui(editor: *Editor) !void {
        editor.setup_dockspace();

        try editor.handle_mainmenu_bar();
        try editor.handle_options_gui();
        try editor.handle_toolbox_gui();
        try editor.handle_designer_gui();
        try editor.handle_properties_gui();
        try editor.handle_hierarchy_gui();
        try editor.handle_preview_window();
    }

    fn get_selected_widget(editor: *Editor) ?*model.Widget {
        return if (editor.maybe_selected_widget_index) |index|
            &editor.document.window.widgets.items[index]
        else
            null;
    }

    fn select_by_index(editor: *Editor, index: ?usize) void {
        editor.maybe_selected_widget_index = index;
        editor.widget_drag = null;
    }

    fn invalidate_preview(editor: *Editor) void {
        editor.preview_surface.dirty = true;
    }

    fn touch(editor: *Editor, changed: bool) void {
        if (changed)
            editor.invalidate_preview();
    }

    fn move_to_index(editor: *Editor, action: struct { from: usize, to: usize }) void {
        const widgets = editor.document.window.widgets.items;

        const from = @min(action.from, widgets.len -| 1);
        const to = @min(action.to, widgets.len -| 1);

        std.log.debug("move_to_index(from={}, to={})", .{ from, to });

        if (from == to)
            return;

        std.debug.assert(from < widgets.len);
        std.debug.assert(to < widgets.len);

        if (from == to + 1 or from + 1 == to) {
            // Distance is 1, we can just swap the elements without doing more complex operations:
            std.mem.swap(model.Widget, &widgets[from], &widgets[to]);
        } else {
            // Determine the window where we will operate in:
            const low = @min(from, to);
            const high = @max(from, to);
            const move_range: []model.Widget = widgets[low .. high + 1];
            const count = move_range.len;

            if (from < to) {
                // We move to the elements down from the end to the start
                std.debug.assert(to == high);
                std.debug.assert(from == low);

                const clone = widgets[0];
                std.mem.copyForwards(model.Widget, move_range[0 .. count - 1], move_range[1..count]);
                move_range[count - 1] = clone;
            } else {
                // We move to the elements up to the end
                std.debug.assert(to == low);
                std.debug.assert(from == high);

                const clone = widgets[count - 1];
                std.mem.copyBackwards(model.Widget, move_range[1..count], move_range[0 .. count - 1]);
                move_range[0] = clone;
            }
        }

        editor.invalidate_preview();

        // Fixup selection:
        if (editor.maybe_selected_widget_index == from) {
            editor.select_by_index(to);
        }
    }

    fn delete_at_index(editor: *Editor, index: usize) void {

        // Deletion is sharing most of its implementation with move_to_index,
        // so we utilize the fact that we can move the element to the end of the list:
        editor.move_to_index(.{ .from = index, .to = std.math.maxInt(usize) });

        // And then removing the last element:
        const widgets = &editor.document.window.widgets;
        if (widgets.items.len == 0)
            return;

        const last = widgets.items.len - 1;

        widgets.items[last].deinit(editor.document.allocator);
        widgets.shrinkRetainingCapacity(last);

        if (editor.maybe_selected_widget_index == last) {
            editor.select_by_index(null);
        }
    }

    fn handle_options_gui(editor: *Editor) !void {
        defer zgui.end();
        if (!zgui.begin("Options", .{ .flags = .{ .always_auto_resize = true, .no_resize = true } }))
            return;

        _ = zgui.checkbox("Preview Window", .{ .v = &editor.preview_visible });

        zgui.sameLine(.{});

        _ = zgui.checkbox("Show Grid", .{ .v = &editor.options.render_grid });

        zgui.sameLine(.{});
        _ = zgui.checkbox("Snap##SnapToGrid", .{ .v = &editor.options.snap_to_grid });
        zgui.sameLine(.{});

        zgui.textUnformatted("Grid Size");
        zgui.sameLine(.{});
        zgui.setNextItemWidth(40);

        const grid_min = 1;
        const grid_max = 256;

        _ = zgui.dragInt("##GridSize", .{
            .v = &editor.options.grid_size,
            .speed = 1,
            .min = grid_min,
            .max = grid_max,
        });

        zgui.sameLine(.{});
        {
            zgui.beginDisabled(.{ .disabled = (editor.options.grid_size <= grid_min) });
            defer zgui.endDisabled();
            if (zgui.button("-##minus_GridSize", .{})) {
                editor.options.grid_size -|= 1;
            }
        }
        zgui.sameLine(.{});

        {
            zgui.beginDisabled(.{ .disabled = (editor.options.grid_size >= grid_max) });
            defer zgui.endDisabled();
            if (zgui.button("+##plus_GridSize", .{})) {
                editor.options.grid_size +|= 1;
            }
        }

        editor.options.grid_size = @max(grid_min, @min(grid_max, editor.options.grid_size));

        zgui.sameLine(.{});

        zgui.textUnformatted("Zoom");
        zgui.sameLine(.{});
        zgui.setNextItemWidth(40);

        const zoom_min = 1;
        const zoom_max = 256;

        _ = zgui.dragInt("##ZoomFactor", .{
            .v = &editor.options.zoom_factor,
            .speed = 1,
            .min = zoom_min,
            .max = zoom_max,
        });

        zgui.sameLine(.{});
        {
            zgui.beginDisabled(.{ .disabled = (editor.options.zoom_factor <= zoom_min) });
            defer zgui.endDisabled();
            if (zgui.button("-##minus_ZoomFactor", .{})) {
                editor.options.zoom_factor -|= 1;
            }
        }
        zgui.sameLine(.{});

        {
            zgui.beginDisabled(.{ .disabled = (editor.options.zoom_factor >= zoom_max) });
            defer zgui.endDisabled();
            if (zgui.button("+##plus_ZoomFactor", .{})) {
                editor.options.zoom_factor +|= 1;
            }
        }
        editor.options.zoom_factor = @max(zoom_min, @min(zoom_max, editor.options.zoom_factor));

        zgui.sameLine(.{});

        zgui.textUnformatted("Preview Zoom");
        zgui.sameLine(.{});
        zgui.setNextItemWidth(40);

        _ = zgui.dragInt("##PreviewZoomFactor", .{
            .v = &editor.options.preview_zoom_factor,
            .speed = 1,
            .min = zoom_min,
            .max = zoom_max,
        });

        zgui.sameLine(.{});
        {
            zgui.beginDisabled(.{ .disabled = (editor.options.preview_zoom_factor <= zoom_min) });
            defer zgui.endDisabled();
            if (zgui.button("-##minus_PreviewZoomFactor", .{})) {
                editor.options.preview_zoom_factor -|= 1;
            }
        }
        zgui.sameLine(.{});

        {
            zgui.beginDisabled(.{ .disabled = (editor.options.preview_zoom_factor >= zoom_max) });
            defer zgui.endDisabled();
            if (zgui.button("+##plus_PreviewZoomFactor", .{})) {
                editor.options.preview_zoom_factor +|= 1;
            }
        }
        editor.options.preview_zoom_factor = @max(zoom_min, @min(zoom_max, editor.options.preview_zoom_factor));
    }

    fn handle_toolbox_gui(editor: *Editor) !void {
        defer zgui.end();
        if (!zgui.begin("Toolbox", .{ .flags = .{ .always_vertical_scrollbar = true } }))
            return;

        const w = zgui.getContentRegionAvail()[0];

        for (editor.metadata.get_class_names()) |class_name| {
            if (zgui.button(class_name, .{ .w = w })) {
                std.debug.print("Button pressed\n", .{});
            }
            if (zgui.beginDragDropSource(.{})) {
                defer zgui.endDragDropSource();

                _ = zgui.setDragDropPayload(widget_class_tag, class_name[0 .. class_name.len + 1], .once);
            }
        }
    }

    fn handle_preview_window(editor: *Editor) !void {
        if (!editor.preview_visible)
            return;

        const window = &editor.document.window;
        const zoom = editor.options.preview_zoom();

        zgui.pushStyleVar2f(.{ .idx = .window_padding, .v = .{ 0, 0 } });
        defer zgui.popStyleVar(.{});

        const style = zgui.getStyle();

        const hpad = 2.0 * style.window_border_size;
        const vpad = 2.0 * style.window_border_size + 2.0 * style.frame_padding[1] + zgui.getFontSize();

        zgui.setNextWindowSize(.{
            .cond = .appearing,
            .w = @as(f32, @floatFromInt(window.design_size.width)) * zoom + hpad,
            .h = @as(f32, @floatFromInt(window.design_size.height)) * zoom + vpad,
        });

        defer zgui.end();
        if (zgui.begin("Preview", .{
            .flags = .{ .no_docking = true, .no_collapse = true },
            .popen = &editor.preview_visible,
        })) {
            const size: [2]f32 = zgui.getContentRegionAvail();

            const frame_size: Size = .new(
                @intFromFloat(@max(0, size[0] / zoom)),
                @intFromFloat(@max(0, size[1] / zoom)),
            );

            if (frame_size.width == 0 or frame_size.height == 0) {
                zgui.textUnformatted("Preview is too small.");
                return;
            }

            if (frame_size.width > preview_texture_extent or frame_size.height > preview_texture_extent) {
                zgui.text("Preview exceeds {d}x{d}.", .{ preview_texture_extent, preview_texture_extent });
                return;
            }

            if (editor.preview_surface.used_size.width != frame_size.width or editor.preview_surface.used_size.height != frame_size.height) {
                editor.preview_surface.used_size = frame_size;
                editor.invalidate_preview();
            }

            if (editor.preview_surface.dirty) {
                try editor.render_preview(frame_size);
            }

            const tex_ref: zgui.TextureRef = .{
                .tex_data = null,
                .tex_id = @enumFromInt(editor.preview_surface.texture),
            };

            zgui.image(tex_ref, .{
                .w = @as(f32, @floatFromInt(frame_size.width)) * zoom,
                .h = @as(f32, @floatFromInt(frame_size.height)) * zoom,
                .uv1 = .{
                    @as(f32, @floatFromInt(frame_size.width)) / preview_texture_extent,
                    @as(f32, @floatFromInt(frame_size.height)) / preview_texture_extent,
                },
            });
        }
    }

    fn render_preview(editor: *Editor, frame_size: Size) !void {
        const window = &editor.document.window;

        try editor.preview_surface.ensureInitialized(editor.document.allocator);
        editor.preview_surface.used_size = frame_size;
        editor.preview_surface.clear(editor.preview_theme.window_active.background);

        var queue = try CommandQueue.init(editor.document.allocator);
        defer queue.deinit();

        queue.reset();
        try encode_preview_window_border(&queue, editor.preview_theme, frame_size);
        try rasterize_preview_queue(editor.document.allocator, queue.data.written(), .{
            .pixels = editor.preview_surface.indexed_pixels.ptr,
            .width = frame_size.width,
            .height = frame_size.height,
            .stride = preview_texture_extent,
        });

        for (window.widgets.items) |widget| {
            const bounds = resolve_preview_widget_bounds(window, frame_size, widget);
            try render_preview_widget(editor, &queue, widget, bounds);
        }

        editor.preview_surface.upload();
        editor.preview_surface.dirty = false;
    }

    fn handle_hierarchy_gui(editor: *Editor) !void {
        defer zgui.end();
        if (!zgui.begin("Hierarchy", .{ .flags = .{ .always_vertical_scrollbar = true } }))
            return;

        if (zgui.beginListBox("##Hierarchy", .{})) {
            defer zgui.endListBox();

            for (editor.document.window.widgets.items, 0..) |widget, index| {
                var buf: [256]u8 = undefined;

                var fbs = std.io.fixedBufferStream(&buf);

                try fbs.writer().print("{s}", .{
                    widget.class.name,
                });

                if (widget.identifier.items.len > 0) {
                    try fbs.writer().print(": {s}", .{widget.identifier.items});
                }

                try fbs.writer().print("##{s}_{d}\x00", .{
                    widget.class.name,
                    index,
                });

                const key = fbs.getWritten()[0 .. fbs.pos - 1 :0];

                if (zgui.selectable(key, .{ .selected = (editor.maybe_selected_widget_index == index) })) {
                    editor.select_by_index(index);
                }
            }
        }
    }

    fn handle_designer_gui(editor: *Editor) !void {
        defer zgui.end();
        if (!zgui.begin("Window Designer", .{}))
            return;

        const window: *model.Window = &editor.document.window;
        const zoom = editor.options.designer_zoom();

        const base = zgui.getCursorScreenPos();
        const draw = zgui.getWindowDrawList();

        const mouse_pos_raw = zgui.getMousePos();
        const mouse_pos: [2]f32 = .{ @max(0, mouse_pos_raw[0]), @max(0, mouse_pos_raw[1]) };

        const topleft = base;
        const bottomright: [2]f32 = .{
            topleft[0] + @as(f32, @floatFromInt(window.design_size.width)) * zoom,
            topleft[1] + @as(f32, @floatFromInt(window.design_size.height)) * zoom,
        };

        const pos: model.Point = .new(
            @intFromFloat((mouse_pos[0] - topleft[0]) / zoom),
            @intFromFloat((mouse_pos[1] - topleft[1]) / zoom),
        );

        const maybe_hovered_widget = window.widget_from_pos(pos);

        const is_window_clicked_raw = zgui.invisibleButton("Window Preview", .{
            .w = @as(f32, @floatFromInt(window.design_size.width)) * zoom,
            .h = @as(f32, @floatFromInt(window.design_size.height)) * zoom,
        });

        if (maybe_hovered_widget != null or editor.maybe_popup_widget != null) {
            const maybe_target_widget: ?model.WidgetRef = if (editor.maybe_popup_widget) |popup|
                popup
            else if (maybe_hovered_widget) |tup|
                tup
            else
                null;

            if (maybe_target_widget) |target_widget| {
                if (zgui.beginPopupContextWindow()) {
                    defer zgui.endPopup();

                    editor.maybe_selected_widget_index = target_widget.index;
                    editor.maybe_popup_widget = target_widget;

                    _ = zgui.menuItem("Copy", .{});
                    _ = zgui.menuItem("Cut", .{});
                    _ = zgui.separator();

                    if (zgui.menuItem("Snap position to grid", .{})) {
                        const new_pos = editor.options.snap_pos(target_widget.ptr.bounds.position());
                        target_widget.ptr.bounds.x = new_pos.x;
                        target_widget.ptr.bounds.y = new_pos.y;
                        editor.invalidate_preview();
                    }

                    if (zgui.menuItem("Shrink size to grid", .{})) {
                        const new_size = editor.options.snap_size(target_widget.ptr.bounds.size(), .shrink);
                        target_widget.ptr.bounds.width = new_size.width;
                        target_widget.ptr.bounds.height = new_size.height;
                        editor.invalidate_preview();
                    }

                    if (zgui.menuItem("Grow size to grid", .{})) {
                        const new_size = editor.options.snap_size(target_widget.ptr.bounds.size(), .grow);
                        target_widget.ptr.bounds.width = new_size.width;
                        target_widget.ptr.bounds.height = new_size.height;
                        editor.invalidate_preview();
                    }

                    _ = zgui.separator();
                    if (zgui.menuItem("Bring to front", .{})) {
                        editor.move_to_index(.{ .from = target_widget.index, .to = std.math.maxInt(usize) });
                    }
                    if (zgui.menuItem("Send to back", .{})) {
                        editor.move_to_index(.{ .from = target_widget.index, .to = 0 });
                    }
                    if (zgui.menuItem("Raise one layer", .{})) {
                        editor.move_to_index(.{ .from = target_widget.index, .to = target_widget.index +| 1 });
                    }
                    if (zgui.menuItem("Lower one layer", .{})) {
                        editor.move_to_index(.{ .from = target_widget.index, .to = target_widget.index -| 1 });
                    }
                    _ = zgui.separator();
                    if (zgui.menuItem("Delete", .{})) {
                        editor.delete_at_index(target_widget.index);
                    }
                } else {
                    editor.maybe_popup_widget = null;
                }
            } else {
                std.debug.assert(editor.maybe_popup_widget == null);
            }
        }

        const is_window_pressed = zgui.isItemActive();
        defer editor.previously_window_clicked = is_window_pressed;

        const mouse_down = is_window_pressed and !editor.previously_window_clicked;
        const mouse_up = !is_window_pressed and editor.previously_window_clicked;
        _ = mouse_down;

        const drag_fdx, const drag_fdy = zgui.getMouseDragDelta(.left, .{});

        const drag_dx: i16 = @intFromFloat(drag_fdx / zoom);
        const drag_dy: i16 = @intFromFloat(drag_fdy / zoom);

        const dragging = (editor.widget_drag != null);
        const is_window_clicked = is_window_clicked_raw and !dragging;

        defer if (mouse_up) {
            editor.widget_drag = null;
        };

        if (editor.widget_drag) |drag| {
            const newpos = editor.options.maybe_snap_pos(.new(
                drag.start.x +| drag_dx,
                drag.start.y +| drag_dy,
            ));

            if (drag.widget.bounds.x != newpos.x or drag.widget.bounds.y != newpos.y) {
                drag.widget.bounds.x = newpos.x;
                drag.widget.bounds.y = newpos.y;
                editor.invalidate_preview();
            }
        } else {
            // "Not dragging"
            if (is_window_clicked) {
                if (maybe_hovered_widget) |clicked_widget| {
                    editor.select_by_index(clicked_widget.index);
                } else {
                    editor.select_by_index(null);
                }
            } else if (is_window_pressed) {
                if (maybe_hovered_widget) |hovered_widget| {
                    if (hovered_widget.index == editor.maybe_selected_widget_index and (drag_fdx != 0 or drag_fdy != 0)) {
                        editor.widget_drag = .{
                            .widget = hovered_widget.ptr,
                            .start = hovered_widget.ptr.bounds.position(),
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
                topleft[0] + @as(f32, @floatFromInt(window.min_size.width)) * zoom,
                topleft[1] + @as(f32, @floatFromInt(window.min_size.height)) * zoom,
            };
            draw.addRectFilled(.{
                .pmin = topleft,
                .pmax = min_bottomright,
                .col = 0x10000000,
            });
        }

        if (editor.options.render_grid and editor.options.grid_size > 1) {
            const grid_increment: f32 = @as(f32, @floatFromInt(editor.options.grid_size)) * zoom;
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
            paintWidget(draw, base, widget, zoom, editor.maybe_selected_widget_index == index);
        }

        if (zgui.beginDragDropTarget()) {
            defer zgui.endDragDropTarget();

            if (zgui.getDragDropPayload()) |payload| {
                if (widget_from_payload(editor.metadata, editor.options, payload, pos)) |widget| {
                    paintWidget(draw, base, widget, zoom, false);
                }
            }

            if (zgui.acceptDragDropPayload(widget_class_tag, .{})) |payload| {
                if (widget_from_payload(editor.metadata, editor.options, payload, pos)) |widget| {
                    try window.widgets.append(editor.document.allocator, widget);
                    editor.select_by_index(window.widgets.items.len - 1);
                    editor.invalidate_preview();
                }
            }
        }

        if (editor.maybe_selected_widget_index == null) {
            draw.addRect(.{
                .pmin = .{ topleft[0] - 2, topleft[1] - 2 },
                .pmax = .{ bottomright[0] + 2, bottomright[1] + 2 },
                .col = 0xFF00FFFF,
            });
        }
    }

    fn handle_properties_gui(editor: *Editor) !void {
        const window: *model.Window = &editor.document.window;

        zgui.setNextWindowSize(.{ .w = 300, .h = -1, .cond = .once });
        defer zgui.end();
        if (!zgui.begin("Properties", .{}))
            return;

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

                pub fn sizeField(self: @This(), comptime display: [:0]const u8, value_ptr: anytype, min: anytype, max: anytype) bool {
                    self.beginField(display);

                    zgui.beginDisabled(.{ .disabled = min >= max });
                    defer zgui.endDisabled();

                    var value: i32 = value_ptr.*;
                    const previous = value;

                    _ = zgui.dragInt("##edit_" ++ display, .{ .v = &value, .min = min, .max = max });

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
                    return value != previous;
                }
            };
            var utils: Utils = .{};

            if (editor.get_selected_widget()) |selected_widget| {
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

                    // Ensure we have some space for receiving input text:
                    try selected_widget.identifier.ensureUnusedCapacity(editor.document.allocator, 16);

                    const capacity = selected_widget.identifier.capacity;
                    const string: *[]u8 = &selected_widget.identifier.items;

                    // This is a safe operation, as we know .capacity is the "true" size of ".items":
                    const oldlen = string.len;
                    string.len = capacity;

                    // ensure we pad the whole string with NULs to ensure
                    // both NUL termination and minimum string length:
                    @memset(string.*[oldlen..], 0);

                    // Slice into NUL-terminated buffer:
                    const zbuffer: [:0]u8 = string.*[0 .. capacity - 1 :0];

                    _ = zgui.inputText("##name", .{ .buf = zbuffer });

                    // Reset string into the length of the NUL-terminated string:
                    string.len = std.mem.indexOfScalar(u8, string.*, 0).?;
                }

                utils.header("Geometry");

                editor.touch(utils.sizeField("X", &selected_widget.bounds.x, std.math.minInt(i16), std.math.maxInt(i16)));
                editor.touch(utils.sizeField("Y", &selected_widget.bounds.y, std.math.minInt(i16), std.math.maxInt(i16)));

                editor.touch(utils.sizeField("Width", &selected_widget.bounds.width, selected_widget.class.min_size.width, selected_widget.class.max_size.width));
                editor.touch(utils.sizeField("Height", &selected_widget.bounds.height, selected_widget.class.min_size.height, selected_widget.class.max_size.height));

                utils.beginField("Anchor");

                if (zgui.beginTable("Anchor##anchor", .{ .column = 3 })) {
                    defer zgui.endTable();

                    zgui.tableNextRow(.{});

                    _ = zgui.tableSetColumnIndex(1);
                    editor.touch(zgui.checkbox("Top", .{ .v = &selected_widget.anchor.top }));

                    zgui.tableNextRow(.{});

                    _ = zgui.tableSetColumnIndex(0);
                    editor.touch(zgui.checkbox("Left", .{ .v = &selected_widget.anchor.left }));
                    _ = zgui.tableSetColumnIndex(2);
                    editor.touch(zgui.checkbox("Right", .{ .v = &selected_widget.anchor.right }));

                    zgui.tableNextRow(.{});

                    _ = zgui.tableSetColumnIndex(1);
                    editor.touch(zgui.checkbox("Bottom", .{ .v = &selected_widget.anchor.bottom }));
                }

                utils.header("Visuals");

                utils.beginField("Visible");
                editor.touch(zgui.checkbox("##Visible", .{ .v = &selected_widget.visible }));

                if (selected_widget.class.properties.count() > 0) {
                    utils.header("Widget Properties");

                    for (selected_widget.class.properties.keys(), selected_widget.class.properties.values()) |prop_name, prop_desc| {
                        const gop = try selected_widget.properties.getOrPut(editor.document.allocator, prop_name);
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

                editor.touch(utils.sizeField("Min Width", &window.min_size.width, 0, window.max_size.width));
                editor.touch(utils.sizeField("Min Height", &window.min_size.height, 0, window.max_size.height));

                editor.touch(utils.sizeField("Max Width", &window.max_size.width, window.min_size.width, std.math.maxInt(u15)));
                editor.touch(utils.sizeField("Max Height", &window.max_size.height, window.min_size.height, std.math.maxInt(u15)));

                editor.touch(utils.sizeField("Design Width", &window.design_size.width, window.min_size.width, window.max_size.width));
                editor.touch(utils.sizeField("Design Height", &window.design_size.height, window.min_size.height, window.max_size.height));
            }
        }
    }

    fn setup_dockspace(editor: *Editor) void {
        const dockspace_id = zgui.dockSpaceOverViewport(0, zgui.getMainViewport(), .{ .auto_hide_tab_bar = true });

        if (editor.dock_layout_setup_done)
            return;

        defer editor.dock_layout_setup_done = true;

        var center_dockspace_id = dockspace_id;
        const left_id = zgui.dockBuilderSplitNode(dockspace_id, .left, 0.2, null, &center_dockspace_id);

        var toolbox_space_id: u32 = 0;
        const hierarchy_space_id: u32 = zgui.dockBuilderSplitNode(left_id, .down, 0.5, null, &toolbox_space_id);

        const right_id = zgui.dockBuilderSplitNode(center_dockspace_id, .right, 0.4, null, &center_dockspace_id);
        const options_id = zgui.dockBuilderSplitNode(center_dockspace_id, .up, 0.1, null, &center_dockspace_id);

        zgui.dockBuilderDockWindow("Hierarchy", hierarchy_space_id);
        zgui.dockBuilderDockWindow("Toolbox", toolbox_space_id);
        zgui.dockBuilderDockWindow("Properties", right_id);
        zgui.dockBuilderDockWindow("Window Designer", center_dockspace_id);
        zgui.dockBuilderDockWindow("Options", options_id);
        zgui.dockBuilderFinish(center_dockspace_id);
    }

    fn handle_mainmenu_bar(editor: *Editor) !void {
        if (!zgui.beginMainMenuBar())
            return;
        defer zgui.endMainMenuBar();

        if (zgui.beginMenu("File", true)) {
            defer zgui.endMenu();

            _ = zgui.menuItem("Restore", .{});

            if (zgui.menuItem("Save", .{})) {
                var file_buffer: [2048]u8 = undefined;

                var result_file = try std.fs.cwd().atomicFile("current.gui.json", .{ .write_buffer = &file_buffer });
                defer result_file.deinit();

                try model.save_design(editor.document.window, &result_file.file_writer.interface);

                try result_file.finish();
            }

            zgui.separator();
            if (zgui.menuItem("Close", .{})) {
                return error.AppExit;
            }
        }
    }
};

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
            options.maybe_snap_pos(.new(
                center.x -| @as(i16, @intCast(class.default_size.width / 2)),
                center.y -| @as(i16, @intCast(class.default_size.height / 2)),
            )),
            class.default_size,
        ),
        .anchor = .top_left,
    };

    return new;
}

fn resolve_preview_widget_bounds(window: *const Window, frame_size: Size, widget: Widget) Rectangle {
    const h_align: Alignment = .from_anchor(widget.anchor.left, widget.anchor.right);
    const v_align: Alignment = .from_anchor(widget.anchor.top, widget.anchor.bottom);

    const h_bounds: Alignment.Bounds = .{
        .near_margin = widget.bounds.x,
        .far_margin = @intCast(window.design_size.width -| (@as(i32, widget.bounds.x) +| widget.bounds.width)),
        .size = widget.bounds.width,
        .limit = frame_size.width,
    };
    const v_bounds: Alignment.Bounds = .{
        .near_margin = widget.bounds.y,
        .far_margin = @intCast(window.design_size.height -| (@as(i32, widget.bounds.y) +| widget.bounds.height)),
        .size = widget.bounds.height,
        .limit = frame_size.height,
    };

    return .{
        .x = h_align.compute_pos(h_bounds),
        .y = v_align.compute_pos(v_bounds),
        .width = h_align.compute_size(h_bounds),
        .height = v_align.compute_size(v_bounds),
    };
}

fn embed_preview_font(data: []const u8, hint: agp_swrast.fonts.FontHint) ashet.graphics.Font {
    @setEvalBranchQuota(10_000);
    return @ptrCast(@constCast(&(agp_swrast.fonts.FontInstance.load(data, hint) catch unreachable)));
}

fn load_preview_font(name: []const u8) error{ Unexpected, FileNotFound, SystemResources }!ashet.graphics.Font {
    if (std.mem.eql(u8, name, "sans-6"))
        return preview_sans_6_font;
    if (std.mem.eql(u8, name, "mono-8"))
        return preview_mono_8_font;

    return error.FileNotFound;
}

/// Mock implementation of the system call for Ashet OS font measurement:
export fn ashet_syscalls_draw_measure_text_size(font_ptr: ashet.abi.Font, text_ptr: [*]const u8, text_len: usize, size: *Size) callconv(.c) u16 {
    const text = text_ptr[0..text_len];
    const font: *const agp_swrast.fonts.FontInstance = @ptrCast(@alignCast(font_ptr));

    const width = font.measure_width(text);

    size.* = .new(width, font.line_height());

    return 0;
}

fn render_preview_widget(editor: *Editor, queue: *CommandQueue, widget: Widget, bounds: Rectangle) !void {
    const target = get_preview_target(editor, bounds) orelse return;

    queue.reset();
    try encode_preview_widget(queue, editor.preview_theme, widget, Size.new(bounds.width, bounds.height));
    try rasterize_preview_queue(editor.document.allocator, queue.data.written(), target);
}

fn get_preview_target(editor: *Editor, bounds: Rectangle) ?agp_swrast.RenderTarget {
    if (bounds.width == 0 or bounds.height == 0 or bounds.x < 0 or bounds.y < 0)
        return null;

    const x: usize = @intCast(bounds.x);
    const y: usize = @intCast(bounds.y);

    if (x >= editor.preview_surface.used_size.width or y >= editor.preview_surface.used_size.height)
        return null;

    const visible_width = @min(bounds.width, editor.preview_surface.used_size.width - x);
    const visible_height = @min(bounds.height, editor.preview_surface.used_size.height - y);

    return .{
        .pixels = editor.preview_surface.indexed_pixels.ptr + y * preview_texture_extent + x,
        .width = visible_width,
        .height = visible_height,
        .stride = preview_texture_extent,
    };
}

fn encode_preview_widget(queue: *CommandQueue, preview_theme: *const PreviewTheme, widget: Widget, size: Size) !void {
    const class_name = widget.class.name;

    if (std.mem.eql(u8, class_name, "Label")) {
        var label: standard_widgets.Label = .{
            .text = preview_widget_text(widget),
        };
        try standard_widgets.Label.paint(&label, queue, size);
        return;
    }

    if (std.mem.eql(u8, class_name, "Button")) {
        var button: standard_widgets.Button = .{
            .text = preview_widget_text(widget),
        };
        try standard_widgets.Button.paint(&button, queue, size);
        return;
    }

    if (std.mem.eql(u8, class_name, "ToolButton")) {
        var button: standard_widgets.ToolButton = .{};
        try standard_widgets.ToolButton.paint(&button, queue, size);
        return;
    }

    if (std.mem.eql(u8, class_name, "TextBox")) {
        var textbox: standard_widgets.TextBox = .{
            .text = preview_widget_text(widget),
        };
        try standard_widgets.TextBox.paint(&textbox, queue, size);
        return;
    }

    if (std.mem.eql(u8, class_name, "ListBox")) {
        var listbox: standard_widgets.ListBox = .{};
        try standard_widgets.ListBox.paint(&listbox, queue, size);
        return;
    }

    try encode_preview_placeholder(queue, preview_theme, size);
}

fn preview_widget_text(widget: Widget) std.ArrayListUnmanaged(u8) {
    // We have to capture by-ref as `string` is an *owning* value, not
    // a reference value.
    if (widget.properties.getPtr("text")) |value| {
        if (value.* == .string) {
            const str = value.string.slice();
            return .{
                .items = @constCast(str),
                .capacity = undefined,
            };
        }
    }

    return .empty;
}

fn encode_preview_placeholder(queue: *CommandQueue, preview_theme: *const PreviewTheme, size: Size) !void {
    const rect: Rectangle = .new(.zero, size);
    try queue.fill_rect(rect, preview_theme.widget_background);
    try queue.draw_rect(rect, preview_theme.border_normal);
}

fn encode_preview_window_border(queue: *CommandQueue, preview_theme: *const PreviewTheme, size: Size) !void {
    const rect: Rectangle = .new(.zero, size);
    const window_theme = preview_theme.window_active;

    if (rect.width == 0 or rect.height == 0)
        return;

    try queue.draw_rect(rect, window_theme.border_normal);

    if (rect.width > 2) {
        try queue.draw_line(
            .new(rect.left() +| 1, rect.top() +| 1),
            .new(rect.right() -| 2, rect.top() +| 1),
            window_theme.border_bright,
        );
    }

    if (rect.height > 2) {
        try queue.draw_line(
            .new(rect.left() +| 1, rect.top() +| 1),
            .new(rect.left() +| 1, rect.bottom() -| 2),
            window_theme.border_bright,
        );
        try queue.draw_line(
            .new(rect.right() -| 1, rect.top() +| 1),
            .new(rect.right() -| 1, rect.bottom() -| 2),
            window_theme.border_dark,
        );
    }

    if (rect.width > 2) {
        try queue.draw_line(
            .new(rect.left() +| 1, rect.bottom() -| 1),
            .new(rect.right() -| 1, rect.bottom() -| 1),
            window_theme.border_dark,
        );
    }
}

fn rasterize_preview_queue(allocator: std.mem.Allocator, command_stream: []const u8, target: agp_swrast.RenderTarget) !void {
    var rasterizer = agp_swrast.Rasterizer.init(target);

    var stream = std.io.fixedBufferStream(command_stream);
    var decoder = agp.streamDecoder(allocator, stream.reader());
    defer decoder.deinit();

    var resolver_cookie: u8 = 0;
    const resolver: agp_swrast.Rasterizer.Resolver = .{
        .ctx = @ptrCast(&resolver_cookie),
        .resolve_font_fn = resolve_preview_font,
        .resolve_framebuffer_fn = resolve_preview_framebuffer,
    };

    while (try decoder.next()) |cmd| {
        rasterizer.execute(cmd, resolver);
    }
}

fn resolve_preview_font(_: *anyopaque, font: agp.Font) ?*const agp_swrast.fonts.FontInstance {
    if (@intFromPtr(font) == 0)
        return null;

    return @ptrCast(@alignCast(font));
}

fn resolve_preview_framebuffer(_: *anyopaque, _: agp.Framebuffer) ?agp_swrast.Image {
    return null;
}

fn paintWidget(draw: zgui.DrawList, base: [2]f32, widget: model.Widget, zoom: f32, selected: bool) void {
    const x0: f32 = @as(f32, @floatFromInt(widget.bounds.x)) * zoom;
    const y0: f32 = @as(f32, @floatFromInt(widget.bounds.y)) * zoom;

    const x = base[0] + x0;
    const y = base[1] + y0;

    const w: f32 = @as(f32, @floatFromInt(widget.bounds.width)) * zoom;
    const h: f32 = @as(f32, @floatFromInt(widget.bounds.height)) * zoom;

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
    zoom_factor: i32 = 2,
    preview_zoom_factor: i32 = 1,

    render_grid: bool = true,
    snap_to_grid: bool = true,

    const SnapBias = enum { grow, shrink, best_fit };

    pub fn maybe_snap_pos(opts: EditorOptions, pos: model.Point) model.Point {
        return if (opts.snap_to_grid)
            opts.snap_pos(pos)
        else
            pos;
    }

    pub fn maybe_snap_size(opts: EditorOptions, size: model.Size, bias: SnapBias) model.Point {
        return if (opts.snap_to_grid)
            opts.snap_size(size, bias)
        else
            size;
    }

    pub fn snap_pos(opts: EditorOptions, pos: model.Point) model.Point {
        return .new(opts.snap_value(pos.x, .best_fit), opts.snap_value(pos.y, .best_fit));
    }

    pub fn snap_size(opts: EditorOptions, size: model.Size, snap_dir: SnapBias) model.Size {
        const gs: u15 = @intCast(opts.grid_size);

        const width = opts.snap_value(size.width, snap_dir);
        const height = opts.snap_value(size.height, snap_dir);

        return .new(
            // Prevent both values to ever go zero. Snap to grid-size instead:
            if (width == 0) gs else width,
            if (height == 0) gs else height,
        );
    }

    pub fn snap_value(opts: EditorOptions, value: anytype, bias: SnapBias) @TypeOf(value) {
        const gs: u15 = @intCast(opts.grid_size);
        const bias_offset = switch (bias) {
            .shrink => 0,
            .grow => gs - 1,
            .best_fit => gs / 2,
        };
        return gs * @divFloor(value + bias_offset, gs);
    }

    pub fn designer_zoom(opts: EditorOptions) f32 {
        return @floatFromInt(@max(1, opts.zoom_factor));
    }

    pub fn preview_zoom(opts: EditorOptions) f32 {
        return @floatFromInt(@max(1, opts.preview_zoom_factor));
    }
};
