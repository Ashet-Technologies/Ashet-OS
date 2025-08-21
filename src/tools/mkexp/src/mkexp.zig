const std = @import("std");
const args_parser = @import("args");

const EEPROM_Size = enum(u32) {
    @"32k" = @divExact(32768, 8),
    @"64k" = @divExact(65536, 8),
    @"128k" = @divExact(131072, 8),
};

const CliOptions = struct {
    help: bool = false,

    size: EEPROM_Size = .@"32k",

    pub const shorthands = .{
        .h = "help",
    };
};

const CliVerb = union(enum) {
    encode: struct {
        firmware: ?[]const u8 = null,
        // icon16: ?[]const u8 = null,
        // icon24: ?[]const u8 = null,
        // icon32: ?[]const u8 = null,
        output: []const u8 = "-",
    },
    decode: struct {
        //
    },
    @"render-md": struct {},
};

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cli = args_parser.parseWithVerbForCurrentProcess(CliOptions, CliVerb, allocator, .print) catch return 1;
    defer cli.deinit();

    const verb = cli.verb orelse {
        // TODO: Print usage
        return 1;
    };

    switch (verb) {
        .encode => |options| {
            if (cli.positionals.len != 1)
                return 1;

            const json_data = try std.fs.cwd().readFileAlloc(allocator, cli.positionals[0], 1 << 20);

            var image: EEPROM_Image = .{
                .metadata = try metadata_from_json(json_data),
                // .icon = .{},
                .firmware = .{ .data = @splat(0x00) },
            };

            if (options.firmware) |firmware_path| {
                var fd = try std.fs.cwd().openFile(firmware_path, .{});
                defer fd.close();
                const stat = try fd.stat();
                if (stat.size > image.firmware.data.len)
                    return error.FirmwareTooBig;

                try fd.reader().readNoEof(image.firmware.data[0..stat.size]);

                image.metadata.Properties.@"Has Firmware" = true;
            } else {
                image.metadata.Properties.@"Has Firmware" = false;
            }

            image.metadata.fix_checksum();

            var max_eeprom_image: [16384]u8 = @splat(0xFF);

            const raw_image: []u8 = max_eeprom_image[0..@intFromEnum(cli.options.size)];
            var fbs: std.io.FixedBufferStream([]u8) = .{ .buffer = raw_image, .pos = 0 };

            try fbs.writer().writeStructEndian(image, .little);
            std.debug.assert(fbs.pos == raw_image.len);

            if (std.mem.eql(u8, options.output, "-")) {
                try std.io.getStdOut().writeAll(raw_image);
            } else {
                try std.fs.cwd().writeFile(.{
                    .sub_path = options.output,
                    .data = raw_image,
                });
            }

            return 0;
        },

        .decode => @panic("not implemented yet!"),

        .@"render-md" => {
            dump_type(MetadataBlock);
            return 0;
        },
    }
}

fn String(comptime len: comptime_int) type {
    return extern struct {
        pub const type_name = std.fmt.comptimePrint("[{}]u8", .{len});

        text: [len]u8,

        fn literal(comptime buffer: []const u8) @This() {
            var out: [len]u8 = @splat(0);
            @memcpy(out[0..buffer.len], buffer);
            return .{ .text = out };
        }

        fn init(buffer: []const u8) error{Overflow}!@This() {
            if (buffer.len > len)
                return error.Overflow;
            var out: [len]u8 = @splat(0);
            @memcpy(out[0..buffer.len], buffer);
            return .{ .text = out };
        }
    };
}

const DriverInterface = enum(u32) {
    none = 0,
    _,
};

const Properties = packed struct(u32) {
    @"Requires Audio": bool,
    @"Requires Video": bool,
    @"Has Firmware": bool = false,
    @"Has Icons": bool = false,
    _padding0: u28 = 0,
};

const JsonMetadata = struct {
    @"Vendor ID": u32,
    @"Product ID": u32,
    Properties: Properties,
    @"Driver Interface": DriverInterface,

    @"Driver Specific Data": []const u8 = "",

    @"Vendor Name": []const u8,
    @"Product Name": []const u8,
    @"Serial Number": []const u8,
};

