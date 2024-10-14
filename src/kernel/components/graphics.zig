const std = @import("std");
const ashet = @import("../main.zig");
const agp = @import("agp");
const agp_swrast = @import("agp-swrast");

const logger = std.log.scoped(.graphics);

const fonts = agp_swrast.fonts;
const software_renderer = @import("graphics/software_renderer.zig");

const Rectangle = ashet.abi.Rectangle;
const Point = ashet.abi.Point;
const Size = ashet.abi.Size;

const ColorIndex = ashet.abi.ColorIndex;

comptime {
    std.debug.assert(ColorIndex == agp.ColorIndex);
}

pub fn initialize() !void {
    try initialize_system_fonts();
}

pub const Bitmap = struct {
    width: u16, // width of the image
    height: u16, // height of the image
    stride: u32, // row length in pixels
    pixels: [*]align(4) ColorIndex, // height * stride pixels
};

pub const Framebuffer = struct {
    const Cursor = agp_swrast.PixelCursor(.row_major);
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
        const stride: usize = std.mem.alignForward(usize, width, 4);

        const back_buffer = ashet.memory.allocator.alignedAlloc(ColorIndex, 4, stride * height) catch return error.SystemResources;
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

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(fb: *Framebuffer) void {
        switch (fb.type) {
            .memory => |bmp| {
                const back_buffer = bmp.pixels[0 .. @as(usize, bmp.width) * bmp.stride];
                ashet.memory.allocator.free(back_buffer);
            },
            .video => {},
            .window => {},
            .widget => @panic("Framebuffer(.widget).destroy Not implemented yet!"),
        }
        ashet.memory.type_pool(Framebuffer).free(fb);
    }

    fn invalidate(fb: *Framebuffer) void {
        switch (fb.type) {
            .memory => {}, // no-op, nothing to invalidate
            .video => |video| {
                video.output.flush();
            },
            .window => |win| {
                _ = win;
                // TODO: Forward to owning desktop that the window has been invalidated.
            },
            .widget => @panic("Framebuffer(.widget).invalidate Not implemented yet!"),
        }
    }

    pub fn get_size(fb: Framebuffer) Size {
        const cursor = fb.create_cursor();
        return Size.new(cursor.width, cursor.height);
    }

    pub fn create_cursor(fb: Framebuffer) Cursor {
        const width, const height, const stride = switch (fb.type) {
            .memory => |bmp| .{ bmp.width, bmp.height, bmp.stride },
            .video => |video| .{ video.memory.width, video.memory.height, video.memory.stride },
            .window => |win| .{ win.size.width, win.size.height, win.max_size.width },
            .widget => @panic("Framebuffer(.widget).create_cursor Not implemented yet!"),
        };
        return .{
            .width = width,
            .height = height,
            .stride = stride,
        };
    }

    pub fn emit_pixels(fb: *Framebuffer, cursor: Cursor, color_index: ColorIndex, count: u16) void {
        const framebuffer: [*]ColorIndex = switch (fb.type) {
            .memory => |bmp| bmp.pixels,
            .video => |video| video.memory.base,
            .window => |win| win.pixels.ptr,
            .widget => @panic("Framebuffer(.widget).emit_pixels Not implemented yet!"),
        };

        @memset(framebuffer[cursor.offset..][0..count], color_index);
    }

    pub fn fetch_pixels(fb: *Framebuffer, cursor: Cursor, pixels: []ColorIndex) void {
        const framebuffer: [*]const ColorIndex = switch (fb.type) {
            .memory => |bmp| bmp.pixels,
            .video => |video| video.memory.base,
            .window => |win| win.pixels.ptr,
            .widget => @panic("Framebuffer(.widget).fetch_pixels Not implemented yet!"),
        };
        // logger.info("{s} {*} {*}", .{ @tagName(fb.type), framebuffer, pixels });
        // logger.info("{any}", .{framebuffer[cursor.offset..][0..pixels.len]});
        @memcpy(pixels, framebuffer[cursor.offset..][0..pixels.len]);
    }

    pub fn copy_pixels(fb: *Framebuffer, cursor: Cursor, pixels: []const ColorIndex) void {
        const framebuffer: [*]ColorIndex = switch (fb.type) {
            .memory => |bmp| bmp.pixels,
            .video => |video| video.memory.base,
            .window => |win| win.pixels.ptr,
            .widget => @panic("Framebuffer(.widget).copy_pixels Not implemented yet!"),
        };
        @memcpy(framebuffer[cursor.offset..][0..pixels.len], pixels);
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
};

var system_fonts: std.StringArrayHashMap(Font) = undefined;

fn initialize_system_fonts() !void {
    system_fonts = std.StringArrayHashMap(Font).init(ashet.memory.static_memory_allocator);

    try system_fonts.put("sans-6", Font{
        .system_font = true,
        .raw_data = @embedFile("sans-6.font"),
        .font_data = fonts.FontInstance.load(@embedFile("sans-6.font"), .{}) catch @panic("bad font: sans-6"),
    });
}

pub fn get_system_font(font_name: []const u8) error{FileNotFound}!*Font {
    return system_fonts.getPtr(font_name) orelse return error.FileNotFound;
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
        var decoder = agp.decoder(fbs.reader());
        while (true) {
            const maybe_cmd = decoder.next() catch return error.BadCode;
            if (maybe_cmd == null)
                break;
        }
    }

    fbs.reset();

    // Now render to the framebuffer:
    {
        const Rasterizer = agp_swrast.Rasterizer(.{
            .backend_type = *Framebuffer,
            .framebuffer_type = *Framebuffer,
            .pixel_layout = .row_major,
        });

        var rasterizer = Rasterizer.init(fb);

        var decoder = agp.decoder(fbs.reader());
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
                    rasterizer.blit_framebuffer(
                        Point.new(
                            blit_framebuffer.x,
                            blit_framebuffer.y,
                        ),
                        framebuffer,
                    );
                },
                .blit_partial_framebuffer => |blit_framebuffer| {
                    const framebuffer = ashet.resources.resolve(Framebuffer, call.resource_owner, blit_framebuffer.framebuffer.as_resource()) catch |err| switch (err) {
                        error.TypeMismatch => return error.BadCode,
                        else => |e| return e,
                    };
                    rasterizer.blit_partial_framebuffer(
                        Rectangle.new(
                            Point.new(blit_framebuffer.x, blit_framebuffer.y),
                            Size.new(blit_framebuffer.width, blit_framebuffer.height),
                        ),
                        Point.new(blit_framebuffer.src_x, blit_framebuffer.src_y),
                        framebuffer,
                    );
                },
                else => rasterizer.execute(cmd),
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
