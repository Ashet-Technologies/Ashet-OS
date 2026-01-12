const std = @import("std");
const agp = @import("agp");

pub fn main() !void {
    // Demo: generate a palette + some frames, then stream a GIF to disk.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Output path (default: "out.gif")
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name
    const out_path = args.next() orelse "out.gif";

    const width: u16 = 96;
    const height: u16 = 64;
    const frame_count: usize = 16;
    const delay_cs: u16 = 8; // 0.08s per frame

    // Build a colorful 256-entry palette (HSV wheel).
    var palette: [256][3]u8 = undefined;
    for (&palette, 0..) |*rgb, i| {
        rgb.* = .{
            @intCast(i),
            @intCast(i),
            @intCast(i),
        };
    }

    // Generate frames: simple moving diagonal pattern over the palette.
    const frames = try allocator.alloc([]u8, frame_count);
    defer {
        for (frames) |buf| allocator.free(buf);
        allocator.free(frames);
    }
    const px_count: usize = @as(usize, width) * @as(usize, height);
    for (frames, 0..) |*buf, f| {
        buf.* = try allocator.alloc(u8, px_count);
        var idx: usize = 0;
        var y: usize = 0;
        while (y < height) : (y += 1) {
            var x: usize = 0;
            while (x < width) : (x += 1) {
                const val: u8 = @truncate(((4 * x) ^ (4 * y)) + 8 * f);
                buf.*[idx] = val;
                idx += 1;
            }
        }
    }

    // Open file and stream the GIF (progressive: strictly forward writes).
    var file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer file.close();

    var encoder: GIF_Encoder = try .start(
        file.writer().any(),
        width,
        height,
        delay_cs,
    );

    for (frames) |frame| {
        try encoder.add_frame(frame);
    }
    try encoder.end();

    std.debug.print("Wrote {s} ({d}x{d}, {d} frames)\n", .{ out_path, width, height, frame_count });
}

pub fn write_to_file_path(dir: std.fs.Dir, path: []const u8, width: u16, height: u16, pixels: []const agp.Color) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();

    try write_to_file(file, width, height, pixels);
}

pub fn write_to_file(file: std.fs.File, width: u16, height: u16, pixels: []const agp.Color) !void {
    var encoder: GIF_Encoder = try .start(
        file.writer().any(),
        width,
        height,
        0,
    );
    try encoder.add_frame(pixels);
    try encoder.end();
}

// ---------------- GIF Writer (progressive, no seeking) ----------------

pub const GIF_Encoder = struct {
    writer: std.io.BufferedWriter(4096, std.io.AnyWriter),
    width: u16,
    height: u16,
    delay_cs: u16,

    pub fn start(
        _writer: std.io.AnyWriter,
        width: u16,
        height: u16,
        delay_cs: u16,
    ) !GIF_Encoder {
        var buf_writer: std.io.BufferedWriter(4096, std.io.AnyWriter) = .{ .unbuffered_writer = _writer };
        const writer = buf_writer.writer();

        // Header: GIF89a
        try writer.writeAll("GIF89a");

        // Logical Screen Descriptor
        try writeU16LE(writer, width);
        try writeU16LE(writer, height);
        // Packed: 1(GCT) 111(color res=7) 0(unsorted) 111(GCT size=256)
        try writer.writeByte(0xF7);
        try writer.writeByte(0x00); // background color index
        try writer.writeByte(0x00); // pixel aspect ratio (unused)

        // Global Color Table (256 * 3 bytes)
        for (0..256) |i| {
            const color: agp.Color = .from_u8(@intCast(i));
            const rgb = color.to_rgb888();
            try writer.writeByte(rgb.r);
            try writer.writeByte(rgb.g);
            try writer.writeByte(rgb.b);
        }

        // Application Extension: NETSCAPE2.0 (infinite loop)
        try writer.writeByte(0x21);
        try writer.writeByte(0xFF);
        try writer.writeByte(11);
        try writer.writeAll("NETSCAPE2.0");
        try writer.writeByte(3);
        try writer.writeByte(1);
        try writeU16LE(writer, 0); // loop forever
        try writer.writeByte(0); // terminator

        return .{
            .writer = buf_writer,
            .width = width,
            .height = height,
            .delay_cs = delay_cs,
        };
    }

    pub fn add_frame(gif: *GIF_Encoder, frame: []const agp.Color) !void {
        std.debug.assert(frame.len == (@as(u32, gif.width) * gif.height));
        const w = gif.writer.writer();

        // Graphics Control Extension
        try w.writeByte(0x21);
        try w.writeByte(0xF9);
        try w.writeByte(4);
        try w.writeByte(0x00); // packed: no disposal, no transparency
        try writeU16LE(w, gif.delay_cs); // delay (1/100 s)
        try w.writeByte(0x00); // transparent index (unused)
        try w.writeByte(0x00); // terminator

        // Image Descriptor (full frame, no LCT)
        try w.writeByte(0x2C);
        try writeU16LE(w, 0); // left
        try writeU16LE(w, 0); // top
        try writeU16LE(w, gif.width);
        try writeU16LE(w, gif.height);
        try w.writeByte(0x00); // no local color table

        // Image Data: LZW, min code size = 8 (256-color indices)
        const min_code_size: u8 = 8;
        try w.writeByte(min_code_size);

        var sb = SubBlockWriter.init(w);
        var packer = BitPacker{ .sb = &sb };
        try lzwStoreLiterals(&packer, std.mem.sliceAsBytes(frame), min_code_size);

        try packer.flush();
        try sb.finish(); // writes final 0-sized block
    }

    pub fn end(gif: *GIF_Encoder) !void {
        // Trailer
        try gif.writer.writer().writeByte(0x3B);
        try gif.writer.flush();
    }
};

