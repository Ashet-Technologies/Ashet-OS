const std = @import("std");
const ashet = @import("../main.zig");
const libashet = @import("ashet");
const agp = @import("agp");
const agp_swrast = @import("agp-swrast");
const agp_tiled_rast = @import("agp-tiled-rast");

const logger = std.log.scoped(.graphics);

const fonts = agp_swrast.fonts;
const software_renderer = @import("graphics/software_renderer.zig");

const Rasterizer = agp_swrast.Rasterizer;
const Rectangle = ashet.abi.Rectangle;
const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Color = ashet.abi.Color;

const newage_rasterizer = true;

comptime {
    std.debug.assert(Color == agp.Color);
}

var tiled_rasterizer: agp_tiled_rast.Rasterizer = undefined;

pub fn initialize() !void {
    try initialize_system_fonts();

    tiled_rasterizer = .{};
}

pub const Bitmap = struct {
    width: u16, // width of the image
    height: u16, // height of the image
    stride: u32, // row length in pixels
    pixels: [*]align(64) Color, // height * stride pixels
};

pub const Framebuffer = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    pub const VideoOut = struct {
        memory: ashet.video.VideoMemory,
        output: *ashet.video.Output,
    };

    pub const Type = union(ashet.abi.FramebufferType) {
        memory: Bitmap,
        video: VideoOut,
        window: *ashet.gui.Window,
        widget: *ashet.gui.Widget,
    };

    system_resource: ashet.resources.SystemResource = .{ .type = .framebuffer },
    type: Type,

    pub fn create_memory(width: u16, height: u16) error{SystemResources}!*Framebuffer {
        const stride: usize = std.mem.alignForward(usize, width, 64);

        const back_buffer = ashet.memory.allocator.alignedAlloc(Color, .@"64", stride * height) catch return error.SystemResources;
        errdefer ashet.memory.allocator.free(back_buffer);

        const fb = ashet.memory.type_pool(Framebuffer).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Framebuffer).free(fb);

        fb.* = .{
            .type = .{
                .memory = Bitmap{
                    .width = width,
                    .height = height,
                    .stride = @intCast(stride),
                    .pixels = back_buffer.ptr,
                },
            },
        };

        return fb;
    }

    pub fn create_video_output(output: *ashet.video.Output) error{SystemResources}!*Framebuffer {
        const fb = ashet.memory.type_pool(Framebuffer).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Framebuffer).free(fb);

        fb.* = .{
            .type = .{
                .video = .{
                    .output = output,
                    .memory = output.get_video_memory(),
                },
            },
        };

        return fb;
    }

    pub fn create_window(window: *ashet.gui.Window) error{SystemResources}!*Framebuffer {
        const fb = ashet.memory.type_pool(Framebuffer).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Framebuffer).free(fb);

        fb.* = .{
            .type = .{ .window = window },
        };

        return fb;
    }

    pub fn create_widget(widget: *ashet.gui.Widget) error{SystemResources}!*Framebuffer {
        const fb = ashet.memory.type_pool(Framebuffer).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Framebuffer).free(fb);

        fb.* = .{
            .type = .{ .widget = widget },
        };

        return fb;
    }

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(fb: *Framebuffer) void {
        switch (fb.type) {
            .memory => |bmp| {
                const back_buffer = bmp.pixels[0 .. @as(usize, bmp.width) * bmp.stride];
                ashet.memory.allocator.free(back_buffer);
            },
            .video => {},
            .window => {},
            .widget => {},
        }
        ashet.memory.type_pool(Framebuffer).free(fb);
    }

    fn invalidate(fb: *Framebuffer) void {
        switch (fb.type) {
            .memory => {}, // no-op, nothing to invalidate
            .video => |video| video.output.flush(),
            .window => |win| win.invalidate_full(),
            .widget => |widget| widget.window.invalidate_region(widget.bounds),
        }
    }

    pub fn get_size(fb: Framebuffer) Size {
        return switch (fb.type) {
            .memory => |mem| .new(mem.width, mem.height),
            .video => |video| video.output.get_resolution(),
            .window => |win| win.size,
            .widget => |widget| widget.bounds.size(),
        };
    }

    pub fn get_render_target(fb: Framebuffer) agp_swrast.RenderTarget {
        return fb.get_image_buffer(agp_swrast.RenderTarget);
    }

    pub fn get_image(fb: Framebuffer) agp_swrast.Image {
        return fb.get_image_buffer(agp_swrast.Image);
    }

    fn get_image_buffer(fb: Framebuffer, comptime T: type) T {
        return switch (fb.type) {
            .memory => |mem| .{
                .pixels = mem.pixels,
                .width = mem.width,
                .height = mem.height,
                .stride = mem.stride,
            },
            .video => |video| blk: {
                const mem = video.output.get_video_memory();
                break :blk .{
                    .pixels = mem.base,
                    .height = mem.height,
                    .width = mem.width,
                    .stride = mem.stride,
                };
            },
            .window => |win| .{
                .pixels = win.pixels.ptr,
                .width = win.size.width,
                .height = win.size.height,
                .stride = std.mem.alignForward(usize, win.max_size.width, 64),
            },
            .widget => |widget| .{
                .pixels = widget.pixels.ptr,
                .width = widget.bounds.width,
                .height = widget.bounds.height,
                .stride = std.mem.alignForward(usize, widget.bounds.width, 64),
            },
        };
    }

    pub fn resolve_font(fb: *Framebuffer, font_handle: ashet.abi.Font) !*const fonts.FontInstance {
        _ = fb;
        _ = font_handle;
        @panic("undefined");
    }

    pub fn resolve_framebuffer(fb: *Framebuffer, fb_handle: ashet.abi.Framebuffer) !*Framebuffer {
        _ = fb;
        _ = fb_handle;
        @panic("undefined");
    }
};

