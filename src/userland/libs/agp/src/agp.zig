//!
//! Ashet Graphics Protocol
//!

const std = @import("std");
const ashet = @import("ashet-abi");

pub const text_format = @import("text_format.zig");

pub const ColorIndex = ashet.ColorIndex;
pub const Framebuffer = ashet.Framebuffer;
pub const Font = ashet.Font;
pub const Bitmap = *opaque {};

pub const CommandByte = enum(u8) {
    clear = 0x00,
    set_clip_rect = 0x01,
    set_pixel = 0x02,
    draw_line = 0x03,
    draw_rect = 0x04,
    fill_rect = 0x05,
    draw_text = 0x06,
    blit_bitmap = 0x07,
    blit_framebuffer = 0x08,
    update_color = 0x09,
    blit_partial_bitmap = 0x0A,
    blit_partial_framebuffer = 0x0B,
};

pub fn encoder(enc: anytype) Encoder(@TypeOf(enc)) {
    return .{ .writer = enc };
}

pub fn decoder(dec: anytype) Decoder(@TypeOf(dec)) {
    return .{ .reader = dec };
}

pub fn Encoder(Writer: type) type {
    return struct {
        const Enc = @This();

        const EncError = Writer.Error || error{EndOfStream};

        writer: Writer,

        pub fn encode(enc: Enc, cmd: Command) (EncError || error{Overflow})!void {
            switch (cmd) {
                .clear => |data| try enc.clear(data.color),

                .set_clip_rect => |data| try enc.set_clip_rect(
                    data.x,
                    data.y,
                    data.width,
                    data.height,
                ),
                .set_pixel => |data| try enc.set_pixel(
                    data.x,
                    data.y,
                    data.color,
                ),
                .draw_line => |data| try enc.draw_line(
                    data.x1,
                    data.y1,
                    data.x2,
                    data.y2,
                    data.color,
                ),
                .draw_rect => |data| try enc.draw_rect(
                    data.x,
                    data.y,
                    data.width,
                    data.height,
                    data.color,
                ),
                .fill_rect => |data| try enc.fill_rect(
                    data.x,
                    data.y,
                    data.width,
                    data.height,
                    data.color,
                ),
                .draw_text => |data| try enc.draw_text(
                    data.x,
                    data.y,
                    data.font,
                    data.color,
                    data.text,
                ),
                .blit_bitmap => |data| try enc.blit_bitmap(
                    data.x,
                    data.y,
                    data.bitmap,
                ),
                .blit_framebuffer => |data| try enc.blit_framebuffer(
                    data.x,
                    data.y,
                    data.framebuffer,
                ),
                .update_color => |data| try enc.update_color(
                    data.index,
                    data.r,
                    data.g,
                    data.b,
                ),
                .blit_partial_bitmap => |data| try enc.blit_partial_bitmap(
                    data.x,
                    data.y,
                    data.width,
                    data.height,
                    data.src_x,
                    data.src_y,
                    data.bitmap,
                ),
                .blit_partial_framebuffer => |data| try enc.blit_partial_framebuffer(
                    data.x,
                    data.y,
                    data.width,
                    data.height,
                    data.src_x,
                    data.src_y,
                    data.framebuffer,
                ),
            }
        }

        pub fn clear(
            enc: Enc,
            color: ColorIndex,
        ) EncError!void {
            try enc.enc_cmd(.clear);
            try enc.enc_color(color);
        }

        pub fn set_clip_rect(
            enc: Enc,
            x: i16,
            y: i16,
            width: u16,
            height: u16,
        ) EncError!void {
            try enc.enc_cmd(.set_clip_rect);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_size(width);
            try enc.enc_size(height);
        }

        pub fn set_pixel(
            enc: Enc,
            x: i16,
            y: i16,
            color: ColorIndex,
        ) EncError!void {
            try enc.enc_cmd(.set_pixel);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_color(color);
        }

        pub fn draw_line(
            enc: Enc,
            x1: i16,
            y1: i16,
            x2: i16,
            y2: i16,
            color: ColorIndex,
        ) EncError!void {
            try enc.enc_cmd(.draw_line);
            try enc.enc_coord(x1);
            try enc.enc_coord(y1);
            try enc.enc_coord(x2);
            try enc.enc_coord(y2);
            try enc.enc_color(color);
        }

        pub fn draw_rect(
            enc: Enc,
            x: i16,
            y: i16,
            width: u16,
            height: u16,
            color: ColorIndex,
        ) EncError!void {
            try enc.enc_cmd(.draw_rect);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_size(width);
            try enc.enc_size(height);
            try enc.enc_color(color);
        }

        pub fn fill_rect(
            enc: Enc,
            x: i16,
            y: i16,
            width: u16,
            height: u16,
            color: ColorIndex,
        ) EncError!void {
            try enc.enc_cmd(.fill_rect);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_size(width);
            try enc.enc_size(height);
            try enc.enc_color(color);
        }

        pub fn draw_text(
            enc: Enc,
            x: i16,
            y: i16,
            font: Font,
            color: ColorIndex,
            text: []const u8,
        ) (EncError || error{Overflow})!void {
            const len = std.math.cast(u16, text.len) orelse return error.Overflow;
            try enc.enc_cmd(.draw_text);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_handle(Font, font);
            try enc.enc_color(color);
            try enc.enc_ptr([*]const u8, text.ptr);
            try enc.enc_int(u16, len);
        }

        pub fn blit_bitmap(
            enc: Enc,
            x: i16,
            y: i16,
            bitmap: Bitmap,
        ) EncError!void {
            try enc.enc_cmd(.blit_bitmap);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_handle(Bitmap, bitmap);
        }

        pub fn blit_framebuffer(
            enc: Enc,
            x: i16,
            y: i16,
            framebuffer: Framebuffer,
        ) EncError!void {
            try enc.enc_cmd(.blit_framebuffer);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_handle(Framebuffer, framebuffer);
        }

        pub fn update_color(
            enc: Enc,
            index: ColorIndex,
            r: u8,
            g: u8,
            b: u8,
        ) EncError!void {
            try enc.enc_cmd(.update_color);
            try enc.enc_color(index);
            try enc.enc_int(u8, r);
            try enc.enc_int(u8, g);
            try enc.enc_int(u8, b);
        }

        pub fn blit_partial_bitmap(
            enc: Enc,
            x: i16,
            y: i16,
            width: u16,
            height: u16,
            src_x: i16,
            src_y: i16,
            bitmap: Bitmap,
        ) EncError!void {
            try enc.enc_cmd(.blit_partial_bitmap);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_size(width);
            try enc.enc_size(height);
            try enc.enc_coord(src_x);
            try enc.enc_coord(src_y);
            try enc.enc_handle(Bitmap, bitmap);
        }

        pub fn blit_partial_framebuffer(
            enc: Enc,
            x: i16,
            y: i16,
            width: u16,
            height: u16,
            src_x: i16,
            src_y: i16,
            framebuffer: Framebuffer,
        ) EncError!void {
            try enc.enc_cmd(.blit_partial_framebuffer);
            try enc.enc_coord(x);
            try enc.enc_coord(y);
            try enc.enc_size(width);
            try enc.enc_size(height);
            try enc.enc_coord(src_x);
            try enc.enc_coord(src_y);
            try enc.enc_handle(Framebuffer, framebuffer);
        }

        fn enc_coord(enc: Enc, value: i16) !void {
            try enc.writer.writeInt(i16, value, .little);
        }

        fn enc_size(enc: Enc, value: u16) !void {
            try enc.writer.writeInt(u16, value, .little);
        }

        fn enc_color(enc: Enc, value: ColorIndex) !void {
            try enc.writer.writeInt(u8, @intFromEnum(value), .little);
        }

        fn enc_handle(enc: Enc, Handle: type, value: Handle) !void {
            try enc.writer.writeInt(usize, @intFromPtr(value), .little);
        }

        fn enc_int(enc: Enc, Int: type, value: Int) !void {
            try enc.writer.writeInt(Int, value, .little);
        }

        fn enc_ptr(enc: Enc, Pointer: type, value: Pointer) !void {
            try enc.writer.writeInt(usize, @intFromPtr(value), .little);
        }

        fn enc_cmd(enc: Enc, cmd: CommandByte) !void {
            try enc.writer.writeInt(u8, @intFromEnum(cmd), .little);
        }
    };
}

