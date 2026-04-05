const std = @import("std");
const agp = @import("agp");

pub fn write_to_file_path(dir: std.fs.Dir, path: []const u8, width: u16, height: u16, pixels: []const agp.Color) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();

    try write_to_file(file, width, height, pixels);
}

pub fn write_to_file(file: std.fs.File, width: u16, height: u16, pixels: []const agp.Color) !void {
    var buffer: [8192]u8 = undefined;
    var file_writer = file.writer(&buffer);

    var encoder: GIF_Encoder = try .start(
        &file_writer.interface,
        width,
        height,
        0,
    );
    try encoder.add_frame(pixels);
    try encoder.end();
}

pub const GIF_Encoder = struct {
    writer: *std.Io.Writer,
    width: u16,
    height: u16,
    delay_cs: u16,

    pub fn start(
        writer: *std.Io.Writer,
        width: u16,
        height: u16,
        delay_cs: u16,
    ) !GIF_Encoder {
        try writer.writeAll("GIF89a");
        try writeU16LE(writer, width);
        try writeU16LE(writer, height);
        try writer.writeByte(0xF7);
        try writer.writeByte(0x00);
        try writer.writeByte(0x00);

        for (0..256) |i| {
            const color: agp.Color = .from_u8(@intCast(i));
            const rgb = color.to_rgb888();
            try writer.writeByte(rgb.r);
            try writer.writeByte(rgb.g);
            try writer.writeByte(rgb.b);
        }

        try writer.writeByte(0x21);
        try writer.writeByte(0xFF);
        try writer.writeByte(11);
        try writer.writeAll("NETSCAPE2.0");
        try writer.writeByte(3);
        try writer.writeByte(1);
        try writeU16LE(writer, 0);
        try writer.writeByte(0);

        return .{
            .writer = writer,
            .width = width,
            .height = height,
            .delay_cs = delay_cs,
        };
    }

    pub fn add_frame(gif: *GIF_Encoder, frame: []const agp.Color) !void {
        std.debug.assert(frame.len == (@as(u32, gif.width) * gif.height));
        const w = gif.writer;

        try w.writeByte(0x21);
        try w.writeByte(0xF9);
        try w.writeByte(4);
        try w.writeByte(0x00);
        try writeU16LE(w, gif.delay_cs);
        try w.writeByte(0x00);
        try w.writeByte(0x00);

        try w.writeByte(0x2C);
        try writeU16LE(w, 0);
        try writeU16LE(w, 0);
        try writeU16LE(w, gif.width);
        try writeU16LE(w, gif.height);
        try w.writeByte(0x00);

        const min_code_size: u8 = 8;
        try w.writeByte(min_code_size);

        var sb = SubBlockWriter.init(w);
        var packer = BitPacker{ .sb = &sb };
        try lzwStoreLiterals(&packer, std.mem.sliceAsBytes(frame), min_code_size);

        try packer.flush();
        try sb.finish();
    }

    pub fn end(gif: *GIF_Encoder) !void {
        try gif.writer.writeByte(0x3B);
        try gif.writer.flush();
    }
};

fn writeU16LE(w: *std.Io.Writer, v: u16) !void {
    try w.writeInt(u16, v, .little);
}

const SubBlockWriter = struct {
    w: *std.Io.Writer,
    buf: [255]u8 = undefined,
    len: u8 = 0,

    pub fn init(w: *std.Io.Writer) SubBlockWriter {
        return .{ .w = w };
    }

    pub fn put(self: *SubBlockWriter, b: u8) !void {
        self.buf[self.len] = b;
        self.len += 1;
        if (self.len == 255) try self.flushBlock();
    }

    fn flushBlock(self: *SubBlockWriter) !void {
        try self.w.writeByte(self.len);
        try self.w.writeAll(self.buf[0..self.len]);
        self.len = 0;
    }

    pub fn finish(self: *SubBlockWriter) !void {
        if (self.len > 0) try self.flushBlock();
        try self.w.writeByte(0);
    }
};

const BitPacker = struct {
    sb: *SubBlockWriter,
    bitbuf: u32 = 0,
    bitcnt: u8 = 0,

    pub fn emitCode(self: *BitPacker, code: u16, code_size: u8) !void {
        const mask: u32 = (@as(u32, 1) << @intCast(code_size)) - 1;
        self.bitbuf |= ((@as(u32, code) & mask) << @intCast(self.bitcnt & 31));
        self.bitcnt +%= code_size;

        while (self.bitcnt >= 8) {
            const out: u8 = @intCast(self.bitbuf & 0xFF);
            try self.sb.put(out);
            self.bitbuf >>= 8;
            self.bitcnt -= 8;
        }
    }

    pub fn flush(self: *BitPacker) !void {
        if (self.bitcnt > 0) {
            const out: u8 = @intCast(self.bitbuf & 0xFF);
            try self.sb.put(out);
            self.bitbuf = 0;
            self.bitcnt = 0;
        }
    }
};

fn lzwStoreLiterals(
    packer: *BitPacker,
    data: []const u8,
    min_code_size: u8,
) !void {
    const clear_code: u16 = @as(u16, 1) << @intCast(min_code_size);
    const eoi_code: u16 = clear_code + 1;
    const code_bits: u8 = min_code_size + 1;

    try packer.emitCode(clear_code, code_bits);
    for (data) |b| {
        try packer.emitCode(b, code_bits);
    }
    try packer.emitCode(eoi_code, code_bits);
}
