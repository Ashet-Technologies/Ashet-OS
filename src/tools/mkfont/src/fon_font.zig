//!
//! Implements support for Windows FON/FNT files.
//!
//! See also:
//! - https://wiki.osdev.org/MZ
//! - https://wiki.osdev.org/NE
//!

const std = @import("std");
const schema = @import("schema.zig");
const logger = std.log.scoped(.fon);

const bmp_font_gen = @import("bmp_font_gen.zig");

pub fn validate(font: schema.FonFontFile) !bool {
    var ok = true;

    if (font.file.len == 0) {
        std.log.warn("Font is missing file path.", .{});
        ok = false;
    }

    if (font.id != null and font.index != null) {
        std.log.warn("ID and index are mutually exclusive.", .{});
        ok = false;
    }

    return ok;
}

pub fn generate(
    allocator: std.mem.Allocator,
    file_writer: *std.fs.File.Writer,
    root_dir: std.fs.Dir,
    font: *schema.FonFontFile,
) !void {
    const fon_data = try root_dir.readFileAlloc(allocator, font.file, 1 * 1024 * 1024);
    defer allocator.free(fon_data);

    if (fon_data.len < 0x40)
        return error.InvalidData;

    const lfarlc = std.mem.readInt(u16, fon_data[0x18..0x1A], .little);
    if (lfarlc != 0x0040) {
        logger.err("file is not a NE file. expected 0x0040, but found 0x{X:0>4}", .{lfarlc});
        return error.InvalidData;
    }
    const lfanew = std.mem.readInt(u32, fon_data[0x3C..0x40], .little);
    if (lfanew +| @sizeOf(NE_Header) >= fon_data.len) {
        logger.err("file is not a NE file. expected file offset, but found 0x{X:0>4}: out of bounds", .{lfanew});
        return error.InvalidData;
    }
    const header = sliceToStruct(NE_Header, fon_data[lfanew..][0..packedStructSize(NE_Header)]);

    if (!std.mem.eql(u8, &header.sig, "NE")) {
        logger.err("file is not a NE file. expected 'NE' but found \"{f}\"", .{std.ascii.hexEscape(&header.sig, .upper)});
        return error.InvalidData;
    }

    const res_table_off = lfanew + header.ResTableOffset;
    if (res_table_off +| 10 >= fon_data.len) { // u16+u16+u16+u32
        logger.err("file is not a NE file. expected file offset, but found 0x{X:0>4} >= 0x{X:0>4}: out of bounds", .{ res_table_off, fon_data.len });
        return error.InvalidData;
    }

    const font_info: FontInfo = search_loop: {
        var reader: std.Io.Reader = .fixed(fon_data[res_table_off..]);

        const alignment_shift_count = try reader.takeInt(u16, .little);
        if (alignment_shift_count >= @bitSizeOf(u32))
            return error.InvalidData;

        const page_size: u32 = @as(u32, 1) << @intCast(alignment_shift_count);

        while (true) {
            const type_id = try reader.takeInt(u16, .little);
            if (type_id == 0) {
                logger.err("No matching fonts found", .{});
                return error.FontNotFound;
            }
            if ((type_id & 0x8000) == 0) {
                logger.err("string resource types are unsupported", .{});
                return error.InvalidData;
            }

            const res_type: ResourceType = @enumFromInt(type_id & 0x7FFF);

            logger.debug("type:  0x{X:0>4} / {}", .{ type_id & 0x7FFF, res_type });
            const resource_count = try reader.takeInt(u16, .little);
            logger.debug("count: {}", .{resource_count});
            _ = try reader.takeInt(u32, .little);

            for (0..resource_count) |res_index| {
                logger.debug("  Res {}:", .{res_index});

                const file_offset_page = try reader.takeInt(u16, .little);
                const resource_length_page = try reader.takeInt(u16, .little);
                const resource_flags = try reader.takeInt(u16, .little);
                const resource_id = try reader.takeInt(u16, .little);
                _ = try reader.takeInt(u32, .little);

                logger.debug("    offset={} size={} flags=0x{X:0>4} id={}", .{
                    page_size * file_offset_page,
                    page_size * resource_length_page,
                    resource_flags,
                    resource_id,
                });

                if (res_type == .font) {
                    if (font.id) |id|
                        if (id != resource_id)
                            continue;
                    if (font.index) |index|
                        if (index != res_index)
                            continue;
                    break :search_loop .{
                        .file_offset = page_size * file_offset_page,
                        .length = page_size * resource_length_page,
                        .flags = resource_flags,
                        .id = resource_id,
                    };
                }
            }
        } else {
            logger.err("No matching fonts found", .{});
            return error.FontNotFound;
        }
    };

    logger.info("font info: {}", .{font_info});

    if (font_info.file_offset + font_info.length > fon_data.len) {
        logger.err("FONTDATA is out of bounds. 0x{X:0>4} > 0x{X:0>4}", .{
            font_info.file_offset + font_info.length,
            fon_data.len,
        });
        return error.InvalidData;
    }
    if (font_info.length < @sizeOf(FNT_Header)) {
        logger.err("FONTDATA area is too small. expected at least {} bytes, but got {}", .{
            @sizeOf(FNT_Header),
            font_info.length,
        });
        return error.InvalidData;
    }

    const fnt_data = fon_data[font_info.file_offset..][0..font_info.length];

    const fontheader = sliceToStruct(FNT_Header, fnt_data[0..packedStructSize(FNT_Header)]);

    const fontheader_size: usize = switch (fontheader.dfVersion) {
        .win2 => 118,
        .win3 => 148,
        _ => {
            logger.err("unsupported file version: 0x{X:0>4}", .{fontheader.dfVersion});
            return error.UnsupportedFile;
        },
    };

    if (fontheader.dfType != 0) {
        logger.err("unsupported file type: 0x{X:0>4}", .{fontheader.dfType});
        return error.UnsupportedFile;
    }

    logger.info("{}", .{fontheader});

    var builder: bmp_font_gen.Builder = .init(allocator);
    defer builder.deinit();

    const char_count = (@as(usize, fontheader.dfLastChar) -| fontheader.dfFirstChar) +| 2;
    switch (fontheader.dfVersion) {
        .win2 => {
            logger.info("win2 font", .{});
            var reader: std.Io.Reader = .fixed(fnt_data[fontheader_size..]);
            for (0..char_count) |index| {
                const width = try reader.takeInt(u16, .little);
                const offset = try reader.takeInt(u16, .little);

                if (width > fontheader.dfMaxWidth) {
                    logger.info("char[{}] exceeds max width of {} px: has width of {} px", .{
                        index,
                        fontheader.dfMaxWidth,
                        width,
                    });
                    return error.InvalidData;
                }

                const codepoint = @as(u21, @intCast(index)) + fontheader.dfFirstChar;

                logger.info("char[{}] = '{u}', {}*{} px, +{}byte", .{
                    index,
                    codepoint,
                    width,
                    fontheader.dfPixHeight,
                    offset,
                });

                const glyph = try builder.add(codepoint, .{
                    .width = width,
                    .height = fontheader.dfPixHeight,
                    .advance = @intCast(width + 1),
                    .offset_x = 0,
                    .offset_y = 0,
                });

                const bitmap = fnt_data[offset..];

                for (0..fontheader.dfPixHeight) |y| {
                    for (0..width) |x| {
                        const col = x / 8;
                        const bits = bitmap[col * fontheader.dfPixHeight + y];

                        const mask = @as(u8, 0x80) >> @intCast(x & 7);
                        const bit = (bits & mask) != 0;

                        glyph.set_pixel(x, y, if (bit) .set else .unset);
                    }
                }

                // glyph.dump("  <");

                // glyph.optimize();

                // glyph.dump("  >");
            }
        },
        .win3 => {
            logger.info("win3 font", .{});
            var reader: std.Io.Reader = .fixed(fnt_data[fontheader_size..]);
            for (0..char_count) |index| {
                const width = try reader.takeInt(u16, .little);
                const offset = try reader.takeInt(u32, .little);
                logger.info("char[{}] = {}px, +{}byte", .{ index, width, offset });
            }
            @panic("Win3 fonts not implemented yet!");
        },
        _ => unreachable,
    }

    try bmp_font_gen.render(allocator, file_writer, builder, .{
        .line_height = @intCast(fontheader.dfAscent),
    });
}