pub fn Decoder(Reader: type) type {
    return struct {
        const Dec = @This();

        reader: Reader,

        pub const NextError = error{ InvalidCommand, EndOfStream } || Reader.Error;

        pub fn next(dec: Dec) NextError!?Command {
            const cmd_byte = dec.reader.readByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => |e| return e,
            };

            const cmd = std.meta.intToEnum(CommandByte, cmd_byte) catch return error.InvalidCommand;

            return switch (cmd) {
                .clear => .{
                    .clear = .{
                        .color = try dec.fetch_color(),
                    },
                },
                .set_clip_rect => .{
                    .set_clip_rect = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .width = try dec.fetch_size(),
                        .height = try dec.fetch_size(),
                    },
                },
                .set_pixel => .{
                    .set_pixel = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .color = try dec.fetch_color(),
                    },
                },
                .draw_line => .{
                    .draw_line = .{
                        .x1 = try dec.fetch_coord(),
                        .y1 = try dec.fetch_coord(),
                        .x2 = try dec.fetch_coord(),
                        .y2 = try dec.fetch_coord(),
                        .color = try dec.fetch_color(),
                    },
                },
                .draw_rect => .{
                    .draw_rect = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .width = try dec.fetch_size(),
                        .height = try dec.fetch_size(),
                        .color = try dec.fetch_color(),
                    },
                },
                .fill_rect => .{
                    .fill_rect = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .width = try dec.fetch_size(),
                        .height = try dec.fetch_size(),
                        .color = try dec.fetch_color(),
                    },
                },
                .draw_text => .{
                    .draw_text = blk: {
                        const x = try dec.fetch_coord();
                        const y = try dec.fetch_coord();
                        const font = try dec.fetch_handle(Font);
                        const color = try dec.fetch_color();
                        const text_ptr = try dec.fetch_ptr([*]const u8);
                        const text_len = try dec.fetch_int(u16);
                        break :blk .{
                            .x = x,
                            .y = y,
                            .font = font,
                            .color = color,
                            .text = text_ptr[0..text_len],
                        };
                    },
                },
                .blit_bitmap => .{
                    .blit_bitmap = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .bitmap = try dec.fetch_handle(Bitmap),
                    },
                },
                .blit_framebuffer => .{
                    .blit_framebuffer = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .framebuffer = try dec.fetch_handle(Framebuffer),
                    },
                },
                .update_color => .{
                    .update_color = .{
                        .index = try dec.fetch_color(),
                        .r = try dec.fetch_int(u8),
                        .g = try dec.fetch_int(u8),
                        .b = try dec.fetch_int(u8),
                    },
                },
                .blit_partial_bitmap => .{
                    .blit_partial_bitmap = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .width = try dec.fetch_size(),
                        .height = try dec.fetch_size(),
                        .src_x = try dec.fetch_coord(),
                        .src_y = try dec.fetch_coord(),
                        .bitmap = try dec.fetch_handle(Bitmap),
                    },
                },
                .blit_partial_framebuffer => .{
                    .blit_partial_framebuffer = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .width = try dec.fetch_size(),
                        .height = try dec.fetch_size(),
                        .src_x = try dec.fetch_coord(),
                        .src_y = try dec.fetch_coord(),
                        .framebuffer = try dec.fetch_handle(Framebuffer),
                    },
                },
            };
        }

        fn fetch_coord(dec: Dec) !i16 {
            return try dec.reader.readInt(i16, .little);
        }

        fn fetch_size(dec: Dec) !u16 {
            return try dec.reader.readInt(u16, .little);
        }

        fn fetch_color(dec: Dec) !ColorIndex {
            return @enumFromInt(
                try dec.reader.readInt(u8, .little),
            );
        }

        fn fetch_handle(dec: Dec, Handle: type) !Handle {
            return @ptrFromInt(
                try dec.reader.readInt(usize, .little),
            );
        }

        fn fetch_int(dec: Dec, Int: type) !Int {
            return try dec.reader.readInt(Int, .little);
        }

        fn fetch_ptr(dec: Dec, Pointer: type) !Pointer {
            return @ptrFromInt(
                @as(usize, @intCast(try dec.reader.readInt(usize, .little))),
            );
        }
    };
}

