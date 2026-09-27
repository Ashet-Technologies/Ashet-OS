const std = @import("std");
const abi = @import("ashet-abi");
const agp = @import("agp");
const swrast = @import("agp-swrast");
const gif = @import("gif.zig");

pub const Context = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    fonts: std.ArrayList(*swrast.fonts.FontInstance) = .empty,

    pub fn deinit(self: *Context) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn create_framebuffer(self: *Context, width: u16, height: u16) !Framebuffer {
        if (width == 0 or height == 0) return error.InvalidSize;
        const pixels = try self.allocator.alloc(abi.Color, @as(usize, width) * height);
        @memset(pixels, .black);
        return .{
            .context = self,
            .width = width,
            .height = height,
            .stream = .init(self.allocator),
            .pixels = pixels,
        };
    }

    /// Register a bitmap or vector font. The context owns its copy of `data`.
    pub fn load_font(self: *Context, data: []const u8, hint: swrast.fonts.FontHint) !agp.Font {
        _ = try swrast.fonts.FontInstance.load(data, hint);
        const heap = self.arena.allocator();
        const copy = try heap.dupe(u8, data);
        const font = try heap.create(swrast.fonts.FontInstance);
        font.* = try swrast.fonts.FontInstance.load(copy, hint);
        try self.fonts.append(heap, font);
        return @ptrCast(font);
    }

    /// Register an ABM bitmap. Its pixels and metadata remain valid until deinit.
    pub fn load_bitmap(self: *Context, data: []const u8) !*const agp.Bitmap {
        const parsed = try parse_abm(data);
        const heap = self.arena.allocator();
        const count = @as(usize, parsed.width) * parsed.height;
        const pixels = try heap.dupe(abi.Color, parsed.pixels[0..count]);
        const bitmap = try heap.create(agp.Bitmap);
        bitmap.* = parsed;
        bitmap.pixels = pixels.ptr;
        return bitmap;
    }

    pub fn measure_text_size(self: *const Context, font: agp.Font, text: []const u8) error{InvalidFont}!abi.Size {
        const instance = self.find_font(font) orelse return error.InvalidFont;
        return .{ .width = instance.measure_width(text), .height = instance.line_height() };
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
};

pub const Framebuffer = struct {
    context: *Context,
    width: u16,
    height: u16,
    stream: std.Io.Writer.Allocating,
    pixels: []abi.Color,

    pub fn deinit(self: *Framebuffer) void {
        self.context.allocator.free(self.pixels);
        self.stream.deinit();
        self.* = undefined;
    }

    pub fn encoder(self: *Framebuffer) agp.Encoder {
        return agp.encoder(&self.stream.writer);
    }

    /// The returned bytes remain valid until the next encoder write or deinit.
    pub fn get_agp_stream(self: *Framebuffer) []const u8 {
        return self.stream.written();
    }

    /// Render the current command stream into this framebuffer's reusable pixels.
    pub fn render(self: *Framebuffer) ![]abi.Color {
        @memset(self.pixels, .black);
        var rasterizer = swrast.Rasterizer.init(.{
            .pixels = self.pixels.ptr,
            .width = self.width,
            .height = self.height,
            .stride = self.width,
        });
        var decoder = agp.BufferDecoder.init(self.get_agp_stream());
        const resolver: swrast.Rasterizer.Resolver = .{
            .ctx = self.context,
            .resolve_font_fn = Context.resolve_font,
            .resolve_framebuffer_fn = unsupported_framebuffer,
        };
        while (try decoder.next()) |cmd| rasterizer.execute(cmd, resolver);
        return self.pixels;
    }

    pub fn write_to(self: *Framebuffer, dir: std.fs.Dir, path: []const u8) !void {
        try gif.write_to_file_path(dir, path, self.width, self.height, try self.render());
    }

    fn unsupported_framebuffer(_: *anyopaque, _: agp.Framebuffer) ?swrast.Image {
        return null;
    }
};