const FontInfo = struct {
    file_offset: u32,
    length: u32,
    flags: u16,
    id: u16,
};

const NE_Header = extern struct {
    sig: [2]u8, // {'N', 'E'}
    MajLinkerVersion: u8, //The major linker version
    MinLinkerVersion: u8, //The minor linker version (also known as the linker revision)
    EntryTableOffset: u16, //Offset of entry table from start of NE_Header
    EntryTableLength: u16, //Length of entry table in bytes
    FileLoadCRC: u32, //32-bit CRC of entire contents of file
    FlagWord: u16, // Uses the FlagWord enum
    AutoDataSegIndex: u16, //The automatic data segment index
    InitHeapSize: u16, //The initial local heap size
    InitStackSize: u16, //The initial stack size
    EntryPoint: u32, //CS:IP entry point, CS is index into segment table
    InitStack: u32, //SS:SP initial stack pointer, SS is index into segment table
    SegCount: u16, //Number of segments in segment table
    ModRefs: u16, //Number of module references (DLLs)
    NoResNamesTabSiz: u16, //Size of non-resident names table in bytes
    SegTableOffset: u16, //Offset of segment table from start of NE_Header
    ResTableOffset: u16, //Offset of resources table from start of NE_Header
    ResidNamTable: u16, //Offset of resident names table from start of NE_Header
    ModRefTable: u16, //Offset of module reference table from start of NE_Header
    ImportNameTable: u16, //Offset of imported names table from start of NE_Header
    OffStartNonResTab: u32, //Offset of non-resident names table from start of file (!)
    MovEntryCount: u16, //Count of moveable entry point listed in entry table
    FileAlnSzShftCnt: u16, //File alignment size shift count (0=9(default 512 byte pages))
    nResTabEntries: u16, //Number of resource table entries (often inaccurate!)
    targOS: u8, //Target OS

    //
    // The rest of these are not defined in the Windows 3.0 standard and
    // appear to be specific to OS/2.

    OS2EXEFlags: u8, //Other OS/2 flags
    retThunkOffset: u16, //Offset to return thunks or start of gangload area - what is gangload?
    segrefthunksoff: u16, //Offset to segment reference thunks or size of gangload area
    mincodeswap: u16, //Minimum code swap area size
    expctwinver: [2]u8, //Expected windows version (minor first)
};

