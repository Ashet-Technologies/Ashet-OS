//!
//! Ashet Graphics Protocol
//!

const std = @import("std");
const ashet = @import("ashet-abi");

pub const text_format = @import("text_format.zig");

pub const Color = ashet.Color;
pub const Framebuffer = ashet.Framebuffer;
pub const Font = ashet.Font;

/// A bitmap is a typical row-major organized data structure
/// that stores pixel data in host memory.
///
/// The memory it points to is read-only to allow static bitmaps,
/// but it isn't required to be never mutated.
pub const Bitmap = extern struct {
    pixels: [*]const Color, // TODO: can we somehow get align(4) back?
    width: u16,
    height: u16,
    stride: usize,
    transparency_key: Color,
    has_transparency: bool,
};

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
    blit_partial_bitmap = 0x09,
    blit_partial_framebuffer = 0x0A,
};

pub fn encoder(enc: *std.Io.Writer) Encoder {
    return .{ .writer = enc };
}

pub fn streamDecoder(allocator: std.mem.Allocator, dec: anytype) StreamDecoder(@TypeOf(dec)) {
    return .init(allocator, dec);
}

pub const Encoder = struct {
    const EncError = std.Io.Writer.Error || error{EndOfStream};

    writer: *std.Io.Writer,

    pub fn encode(enc: Encoder, cmd: Command) (EncError || error{Overflow})!void {
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
                &data.bitmap,
            ),
            .blit_framebuffer => |data| try enc.blit_framebuffer(
                data.x,
                data.y,
                data.framebuffer,
            ),
            .blit_partial_bitmap => |data| try enc.blit_partial_bitmap(
                data.x,
                data.y,
                data.width,
                data.height,
                data.src_x,
                data.src_y,
                &data.bitmap,
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
        enc: Encoder,
        color: Color,
    ) EncError!void {
        try enc.enc_cmd(.clear);
        try enc.enc_color(color);
    }

    pub fn set_clip_rect(
        enc: Encoder,
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
        enc: Encoder,
        x: i16,
        y: i16,
        color: Color,
    ) EncError!void {
        try enc.enc_cmd(.set_pixel);
        try enc.enc_coord(x);
        try enc.enc_coord(y);
        try enc.enc_color(color);
    }

    pub fn draw_line(
        enc: Encoder,
        x1: i16,
        y1: i16,
        x2: i16,
        y2: i16,
        color: Color,
    ) EncError!void {
        try enc.enc_cmd(.draw_line);
        try enc.enc_coord(x1);
        try enc.enc_coord(y1);
        try enc.enc_coord(x2);
        try enc.enc_coord(y2);
        try enc.enc_color(color);
    }

    pub fn draw_rect(
        enc: Encoder,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        color: Color,
    ) EncError!void {
        try enc.enc_cmd(.draw_rect);
        try enc.enc_coord(x);
        try enc.enc_coord(y);
        try enc.enc_size(width);
        try enc.enc_size(height);
        try enc.enc_color(color);
    }

    pub fn fill_rect(
        enc: Encoder,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        color: Color,
    ) EncError!void {
        try enc.enc_cmd(.fill_rect);
        try enc.enc_coord(x);
        try enc.enc_coord(y);
        try enc.enc_size(width);
        try enc.enc_size(height);
        try enc.enc_color(color);
    }

    pub fn draw_text(
        enc: Encoder,
        x: i16,
        y: i16,
        font: Font,
        color: Color,
        text: []const u8,
    ) (EncError || error{Overflow})!void {
        const len = std.math.cast(u16, text.len) orelse return error.Overflow;

        // Skip encoding if nothing would be drawn anyways
        if (len == 0)
            return;

        try enc.enc_cmd(.draw_text);
        try enc.enc_coord(x);
        try enc.enc_coord(y);
        try enc.enc_handle(Font, font);
        try enc.enc_color(color);
        try enc.enc_int(u16, len);
        try enc.writer.writeAll(text);
    }

    pub fn blit_bitmap(
        enc: Encoder,
        x: i16,
        y: i16,
        bitmap: *const Bitmap,
    ) EncError!void {

        // Skip encoding if nothing would be drawn anyways
        if (bitmap.width == 0 or bitmap.height == 0)
            return;

        try enc.enc_cmd(.blit_bitmap);
        try enc.enc_coord(x);
        try enc.enc_coord(y);
        try enc.enc_bitmap(bitmap);
    }

    pub fn blit_framebuffer(
        enc: Encoder,
        x: i16,
        y: i16,
        framebuffer: Framebuffer,
    ) EncError!void {
        try enc.enc_cmd(.blit_framebuffer);
        try enc.enc_coord(x);
        try enc.enc_coord(y);
        try enc.enc_handle(Framebuffer, framebuffer);
    }

    pub fn blit_partial_bitmap(
        enc: Encoder,
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        src_x: i16,
        src_y: i16,
        bitmap: *const Bitmap,
    ) EncError!void {
        // Skip encoding if nothing would be drawn anyways
        if (bitmap.width == 0 or bitmap.height == 0)
            return;
        if (width == 0 or height == 0)
            return;

        try enc.enc_cmd(.blit_partial_bitmap);
        try enc.enc_coord(x);
        try enc.enc_coord(y);
        try enc.enc_size(width);
        try enc.enc_size(height);
        try enc.enc_coord(src_x);
        try enc.enc_coord(src_y);
        try enc.enc_bitmap(bitmap);
    }

    pub fn blit_partial_framebuffer(
        enc: Encoder,
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

    fn enc_coord(enc: Encoder, value: i16) !void {
        try enc.writer.writeInt(i16, value, .little);
    }

    fn enc_size(enc: Encoder, value: u16) !void {
        try enc.writer.writeInt(u16, value, .little);
    }

    fn enc_color(enc: Encoder, value: Color) !void {
        try enc.writer.writeInt(u8, @bitCast(value), .little);
    }

    fn enc_handle(enc: Encoder, Handle: type, value: Handle) !void {
        try enc.writer.writeInt(usize, @intFromPtr(value), .little);
    }

    fn enc_int(enc: Encoder, Int: type, value: Int) !void {
        try enc.writer.writeInt(Int, value, .little);
    }

    fn enc_ptr(enc: Encoder, Pointer: type, value: Pointer) !void {
        try enc.writer.writeInt(usize, @intFromPtr(value), .little);
    }

    fn enc_cmd(enc: Encoder, cmd: CommandByte) !void {
        try enc.writer.writeInt(u8, @intFromEnum(cmd), .little);
    }

    fn enc_bitmap(enc: Encoder, bmp: *const Bitmap) !void {
        std.debug.assert(bmp.width > 0 and bmp.height > 0);

        try enc.enc_int(u8, if (bmp.has_transparency) @as(u8, 1) else 0);

        if (bmp.has_transparency) {
            try enc.enc_color(bmp.transparency_key);
        }

        try enc.enc_size(bmp.width);
        try enc.enc_size(bmp.height);
        try enc.enc_int(usize, bmp.stride);

        try enc.writer.writeAll(std.mem.sliceAsBytes(bmp.pixels[0 .. bmp.height * bmp.stride]));
    }
};

// TODO: Refactor to use the std.Io.Reader
pub fn StreamDecoder(Reader: type) type {
    return struct {
        const Dec = @This();

        reader: Reader,
        heap: std.array_list.AlignedManaged(u8, .@"16"),

        pub const NextError = error{ InvalidCommand, EndOfStream, OutOfMemory } || Reader.Error;

        pub fn init(allocator: std.mem.Allocator, reader: Reader) Dec {
            return .{
                .heap = .init(allocator),
                .reader = reader,
            };
        }

        pub fn deinit(dec: *Dec) void {
            dec.heap.deinit();
            dec.* = undefined;
        }

        pub fn next(dec: *Dec) NextError!?Command {
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
                        const text_len = try dec.fetch_int(u16);

                        try dec.heap.resize(text_len +| 1);
                        try dec.reader.readNoEof(dec.heap.items[0..text_len]);
                        dec.heap.items[text_len] = 0;

                        break :blk .{
                            .x = x,
                            .y = y,
                            .font = font,
                            .color = color,
                            .text = dec.heap.items[0..text_len :0],
                        };
                    },
                },
                .blit_bitmap => .{ .blit_bitmap = .{
                    .x = try dec.fetch_coord(),
                    .y = try dec.fetch_coord(),
                    .bitmap = try dec.fetch_bitmap(),
                } },
                .blit_framebuffer => .{
                    .blit_framebuffer = .{
                        .x = try dec.fetch_coord(),
                        .y = try dec.fetch_coord(),
                        .framebuffer = try dec.fetch_handle(Framebuffer),
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
                        .bitmap = try dec.fetch_bitmap(),
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

        /// NOTE: Returned bitmap is valid until next call to any `fetch_*` function.
        fn fetch_bitmap(dec: *Dec) !Bitmap {
            const flags = try dec.fetch_int(u8);

            const has_transparency = (flags & 1) != 0;

            const tkey: Color = if (has_transparency)
                try dec.fetch_color()
            else
                .black;

            const width = try dec.fetch_size();
            const height = try dec.fetch_size();
            const stride = try dec.fetch_int(usize);

            const size = height * stride * @sizeOf(Color);

            try dec.heap.resize(size);
            try dec.reader.readNoEof(dec.heap.items[0..size]);

            return .{
                .has_transparency = has_transparency,
                .transparency_key = tkey,
                .width = width,
                .height = height,
                .stride = stride,
                .pixels = @ptrCast(dec.heap.items.ptr),
            };
        }

        fn fetch_coord(dec: Dec) !i16 {
            return try dec.reader.readInt(i16, .little);
        }

        fn fetch_size(dec: Dec) !u16 {
            return try dec.reader.readInt(u16, .little);
        }

        fn fetch_color(dec: Dec) !Color {
            return Color.from_u8(
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
    };
}

pub const BufferDecoder = struct {
    const Dec = @This();

    buffer: []const u8,
    cursor: usize = 0,

    pub const NextError = error{ InvalidCommand, EndOfStream };

    pub fn init(buffer: []const u8) Dec {
        return .{ .buffer = buffer };
    }

    pub fn next(dec: *Dec) NextError!?Command {
        const cmd_byte = dec.fetch_int(u8) catch |err| switch (err) {
            error.EndOfStream => return null,
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
                    const text_len = try dec.fetch_int(u16);
                    const string = try dec.fetch_slice(text_len);

                    break :blk .{
                        .x = x,
                        .y = y,
                        .font = font,
                        .color = color,
                        .text = string,
                    };
                },
            },
            .blit_bitmap => .{ .blit_bitmap = .{
                .x = try dec.fetch_coord(),
                .y = try dec.fetch_coord(),
                .bitmap = try dec.fetch_bitmap(),
            } },
            .blit_framebuffer => .{
                .blit_framebuffer = .{
                    .x = try dec.fetch_coord(),
                    .y = try dec.fetch_coord(),
                    .framebuffer = try dec.fetch_handle(Framebuffer),
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
                    .bitmap = try dec.fetch_bitmap(),
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

    /// NOTE: Returned bitmap is valid until next call to any `fetch_*` function.
    fn fetch_bitmap(dec: *Dec) !Bitmap {
        const flags = try dec.fetch_int(u8);

        const has_transparency = (flags & 1) != 0;

        const tkey: Color = if (has_transparency)
            try dec.fetch_color()
        else
            .black;

        const width = try dec.fetch_size();
        const height = try dec.fetch_size();
        const stride = try dec.fetch_int(usize);

        const size = height * stride * @sizeOf(Color);

        const pixels = try dec.fetch_slice(size);

        return .{
            .has_transparency = has_transparency,
            .transparency_key = tkey,
            .width = width,
            .height = height,
            .stride = stride,
            .pixels = @ptrCast(pixels),
        };
    }

    fn fetch_coord(dec: *Dec) !i16 {
        return try dec.fetch_int(i16);
    }

    fn fetch_size(dec: *Dec) !u16 {
        return try dec.fetch_int(u16);
    }

    fn fetch_color(dec: *Dec) !Color {
        return Color.from_u8(
            try dec.fetch_int(u8),
        );
    }

    fn fetch_handle(dec: *Dec, Handle: type) !Handle {
        return @ptrFromInt(
            try dec.fetch_int(usize),
        );
    }

    fn fetch_int(dec: *Dec, Int: type) error{EndOfStream}!Int {
        const bytes = try dec.fetch_bytes(@sizeOf(Int));
        return std.mem.readInt(Int, bytes, .little);
    }

    fn fetch_bytes(dec: *Dec, comptime size: usize) error{EndOfStream}!*const [size]u8 {
        const slice = try dec.fetch_slice(size);
        return slice[0..size];
    }

    fn fetch_slice(dec: *Dec, size: usize) error{EndOfStream}![]const u8 {
        if (dec.cursor + size > dec.buffer.len)
            return error.EndOfStream;
        const slice = dec.buffer[dec.cursor..][0..size];
        dec.cursor += size;
        return slice;
    }
};

pub const Command = union(CommandByte) {
    pub fn type_map(byte: CommandByte) type {
        return switch (byte) {
            .clear => Clear,
            .set_clip_rect => SetClipRect,
            .set_pixel => SetPixel,
            .draw_line => DrawLine,
            .draw_rect => DrawRect,
            .fill_rect => FillRect,
            .draw_text => DrawText,
            .blit_bitmap => BlitBitmap,
            .blit_framebuffer => BlitFramebuffer,
            .blit_partial_bitmap => BlitPartialBitmap,
            .blit_partial_framebuffer => BlitPartialFramebuffer,
        };
    }

    clear: Clear,
    set_clip_rect: SetClipRect,
    set_pixel: SetPixel,
    draw_line: DrawLine,
    draw_rect: DrawRect,
    fill_rect: FillRect,
    draw_text: DrawText,
    blit_bitmap: BlitBitmap,
    blit_framebuffer: BlitFramebuffer,
    blit_partial_bitmap: BlitPartialBitmap,
    blit_partial_framebuffer: BlitPartialFramebuffer,

    pub fn get_area_of_effect(cmd: *const Command) ashet.Rectangle {
        return switch (cmd.*) {
            inline else => |item| item.get_area_of_effect(),
        };
    }

    pub const Clear = struct {
        color: Color,

        pub fn get_area_of_effect(cmd: Clear) ashet.Rectangle {
            _ = cmd;
            return .everything;
        }
    };

    pub const SetClipRect = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,

        pub fn get_area_of_effect(cmd: SetClipRect) ashet.Rectangle {
            _ = cmd;
            return .new(.zero, .empty);
        }
    };

    pub const SetPixel = struct {
        x: i16,
        y: i16,
        color: Color,

        pub fn get_area_of_effect(cmd: SetPixel) ashet.Rectangle {
            return .new(.new(cmd.x, cmd.y), .new(1, 1));
        }
    };

    pub const DrawLine = struct {
        x1: i16,
        y1: i16,
        x2: i16,
        y2: i16,
        color: Color,

        pub fn get_area_of_effect(cmd: DrawLine) ashet.Rectangle {
            const left = @min(cmd.x1, cmd.x2);
            const right = @max(cmd.x1, cmd.x2);

            const top = @min(cmd.y1, cmd.y2);
            const bottom = @max(cmd.y1, cmd.y2);

            return .new(
                .new(left, top),
                .new(@intCast(right - left + 1), @intCast(bottom - top + 1)),
            );
        }
    };

    pub const DrawRect = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        color: Color,

        pub fn get_area_of_effect(cmd: DrawRect) ashet.Rectangle {
            return .{
                .x = cmd.x,
                .y = cmd.y,
                .width = cmd.width,
                .height = cmd.height,
            };
        }
    };

    pub const FillRect = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        color: Color,

        pub fn get_area_of_effect(cmd: FillRect) ashet.Rectangle {
            return .{
                .x = cmd.x,
                .y = cmd.y,
                .width = cmd.width,
                .height = cmd.height,
            };
        }
    };

    pub const DrawText = struct {
        x: i16,
        y: i16,
        font: Font,
        color: Color,
        text: []const u8,

        pub fn get_area_of_effect(cmd: DrawText) ashet.Rectangle {
            _ = cmd;
            @panic("Not possible in the state of things. This must be fixed.");
        }
    };

    pub const BlitBitmap = struct {
        x: i16,
        y: i16,
        bitmap: Bitmap,

        pub fn get_area_of_effect(cmd: BlitBitmap) ashet.Rectangle {
            return .{
                .x = cmd.x,
                .y = cmd.y,
                .width = cmd.bitmap.width,
                .height = cmd.bitmap.height,
            };
        }
    };

    pub const BlitFramebuffer = struct {
        x: i16,
        y: i16,
        framebuffer: Framebuffer,

        pub fn get_area_of_effect(cmd: BlitFramebuffer) ashet.Rectangle {
            _ = cmd;
            @panic("Not possible in the state of things. This must be fixed.");
        }
    };

    pub const BlitPartialBitmap = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        src_x: i16,
        src_y: i16,
        bitmap: Bitmap,

        pub fn get_area_of_effect(cmd: BlitPartialBitmap) ashet.Rectangle {
            return .{
                .x = cmd.x,
                .y = cmd.y,
                .width = cmd.width,
                .height = cmd.height,
            };
        }
    };

    pub const BlitPartialFramebuffer = struct {
        x: i16,
        y: i16,
        width: u16,
        height: u16,
        src_x: i16,
        src_y: i16,
        framebuffer: Framebuffer,

        pub fn get_area_of_effect(cmd: BlitPartialFramebuffer) ashet.Rectangle {
            _ = cmd;
            @panic("Not possible in the state of things. This must be fixed.");
        }
    };
};