fn writeU16LE(w: std.io.BufferedWriter(4096, std.io.AnyWriter).Writer, v: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, v, .little);
    try w.writeAll(buf[0..]);
}

// ---------------- Sub-block writer (≤255 bytes + size prefix) ----------------

const SubBlockWriter = struct {
    w: std.io.BufferedWriter(4096, std.io.AnyWriter).Writer,
    buf: [255]u8 = undefined,
    len: u8 = 0,

    pub fn init(w: std.io.BufferedWriter(4096, std.io.AnyWriter).Writer) SubBlockWriter {
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
        try self.w.writeByte(0); // zero-sized terminator
    }
};

// ---------------- Bit packer (LSB-first) ----------------

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

// ---------------- LZW encoder (dictionary on (prefix_code, k)) ----------------

fn lzwStoreLiterals(
    packer: *BitPacker,
    data: []const u8,
    min_code_size: u8,
) !void {
    // Use constant 9-bit codes (for min_code_size = 8).
    const clear_code: u16 = @as(u16, 1) << @intCast(min_code_size); // 256
    const eoi_code: u16 = clear_code + 1; // 257
    const code_bits: u8 = min_code_size + 1; // 9

    // For debugging: CLEAR before every pixel, then the literal.
    // Dictionary never grows; decoder always stays at 9-bit codes.
    for (data) |b| {
        try packer.emitCode(clear_code, code_bits);
        try packer.emitCode(@as(u16, b), code_bits);
    }

    // Finish the image.
    try packer.emitCode(eoi_code, code_bits);
}

const Key = packed struct {
    prefix: u16,
    k: u8,
};

fn reset(dict: *std.AutoHashMap(Key, u16), next_code_ptr: *u16, code_size_ptr: *u8, min_size: u8) void {
    dict.clearRetainingCapacity();
    next_code_ptr.* = (@as(u16, 1) << @intCast(min_size)) + 2; // EOI + 1
    code_size_ptr.* = min_size + 1;
}

fn lzwEncodeIndices(
    allocator: std.mem.Allocator,
    packer: *BitPacker,
    data: []const u8,
    min_code_size: u8,
) !void {
    // Handle degenerate case (shouldn't happen for valid frames)
    if (data.len == 0) {
        // Emit CLEAR + EOI anyway (legal but meaningless)
        const clear_code: u16 = @as(u16, 1) << @intCast(min_code_size);
        const eoi_code: u16 = clear_code + 1;
        const code_size: u8 = min_code_size + 1;
        try packer.emitCode(clear_code, code_size);
        try packer.emitCode(eoi_code, code_size);
        return;
    }

    var map = std.AutoHashMap(Key, u16).init(allocator);
    defer map.deinit();

    const clear_code: u16 = @as(u16, 1) << @intCast(min_code_size); // 256
    const eoi_code: u16 = clear_code + 1; // 257
    const max_code: u16 = 0x0FFF;
    const max_bits: u8 = 12;

    var code_size: u8 = min_code_size + 1; // start at 9 for min_code_size=8
    var next_code: u16 = eoi_code + 1; // 258

    try packer.emitCode(clear_code, code_size);

    var w_code: u16 = data[0]; // first symbol as code
    var i: usize = 1;

    while (i < data.len) : (i += 1) {
        const k: u8 = data[i];
        const key = Key{ .prefix = w_code, .k = k };

        if (map.get(key)) |value| {
            w_code = value;
        } else {
            // Emit current sequence code
            try packer.emitCode(w_code, code_size);

            // Add new code if space remains
            if (next_code <= max_code) {
                try map.put(key, next_code);
                next_code += 1;

                if ((next_code == (@as(u16, 1) << @intCast(code_size))) and (code_size < max_bits)) {
                    code_size += 1;
                }
            } else {
                // Dictionary full: emit CLEAR and reset
                try packer.emitCode(clear_code, code_size);
                reset(&map, &next_code, &code_size, min_code_size);
            }

            // Start new sequence with the single symbol
            w_code = k;
        }
    }

    // Emit final code and EOI
    try packer.emitCode(w_code, code_size);
    try packer.emitCode(eoi_code, code_size);
}
