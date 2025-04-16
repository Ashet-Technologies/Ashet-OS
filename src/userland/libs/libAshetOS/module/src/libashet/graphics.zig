const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../libashet.zig");
const logger = std.log.scoped(.graphics);

pub const Point = ashet.abi.Point;
pub const Size = ashet.abi.Size;
pub const Rectangle = ashet.abi.Rectangle;

pub const Color = ashet.abi.Color;

pub const Font = ashet.abi.Font;
pub const Bitmap = agp.Bitmap;
pub const Framebuffer = ashet.abi.Framebuffer;

pub const agp = @import("agp");

pub const known_colors = struct {
    pub const black = Color.from_html("#000000");
    pub const dark_blue = Color.from_html("#2d1a71");
    pub const blue = Color.from_html("#3e32d5");
    pub const dark_red = Color.from_html("#af102e");
    pub const red = Color.from_html("#e4162b");
    pub const dark_green = Color.from_html("#0e3e12");
    pub const green = Color.from_html("#38741a");
    pub const brown = Color.from_html("#8d4131");
    pub const yellow = Color.from_html("#ffff40");
    pub const dark_gray = Color.from_html("#505d6d");
    pub const gray = Color.from_html("#7b95a0");
    pub const bright_gray = Color.from_html("#a6cfd0");
    pub const violet = Color.from_html("#b44cef");
    pub const pink = Color.from_html("#e444c3");
    pub const teal = Color.from_html("#00bc9f");
    pub const white = Color.from_html("#ffffff");
    pub const bright_green = Color.from_html("#afe356");
    pub const dim_gray = Color.from_html("#2f3143");
    pub const gold = Color.from_html("#fbc800");
};

pub fn render(target: Framebuffer, command_sequence: []const u8, auto_invalidate: bool) !void {
    if (builtin.mode == .Debug) {
        // In Debug mode, assert that we have a valid command sequence:
        var fbs = std.io.fixedBufferStream(command_sequence);
        var decoder = agp.decoder(ashet.process.mem.allocator(), fbs.reader());
        defer decoder.deinit();
        while (true) {
            const res = decoder.next() catch @panic("Invalid command sequence detected!");
            if (res == null)
                break;
        }
    }

    _ = try ashet.overlapped.performOne(ashet.abi.draw.Render, .{
        .target = target,
        .sequence_ptr = command_sequence.ptr,
        .sequence_len = command_sequence.len,
        .auto_invalidate = auto_invalidate,
    });
}

