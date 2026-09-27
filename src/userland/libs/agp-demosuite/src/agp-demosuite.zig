const std = @import("std");
const abi = @import("ashet-abi");
const agp = @import("agp");
const swrast = @import("agp-swrast");
const gif = @import("gif.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    stream: std.Io.Writer.Allocating,
    pixels: []abi.Color,
    fonts: std.ArrayList(*swrast.fonts.FontInstance) = .empty,

    pub fn deinit(self: *Context) void {
        for (self.fonts.items) |font| self.allocator.destroy(font);
        self.fonts.deinit(self.allocator);
        self.allocator.free(self.pixels);
        self.stream.deinit();
        self.* = undefined;
    }

    pub fn encoder(self: *Context) agp.Encoder {
        return agp.encoder(&self.stream.writer);
    }

    /// The returned bytes remain valid until the next encoder write or deinit.
    pub fn get_agp_stream(self: *Context) []const u8 {
        return self.stream.written();
    }

    /// Register a bitmap or vector font. Keep `data` alive until deinit.
    pub fn load_font(self: *Context, data: []const u8, hint: swrast.fonts.FontHint) !agp.Font {
        const font = try self.allocator.create(swrast.fonts.FontInstance);
        errdefer self.allocator.destroy(font);
        font.* = try swrast.fonts.FontInstance.load(data, hint);
        try self.fonts.append(self.allocator, font);
        return @ptrCast(font);
    }

    pub fn measure_text_size(self: *const Context, font: agp.Font, text: []const u8) error{InvalidFont}!abi.Size {
        const instance = self.find_font(font) orelse return error.InvalidFont;
        return .{ .width = instance.measure_width(text), .height = instance.line_height() };
    }

    /// Render the current command stream into the context's reusable framebuffer.
    pub fn get_framebuffer(self: *Context) ![]abi.Color {
        @memset(self.pixels, .black);
        var rasterizer = swrast.Rasterizer.init(.{
            .pixels = self.pixels.ptr,
            .width = self.width,
            .height = self.height,
            .stride = self.width,
        });
        var decoder = agp.BufferDecoder.init(self.get_agp_stream());
        const resolver: swrast.Rasterizer.Resolver = .{
            .ctx = self,
            .resolve_font_fn = resolve_font,
            .resolve_framebuffer_fn = resolve_framebuffer,
        };
        while (try decoder.next()) |cmd| rasterizer.execute(cmd, resolver);
        return self.pixels;
    }

    pub fn write_to(self: *Context, dir: std.fs.Dir, path: []const u8) !void {
        try gif.write_to_file_path(dir, path, self.width, self.height, try self.get_framebuffer());
    }

    fn find_font(self: *const Context, handle: agp.Font) ?*const swrast.fonts.FontInstance {
        for (self.fonts.items) |font| {
            if (@intFromPtr(font) == @intFromPtr(handle)) return font;
        }
        return null;
    }

    fn resolve_font(ctx: *anyopaque, handle: agp.Font) ?*const swrast.fonts.FontInstance {
        const self: *Context = @ptrCast(@alignCast(ctx));
        return self.find_font(handle);
    }

    fn resolve_framebuffer(_: *anyopaque, _: agp.Framebuffer) ?swrast.Image {
        return null;
    }
};

pub fn create_context(allocator: std.mem.Allocator, width: u16, height: u16) !Context {
    if (width == 0 or height == 0) return error.InvalidSize;
    const pixels = try allocator.alloc(abi.Color, @as(usize, width) * height);
    @memset(pixels, .black);
    return .{
        .allocator = allocator,
        .width = width,
        .height = height,
        .stream = .init(allocator),
        .pixels = pixels,
    };
}

/// Borrow pixels from an ABM image; keep `data` alive while using the bitmap.
pub fn bitmap_from_abm(data: []const u8) error{InvalidImage}!agp.Bitmap {
    if (data.len < 12 or std.mem.readInt(u32, data[0..4], .little) != 0x48198b74)
        return error.InvalidImage;
    const width = std.mem.readInt(u16, data[4..6], .little);
    const height = std.mem.readInt(u16, data[6..8], .little);
    const flags = std.mem.readInt(u16, data[8..10], .little);
    if (width == 0 or height == 0 or flags & ~@as(u16, 1) != 0)
        return error.InvalidImage;
    const count = @as(usize, width) * height;
    if (data.len - 12 < count) return error.InvalidImage;
    return .{
        .pixels = @ptrCast(data[12..].ptr),
        .width = width,
        .height = height,
        .stride = width,
        .has_transparency = flags & 1 != 0,
        .transparency_key = abi.Color.from_u8(data[11]),
    };
}

