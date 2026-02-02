const std = @import("std");
const agp = @import("agp");
const agp_swrast = @import("agp-swrast");

const gif = @import("gif.zig");

const ColorIndex = agp.Color;

const mono_6_font: agp.Font = @ptrCast(@constCast(&@as(u8, 0)));
const sans_var_font: agp.Font = @ptrCast(@constCast(&@as(u8, 1)));

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // try verify_encoder_decoder(arena.allocator());

    try @import("widgets.zig").render_demo(
        arena.allocator(),
        "widgets.gif",
    );

    // try render_example_image(
    //     arena.allocator(),
    //     "swrast.gif",
    //     "overdraw.pgm",
    //     "sequence.pgm",
    //     "commands.gif",
    // );
}

fn render_example_image(
    allocator: std.mem.Allocator,
    path: []const u8,
    overdraw_path: ?[]const u8,
    sequence_path: ?[]const u8,
    commands_path: []const u8,
) !void {
    const width = 480;
    const height = 320;

    const black: ColorIndex = .black;
    const red: ColorIndex = .red;
    const green: ColorIndex = .green;
    const blue: ColorIndex = .blue;
    const white: ColorIndex = .white;

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

            try enc.draw_text(100, 230, mono_6_font, .purple, "Hello, World!");
            try enc.draw_text(100, 250, sans_var_font, .cyan, "Hello, World!");
        }
        break :blk fbs.getWritten();
    };

    const Color = agp.Color.RGB888;
    comptime {
        std.debug.assert(@sizeOf(Color) == 3);
        std.debug.assert(@offsetOf(Color, "r") == 0);
        std.debug.assert(@offsetOf(Color, "g") == 1);
        std.debug.assert(@offsetOf(Color, "b") == 2);
    }

    var pixel_buffer: [width * height]agp.Color = undefined;
    var attrs_buffer: [width * height]Color = undefined;
    @memset(&attrs_buffer, Color{ .r = 0, .g = 0, .b = 0 });

    var cmd_preview: [width * height]agp.Color = undefined;
    @memset(&cmd_preview, .from_gray(32));

    var gif_file = try std.fs.cwd().createFile(commands_path, .{});
    defer gif_file.close();

    var gif_img: gif.GIF_Encoder = try .start(gif_file.writer().any(), width, height, 3);

    // Render image:
    {
        const Backend = struct {
            const Cursor = agp_swrast.PixelCursor(.row_major);

            framebuffer: []agp.Color,
            attributes: []Color,
            command_preview: []agp.Color,
            gif_img: *gif.GIF_Encoder,

            width: usize,
            height: usize,
            stride: usize,

            cache_line_size: usize,

            next_color_id: u8 = 0,
            last_offset: usize = std.math.maxInt(usize),

            max_allowed_fwd_skip: u16 = 8, // report discontiuations when more than 8 pixels are skipped

            cache_misses: usize = 0,
            discontinuations: usize = 0,

            pub fn create_cursor(back: @This()) Cursor {
                return .{
                    .width = @intCast(back.width),
                    .height = @intCast(back.height),
                    .stride = back.stride,
                };
            }

            pub fn resolve_font(back: @This(), font: agp.Font) error{InvalidFont}!*const agp_swrast.fonts.FontInstance {
                _ = back;

                @setEvalBranchQuota(10_000);
                const mono_6 = comptime agp_swrast.fonts.FontInstance.load(@embedFile("mono-6.font"), .{}) catch unreachable;
                const sans_var = comptime agp_swrast.fonts.FontInstance.load(@embedFile("sans.font"), .{ .size = 12 }) catch unreachable;

                comptime std.debug.assert(mono_6 == .bitmap);
                comptime std.debug.assert(sans_var == .vector);

                if (font == mono_6_font) return &mono_6;
                if (font == sans_var_font) return &sans_var;

                return error.InvalidFont;
            }

            pub fn copy_pixels(back: @This(), cursor: Cursor, pixels: []const agp.Color) void {
                _ = back;
                _ = cursor;
                _ = pixels;
                @panic("ohno");
            }

            pub fn emit_pixels(back: *@This(), cursor: Cursor, color_index: ColorIndex, count: u16) void {
                std.debug.assert(count > 0);
                std.debug.assert(@as(usize, cursor.x) + count <= back.width);

                @memset(
                    back.framebuffer[cursor.offset..][0..count],
                    color_index,
                );
                for (back.attributes[cursor.offset..][0..count]) |*cnt| {
                    cnt.r +|= 1;
                    cnt.g = back.next_color_id;
                }

                // const back_color: agp.Color = .from_rgb(
                //     255 - color.r,
                //     255 - color.g,
                //     255 - color.b,
                // );

                // @memset(back.command_preview, back_color);
                @memset(
                    back.command_preview[cursor.offset..][0..count],
                    color_index,
                );
                back.gif_img.add_frame(back.command_preview) catch @panic("i/o error");

                std.debug.print("emit(Point({}, {}), color={}, count={}, index={})\n", .{
                    cursor.x,            cursor.y,
                    color_index.to_u8(), count,
                    back.next_color_id,
                });
                back.next_color_id +%= 1;

                const new_offset = cursor.offset + count;
                if (back.last_offset != std.math.maxInt(usize)) {
                    const delta: isize = @bitCast(new_offset -% back.last_offset);

                    const current_cache_line = @divTrunc(new_offset, back.cache_line_size);
                    const previous_cache_line = @divTrunc(back.last_offset, back.cache_line_size);

                    if (delta < 0 or delta > back.max_allowed_fwd_skip) {
                        std.debug.print("  discontiuation detected, jump by {} bytes from {} to {}\n", .{ delta, back.last_offset, new_offset });
                        back.discontinuations += 1;
                    }
                    if (current_cache_line != previous_cache_line and current_cache_line != (previous_cache_line + 1)) {
                        std.debug.print("  cache miss detected, switches from CL{} to CL{}\n", .{ previous_cache_line, current_cache_line });
                        back.cache_misses += 1;
                    }
                }

                back.last_offset = new_offset;
            }
        };

        const Rasterizer = agp_swrast.Rasterizer(.{
            .backend_type = *Backend,
            .framebuffer_type = null,
            .pixel_layout = .row_major,
        });

        var backend: Backend = .{
            .framebuffer = &pixel_buffer,
            .attributes = &attrs_buffer,
            .command_preview = &cmd_preview,
            .gif_img = &gif_img,
            .width = width,
            .height = height,
            .stride = width,

            // configurable:
            .cache_line_size = 8, // RP2350 XIP Cache
        };
        var rasterizer = Rasterizer.init(&backend);

        var fbs = std.io.fixedBufferStream(cmd_stream);

        var decoder = agp.decoder(allocator, fbs.reader());
        defer decoder.deinit();

        while (try decoder.next()) |cmd| {
            try rasterizer.execute(cmd);
        }

        std.debug.print("cache misses:     {}\n", .{backend.cache_misses});
        std.debug.print("discontinuations: {}\n", .{backend.discontinuations});
    }

    try gif_img.end();

    // Writeout image:
    try gif.write_to_file_path(std.fs.cwd(), path, width, height, &pixel_buffer);

    // Writeout overdraw
    if (overdraw_path) |_overdraw_path| {
        const overdraw_gradient = [_]Color{
            .{ .r = 0xFF, .g = 0x00, .b = 0xFF }, // this would mean clear has failed
            .{ .r = 0x00, .g = 0x00, .b = 0x00 }, // no draw (clear)
            .{ .r = 0xFF, .g = 0xFF, .b = 0xFF }, // 0x overdraw
            .{ .r = 0x3c, .g = 0xeb, .b = 0x0c }, // 1x overdraw
            .{ .r = 0x6e, .g = 0xae, .b = 0x09 }, // 2x overdraw
            .{ .r = 0x9e, .g = 0x74, .b = 0x06 }, // 3x overdraw
            .{ .r = 0xcf, .g = 0x3a, .b = 0x03 }, // 4x overdraw
            .{ .r = 0xff, .g = 0x00, .b = 0x00 }, // 5x overdraw
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
            .{ .r = 0xaa, .g = 0x00, .b = 0x55 },
            .{ .r = 0xff, .g = 0x55, .b = 0x55 },
            .{ .r = 0xaa, .g = 0x55, .b = 0x55 },
            .{ .r = 0x55, .g = 0xff, .b = 0xaa },
            .{ .r = 0x00, .g = 0x55, .b = 0xff },
            .{ .r = 0x55, .g = 0x55, .b = 0x55 },
            .{ .r = 0xff, .g = 0x00, .b = 0x55 },
            .{ .r = 0xff, .g = 0xff, .b = 0x00 },
            .{ .r = 0x55, .g = 0x55, .b = 0x00 },
            .{ .r = 0xff, .g = 0xaa, .b = 0xaa },
            .{ .r = 0x00, .g = 0xff, .b = 0x00 },
            .{ .r = 0x55, .g = 0xff, .b = 0xff },
            .{ .r = 0xff, .g = 0x55, .b = 0xff },
            .{ .r = 0x55, .g = 0xaa, .b = 0xff },
            .{ .r = 0xff, .g = 0xaa, .b = 0x55 },
            .{ .r = 0x00, .g = 0x00, .b = 0xff },
            .{ .r = 0xaa, .g = 0x00, .b = 0xaa },
            .{ .r = 0x55, .g = 0x00, .b = 0x00 },
            .{ .r = 0x00, .g = 0xaa, .b = 0xff },
            .{ .r = 0xff, .g = 0x00, .b = 0xff },
            .{ .r = 0x00, .g = 0xaa, .b = 0xaa },
            .{ .r = 0xaa, .g = 0x00, .b = 0x00 },
            .{ .r = 0xff, .g = 0x00, .b = 0xaa },
            .{ .r = 0x55, .g = 0xaa, .b = 0x00 },
            .{ .r = 0x55, .g = 0x00, .b = 0xaa },
            .{ .r = 0x55, .g = 0xaa, .b = 0xaa },
            .{ .r = 0xaa, .g = 0xff, .b = 0x00 },
            .{ .r = 0x00, .g = 0xff, .b = 0x55 },
            .{ .r = 0xaa, .g = 0xaa, .b = 0x00 },
            .{ .r = 0x55, .g = 0x00, .b = 0x55 },
            .{ .r = 0xaa, .g = 0x55, .b = 0xaa },
            .{ .r = 0xff, .g = 0x00, .b = 0x00 },
            .{ .r = 0x55, .g = 0x55, .b = 0xff },
            .{ .r = 0xff, .g = 0xaa, .b = 0x00 },
            .{ .r = 0xff, .g = 0xff, .b = 0x55 },
            .{ .r = 0xaa, .g = 0x00, .b = 0xff },
            .{ .r = 0xff, .g = 0x55, .b = 0x00 },
            .{ .r = 0xaa, .g = 0xff, .b = 0xaa },
            .{ .r = 0x00, .g = 0x55, .b = 0xaa },
            .{ .r = 0x00, .g = 0x55, .b = 0x55 },
            .{ .r = 0xaa, .g = 0xff, .b = 0xff },
            .{ .r = 0x00, .g = 0x55, .b = 0x00 },
            .{ .r = 0xaa, .g = 0x55, .b = 0x00 },
            .{ .r = 0xaa, .g = 0xaa, .b = 0xff },
            .{ .r = 0x00, .g = 0xaa, .b = 0x00 },
            .{ .r = 0x00, .g = 0xff, .b = 0xaa },
            .{ .r = 0xff, .g = 0xff, .b = 0xaa },
            .{ .r = 0xff, .g = 0xaa, .b = 0xff },
            .{ .r = 0xaa, .g = 0xaa, .b = 0xaa },
            .{ .r = 0x00, .g = 0xff, .b = 0xff },
            .{ .r = 0x55, .g = 0xff, .b = 0x55 },
            .{ .r = 0x00, .g = 0x00, .b = 0xaa },
            .{ .r = 0xaa, .g = 0xaa, .b = 0x55 },
            .{ .r = 0x55, .g = 0xaa, .b = 0x55 },
            .{ .r = 0x00, .g = 0xaa, .b = 0x55 },
            .{ .r = 0xaa, .g = 0x55, .b = 0xff },
            .{ .r = 0x55, .g = 0xff, .b = 0x00 },
            .{ .r = 0xaa, .g = 0xff, .b = 0x55 },
            .{ .r = 0xff, .g = 0x55, .b = 0xaa },
            .{ .r = 0x55, .g = 0x55, .b = 0xaa },
            .{ .r = 0x00, .g = 0x00, .b = 0x55 },
            .{ .r = 0x55, .g = 0x00, .b = 0xff },
        };

        var seq_buffer = attrs_buffer;
        for (&seq_buffer) |*pix| {
            pix.* = if (pix.r <= 1)
                .{ .r = 0, .g = 0, .b = 0 } // background or faulty pixels
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
    var rand_engine: std.Random.DefaultPrng = .init(0x1337);
    const rng = rand_engine.random();

    const rand_buffer = try allocator.alloc(u8, 8192);
    rng.bytes(rand_buffer);

    const input_cmd_stream = try allocator.alloc(agp.Command, 1024);
    for (input_cmd_stream) |*item| {
        item.* = rand_cmd(rng, rand_buffer);
    }

    const encoded_cmd_stream = blk: {
        var stream: std.Io.Writer.Allocating = .init(allocator);
        defer stream.deinit();

        var encoder = agp.encoder(&stream.writer);

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
        var decoder = agp.decoder(allocator, fbs.reader());
        defer decoder.deinit();

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

fn rand_cmd(rng: std.Random, buffer_range: []const u8) agp.Command {
    const cmd_id = rng.enumValue(agp.CommandByte);
    switch (cmd_id) {
        inline else => |tag| {
            const Cmd = agp.Command.type_map(tag);

            var cmd: Cmd = undefined;

            inline for (std.meta.fields(Cmd)) |fld| {
                @field(cmd, fld.name) = switch (fld.type) {
                    []const u8 => blk: {
                        const start = rng.intRangeLessThan(usize, 0, buffer_range.len);
                        const end = rng.intRangeLessThan(usize, start, buffer_range.len);
                        break :blk buffer_range[start..end];
                    },

                    agp.Color => @bitCast(rng.int(u8)),
                    agp.Font => @ptrFromInt(rng.int(usize)),
                    agp.Framebuffer => @ptrFromInt(rng.int(usize) *% 16),
                    *const agp.Bitmap => @ptrFromInt(rng.int(usize) *% 16),

                    u8, u16, i16 => rng.int(fld.type),

                    else => @compileError("unsupported type: " ++ @typeName(fld.type)),
                };
            }

            return @unionInit(agp.Command, @tagName(tag), cmd);
        },
    }
}