const MetadataBlock = extern struct {
    @"Magic Number": u32 = 0xa0bbf5e9, // chosen by a fair dice roll
    Version: u32 = 1, // only defined version right now

    @"Vendor ID": u32 align(16),
    @"Product ID": u32,

    Properties: Properties,
    @"Driver Interface": DriverInterface,

    @"Driver Specific Data": String(128) align(128) = .literal(""),

    @"Vendor Name": String(64) align(256),
    @"Product Name": String(64) align(64),
    @"Serial Number": String(32) align(16),

    _reserved: [60]u8 align(64) = @splat(0),

    @"CRC32 Checksum": u32 = 0xFFFFFFFF, // CRC-32 ISO/HDLC (polynomial=0x04C11DB7, initial=0xffffffff, reflect_input=on, reflect_output=on, invert_output=on, reversed=no)

    pub fn fix_checksum(mdb: *MetadataBlock) void {
        mdb.@"CRC32 Checksum" = mdb.compute_checksum();
    }

    pub fn compute_checksum(mdb: MetadataBlock) u32 {
        var chunk_buffer: [512]u8 = undefined;

        var fbs = std.io.fixedBufferStream(&chunk_buffer);
        fbs.writer().writeStructEndian(mdb, .little) catch unreachable;
        std.debug.assert(fbs.pos == @sizeOf(MetadataBlock));
        fbs.pos -= @sizeOf(u32);
        std.debug.assert(fbs.pos == @offsetOf(MetadataBlock, "CRC32 Checksum"));

        return std.hash.crc.Crc32IsoHdlc.hash(fbs.getWritten());
    }

    pub fn is_checksum_ok(mdb: MetadataBlock) bool {
        return mdb.compute_checksum() == mdb.@"CRC32 Checksum";
    }
};

const IconConfig = packed struct(u8) {
    pub const disabled: IconConfig = .{ .color_count = 0 };

    color_count: u6,
    _reserved: u2 = 0,
};

const RGB = extern struct { r: u8, g: u8, b: u8 };

const IconBlock = extern struct {
    pixels_16x16: [16 * 16]u8 = @splat(0x00),
    pixels_24x24: [24 * 24]u8 = @splat(0x00),
    pixels_32x32: [32 * 32]u8 = @splat(0x00),

    config_16x16: IconConfig = .disabled,
    config_24x24: IconConfig = .disabled,
    config_32x32: IconConfig = .disabled,

    palette: [63]RGB = @splat(.{ .r = 0, .g = 0, .b = 0 }),
};

comptime {
    if (@sizeOf(IconBlock) != 0x0800) {
        @compileLog(@sizeOf(IconBlock), 0x0800);
    }
}

const FirmwareBlock = extern struct {
    data: [2048]u8 = @splat(0x00),
};

const EEPROM_Image = extern struct {
    metadata: MetadataBlock,

    reserved: [512]u8 = @splat(0),

    firmware: FirmwareBlock align(2048),

    // icon: IconBlock align(1024),
};

comptime {
    if (@sizeOf(MetadataBlock) != 0x0200) {
        @compileLog(@sizeOf(MetadataBlock), 0x0200);
    }
    if (@offsetOf(MetadataBlock, "CRC32 Checksum") != 0x01FC) {
        @compileLog(@offsetOf(MetadataBlock, "CRC32 Checksum"), 0x01FC);
    }

    if (@sizeOf(IconBlock) != 0x0800) {
        @compileLog(@sizeOf(IconBlock), 0x0800);
    }
}

fn typeName(comptime T: type) []const u8 {
    switch (@typeInfo(T)) {
        .@"struct" => |info| if (@hasDecl(T, "type_name"))
            return T.type_name
        else if (info.backing_integer) |int|
            return @typeName(int),
        .@"union" => if (@hasDecl(T, "type_name"))
            return T.type_name,
        .@"enum" => |info| if (@hasDecl(T, "type_name"))
            return T.type_name
        else
            return @typeName(info.tag_type),
        .@"opaque" => if (@hasDecl(T, "type_name"))
            return T.type_name,
        else => {},
    }
    return @typeName(T);
}

fn dump_type(comptime T: type) void {
    const row_fmt = "| `{X:0>4}` | {s: <20} | {s: >10} | {d: >4} | {s: <30} |\n";

    comptime var last_end = 0;
    inline for (@typeInfo(T).@"struct".fields) |fld| {
        if (fld.name[0] == '_')
            continue;

        const offset = @offsetOf(T, fld.name);
        defer last_end = offset + @sizeOf(fld.type);

        if (last_end != offset) {
            std.debug.print(row_fmt, .{
                last_end,
                "",
                "",
                offset - last_end,
                "*padding*",
            });
        }

        std.debug.print(row_fmt, .{
            offset,
            fld.name,
            typeName(fld.type),
            @sizeOf(fld.type),
            "-",
        });
    }
}

fn metadata_from_json(json_code: []const u8) !MetadataBlock {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const metadata_store = try std.json.parseFromSlice(JsonMetadata, allocator, json_code, .{
        .allocate = .alloc_if_needed,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .parse_numbers = true,
    });
    const metadata = &metadata_store.value;

    var meta: MetadataBlock = .{
        .@"Vendor ID" = metadata.@"Vendor ID",
        .@"Product ID" = metadata.@"Product ID",
        .@"Vendor Name" = try .init(metadata.@"Vendor Name"),
        .@"Product Name" = try .init(metadata.@"Product Name"),
        .@"Serial Number" = try .init(metadata.@"Serial Number"),

        .Properties = metadata.Properties,

        .@"Driver Interface" = metadata.@"Driver Interface",

        .@"Driver Specific Data" = try .init(metadata.@"Driver Specific Data"),
    };
    meta.fix_checksum();

    return meta;
}
