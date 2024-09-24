const std = @import("std");
const ashet = @import("../main.zig");
const agp = @import("agp");
const agp_swrast = @import("agp-swrast");

const logger = std.log.scoped(.graphics);

const fonts = @import("graphics/fonts.zig");
const software_renderer = @import("graphics/software_renderer.zig");

const Size = ashet.abi.Size;
const ColorIndex = ashet.abi.ColorIndex;
comptime {
    std.debug.assert(ColorIndex == agp.ColorIndex);
}

pub const Bitmap = struct {
    width: u16, // width of the image
    height: u16, // height of the image
    stride: u32, // row length in pixels
    pixels: [*]ColorIndex, // height * stride pixels
};

pub const Framebuffer = struct {
    const Cursor = agp_swrast.PixelCursor(.row_major);
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    pub const Type = union(ashet.abi.FramebufferType) {
        memory: Bitmap,
        video: ashet.video.VideoMemory,
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
            .type = .{ .video = output.get_video_memory() },
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
            .window => @panic("Framebuffer(.window).destroy Not implemented yet!"),
            .widget => @panic("Framebuffer(.widget).destroy Not implemented yet!"),
        }
        ashet.memory.type_pool(Framebuffer).free(fb);
    }

    fn invalidate(fb: *Framebuffer) void {
        _ = fb;
    }

    pub fn get_size(fb: Framebuffer) Size {
        const cursor = fb.create_cursor();
        return Size.new(cursor.width, cursor.height);
    }

    pub fn create_cursor(fb: Framebuffer) Cursor {
        const width, const height, const stride = switch (fb.type) {
            .memory => |bmp| .{ bmp.width, bmp.height, bmp.stride },
            .video => |vmem| .{ vmem.width, vmem.height, vmem.stride },
            .window => @panic("Framebuffer(.window).destroy Not implemented yet!"),
            .widget => @panic("Framebuffer(.widget).destroy Not implemented yet!"),
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
            .video => |vmem| vmem.base,
            .window => @panic("Framebuffer(.window).destroy Not implemented yet!"),
            .widget => @panic("Framebuffer(.widget).destroy Not implemented yet!"),
        };

        @memset(framebuffer[cursor.offset..][0..count], color_index);
    }
};

pub const Font = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .font },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *Font) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

fn render_sync(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.draw.Render.Inputs) ashet.abi.draw.Render.Error!ashet.abi.draw.Render.Outputs {
    logger.info("render sync!", .{});

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
        const Rasterizer = agp_swrast.Rasterizer(*Framebuffer, .{
            .pixel_layout = .row_major,
        });

        var rasterizer = Rasterizer.init(fb);

        var decoder = agp.decoder(fbs.reader());
        while (decoder.next() catch unreachable) |cmd| {
            logger.debug("execute {s}", .{@tagName(cmd)});
            rasterizer.execute(cmd);
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