const ResourceType = enum(u16) {
    /// Accelerator table.
    accelerator = 9,
    /// Animated cursor.
    anicursor = 21,
    /// Animated icon.
    aniicon = 22,
    /// Bitmap resource.
    bitmap = 2,
    /// Hardware-dependent cursor resource.
    cursor = 1,
    /// Dialog box.
    dialog = 5,
    /// Allows a resource editing tool to associate a string with an .rc file. Typically, the string is the name of the header file that provides symbolic names. The resource compiler parses the string but otherwise ignores the value. For example,
    /// 1 DLGINCLUDE "MyFile.h"
    dlginclude = 17,
    /// Font resource.
    font = 8,
    /// Font directory resource.
    fontdir = 7,
    /// Hardware-independent cursor resource.
    group_cursor = 11 + 1, //  MAKEINTRESOURCE((ULONG_PTR)(RT_CURSOR) + 11),
    /// Hardware-independent icon resource.
    group_icon = 11 + 3, //  MAKEINTRESOURCE((ULONG_PTR)(RT_ICON) + 11),
    /// HTML resource.
    html = 23,
    /// Hardware-dependent icon resource.
    icon = 3,
    /// Side-by-Side Assembly Manifest.
    manifest = 24,
    /// Menu resource.
    menu = 4,
    /// Message-table entry.
    messagetable = 11,
    /// Plug and Play resource.
    plugplay = 19,
    /// Application-defined resource (raw data).
    rcdata = 10,
    /// String-table entry.
    string = 6,
    /// Version resource.
    version = 16,
    /// VXD.
    vxd = 20,

    _,
};