test "context rejects empty dimensions and renders the current stream again" {
    try std.testing.expectError(error.InvalidSize, create_context(std.testing.allocator, 0, 3));
    try std.testing.expectError(error.InvalidSize, create_context(std.testing.allocator, 3, 0));

    var context = try create_context(std.testing.allocator, 4, 3);
    defer context.deinit();
    try std.testing.expectEqual(@as(usize, 0), context.get_agp_stream().len);
    try std.testing.expectEqual(abi.Color.black, (try context.get_framebuffer())[0]);

    const enc = context.encoder();
    try enc.clear(.red);
    try enc.set_pixel(1, 1, .blue);
    try enc.fill_rect(3, 0, 2, 2, .green); // right edge clips to one pixel
    const stream = context.get_agp_stream();
    try std.testing.expectEqual(@as(u8, @intFromEnum(agp.CommandByte.clear)), stream[0]);
    try std.testing.expectEqual(abi.Color.red.to_u8(), stream[1]);

    const first = try context.get_framebuffer();
    try std.testing.expectEqual(@as(usize, 12), first.len);
    try std.testing.expectEqual(abi.Color.blue, first[1 + 4]);
    try std.testing.expectEqual(abi.Color.green, first[3]);
    try std.testing.expectEqual(abi.Color.red, first[2 + 2 * 4]);

    first[1 + 4] = .white;
    try std.testing.expectEqual(abi.Color.blue, (try context.get_framebuffer())[1 + 4]);
    try enc.set_pixel(0, 2, .cyan);
    try std.testing.expectEqual(abi.Color.cyan, (try context.get_framebuffer())[2 * 4]);
}

test "font handles measure text and render glyphs" {
    const font_data = [_]u8{
        0xbe, 0x65, 0x37, 0xcb, // bitmap font magic
        8, 0, 0, 0, // line height
        1, 0, 0, 0, // one glyph
        'A', 0, 0, 6, // codepoint and advance
        0, 0, 0, 0, // glyph offset
        1, 1, 0, 0, 1, // one pixel glyph
    };
    var context = try create_context(std.testing.allocator, 16, 8);
    defer context.deinit();
    var other = try create_context(std.testing.allocator, 1, 1);
    defer other.deinit();

    try std.testing.expectError(error.InvalidFont, context.load_font("bad font", .{}));
    const font = try context.load_font(&font_data, .{});
    try std.testing.expectEqual(abi.Size{ .width = 12, .height = 8 }, try context.measure_text_size(font, "AA"));
    try std.testing.expectError(error.InvalidFont, other.measure_text_size(font, "A"));
    try context.encoder().draw_text(2, 3, font, .white, "A");
    const pixels = try context.get_framebuffer();
    try std.testing.expectEqual(abi.Color.white, pixels[2 + 3 * 16]);
    try std.testing.expectEqual(abi.Color.black, pixels[3 + 3 * 16]);
}

test "ABM images validate headers and preserve transparency" {
    const image = [_]u8{
        0x74, 0x8b, 0x19, 0x48, // ABM magic
        2, 0, 1, 0, // two pixels
        1, 0, 5, 0x22, // transparency, palette size, key
        0x22, 0x44, // transparent pixel, visible pixel
    };
    const bitmap = try bitmap_from_abm(&image);
    try std.testing.expectEqual(@as(u16, 2), bitmap.width);
    try std.testing.expectEqual(@as(u16, 1), bitmap.height);
    try std.testing.expectEqual(@as(usize, 2), bitmap.stride);
    try std.testing.expect(bitmap.has_transparency);
    try std.testing.expectEqual(@intFromPtr(&image[12]), @intFromPtr(bitmap.pixels));

    var context = try create_context(std.testing.allocator, 4, 2);
    defer context.deinit();
    const enc = context.encoder();
    try enc.clear(.green);
    try enc.blit_bitmap(1, 1, &bitmap);
    const pixels = try context.get_framebuffer();
    try std.testing.expectEqual(abi.Color.green, pixels[1 + 4]);
    try std.testing.expectEqual(abi.Color.from_u8(0x44), pixels[2 + 4]);

    try std.testing.expectError(error.InvalidImage, bitmap_from_abm(image[0..11]));
    try std.testing.expectError(error.InvalidImage, bitmap_from_abm(image[0..13]));
    var invalid = image;
    invalid[0] = 0;
    try std.testing.expectError(error.InvalidImage, bitmap_from_abm(&invalid));
    invalid = image;
    invalid[4] = 0;
    try std.testing.expectError(error.InvalidImage, bitmap_from_abm(&invalid));
    invalid = image;
    invalid[8] = 2;
    try std.testing.expectError(error.InvalidImage, bitmap_from_abm(&invalid));
}

test "write_to writes a single GIF with the rendered size and palette" {
    var context = try create_context(std.testing.allocator, 2, 1);
    defer context.deinit();
    const enc = context.encoder();
    try enc.clear(.red);
    try enc.set_pixel(1, 0, .blue);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try context.write_to(tmp.dir, "image.gif");
    const bytes = try tmp.dir.readFileAlloc(std.testing.allocator, "image.gif", 4096);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings("GIF89a", bytes[0..6]);
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, bytes[6..8], .little));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes[8..10], .little));
    const red = abi.Color.red.to_rgb888();
    const offset = 13 + @as(usize, abi.Color.red.to_u8()) * 3;
    try std.testing.expectEqualSlices(u8, &.{ red.r, red.g, red.b }, bytes[offset..][0..3]);
    try std.testing.expectEqual(@as(u8, 0x3b), bytes[bytes.len - 1]);
    try std.testing.expectEqual(abi.Color.blue, (try context.get_framebuffer())[1]);
}
