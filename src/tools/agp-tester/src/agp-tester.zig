const std = @import("std");
const agp = @import("agp");
const agp_swrast = @import("agp-swrast");

const ColorIndex = agp.ColorIndex;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    try verify_encoder_decoder(arena.allocator());

    try render_example_image("swrast.pgm", "overdraw.pgm", "sequence.pgm");
}

fn render_example_image(path: []const u8, overdraw_path: ?[]const u8, sequence_path: ?[]const u8) !void {
    const width = 480;
    const height = 320;

    const black: ColorIndex = @enumFromInt(0);
    const red: ColorIndex = @enumFromInt(1);
    const green: ColorIndex = @enumFromInt(2);
    const blue: ColorIndex = @enumFromInt(3);
    const white: ColorIndex = @enumFromInt(4);

    if (false)
        _ = .{ black, red, green, blue, white };

    var cmd_buffer: [2048]u8 = undefined;

    // Collect draw commands:
    const cmd_stream: []const u8 = blk: {
        var fbs = std.io.fixedBufferStream(&cmd_buffer);
        var enc = agp.encoder(fbs.writer());
        {
            try enc.clear(black);

            try enc.draw_line(
                100,
                60,
                200,
                60,
                white,
            );

            try enc.draw_line(
                100,
                70,
                100,
                150,
                white,
            );

            try enc.draw_rect(
                110,
                70,
                123,
                35,
                red,
            );

            try enc.fill_rect(
                112,
                72,
                119,
                31,
                blue,
            );

            try enc.set_pixel(100, 55, red);
            try enc.set_pixel(102, 55, green);
            try enc.set_pixel(104, 55, blue);

            // Steep slope down
            try enc.draw_line(
                100,
                160,
                110,
                180,
                red,
            );

            // 45° slope down
            try enc.draw_line(
                120,
                160,
                140,
                180,
                red,
            );

            // Gentle slope down
            try enc.draw_line(
                150,
                160,
                180,
                180,
                red,
            );

            // Steep slope up
            try enc.draw_line(
                100,
                210,
                110,
                190,
                blue,
            );

            // 45° slope up
            try enc.draw_line(
                120,
                210,
                140,
                190,
                blue,
            );

            // Gentle slope up
            try enc.draw_line(
                150,
                210,
                180,
                190,
                blue,
            );
        }
        break :blk fbs.getWritten();
    };

    const Color = extern struct {
        r: u8,
        g: u8,
        b: u8,

        comptime {
            if (@sizeOf(@This()) != 3)
                @compileError("Color must be exactly 3 bytes!");
        }

        fn new(r: u8, g: u8, b: u8) @This() {
            return .{ .r = r, .g = g, .b = b };
        }
    };

    const Palette = std.enums.EnumArray(ColorIndex, Color);
    var palette = Palette.initFill(Color.new(0xFF, 0x00, 0x0FF));

    palette.set(black, Color.new(0x00, 0x00, 0x00));
    palette.set(red, Color.new(0xFF, 0x00, 0x00));
    palette.set(green, Color.new(0x00, 0xFF, 0x00));
    palette.set(blue, Color.new(0x00, 0x00, 0xFF));
    palette.set(white, Color.new(0xFF, 0xFF, 0xFF));

    var pixel_buffer: [width * height]Color = undefined;
    var attrs_buffer: [width * height]Color = undefined;
    @memset(&attrs_buffer, Color{ .r = 0, .g = 0, .b = 0 });

    // Render image:
    {
        const Backend = struct {
            palette: *Palette,
            framebuffer: []Color,
            attributes: []Color,
            next_color_id: *u8,

            width: usize,
            height: usize,
            stride: usize,

            pub fn create_cursor(back: @This()) agp_swrast.PixelCursor(.row_major) {
                return .{
                    .width = @intCast(back.width),
                    .height = @intCast(back.height),
                    .stride = back.stride,
                };
            }

            pub fn emit_pixels(back: @This(), cursor: agp_swrast.PixelCursor(.row_major), color_index: ColorIndex, count: u16) void {
                std.debug.assert(@as(usize, cursor.x) + count <= back.width);
                const color = back.palette.get(color_index);
                @memset(
                    back.framebuffer[cursor.offset..][0..count],
                    color,
                );
                for (back.attributes[cursor.offset..][0..count]) |*cnt| {
                    cnt.r +|= 1;
                    cnt.g = back.next_color_id.*;
                }
                std.debug.print("emit(Point({}, {}), color={}, count={}, index={})\n", .{
                    cursor.x,                  cursor.y,
                    @intFromEnum(color_index), count,
                    back.next_color_id.*,
                });
                back.next_color_id.* +%= 1;
            }
        };

        const Rasterizer = agp_swrast.Rasterizer(Backend, .{
            .pixel_layout = .row_major,
        });

        var next_color_id: u8 = 0;
        var rasterizer = Rasterizer.init(.{
            .palette = &palette,
            .framebuffer = &pixel_buffer,
            .attributes = &attrs_buffer,
            .next_color_id = &next_color_id,
            .width = width,
            .height = height,
            .stride = width,
        });

        var fbs = std.io.fixedBufferStream(cmd_stream);

        var decoder = agp.decoder(fbs.reader());

        while (try decoder.next()) |cmd| {
            rasterizer.execute(cmd);
        }
    }

    // Writeout image:
    {
        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writer().print("P6 {} {} 255\n", .{ width, height });
        try file.writeAll(std.mem.asBytes(&pixel_buffer));
    }
    // Writeout overdraw
    if (overdraw_path) |_overdraw_path| {
        const overdraw_gradient = [_]Color{
            Color.new(0xFF, 0x00, 0xFF), // this would mean clear has failed
            Color.new(0x00, 0x00, 0x00), // no draw (clear)
            Color.new(0xFF, 0xFF, 0xFF), // 0x overdraw
            Color.new(0x3c, 0xeb, 0x0c), // 1x overdraw
            Color.new(0x6e, 0xae, 0x09), // 2x overdraw
            Color.new(0x9e, 0x74, 0x06), // 3x overdraw
            Color.new(0xcf, 0x3a, 0x03), // 4x overdraw
            Color.new(0xff, 0x00, 0x00), // 5x overdraw
        };

        var overdraw_buffer = attrs_buffer;
        for (&overdraw_buffer) |*pix| {
            pix.* = overdraw_gradient[@min(pix.r, overdraw_gradient.len - 1)];
        }

        var file = try std.fs.cwd().createFile(_overdraw_path, .{});
        defer file.close();

        try file.writer().print("P6 {} {} 255\n", .{ width, height });
        try file.writeAll(std.mem.asBytes(&overdraw_buffer));
    }
    if (sequence_path) |_seq_path| {
        const seq_palette = [_]Color{
            Color.new(0xaa, 0x00, 0x55),
            Color.new(0xff, 0x55, 0x55),
            Color.new(0xaa, 0x55, 0x55),
            Color.new(0x55, 0xff, 0xaa),
            Color.new(0x00, 0x55, 0xff),
            Color.new(0x55, 0x55, 0x55),
            Color.new(0xff, 0x00, 0x55),
            Color.new(0xff, 0xff, 0x00),
            Color.new(0x55, 0x55, 0x00),
            Color.new(0xff, 0xaa, 0xaa),
            Color.new(0x00, 0xff, 0x00),
            Color.new(0x55, 0xff, 0xff),
            Color.new(0xff, 0x55, 0xff),
            Color.new(0x55, 0xaa, 0xff),
            Color.new(0xff, 0xaa, 0x55),
            Color.new(0x00, 0x00, 0xff),
            Color.new(0xaa, 0x00, 0xaa),
            Color.new(0x55, 0x00, 0x00),
            Color.new(0x00, 0xaa, 0xff),
            Color.new(0xff, 0x00, 0xff),
            Color.new(0x00, 0xaa, 0xaa),
            Color.new(0xaa, 0x00, 0x00),
            Color.new(0xff, 0x00, 0xaa),
            Color.new(0x55, 0xaa, 0x00),
            Color.new(0x55, 0x00, 0xaa),
            Color.new(0x55, 0xaa, 0xaa),
            Color.new(0xaa, 0xff, 0x00),
            Color.new(0x00, 0xff, 0x55),
            Color.new(0xaa, 0xaa, 0x00),
            Color.new(0x55, 0x00, 0x55),
            Color.new(0xaa, 0x55, 0xaa),
            Color.new(0xff, 0x00, 0x00),
            Color.new(0x55, 0x55, 0xff),
            Color.new(0xff, 0xaa, 0x00),
            Color.new(0xff, 0xff, 0x55),
            Color.new(0xaa, 0x00, 0xff),
            Color.new(0xff, 0x55, 0x00),
            Color.new(0xaa, 0xff, 0xaa),
            Color.new(0x00, 0x55, 0xaa),
            Color.new(0x00, 0x55, 0x55),
            Color.new(0xaa, 0xff, 0xff),
            Color.new(0x00, 0x55, 0x00),
            Color.new(0xaa, 0x55, 0x00),
            Color.new(0xaa, 0xaa, 0xff),
            Color.new(0x00, 0xaa, 0x00),
            Color.new(0x00, 0xff, 0xaa),
            Color.new(0xff, 0xff, 0xaa),
            Color.new(0xff, 0xaa, 0xff),
            Color.new(0xaa, 0xaa, 0xaa),
            Color.new(0x00, 0xff, 0xff),
            Color.new(0x55, 0xff, 0x55),
            Color.new(0x00, 0x00, 0xaa),
            Color.new(0xaa, 0xaa, 0x55),
            Color.new(0x55, 0xaa, 0x55),
            Color.new(0x00, 0xaa, 0x55),
            Color.new(0xaa, 0x55, 0xff),
            Color.new(0x55, 0xff, 0x00),
            Color.new(0xaa, 0xff, 0x55),
            Color.new(0xff, 0x55, 0xaa),
            Color.new(0x55, 0x55, 0xaa),
            Color.new(0x00, 0x00, 0x55),
            Color.new(0x55, 0x00, 0xff),
        };

        var seq_buffer = attrs_buffer;
        for (&seq_buffer) |*pix| {
            pix.* = if (pix.r <= 1)
                Color.new(0, 0, 0) // background or faulty pixels
            else
                seq_palette[pix.g % seq_palette.len];
        }

        var file = try std.fs.cwd().createFile(_seq_path, .{});
        defer file.close();

        try file.writer().print("P6 {} {} 255\n", .{ width, height });
        try file.writeAll(std.mem.asBytes(&seq_buffer));
    }
}