// https://jeffpar.github.io/kbarchive/kb/065/Q65123/
const FNT_Header = extern struct {
    const FontVersion = enum(u16) {
        win2 = 0x200,
        win3 = 0x300,
        _,
    };

    /// dfVersion      2 bytes specifying the version (0200H or 0300H) of
    ///               the file.
    dfVersion: FontVersion,

    /// dfSize         4 bytes specifying the total size of the file in
    ///               bytes.
    dfSize: u32,

    /// dfCopyright    60 bytes specifying copyright information.
    dfCopyright: [60]u8,

    /// dfType         2 bytes specifying the type of font file.
    ///
    ///               The low-order byte is exclusively for GDI use. If the
    ///               low-order bit of the WORD is zero, it is a bitmap
    ///               (raster) font file. If the low-order bit is 1, it is a
    ///               vector font file. The second bit is reserved and must
    ///               be zero. If no bits follow in the file and the bits are
    ///               located in memory at a fixed address specified in
    ///               dfBitsOffset, the third bit is set to 1; otherwise, the
    ///               bit is set to 0 (zero). The high-order bit of the low
    ///               byte is set if the font was realized by a device. The
    ///               remaining bits in the low byte are reserved and set to
    ///               zero.
    ///
    ///               The high byte is reserved for device use and will
    ///               always be set to zero for GDI-realized standard fonts.
    ///               Physical fonts with the high-order bit of the low byte
    ///               set may use this byte to describe themselves. GDI will
    ///               never inspect the high byte.
    dfType: u16,

    /// dfPoints       2 bytes specifying the nominal point size at which
    ///               this character set looks best.
    dfPoints: u16,

    /// dfVertRes      2 bytes specifying the nominal vertical resolution
    ///               (dots-per-inch) at which this character set was
    ///               digitized.
    dfVertRes: u16,

    /// dfHorizRes     2 bytes specifying the nominal horizontal resolution
    ///               (dots-per-inch) at which this character set was
    ///               digitized.
    dfHorizRes: u16,

    /// dfAscent       2 bytes specifying the distance from the top of a
    ///               character definition cell to the baseline of the
    ///               typographical font. It is useful for aligning the
    ///               baselines of fonts of different heights.
    dfAscent: u16,

    /// dfInternalLeading
    ///               Specifies the amount of leading inside the bounds set
    ///               by dfPixHeight. Accent marks may occur in this area.
    ///               This may be zero at the designer's option.
    dfInternalLeading: u16,

    /// dfExternalLeading
    ///               Specifies the amount of extra leading that the designer
    ///               requests the application add between rows. Since this
    ///               area is outside of the font proper, it contains no
    ///               marks and will not be altered by text output calls in
    ///               either the OPAQUE or TRANSPARENT mode. This may be zero
    ///               at the designer's option.
    dfExternalLeading: u16,

    /// dfItalic       1 (one) byte specifying whether or not the character
    ///               definition data represent an italic font. The low-order
    ///               bit is 1 if the flag is set. All the other bits are
    ///               zero.
    dfItalic: u8,

    /// dfUnderline    1 byte specifying whether or not the character
    ///               definition data represent an underlined font. The
    ///               low-order bit is 1 if the flag is set. All the other
    ///               bits are 0 (zero).
    dfUnderline: u8,

    /// dfStrikeOut    1 byte specifying whether or not the character
    ///               definition data represent a struckout font. The low-
    ///               order bit is 1 if the flag is set. All the other bits are
    ///               zero.
    dfStrikeOut: u8,

    /// dfWeight       2 bytes specifying the weight of the characters in the
    ///               character definition data, on a scale of 1 to 1000. A
    ///               dfWeight of 400 specifies a regular weight.
    dfWeight: u16,

    /// dfCharSet      1 byte specifying the character set defined by this
    ///               font.
    dfCharSet: u8,

    /// dfPixWidth     2 bytes. For vector fonts, specifies the width of the
    ///               grid on which the font was digitized. For raster fonts,
    ///               if dfPixWidth is nonzero, it represents the width for
    ///               all the characters in the bitmap; if it is zero, the
    ///               font has variable width characters whose widths are
    ///               specified in the dfCharTable array.
    dfPixWidth: u16,

    /// dfPixHeight    2 bytes specifying the height of the character bitmap
    ///               (raster fonts), or the height of the grid on which a
    ///               vector font was digitized.
    dfPixHeight: u16,

    /// dfPitchAndFamily
    ///               Specifies the pitch and font family. The low bit is set
    ///               if the font is variable pitch. The high four bits give
    ///               the family name of the font. Font families describe in
    ///               a general way the look of a font. They are intended for
    ///               specifying fonts when the exact face name desired is
    ///               not available. The families are as follows:
    ///
    ///                  Family               Description
    ///                  ------               -----------
    ///                  FF_DONTCARE (0<<4)   Don't care or don't know.
    ///                  FF_ROMAN (1<<4)      Proportionally spaced fonts
    ///                                       with serifs.
    ///                  FF_SWISS (2<<4)      Proportionally spaced fonts
    ///                                       without serifs.
    ///                  FF_MODERN (3<<4)     Fixed-pitch fonts.
    ///                  FF_SCRIPT (4<<4)
    ///                  FF_DECORATIVE (5<<4)
    dfPitchAndFamily: packed struct(u8) {
        variable_pitch: bool,
        _padding: u3,
        family: enum(u4) {
            dont_care = 0,
            roman = 1,
            swiss = 2,
            modern = 3,
            script = 4,
            decorative = 5,
            _,
        },
    },

    /// dfAvgWidth     2 bytes specifying the width of characters in the font.
    ///               For fixed-pitch fonts, this is the same as dfPixWidth.
    ///               For variable-pitch fonts, this is the width of the
    ///               character "X."
    dfAvgWidth: u16,

    /// dfMaxWidth     2 bytes specifying the maximum pixel width of any
    ///               character in the font. For fixed-pitch fonts, this is
    ///               simply dfPixWidth.
    dfMaxWidth: u16,

    /// dfFirstChar    1 byte specifying the first character code defined by
    ///               this font. Character definitions are stored only for
    ///               the characters actually present in a font. Therefore,
    ///               use this field when calculating indexes into either
    ///               dfBits or dfCharOffset.
    dfFirstChar: u8,

    /// dfLastChar     1 byte specifying the last character code defined by
    ///               this font. Note that all the characters with codes
    ///               between dfFirstChar and dfLastChar must be present in
    ///               the font character definitions.
    dfLastChar: u8,

    /// dfDefaultChar  1 byte specifying the character to substitute
    ///               whenever a string contains a character out of the
    ///               range. The character is given relative to dfFirstChar
    ///               so that dfDefaultChar is the actual value of the
    ///               character, less dfFirstChar. The dfDefaultChar should
    ///               indicate a special character that is not a space.
    dfDefaultChar: u8,

    /// dfBreakChar    1 byte specifying the character that will define word
    ///               breaks. This character defines word breaks for word
    ///               wrapping and word spacing justification. The character
    ///               is given relative to dfFirstChar so that dfBreakChar is
    ///               the actual value of the character, less that of
    ///               dfFirstChar. The dfBreakChar is normally (32 -
    ///               dfFirstChar), which is an ASCII space.
    dfBreakChar: u8,

    /// dfWidthBytes   2 bytes specifying the number of bytes in each row of
    ///               the bitmap. This is always even, so that the rows start
    ///               on WORD boundaries. For vector fonts, this field has no
    ///               meaning.
    dfWidthBytes: u16,

    /// dfDevice       4 bytes specifying the offset in the file to the string
    ///               giving the device name. For a generic font, this value
    ///               is zero.
    dfDevice: u32,

    /// dfFace         4 bytes specifying the offset in the file to the
    ///               null-terminated string that names the face.
    dfFace: u32,

    /// dfBitsPointer  4 bytes specifying the absolute machine address of
    ///               the bitmap. This is set by GDI at load time. The
    ///               dfBitsPointer is guaranteed to be even.
    dfBitsPointer: u32,

    /// dfBitsOffset   4 bytes specifying the offset in the file to the
    ///               beginning of the bitmap information. If the 04H bit in
    ///               the dfType is set, then dfBitsOffset is an absolute
    ///               address of the bitmap (probably in ROM).
    ///
    ///               For raster fonts, dfBitsOffset points to a sequence of
    ///               bytes that make up the bitmap of the font, whose height
    ///               is the height of the font, and whose width is the sum
    ///               of the widths of the characters in the font rounded up
    ///               to the next WORD boundary.
    ///
    ///               For vector fonts, it points to a string of bytes or
    ///               words (depending on the size of the grid on which the
    ///               font was digitized) that specify the strokes for each
    ///               character of the font. The dfBitsOffset field must be
    ///               even.
    dfBitsOffset: u32,

    /// dfReserved     1 byte, not used.
    dfReserved: u8,

    /// dfFlags        4 bytes specifying the bits flags, which are additional
    ///               flags that define the format of the Glyph bitmap, as
    ///               follows:
    ///
    ///               DFF_FIXED            equ  0001h ; font is fixed pitch
    ///               DFF_PROPORTIONAL     equ  0002h ; font is proportional
    ///                                               ; pitch
    ///               DFF_ABCFIXED         equ  0004h ; font is an ABC fixed
    ///                                               ; font
    ///               DFF_ABCPROPORTIONAL  equ  0008h ; font is an ABC pro-
    ///                                               ; portional font
    ///               DFF_1COLOR           equ  0010h ; font is one color
    ///               DFF_16COLOR          equ  0020h ; font is 16 color
    ///               DFF_256COLOR         equ  0040h ; font is 256 color
    ///               DFF_RGBCOLOR         equ  0080h ; font is RGB color
    dfFlags: packed struct(u32) {
        fixed: bool,
        proportional: bool,
        abc_fixed: bool,
        abc_proportional: bool,
        bpp1: bool,
        bpp4: bool,
        bpp8: bool,
        bpp24: bool,
        _reserved: u24,

        pub fn is_fixed(val: @This()) bool {
            return val.fixed or val.abc_fixed;
        }

        pub fn is_proportional(val: @This()) bool {
            return val.proportional or val.abc_proportional;
        }
    },

    /// dfAspace       2 bytes specifying the global A space, if any. The
    ///               dfAspace is the distance from the current position to
    ///               the left edge of the bitmap.
    dfAspace: u16,

    /// dfBspace       2 bytes specifying the global B space, if any. The
    ///               dfBspace is the width of the character.
    dfBspace: u16,

    /// dfCspace       2 bytes specifying the global C space, if any. The
    ///               dfCspace is the distance from the right edge of the
    ///               bitmap to the new current position. The increment of a
    ///               character is the sum of the three spaces. These apply
    ///               to all glyphs and is the case for DFF_ABCFIXED.
    dfCspace: u16,

    /// dfColorPointer
    ///               4 bytes specifying the offset to the color table for
    ///               color fonts, if any. The format of the bits is similar
    ///               to a DIB, but without the header. That is, the
    ///               characters are not split up into disjoint bytes.
    ///               Instead, they are left intact. If no color table is
    ///               needed, this entry is NULL.
    ///               [NOTE: This information is different from that in the
    ///               hard-copy Developer's Notes and reflects a correction.]
    dfColorPointer: u32,

    /// dfReserved1    16 bytes, not used.
    ///               [NOTE: This information is different from that in the
    ///               hard-copy Developer's Notes and reflects a correction.]
    dfReserved1: [16]u8,
};