pub const Font = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    system_resource: ashet.resources.SystemResource = .{ .type = .font },

    system_font: bool,
    raw_data: []const u8,

    font_data: fonts.FontInstance,

    pub fn create(userland_data: []const u8) error{ InvalidData, SystemResources }!*Font {
        _ = fonts.FontInstance.load(userland_data, .{}) catch return error.InvalidData;

        const data = ashet.memory.allocator.dupe(u8, userland_data) catch return error.SystemResources;
        errdefer ashet.memory.allocator.free(data);

        const font = ashet.memory.type_pool(Font).alloc() catch return error.SystemResources;
        errdefer ashet.memory.type_pool(Font).free(font);

        font.* = .{
            .system_font = false,
            .raw_data = data,
            .font_data = fonts.FontInstance.load(data, .{}) catch unreachable,
        };

        return font;
    }

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(font: *Font) void {
        if (font.system_font) {
            // statically allocated objects
            return;
        }
        ashet.memory.allocator.free(font.raw_data);
        ashet.memory.type_pool(Font).free(font);
    }

    pub fn measure_text_size(font: *const Font, text: []const u8) Size {
        const line_height = font.font_data.line_height();

        var height: u16 = 0;
        var width: u16 = 0;

        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            const line_width = font.font_data.measure_width(line);
            width = @max(line_width, width);
            height += line_height;
        }

        return .new(width, height);
    }
};

var system_fonts: std.StringArrayHashMap(Font) = undefined;

fn initialize_system_fonts() !void {
    errdefer |e| logger.err("failed to load system fonts: {s}", .{@errorName(e)});

    system_fonts = .init(ashet.memory.static_memory_allocator);

    var fonts_dir = try libashet.fs.Directory.openDrive(.system, "system/fonts");
    defer fonts_dir.close();

    while (try fonts_dir.next()) |entry| {
        const name = entry.getName();
        if (!std.mem.endsWith(u8, name, ".font"))
            continue;
        load_system_font(fonts_dir, entry) catch {};
    }
}

fn load_system_font(dir: libashet.fs.Directory, info: ashet.abi.FileInfo) !void {
    const file_name = info.getName();
    const ext = std.fs.path.extension(file_name);

    const font_name = try ashet.memory.static_memory_allocator.dupe(u8, file_name[0 .. file_name.len - ext.len]);
    errdefer ashet.memory.static_memory_allocator.free(font_name);

    logger.info("Loading system font '{s}'...", .{font_name});
    errdefer |err| logger.err("failed to load font '{s}': {s}", .{ font_name, @errorName(err) });

    const font_size = std.math.cast(usize, info.size) orelse return error.FileTooBig;

    var font_file = try dir.openFile(file_name, .read_only, .open_existing);
    defer font_file.close();

    const font_data = try ashet.memory.static_memory_allocator.alloc(u8, font_size);
    errdefer ashet.memory.static_memory_allocator.free(font_data);

    if (try font_file.read(0, font_data) != font_data.len)
        return error.InsufficientRead;

    const instance = try fonts.FontInstance.load(font_data, .{});

    try system_fonts.put(font_name, Font{
        .system_font = true,
        .raw_data = font_data,
        .font_data = instance,
    });
}