pub const Command = union(CommandByte) {
    pub const type_map = std.enums.EnumArray(CommandByte, type).init(.{
        .clear = Clear,
        .set_clip_rect = SetClipRect,
        .set_pixel = SetPixel,
        .draw_line = DrawLine,
        .draw_rect = DrawRect,
        .fill_rect = FillRect,
        .draw_text = DrawText,
        .blit_bitmap = BlitBitmap,
        .blit_framebuffer = BlitFramebuffer,
        .update_color = UpdateColor,
        .blit_partial_bitmap = BlitPartialBitmap,
        .blit_partial_framebuffer = BlitPartialFramebuffer,
    });

    clear: Clear,
    set_clip_rect: SetClipRect,
    set_pixel: SetPixel,
    draw_line: DrawLine,
    draw_rect: DrawRect,
    fill_rect: FillRect,
    draw_text: DrawText,
    blit_bitmap: BlitBitmap,
    blit_framebuffer: BlitFramebuffer,
    update_color: UpdateColor,
    blit_partial_bitmap: BlitPartialBitmap,
    blit_partial_framebuffer: BlitPartialFramebuffer,

    pub const Clear = struct {
        color: ColorIndex,
    };

    pub const SetClipRect = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
    };

    pub const SetPixel = struct {
        x: i16,
        y: i16,
        color: ColorIndex,
    };

    pub const DrawLine = struct {
        x1: i16,
        y1: i16,
        x2: i16,
        y2: i16,
        color: ColorIndex,
    };

    pub const DrawRect = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        color: ColorIndex,
    };

    pub const FillRect = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        color: ColorIndex,
    };

    pub const DrawText = struct {
        x: i16,
        y: i16,
        font: Font,
        color: ColorIndex,
        text: []const u8,
    };

    pub const BlitBitmap = struct {
        x: i16,
        y: i16,
        bitmap: Bitmap,
    };

    pub const BlitFramebuffer = struct {
        x: i16,
        y: i16,
        framebuffer: Framebuffer,
    };

    pub const UpdateColor = struct {
        index: ColorIndex,
        r: u8,
        g: u8,
        b: u8,
    };

    pub const BlitPartialBitmap = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        src_x: i16,
        src_y: i16,
        bitmap: Bitmap,
    };

    pub const BlitPartialFramebuffer = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        src_x: i16,
        src_y: i16,
        framebuffer: Framebuffer,
    };
};
