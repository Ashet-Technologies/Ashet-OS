const std = @import("std");
const agp = @import("agp.zig");

const cmd_name = std.StaticStringMap(agp.CommandByte).initComptime(.{
    .{ "clear", .clear },
    .{ "set-clip-rect", .set_clip_rect },
    .{ "set-pixel", .set_pixel },
    .{ "draw-line", .draw_line },
    .{ "draw-rect", .draw_rect },
    .{ "fill-rect", .fill_rect },
    .{ "draw-text", .draw_text },
    .{ "blit-bmp", .blit_bitmap },
    .{ "blit-fb", .blit_framebuffer },
    .{ "update-color", .update_color },
    // .{ "blit-bmp", .blit_partial_bitmap }, // these two are special-cased
    // .{ "blit-fb", .blit_partial_framebuffer }, // these two are special-cased
});

pub fn parser(reader: anytype) Parser(@TypeOf(reader)) {
    return .{ .reader = reader };
}

pub fn Parser(comptime Reader: type) type {
    return struct {
        const Pars = @This();

        reader: Reader,

        pub fn decode(pars: Pars) !?agp.Command {
            var line_buffer: [512]u8 = undefined;

            const line = blk: {
                var fbs = std.io.fixedBufferStream(&line_buffer);

                try pars.reader.readInto(fbs.writer());

                break :blk fbs.getWritten();
            };

            _ = line;
        }
    };
}