pub fn get_system_font(font_name: []const u8) error{FileNotFound}!*Font {
    return system_fonts.getPtr(font_name) orelse return error.FileNotFound;
}

var render_temp_buffer: std.heap.ArenaAllocator = .init(ashet.memory.page_allocator);

fn resolve_render_font(ctx: *anyopaque, handle: agp.Font) ?*const agp_swrast.fonts.FontInstance {
    const resource_owner: *ashet.multi_tasking.Process = @ptrCast(@alignCast(ctx));

    const font = ashet.resources.resolve(Font, resource_owner, handle.as_resource()) catch |err| {
        logger.warn("failed to resolve font resource: {t}", .{err});
        return null;
    };

    return &font.font_data;
}

fn resolve_render_framebuffer(ctx: *anyopaque, handle: agp.Framebuffer) ?agp_tiled_rast.Image {
    const resource_owner: *ashet.multi_tasking.Process = @ptrCast(@alignCast(ctx));

    const framebuffer = ashet.resources.resolve(Framebuffer, resource_owner, handle.as_resource()) catch |err| {
        logger.warn("failed to resolve framebuffer resource: {t}", .{err});
        return null;
    };

    const rt = framebuffer.get_render_target();
    return .{
        .width = rt.width,
        .height = rt.height,
        .stride = rt.stride,
        .pixels = rt.pixels,
    };
}

fn render_sync(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.draw.Render.Inputs) ashet.abi.draw.Render.Error!ashet.abi.draw.Render.Outputs {
    const fb = ashet.resources.resolve(Framebuffer, call.resource_owner, inputs.target.as_resource()) catch |err| return switch (err) {
        error.InvalidHandle,
        error.TypeMismatch,
        => error.InvalidHandle,
    };

    const code = inputs.sequence_ptr[0..inputs.sequence_len];

    var fbs = std.io.fixedBufferStream(code);

    // Validate code before drawing:
    {
        _ = render_temp_buffer.reset(.retain_capacity);

        var decoder = agp.streamDecoder(render_temp_buffer.allocator(), fbs.reader());
        while (true) {
            const maybe_cmd = decoder.next() catch |err| {
                logger.warn("failed to decode AGP: {s}", .{@errorName(err)});
                return error.BadCode;
            };
            if (maybe_cmd == null)
                break;
        }
    }

    fbs.reset();

    // Now render to the framebuffer:

    const target_size = fb.get_size();

    if (target_size.width > 0 and target_size.height > 0) {
        _ = render_temp_buffer.reset(.retain_capacity);

        if (newage_rasterizer) {
            const resolver: agp_tiled_rast.Resolver = .{
                .ctx = call.resource_owner,
                .vtable = comptime &.{
                    .resolve_font_fn = resolve_render_font,
                    .resolve_framebuffer_fn = resolve_render_framebuffer,
                },
            };

            const rt = fb.get_render_target();
            tiled_rasterizer.execute(
                .{
                    .width = rt.width,
                    .height = rt.height,
                    .stride = rt.stride,
                    .pixels = @alignCast(rt.pixels),
                },
                resolver,
                code,
            ) catch |err| {
                std.log.err("rasterizer error: {t}", .{err});
                @panic("rasterizer error");
            };
        } else {
            var rasterizer = Rasterizer.init(fb.get_render_target());

            var decoder = agp.streamDecoder(render_temp_buffer.allocator(), fbs.reader());
            while (decoder.next() catch unreachable) |cmd| {
                // logger.debug("execute {s}: {}", .{ @tagName(cmd), cmd });
                switch (cmd) {
                    .draw_text => |draw_text| {
                        const font = ashet.resources.resolve(Font, call.resource_owner, draw_text.font.as_resource()) catch |err| switch (err) {
                            error.TypeMismatch => return error.BadCode,
                            else => |e| return e,
                        };
                        rasterizer.draw_text(
                            Point.new(draw_text.x, draw_text.y),
                            &font.font_data,
                            draw_text.color,
                            draw_text.text,
                        );
                    },
                    .blit_framebuffer => |blit_framebuffer| {
                        const framebuffer = ashet.resources.resolve(Framebuffer, call.resource_owner, blit_framebuffer.framebuffer.as_resource()) catch |err| switch (err) {
                            error.TypeMismatch => return error.BadCode,
                            else => |e| return e,
                        };
                        rasterizer.blit_image(
                            Point.new(
                                blit_framebuffer.x,
                                blit_framebuffer.y,
                            ),
                            framebuffer.get_image(),
                        );
                        switch (framebuffer.type) {
                            .window => |window| try blit_widget_data(
                                &rasterizer,
                                window,
                                Point.new(blit_framebuffer.x, blit_framebuffer.y),
                                .zero,
                                framebuffer.get_size(),
                            ),
                            .widget, .video, .memory => {},
                        }
                    },
                    .blit_partial_framebuffer => |blit_framebuffer| {
                        const framebuffer = ashet.resources.resolve(Framebuffer, call.resource_owner, blit_framebuffer.framebuffer.as_resource()) catch |err| switch (err) {
                            error.TypeMismatch => return error.BadCode,
                            else => |e| return e,
                        };
                        rasterizer.blit_partial_image(
                            Rectangle.new(
                                Point.new(blit_framebuffer.x, blit_framebuffer.y),
                                Size.new(blit_framebuffer.width, blit_framebuffer.height),
                            ),
                            Point.new(blit_framebuffer.src_x, blit_framebuffer.src_y),
                            framebuffer.get_image(),
                        );
                        switch (framebuffer.type) {
                            .window => |window| try blit_widget_data(
                                &rasterizer,
                                window,
                                Point.new(blit_framebuffer.x, blit_framebuffer.y),
                                Point.new(blit_framebuffer.src_x, blit_framebuffer.src_y),
                                Size.new(blit_framebuffer.width, blit_framebuffer.height),
                            ),
                            .widget, .video, .memory => {},
                        }
                    },
                    else => rasterizer.execute(cmd, undefined),
                }
            }
        }
    }

    if (inputs.auto_invalidate) {
        fb.invalidate();
    }

    return .{};
}

