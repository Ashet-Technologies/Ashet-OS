const std = @import("std");

pub const EEPROM_Image = extern struct {
    metadata: MetadataBlock,

    reserved: [512]u8 = @splat(0),

    firmware: FirmwareBlock align(2048),

    // icon: IconBlock align(1024),
};

pub const FirmwareBlock = extern struct {
    data: [2048]u8 = @splat(0x00),
};

pub const MetadataBlock = extern struct {
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

pub const IconConfig = packed struct(u8) {
    pub const disabled: IconConfig = .{ .color_count = 0 };

    color_count: u6,
    _reserved: u2 = 0,
};

pub const RGB = extern struct { r: u8, g: u8, b: u8 };

pub const IconBlock = extern struct {
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

/// A fixed-size, null-padded string with up to `len` bytes.
pub fn String(comptime len: comptime_int) type {
    return extern struct {
        pub const type_name = std.fmt.comptimePrint("[{}]u8", .{len});

        text: [len]u8,

        /// Converts a comptime value into a string.
        fn literal(comptime buffer: []const u8) @This() {
            var out: [len]u8 = @splat(0);
            @memcpy(out[0..buffer.len], buffer);
            return .{ .text = out };
        }

        /// Converts a runtime value into a string.
        fn init(buffer: []const u8) error{Overflow}!@This() {
            if (buffer.len > len)
                return error.Overflow;
            var out: [len]u8 = @splat(0);
            @memcpy(out[0..buffer.len], buffer);
            return .{ .text = out };
        }

        /// Returns the filled part of the string.
        fn slice(str: *@This()) []const u8 {
            return str.text[0 .. std.mem.indexOfScalar(u8, &str.text, 0) orelse str.text.len];
        }
    };
}

/// Enumeration of potential pre-defined driver interfaces an expansion card could provide.
pub const DriverInterface = enum(u32) {
    none = 0,
    _,
};

pub const Properties = packed struct(u32) {
    // Required features block:
    @"Requires Audio": bool,
    @"Requires Video": bool,
    @"Requires USB": bool,
    _padding0: u13 = 0,

    // Provided features block:
    @"Has Firmware": bool = false,
    @"Has Icons": bool = false,
    _padding1: u14 = 0,
};

pub fn typeName(comptime T: type) []const u8 {
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

pub fn dump_type(comptime T: type) void {
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

pub const json = struct {
    pub const JsonMetadata = struct {
        @"Vendor ID": u32,
        @"Product ID": u32,
        Properties: Properties,
        @"Driver Interface": DriverInterface,

        @"Driver Specific Data": []const u8 = "",

        @"Vendor Name": []const u8,
        @"Product Name": []const u8,
        @"Serial Number": []const u8,
    };

    pub fn load_metadata(json_code: []const u8) !MetadataBlock {
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
};
