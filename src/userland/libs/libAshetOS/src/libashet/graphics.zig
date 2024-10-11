const std = @import("std");
const builtin = @import("builtin");
const ashet = @import("../libashet.zig");
const logger = std.log.scoped(.graphics);

pub const Point = ashet.abi.Point;
pub const Size = ashet.abi.Size;
pub const Rectangle = ashet.abi.Rectangle;

pub const ColorIndex = ashet.abi.ColorIndex;
pub const Color = ashet.abi.Color;

pub const Font = ashet.abi.Font;
pub const Bitmap = agp.Bitmap;
pub const Framebuffer = ashet.abi.Framebuffer;

pub const agp = @import("agp");

pub const known_colors = struct {
    pub const black = ColorIndex.get(0x00); // #000000
    pub const dark_blue = ColorIndex.get(0x01); // #2d1a71
    pub const blue = ColorIndex.get(0x02); // #3e32d5
    pub const dark_red = ColorIndex.get(0x03); // #af102e
    pub const red = ColorIndex.get(0x04); // #e4162b
    pub const dark_green = ColorIndex.get(0x05); // #0e3e12
    pub const green = ColorIndex.get(0x06); // #38741a
    pub const brown = ColorIndex.get(0x07); // #8d4131
    pub const yellow = ColorIndex.get(0x08); // #ffff40
    pub const dark_gray = ColorIndex.get(0x09); // #505d6d
    pub const gray = ColorIndex.get(0x0A); // #7b95a0
    pub const bright_gray = ColorIndex.get(0x0B); // #a6cfd0
    pub const violet = ColorIndex.get(0x0C); // #b44cef
    pub const pink = ColorIndex.get(0x0D); // #e444c3
    pub const teal = ColorIndex.get(0x0E); // #00bc9f
    pub const white = ColorIndex.get(0x0F); // #ffffff
    pub const bright_green = ColorIndex.get(0x10); // #afe356
    pub const dim_gray = ColorIndex.get(0x11); // #2f3143
    pub const gold = ColorIndex.get(0x12); // #fbc800
};