pub fn create_context(allocator: std.mem.Allocator) Context {
    return .{ .allocator = allocator, .arena = .init(allocator) };
}

fn parse_abm(data: []const u8) error{InvalidImage}!agp.Bitmap {
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

const test_font_data = [_]u8{
    0xbe, 0x65, 0x37, 0xcb, // bitmap font magic
    8, 0, 0, 0, // line height
    1, 0, 0, 0, // one glyph
    'A', 0, 0, 6, // codepoint and advance
    0, 0, 0, 0, // glyph offset
    1, 1, 0, 0, 1, // one pixel glyph
};

test "context rejects empty dimensions and renders the current stream again" {
    var context = create_context(std.testing.allocator);
    defer context.deinit();
    try std.testing.expectError(error.InvalidSize, context.create_framebuffer(0, 3));
    try std.testing.expectError(error.InvalidSize, context.create_framebuffer(3, 0));
    var framebuffer = try context.create_framebuffer(4, 3);
    defer framebuffer.deinit();
    try std.testing.expectEqual(@as(usize, 0), framebuffer.get_agp_stream().len);
    try std.testing.expectEqual(abi.Color.black, (try framebuffer.render())[0]);

    const enc = framebuffer.encoder();
    try enc.clear(.red);
    try enc.set_pixel(1, 1, .blue);
    try enc.fill_rect(3, 0, 2, 2, .green); // right edge clips to one pixel
    const stream = framebuffer.get_agp_stream();
    try std.testing.expectEqual(@as(u8, @intFromEnum(agp.CommandByte.clear)), stream[0]);
    try std.testing.expectEqual(abi.Color.red.to_u8(), stream[1]);

    const first = try framebuffer.render();
    try std.testing.expectEqual(@as(usize, 12), first.len);
    try std.testing.expectEqual(abi.Color.blue, first[1 + 4]);
    try std.testing.expectEqual(abi.Color.green, first[3]);
    try std.testing.expectEqual(abi.Color.red, first[2 + 2 * 4]);

    first[1 + 4] = .white;
    try std.testing.expectEqual(abi.Color.blue, (try framebuffer.render())[1 + 4]);
    try enc.set_pixel(0, 2, .cyan);
    try std.testing.expectEqual(abi.Color.cyan, (try framebuffer.render())[2 * 4]);
}

test "font handles measure text and render glyphs" {
    var context = create_context(std.testing.allocator);
    defer context.deinit();
    var other = create_context(std.testing.allocator);
    defer other.deinit();
    var framebuffer = try context.create_framebuffer(16, 8);
    defer framebuffer.deinit();

    try std.testing.expectError(error.InvalidFont, context.load_font("bad font", .{}));
    var input = test_font_data;
    const font = try context.load_font(&input, .{});
    @memset(&input, 0);
    try std.testing.expectEqual(abi.Size{ .width = 12, .height = 8 }, try context.measure_text_size(font, "AA"));
    try std.testing.expectError(error.InvalidFont, other.measure_text_size(font, "A"));
    try framebuffer.encoder().draw_text(2, 3, font, .white, "A");
    const pixels = try framebuffer.render();
    try std.testing.expectEqual(abi.Color.white, pixels[2 + 3 * 16]);
    try std.testing.expectEqual(abi.Color.black, pixels[3 + 3 * 16]);
}

test "framebuffers share context resources but keep independent streams and pixels" {
    var context = create_context(std.testing.allocator);
    defer context.deinit();
    const font = try context.load_font(&test_font_data, .{});
    const image = [_]u8{ 0x74, 0x8b, 0x19, 0x48, 1, 0, 1, 0, 0, 0, 0, 0, 0x44 };
    const bitmap = try context.load_bitmap(&image);

    var first = try context.create_framebuffer(4, 2);
    defer first.deinit();
    var second = try context.create_framebuffer(4, 2);
    defer second.deinit();

    const a = first.encoder();
    try a.clear(.black);
    try a.draw_text(0, 0, font, .white, "A");
    try a.blit_bitmap(2, 1, bitmap);

    const b = second.encoder();
    try b.clear(.blue);
    try b.draw_text(1, 0, font, .cyan, "A");
    try b.blit_bitmap(3, 1, bitmap);

    try std.testing.expect(!std.mem.eql(u8, first.get_agp_stream(), second.get_agp_stream()));
    try std.testing.expectEqual(abi.Color.white, (try first.render())[0]);
    try std.testing.expectEqual(abi.Color.from_u8(0x44), first.pixels[2 + 4]);
    try std.testing.expectEqual(abi.Color.blue, (try second.render())[0]);
    try std.testing.expectEqual(abi.Color.cyan, second.pixels[1]);
    try std.testing.expectEqual(abi.Color.from_u8(0x44), second.pixels[3 + 4]);

    try a.set_pixel(0, 0, .red);
    try std.testing.expectEqual(abi.Color.red, (try first.render())[0]);
    try std.testing.expectEqual(abi.Color.blue, (try second.render())[0]);
}

test "ABM images validate headers and preserve transparency" {
    const image = [_]u8{
        0x74, 0x8b, 0x19, 0x48, // ABM magic
        2, 0, 1, 0, // two pixels
        1, 0, 5, 0x22, // transparency, palette size, key
        0x22, 0x44, // transparent pixel, visible pixel
    };
    var context = create_context(std.testing.allocator);
    defer context.deinit();
    var input = image;
    const bitmap = try context.load_bitmap(&input);
    try std.testing.expectEqual(@as(u16, 2), bitmap.width);
    try std.testing.expectEqual(@as(u16, 1), bitmap.height);
    try std.testing.expectEqual(@as(usize, 2), bitmap.stride);
    try std.testing.expect(bitmap.has_transparency);
    try std.testing.expect(@intFromPtr(&input[12]) != @intFromPtr(bitmap.pixels));
    @memset(input[12..], 0);

    var framebuffer = try context.create_framebuffer(4, 2);
    defer framebuffer.deinit();
    const enc = framebuffer.encoder();
    try enc.clear(.green);
    try enc.blit_bitmap(1, 1, bitmap);
    const pixels = try framebuffer.render();
    try std.testing.expectEqual(abi.Color.green, pixels[1 + 4]);
    try std.testing.expectEqual(abi.Color.from_u8(0x44), pixels[2 + 4]);

    try std.testing.expectError(error.InvalidImage, context.load_bitmap(image[0..11]));
    try std.testing.expectError(error.InvalidImage, context.load_bitmap(image[0..13]));
    var invalid = image;
    invalid[0] = 0;
    try std.testing.expectError(error.InvalidImage, context.load_bitmap(&invalid));
    invalid = image;
    invalid[4] = 0;
    try std.testing.expectError(error.InvalidImage, context.load_bitmap(&invalid));
    invalid = image;
    invalid[8] = 2;
    try std.testing.expectError(error.InvalidImage, context.load_bitmap(&invalid));
}

test "write_to writes a single GIF with the rendered size and palette" {
    var context = create_context(std.testing.allocator);
    defer context.deinit();
    var framebuffer = try context.create_framebuffer(2, 1);
    defer framebuffer.deinit();
    const enc = framebuffer.encoder();
    try enc.clear(.red);
    try enc.set_pixel(1, 0, .blue);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try framebuffer.write_to(tmp.dir, "image.gif");
    const bytes = try tmp.dir.readFileAlloc(std.testing.allocator, "image.gif", 4096);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings("GIF89a", bytes[0..6]);
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, bytes[6..8], .little));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes[8..10], .little));
    const red = abi.Color.red.to_rgb888();
    const offset = 13 + @as(usize, abi.Color.red.to_u8()) * 3;
    try std.testing.expectEqualSlices(u8, &.{ red.r, red.g, red.b }, bytes[offset..][0..3]);
    try std.testing.expectEqual(@as(u8, 0x3b), bytes[bytes.len - 1]);
    try std.testing.expectEqual(abi.Color.blue, (try framebuffer.render())[1]);
}