pub const CommandQueue = struct {
    const WriteError = error{OutOfMemory};
    const Writer = std.io.Writer(*CommandQueue, WriteError, raw_append);
    const Encoder = agp.Encoder(Writer);

    data: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) !CommandQueue {
        return .{
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(cq: *CommandQueue) void {
        cq.data.deinit();
        cq.* = undefined;
    }

    pub const SubmitOptions = struct {
        mode: enum { invalidate, no_refresh } = .invalidate,
        reset: bool = true,
    };
    pub fn submit(cq: *CommandQueue, fb: ashet.abi.Framebuffer, options: SubmitOptions) !void {
        try render(fb, cq.data.items, options.mode == .invalidate);
        if (options.reset)
            cq.reset();
    }

    pub fn reset(cq: *CommandQueue) void {
        cq.data.shrinkRetainingCapacity(0);
    }

    fn raw_append(cq: *CommandQueue, data: []const u8) WriteError!usize {
        try cq.data.appendSlice(data);
        return data.len;
    }

    fn encoder(cq: *CommandQueue) Encoder {
        return .{ .writer = .{ .context = cq } };
    }

    pub fn encode(cq: *CommandQueue, cmd: agp.Command) !void {
        cq.encoder().encode(cmd);
    }

    pub fn clear(cq: *CommandQueue, color: Color) !void {
        try cq.encoder().clear(color);
    }

    pub fn set_clip_rect(cq: *CommandQueue, rectangle: Rectangle) !void {
        try cq.encoder().set_clip_rect(rectangle.x, rectangle.y, rectangle.width, rectangle.height);
    }

    pub fn set_pixel(cq: *CommandQueue, point: Point, color: Color) !void {
        try cq.encoder().set_pixel(point.x, point.y, color);
    }

    pub fn draw_line(cq: *CommandQueue, p1: Point, p2: Point, color: Color) !void {
        try cq.encoder().draw_line(p1.x, p1.y, p2.x, p2.y, color);
    }

    pub fn draw_horizontal_line(cq: *CommandQueue, left: Point, length: u16, color: Color) !void {
        try cq.draw_line(
            left,
            Point.new(left.x + @as(u15, @intCast(length)), left.y),
            color,
        );
    }

    pub fn draw_vertical_line(cq: *CommandQueue, top: Point, length: u16, color: Color) !void {
        try cq.draw_line(
            top,
            Point.new(top.x, top.y + @as(u15, @intCast(length))),
            color,
        );
    }

    pub fn draw_rect(cq: *CommandQueue, rectangle: Rectangle, color: Color) !void {
        try cq.encoder().draw_rect(rectangle.x, rectangle.y, rectangle.width, rectangle.height, color);
    }

    pub fn fill_rect(cq: *CommandQueue, rectangle: Rectangle, color: Color) !void {
        try cq.encoder().fill_rect(rectangle.x, rectangle.y, rectangle.width, rectangle.height, color);
    }

    pub fn draw_text(cq: *CommandQueue, point: Point, font: Font, color: Color, text: []const u8) !void {
        try cq.encoder().draw_text(point.x, point.y, font, color, text);
    }

    pub fn blit_bitmap(cq: *CommandQueue, point: Point, bitmap: *const Bitmap) !void {
        try cq.encoder().blit_bitmap(point.x, point.y, bitmap);
    }

    pub fn blit_framebuffer(cq: *CommandQueue, point: Point, framebuffer: Framebuffer) !void {
        try cq.encoder().blit_framebuffer(point.x, point.y, framebuffer);
    }

    pub fn update_color(cq: *CommandQueue, index: Color, r: u8, g: u8, b: u8) !void {
        try cq.encoder().update_color(index, r, g, b);
    }

    pub fn blit_partial_bitmap(cq: *CommandQueue, target: Rectangle, src_pos: Point, bitmap: *const Bitmap) !void {
        try cq.encoder().blit_partial_bitmap(target.x, target.y, target.width, target.height, src_pos.x, src_pos.y, bitmap);
    }

    pub fn blit_partial_framebuffer(cq: *CommandQueue, target: Rectangle, src_pos: Point, framebuffer: Framebuffer) !void {
        try cq.encoder().blit_partial_framebuffer(target.x, target.y, target.width, target.height, src_pos.x, src_pos.y, framebuffer);
    }
};

pub fn get_system_font(font_name: []const u8) !Font {
    errdefer |e| logger.debug("failed to load font '{s}': {}", .{ font_name, e });
    return try ashet.userland.draw.get_system_font(font_name);
}

pub fn create_memory_framebuffer(size: Size) !Framebuffer {
    return try ashet.userland.draw.create_memory_framebuffer(size);
}

pub fn create_video_framebuffer(output: *ashet.video.Output) !Framebuffer {
    return try ashet.userland.draw.create_video_framebuffer(@ptrCast(output));
}

pub fn create_window_framebuffer(window: ashet.abi.Window) !Framebuffer {
    return try ashet.userland.draw.create_window_framebuffer(window);
}

pub fn get_framebuffer_memory(fb: Framebuffer) !ashet.abi.VideoMemory {
    return try ashet.userland.draw.get_framebuffer_memory(fb);
}

pub fn get_framebuffer_size(fb: Framebuffer) !ashet.abi.Size {
    return try ashet.userland.draw.get_framebuffer_size(fb);
}

pub fn load_texture_file(file: ashet.fs.File) !Framebuffer {
    return try load_texture_file_at(file, 0);
}

pub fn load_texture_file_at(file: ashet.fs.File, abs_offset: u64) !Framebuffer {
    const header = try abm.read_header(file, abs_offset);

    const fb = try create_memory_framebuffer(Size.new(header.width, header.height));
    errdefer fb.release();

    const vmem = get_framebuffer_memory(fb) catch unreachable;

    std.debug.assert(vmem.width == header.width);
    std.debug.assert(vmem.height == header.height);

    try abm.read_pixels(file, abs_offset, header, vmem);

    return fb;
}

pub fn load_bitmap_file(allocator: std.mem.Allocator, file: ashet.fs.File) !Bitmap {
    return try load_bitmap_file_at(allocator, file, 0);
}

pub fn load_bitmap_file_at(allocator: std.mem.Allocator, file: ashet.fs.File, abs_offset: u64) !Bitmap {
    const header = try abm.read_header(file, abs_offset);

    const buffer = try allocator.alignedAlloc(Color, 4, @as(u32, header.width) * header.height);
    errdefer allocator.free(buffer);

    try abm.read_pixels(file, abs_offset, header, .{
        .base = buffer.ptr,
        .stride = header.width,
        .width = header.width,
        .height = header.height,
    });

    return .{
        .pixels = buffer.ptr,
        .width = header.width,
        .height = header.height,
        .stride = header.width,
        .transparency_key = header.transparency_key,
        .has_transparency = header.flags.use_transparent,
    };
}

pub const abm = struct {
    pub fn read_header(file: ashet.fs.File, abm_offset: u64) !Header {
        var header: Header = undefined;

        if (try file.read(abm_offset, std.mem.asBytes(&header)) != @sizeOf(Header)) {
            return error.InvalidFile;
        }

        // Unswap header data:
        inline for (comptime std.meta.fields(Header)) |fld| {
            @field(header, fld.name) = std.mem.littleToNative(fld.type, @field(header, fld.name));
        }

        logger.info("header: 0x{X:0>8} size={}x{}, palette={}, key={}, flags={}", .{
            header.magic,
            header.width,
            header.height,
            header.palette_size,
            header.transparency_key,
            header.flags,
        });

        if (header.magic != Header.magic_number)
            return error.InvalidFile;

        return header;
    }

    pub fn read_pixels(file: ashet.fs.File, abm_offset: u64, header: Header, vmem: ashet.abi.VideoMemory) !void {
        const pixel_count: u32 = @as(u32, header.width) * @as(u32, header.height);
        const pixel_offset: u64 = @sizeOf(abm.Header);

        if (vmem.stride == vmem.width) {
            const len = try file.read(abm_offset + pixel_offset, std.mem.sliceAsBytes(vmem.base[0..pixel_count]));
            if (len != pixel_count)
                return error.InvalidFile;
        } else {
            var scanline: [*]Color = vmem.base;
            var scanline_offset = pixel_offset;

            for (0..header.height) |_| {
                const len = try file.read(abm_offset + scanline_offset, std.mem.sliceAsBytes(scanline[0..vmem.width]));
                if (len != vmem.width)
                    return error.InvalidFile;
                scanline_offset += vmem.width;
                scanline += vmem.stride;
            }
        }
    }

    const Header = extern struct {
        const magic_number: u32 = 0x48198b74;

        magic: u32,
        width: u16,
        height: u16,
        flags: packed struct(u16) {
            use_transparent: bool,
            _padding: u15 = 0,
        },
        palette_size: u8,
        transparency_key: Color,

        comptime {
            std.debug.assert(@sizeOf(@This()) == 12);
        }
    };
};

pub fn embed_comptime_bitmap(comptime palette: anytype, comptime def: []const u8) *const ashet.graphics.Bitmap {
    @setEvalBranchQuota(100_000);

    const Palette = @TypeOf(palette);

    const palette_fields = @typeInfo(Palette).@"struct".fields;
    for (palette_fields) |fld| {
        if (fld.name.len != 1 or fld.name[0] == '.' or fld.name[0] == ' ' or !std.ascii.isPrint(fld.name[0]))
            @compileError("Invalid palette entry: '" + fld.name + "'");
    }

    const size = parsedSpriteSize(def);
    var icon: [size.height][size.width]?Color = [1][size.width]?Color{
        [1]?Color{null} ** size.width,
    } ** size.height;

    var needs_transparency = false;
    var transparency_keys = std.bit_set.StaticBitSet(256).initFull();

    var it = std.mem.splitScalar(u8, def, '\n');
    var y: usize = 0;
    while (it.next()) |line| : (y += 1) {
        var x: usize = 0;
        while (x < icon[0].len) : (x += 1) {
            const color_key = line[x];
            const pixel_color: ?Color = if (color_key == ' ' or color_key == '.')
                null // transparency
            else
                @field(palette, &.{color_key});

            if (pixel_color) |color| {
                transparency_keys.unset(color.to_u8());
            } else {
                // Pixel is transparent
                needs_transparency = true;
            }

            icon[y][x] = pixel_color;
        }
    }

    const transparency_key: ?Color = if (needs_transparency)
        if (transparency_keys.toggleFirstSet()) |key|
            Color.from_u8(@intCast(key))
        else
            @compileError("Can't declare an icon that uses both 0xFF and 0x00!")
    else
        null;

    var output_bits: [size.height * size.width]Color align(4) = undefined;
    var index: usize = 0;
    for (icon) |row| {
        for (row) |pixel| {
            output_bits[index] = pixel orelse transparency_key.?;
            index += 1;
        }
    }

    const const_output_bits align(4) = comptime output_bits;

    return comptime &ashet.graphics.Bitmap{
        .pixels = &const_output_bits,
        .width = size.width,
        .height = size.height,
        .stride = size.width,
        .transparency_key = transparency_key orelse undefined,
        .has_transparency = (transparency_key != null),
    };
}

fn parsedSpriteSize(comptime def: []const u8) Size {
    var it = std.mem.splitScalar(u8, def, '\n');
    const first = it.next().?;
    const width = first.len;
    var height = 1;
    while (it.next()) |line| {
        std.debug.assert(line.len == width);
        height += 1;
    }
    return .{ .width = width, .height = height };
}