fn verify_encoder_decoder(allocator: std.mem.Allocator) !void {
    var rand_engine = std.rand.DefaultPrng.init(0x1337);
    const rng = rand_engine.random();

    const rand_buffer = try allocator.alloc(u8, 8192);
    rng.bytes(rand_buffer);

    const input_cmd_stream = try allocator.alloc(agp.Command, 1024);
    for (input_cmd_stream) |*item| {
        item.* = rand_cmd(rng, rand_buffer);
    }

    const encoded_cmd_stream = blk: {
        var stream = std.ArrayList(u8).init(allocator);
        defer stream.deinit();

        var encoder = agp.encoder(stream.writer());

        for (input_cmd_stream) |cmd| {
            try encoder.encode(cmd);
        }

        break :blk try stream.toOwnedSlice();
    };

    std.debug.print("encoded {} commands into {} bytes of data\n", .{
        input_cmd_stream.len,
        encoded_cmd_stream.len,
    });

    const output_cmd_stream = try allocator.alloc(agp.Command, input_cmd_stream.len);

    {
        var fbs = std.io.fixedBufferStream(encoded_cmd_stream);
        var decoder = agp.decoder(fbs.reader());
        for (output_cmd_stream) |*cmd| {
            cmd.* = if (try decoder.next()) |in|
                in
            else
                @panic("decoder yielded none for expected cmd!");
        }
        std.debug.assert(fbs.pos == encoded_cmd_stream.len);
        std.debug.assert(try decoder.next() == null);
    }

    for (input_cmd_stream, output_cmd_stream) |expected, actual| {
        try std.testing.expectEqual(expected, actual);
    }
}

fn rand_cmd(rng: std.rand.Random, buffer_range: []const u8) agp.Command {
    const cmd_id = rng.enumValue(agp.CommandByte);
    switch (cmd_id) {
        inline else => |tag| {
            const Cmd = agp.Command.type_map.get(tag);

            var cmd: Cmd = undefined;

            inline for (std.meta.fields(Cmd)) |fld| {
                @field(cmd, fld.name) = switch (fld.type) {
                    []const u8 => blk: {
                        const start = rng.intRangeLessThan(usize, 0, buffer_range.len);
                        const end = rng.intRangeLessThan(usize, start, buffer_range.len);
                        break :blk buffer_range[start..end];
                    },

                    agp.ColorIndex => @enumFromInt(rng.int(u8)),
                    agp.Font => @ptrFromInt(rng.int(usize)),
                    agp.Framebuffer => @ptrFromInt(rng.int(usize)),
                    agp.Bitmap => @ptrFromInt(rng.int(usize)),

                    else => rng.int(fld.type),
                };
            }

            return @unionInit(agp.Command, @tagName(tag), cmd);
        },
    }
}