pub fn render_async(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.draw.Render.Inputs) void {
    call.finalize(
        ashet.abi.draw.Render,
        render_sync(call, inputs),
    );
}

fn blit_widget_data(
    rast: *Rasterizer,
    window: *ashet.gui.Window,
    target_pos: Point,
    source_pos: Point,
    size: Size,
) !void {
    if (window.widgets.len == 0)
        return;

    var iter = window.widgets.first;
    while (iter) |node| : (iter = node.next) {
        const widget = ashet.gui.Widget.from_link(node);

        // Compute the enclosing edges:
        const left_edge = @max(source_pos.x, widget.bounds.x);
        const top_edge = @max(source_pos.y, widget.bounds.y);
        const right_edge = @min(@as(i32, source_pos.x) + size.width, @as(i32, widget.bounds.x) + widget.bounds.width);
        const bottom_edge = @min(@as(i32, source_pos.y) + size.height, @as(i32, widget.bounds.y) + widget.bounds.height);

        // Skip the widget completely if it isn't included in the partial update:
        if (right_edge <= left_edge) continue;
        if (bottom_edge <= top_edge) continue;

        const width: u16 = @intCast(right_edge - left_edge);
        const height: u16 = @intCast(bottom_edge - top_edge);

        const dst_dx = @max(0, left_edge - source_pos.x);
        const dst_dy = @max(0, top_edge - source_pos.y);

        const src_dx = @max(0, left_edge - widget.bounds.x);
        const src_dy = @max(0, top_edge - widget.bounds.y);

        std.debug.assert(width <= size.width);
        std.debug.assert(height <= size.height);

        std.debug.assert(width <= widget.bounds.width);
        std.debug.assert(height <= widget.bounds.height);

        const dest: Rectangle = .{
            .x = target_pos.x +| dst_dx,
            .y = target_pos.y +| dst_dy,
            .width = width,
            .height = height,
        };
        const src: Point = .new(src_dx, src_dy);

        const bmp: agp.Bitmap = .{
            .has_transparency = false,
            .transparency_key = undefined,
            .stride = widget.bounds.width,
            .width = widget.bounds.width,
            .height = widget.bounds.height,
            .pixels = widget.pixels.ptr,
        };

        rast.blit_partial_bitmap(dest, src, &bmp);
    }
}
