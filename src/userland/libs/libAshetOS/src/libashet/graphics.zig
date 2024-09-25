const std = @import("std");
const builtin = @import("builtin");
pub const agp = @import("agp");

const ashet = @import("../libashet.zig");

const Size = ashet.abi.Size;

pub const ColorIndex = ashet.abi.ColorIndex;
pub const Color = ashet.abi.Color;

pub const Font = ashet.abi.Font;
pub const Bitmap = agp.Bitmap;
pub const Framebuffer = ashet.abi.Framebuffer;

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

    pub fn set_clip_rect(cq: *CommandQueue, x: i16, y: i16, width: u16, height: u16) !void {
        try cq.encoder().set_clip_rect(x, y, width, height);
    }

    pub fn set_pixel(cq: *CommandQueue, x: i16, y: i16, color: ColorIndex) !void {
        try cq.encoder().set_pixel(x, y, color);
    }

    pub fn draw_line(cq: *CommandQueue, x1: i16, y1: i16, x2: i16, y2: i16, color: ColorIndex) !void {
        try cq.encoder().draw_line(x1, y1, x2, y2, color);
    }

    pub fn draw_rect(cq: *CommandQueue, x: i16, y: i16, width: u16, height: u16, color: ColorIndex) !void {
        try cq.encoder().draw_rect(x, y, width, height, color);
    }

    pub fn fill_rect(cq: *CommandQueue, x: i16, y: i16, width: u16, height: u16, color: ColorIndex) !void {
        try cq.encoder().fill_rect(x, y, width, height, color);
    }

    pub fn draw_text(cq: *CommandQueue, x: i16, y: i16, font: Font, color: ColorIndex, text: []const u8) !void {
        try cq.encoder().draw_text(x, y, font, color, text);
    }

    pub fn blit_bitmap(cq: *CommandQueue, x: i16, y: i16, bitmap: Bitmap) !void {
        try cq.encoder().blit_bitmap(x, y, bitmap);
    }

    pub fn blit_framebuffer(cq: *CommandQueue, x: i16, y: i16, framebuffer: Framebuffer) !void {
        try cq.encoder().blit_framebuffer(x, y, framebuffer);
    }

    pub fn update_color(cq: *CommandQueue, index: ColorIndex, r: u8, g: u8, b: u8) !void {
        try cq.encoder().update_color(index, r, g, b);
    }

    pub fn blit_partial_bitmap(cq: *CommandQueue, x: i16, y: i16, width: u16, height: u16, src_x: i16, src_y: i16, bitmap: Bitmap) !void {
        try cq.encoder().blit_partial_bitmap(x, y, width, height, src_x, src_y, bitmap);
    }

    pub fn blit_partial_framebuffer(cq: *CommandQueue, x: i16, y: i16, width: u16, height: u16, src_x: i16, src_y: i16, framebuffer: Framebuffer) !void {
        try cq.encoder().blit_partial_framebuffer(x, y, width, height, src_x, src_y, framebuffer);
    }
};

pub fn create_memory_framebuffer(size: Size) !Framebuffer {
    return try ashet.userland.draw.create_memory_framebuffer(size);
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