inline fn packedStructSize(comptime T: type) usize {
    return comptime blk: {
        const info = @typeInfo(T).@"struct";

        var size = 0;
        for (info.fields) |fld| {
            size += @sizeOf(fld.type);
        }
        break :blk size;
    };
}

fn sliceToStruct(comptime T: type, data: *const [packedStructSize(T)]u8) T {
    var header: T = undefined;

    const info = @typeInfo(T).@"struct";
    comptime var offset: usize = 0;
    inline for (info.fields) |fld| {
        const field_ptr = data[offset..][0..@sizeOf(fld.type)];

        @field(header, fld.name) = switch (@typeInfo(fld.type)) {
            .int => std.mem.readInt(fld.type, field_ptr, .little),
            .array => field_ptr.*,
            .@"struct" => |s_info| if (s_info.backing_integer) |int|
                @bitCast(std.mem.readInt(int, field_ptr, .little))
            else
                @compileError("unsupported type: " ++ @typeName(fld.type)),
            .@"enum" => |e_info| if (e_info.is_exhaustive == false)
                @enumFromInt(std.mem.readInt(e_info.tag_type, field_ptr, .little))
            else
                @compileError("unsupported type: " ++ @typeName(fld.type)),
            else => @compileError("unsupported type: " ++ @typeName(fld.type)),
        };

        offset += @sizeOf(fld.type);
    }

    return header;
}