pub fn render(target: Framebuffer, command_sequence: []const u8, auto_invalidate: bool) !void {
    if (builtin.mode == .Debug) {
        // In Debug mode, assert that we have a valid command sequence:
        var fbs = std.io.fixedBufferStream(command_sequence);
        var decoder = agp.decoder(fbs.reader());
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

    pub fn clear(cq: *CommandQueue, color: ColorIndex) !void {
        try cq.encoder().clear(color);
    }

    pub fn set_clip_rect(cq: *CommandQueue, rectangle: Rectangle) !void {
        try cq.encoder().set_clip_rect(rectangle.x, rectangle.y, rectangle.width, rectangle.height);
    }

    pub fn set_pixel(cq: *CommandQueue, point: Point, color: ColorIndex) !void {
        try cq.encoder().set_pixel(point.x, point.y, color);
    }

    pub fn draw_line(cq: *CommandQueue, p1: Point, p2: Point, color: ColorIndex) !void {
        try cq.encoder().draw_line(p1.x, p1.y, p2.x, p2.y, color);
    }

    pub fn draw_horizontal_line(cq: *CommandQueue, left: Point, length: u16, color: ColorIndex) !void {
        try cq.draw_line(
            left,
            Point.new(left.x + @as(u15, @intCast(length)), left.y),
            color,
        );
    }

    pub fn draw_vertical_line(cq: *CommandQueue, top: Point, length: u16, color: ColorIndex) !void {
        try cq.draw_line(
            top,
            Point.new(top.x, top.y + @as(u15, @intCast(length))),
            color,
        );
    }

    pub fn draw_rect(cq: *CommandQueue, rectangle: Rectangle, color: ColorIndex) !void {
        try cq.encoder().draw_rect(rectangle.x, rectangle.y, rectangle.width, rectangle.height, color);
    }

    pub fn fill_rect(cq: *CommandQueue, rectangle: Rectangle, color: ColorIndex) !void {
        try cq.encoder().fill_rect(rectangle.x, rectangle.y, rectangle.width, rectangle.height, color);
    }

    pub fn draw_text(cq: *CommandQueue, point: Point, font: Font, color: ColorIndex, text: []const u8) !void {
        try cq.encoder().draw_text(point.x, point.y, font, color, text);
    }

    pub fn blit_bitmap(cq: *CommandQueue, point: Point, bitmap: *const Bitmap) !void {
        try cq.encoder().blit_bitmap(point.x, point.y, bitmap);
    }

    pub fn blit_framebuffer(cq: *CommandQueue, point: Point, framebuffer: Framebuffer) !void {
        try cq.encoder().blit_framebuffer(point.x, point.y, framebuffer);
    }

    pub fn update_color(cq: *CommandQueue, index: ColorIndex, r: u8, g: u8, b: u8) !void {
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
    return try ashet.userland.draw.get_system_font(font_name);
}

pub fn create_memory_framebuffer(size: Size) !Framebuffer {
    return try ashet.userland.draw.create_memory_framebuffer(size);
}

pub fn create_window_framebuffer(window: ashet.abi.Window) !Framebuffer {
    return try ashet.userland.draw.create_window_framebuffer(window);
}

pub fn get_framebuffer_memory(fb: Framebuffer) !ashet.abi.VideoMemory {
    return try ashet.userland.draw.get_framebuffer_memory(fb);
}

pub fn load_bitmap_file(file: ashet.fs.File) !Framebuffer {
    var header: ABM_Header = undefined;

    if (try file.read(0, std.mem.asBytes(&header)) != @sizeOf(ABM_Header)) {
        return error.InvalidFile;
    }

    // Unswap header data:
    inline for (comptime std.meta.fields(ABM_Header)) |fld| {
        @field(header, fld.name) = std.mem.littleToNative(fld.type, @field(header, fld.name));
    }

    logger.info("header: 0x{X:0>8} size={}x{}, palette={}, key=0x{X:0>2}, flags={X:0>4}", .{
        header.magic,
        header.width,
        header.height,
        header.palette_size,
        header.transparency_key,
        header.flags,
    });

    if (header.magic != ABM_Header.magic_number)
        return error.InvalidFile;

    const pixel_count: u32 = @as(u32, header.width) * @as(u32, header.height);
    const pixel_offset: u64 = @sizeOf(ABM_Header);
    const palette_offset: u64 = pixel_offset + pixel_count;
    const palette_entry_count: u16 = if (header.palette_size == 0)
        256
    else
        header.palette_size;

    const fb = try create_memory_framebuffer(Size.new(header.width, header.height));
    errdefer fb.release();

    const vmem = get_framebuffer_memory(fb) catch unreachable;

    std.debug.assert(vmem.width == header.width);
    std.debug.assert(vmem.height == header.height);

    if (vmem.stride == vmem.width) {
        const len = try file.read(pixel_offset, std.mem.sliceAsBytes(vmem.base[0..pixel_count]));
        if (len != pixel_count)
            return error.InvalidFile;
    } else {
        var scanline: [*]ColorIndex = vmem.base;
        var scanline_offset = pixel_offset;

        for (0..header.height) |_| {
            const len = try file.read(scanline_offset, std.mem.sliceAsBytes(scanline[0..vmem.width]));
            if (len != vmem.width)
                return error.InvalidFile;
            scanline_offset += vmem.width;
            scanline += vmem.stride;
        }
    }

    // TODO(fqu): Implement distinct palette support for framebuffers?
    _ = palette_entry_count;
    _ = palette_offset;

    return fb;
}

const ABM_Header = extern struct {
    const magic_number: u32 = 0x48198b74;

    magic: u32,
    width: u16,
    height: u16,
    flags: u16,
    palette_size: u8,
    transparency_key: u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 12);
    }
};

pub fn embed_comptime_bitmap(comptime base: comptime_int, comptime def: []const u8) *const ashet.graphics.Bitmap {
    @setEvalBranchQuota(10_000);

    const size = parsedSpriteSize(def);
    var icon: [size.height][size.width]?ColorIndex = [1][size.width]?ColorIndex{
        [1]?ColorIndex{null} ** size.width,
    } ** size.height;

    var needs_transparency = false;
    var can_use_0xFF = true;
    var can_use_0x00 = true;

    var it = std.mem.splitScalar(u8, def, '\n');
    var y: usize = 0;
    while (it.next()) |line| : (y += 1) {
        var x: usize = 0;
        while (x < icon[0].len) : (x += 1) {
            icon[y][x] = if (std.fmt.parseInt(u8, line[x .. x + 1], 16)) |index|
                ColorIndex.get(base + index)
            else |_|
                null;
            if (icon[y][x] == null)
                needs_transparency = true;
            if (icon[y][x] == ColorIndex.get(0x00))
                can_use_0x00 = false;
            if (icon[y][x] == ColorIndex.get(0xFF))
                can_use_0xFF = false;
        }
    }

    const transparency_key: ColorIndex = if (needs_transparency)
        if (can_use_0x00)
            ColorIndex.get(0x00)
        else if (can_use_0xFF)
            ColorIndex.get(0xFF)
        else
            @compileError("Can't declare an icon that uses both 0xFF and 0x00!")
    else
        undefined;

    var output_bits: [size.height * size.width]ColorIndex = undefined;
    var index: usize = 0;
    for (icon) |row| {
        for (row) |pixel| {
            output_bits[index] = pixel orelse transparency_key;
            index += 1;
        }
    }

    const const_output_bits = output_bits;

    return comptime &ashet.graphics.Bitmap{
        .pixels = &const_output_bits,
        .width = size.width,
        .height = size.height,
        .stride = size.width,
        .transparency_key = if (needs_transparency)
            transparency_key
        else
            null,
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
