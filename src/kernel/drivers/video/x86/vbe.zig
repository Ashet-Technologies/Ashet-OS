const std = @import("std");

pub const VideoMode = packed struct(u16) {
    number: u9,
    reserved0: u2,
    custom_crtc: bool,
    reserved1: u2,
    linear: bool,
    preserve: bool,
};

pub const Control = extern struct {
    pub const signature: u32 = @bitCast(u32, [4]u8{ 'V', 'E', 'S', 'A' });

    // 0	Signatur	4	Hier sollte "VESA" stehen (=0x56455341)
    signature: u32,
    version: BCD(u16),
    // 4	Version	2	BCD-kodiert: 0x0100 für 1.0, 0x0200 für 2.0, 0x0300 für 3.0
    oemstring: FarPtr([*:0]const u8), // 6	Zeiger auf OEMString	4 (FARPTR)
    flags: Flags align(2), // 10	Eigenschaften des Grafikcontrollers	4
    //     Bit 2: RAMDAC-Operation: 0=Normal; 1=Leeres Bit benutzen bei großen Blöcken
    //     Bit 1: 0=Controller ist VGA-kompatibel
    //     Bit 0: DAC-Breite: 0=6 Bits; 1=6 oder 8 Bits
    mode_ptr: FarPtr([*]const u16), // 14	Zeiger auf eine Liste mit unterstützten Grafikmodi	4 (FARPTR)	Diese Liste ist ein Array aus 16 Bit großen Einträgen, die jeweils die Nummer eines unterstützten Modus sind. Der letzte Eintrag ist 0xFFFF.
    ram_size: u16, // 18	Größe des Grafikspeichers	2	Die Größe des Grafikspeichers in 64-kB-Blöcken
    oem_sw_rev: BCD(u16), // 20	OEMSoftwareRevision	2
    oem_vendor_name: FarPtr([*:0]const u8), // 22	Zeiger auf OEMVendorNameString	4 (FARPTR)
    oem_product_name: FarPtr([*:0]const u8), // 26	Zeiger auf OEMProductNameString	4 (FARPTR)
    oem_product_rev: FarPtr([*:0]const u8), // 30	Zeiger auf OEMProductRevision	4 (FARPTR)
    reserved: [222]u8, // 34	reserviert	222
    // 256	Datenbereich für OEMStrings	256
    oem_strings: [256]u8,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 512);
    }

    pub const Flags = packed struct(u32) {
        support_8bit_colors: bool,
        not_vga_compatible: bool,
        requires_09h: bool,
        hardware_stereoscopic_support: bool,
        stereo_signalling: bool,
        reserved: u27,
    };
};

pub const ModeInfo = extern struct {
    // Mandatory information for all VBE revisions

    /// mode attributes
    mode_attributes: ModeAttributes,
    /// window A attributes
    win_a_attributes: WinAttributes,
    /// window B attributes
    win_b_attributes: WinAttributes,
    /// window granularity
    win_granularity: u16,
    /// window size
    win_size: u16,
    /// window A start segment
    win_a_segment: u16,
    /// window B start segment
    win_b_segment: u16,
    /// real mode pointer to window function
    win_func_ptr: u32,
    /// bytes per scan line
    bytes_per_scan_line: u16,

    // Mandatory information for VBE 1.2 and above

    /// horizontal resolution in pixels or characters (Pixels in graphics modes, characters in text modes.)
    x_resolution: u16,
    /// vertical resolution in pixels or characters
    y_resolution: u16,
    /// character cell width in pixels
    x_char_size: u8,
    /// character cell height in pixels
    y_char_size: u8,
    /// number of memory planes
    number_of_planes: u8,
    /// bits per pixel
    bits_per_pixel: u8,
    /// number of banks
    number_of_banks: u8,
    /// memory model type
    memory_model: MemoryModel,
    /// bank size in KB
    bank_size: u8,
    /// number of images
    number_of_image_pages: u8,
    /// reserved for page function
    reserved0: u8,

    // Direct Color fields (required for direct/6 and YUV/7 memory models)

    /// size of direct color red mask in bits
    red_mask_size: u8,
    /// bit position of lsb of red mask
    red_field_position: u8,
    /// size of direct color green mask in bits
    green_mask_size: u8,
    /// bit position of lsb of green mask
    green_field_position: u8,
    /// size of direct color blue mask in bits
    blue_mask_size: u8,
    /// bit position of lsb of blue mask
    blue_field_position: u8,
    /// size of direct color reserved mask in bits
    rsvd_mask_size: u8,
    /// bit position of lsb of reserved mask
    rsvd_field_position: u8,
    /// direct color mode attributes
    direct_color_mode_info: u8,

    // Mandatory information for VBE 2.0 and above

    /// physical address for flat memory frame buffer
    phys_base_ptr: [*]u8,
    /// Reserved - always set to 0
    reserved1: u32 = 0,
    /// Reserved - always set to 0
    reserved2: u16 = 0,

    // ; Mandatory information for VBE 3.0 and above

    /// bytes per scan line for linear modes
    lin_bytes_per_scan_line: u16,
    /// number of images for banked modes
    bnk_number_of_image_pages: u8,
    /// number of images for linear modes
    lin_number_of_image_pages: u8,
    /// size of direct color red mask (linear modes)
    lin_red_mask_size: u8,
    /// bit position of lsb of red mask (linear modes)
    lin_red_field_position: u8,
    /// size of direct color green mask (linear modes)
    lin_green_mask_size: u8,
    /// bit position of lsb of green mask (linear modes)
    lin_green_field_position: u8,
    /// size of direct color blue mask (linear modes)
    lin_blue_mask_size: u8,
    /// bit position of lsb of blue mask (linear modes)
    lin_blue_field_position: u8,
    /// size of direct color reserved mask (linear modes)
    lin_rsvd_mask_size: u8,
    /// bit position of lsb of reserved mask (linear modes)
    lin_rsvd_field_position: u8,
    /// maximum pixel clock (in Hz) for graphics mode
    max_pixel_clock: u32,

    reserved3: [189]u8, // remainder of ModeInfoBlock

    pub const ModeAttributes = packed struct(u16) {
        const InverseBool = enum(u1) { yes = 0, no = 1 };

        /// Bit D0 is set to indicate that this mode can be initialized in the present hardware configuration.
        /// This bit is reset to indicate the unavailability of a graphics mode if it requires a certain monitor
        /// type, more memory than is physically installed, etc.
        hardware_support: bool,

        /// Bit D1 was used by VBE 1.0 and 1.1 to indicate that the optional information following the
        /// BytesPerScanLine field were present in the data structure. This information became mandatory
        /// with VBE version 1.2 and above, so D1 is no longer used and should be set to 1. The Direct
        /// Color fields are valid only if the MemoryModel field is set to a 6 (Direct Color) or 7 (YUV).
        reserved0: bool,

        /// Bit D2 indicates whether the video BIOS has support for output functions like TTY output,
        /// scroll, etc. in this mode. TTY support is recommended but not required for all extended text and
        /// graphic modes. If bit D2 is set to 1, then the INT 10h BIOS must support all of the standard
        /// output functions listed below.
        /// All of the following TTY functions must be supported when this bit is set:
        /// - 01 Set Cursor Size
        /// - 02 Set Cursor Position
        /// - 06 Scroll TTY window up or Blank Window
        /// - 07 Scroll TTY window down or Blank Window
        /// - 09 Write character and attribute at cursor position
        /// - 0A Write character only at cursor position
        /// - 0E Write character and advance cursor
        tty_output_supported: bool,

        /// Bit D3 is set to indicate color modes, and cleared for monochrome modes.
        color_mode: enum(u1) { monochrome = 0, color = 1 },

        /// Bit D4 is set to indicate graphics modes, and cleared for text modes.
        mode_type: enum(u1) { text = 0, graphics = 1 },

        /// Bit D5 is used to indicate if the mode is compatible with the VGA hardware registers and I/O
        /// ports. If this bit is set, then the mode is NOT VGA compatible and no assumptions should be
        /// made about the availability of any VGA registers. If clear, then the standard VGA I/O ports and
        /// frame buffer address defined in WinASegment and/or WinBSegment can be assumed.
        vga_compatible: InverseBool,

        /// Bit D6 is used to indicate if the mode provides Windowing or Banking of the frame buffer into
        /// the frame buffer memory region specified by WinASegment and WinBSegment. If set, then
        /// Windowing of the frame buffer is NOT possible. If clear, then the device is capable of mapping
        /// the frame buffer into the segment specified in WinASegment and/or WinBSegment. (This bit is
        /// used in conjunction with bit D7, see table following D7 for usage).
        vga_compatible_windowed_mode_available: InverseBool,

        /// Bit D7 indicates the presence of a Linear Frame Buffer memory model. If this bit is set, the
        /// display controller can be put into a flat memory model by setting the mode (VBE Function 02h)
        /// with the Flat Memory Model bit set. (This bit is used in conjunction with bit D6, see following
        /// table for usage)
        /// ```
        /// |                            | D7 | D6 |
        /// | Windowed frame buffer only | 0  | 0  |
        /// | n/a                        | 0  | 1  |
        /// | Both Windowed and Linear   | 1  | 0  |
        /// | Linear frame buffer only   | 1  | 1  |
        /// ```
        linear_framebuffer_mode_available: bool,

        /// Bit D8 indicates if the video mode can support double scanning or not. If this bit is set, the video
        /// mode can be initialized with the double scan flag set and the vertical resolution of the mode will
        /// be half the value of the vertical CRTC values. Double scanning is necessary to be able to support
        /// 200, 240 and 300 scanline graphics modes on modern controllers. Note that all 200, 240 and 300
        /// scanline modes will have the double scan bit set.
        double_scan_mode_available: bool,

        /// Bit D9 indicates if the video mode can support interlaced operation or not. If this bit is set, the
        /// video mode can be initialized with the interlaced flag set and the controller will be initialized for
        /// an interlaced graphics mode. Note that some controllers may not support interlaced operation, so
        /// you must check this bit before attempting to initialize an interlaced mode.
        interlaced_mode_available: bool,

        /// Bit D10 indicates if the video mode can support hardware triple buffering or not. If this bit is set,
        /// the application program can use Function 4F07h, subfunction 04h to implement hardware triple
        /// buffering. If hardware triple buffering is not supported, the application program may use the new
        /// 02/82h subfunctions to set the display start address, but cannot use subfunction 04h to get status
        /// information on the scheduled display start address change.
        hardware_triple_buffering_support: bool,

        /// Bit D11 indicates if the video mode can support hardware stereoscopic displays or not (for LC
        /// shutter glasses). If this bit is set, the application program can use Function 4F07h, subfunctions
        /// 02h/05/06h/82h to implement hardware stereoscopic display buffering. If bit D12 is also set,
        /// applications can take advantage of dual display start address hardware when present. If bit D10 is
        /// also set, applications can use subfunction 04h to get status information on the scheduled display
        /// start address change. Note that it is possible for hardware to support stereoscopic display
        /// buffering but not support hardware triple buffering.
        hardware_stereoscopic_display_support: bool,

        /// Bit D12 indicates if the video mode can support dual display start addresses or not (for LC shutter
        /// glasses). If this bit is set, the application program can use Function 4F07h, subfunctions 03h/83h
        /// to implement hardware stereoscopic display buffering using the dual display start address
        /// capabilities, allowing the application to directly program the locations of the left and right image
        /// buffers. If this bit is not set, applications will have to ensure that the left and right images are
        /// consecutive in memory as explained in the section on using hardware stereoscopic above.
        dual_display_start_address_support: bool,

        reserved1: u3,
    };

    pub const WinAttributes = packed struct(u8) {
        relocatable_window_support: bool,
        window_readable: bool,
        window_writeable: bool,
        reserved: u5,
    };

    pub const MemoryModel = enum(u8) {
        text_mode = 0, // Text mode
        cga_graphics = 1, // CGA graphics
        hercules_graphics = 2, // Hercules graphics
        planar = 3, // Planar
        packed_pixel = 4, // Packed pixel
        non_chain_4_256_color = 5, // Non-chain 4, 256 color
        direct_color = 6, // Direct Color
        yuv = 7, // YUV
        _,
        // Reserved, to be defined by VESA
        // To be defined by OEM
    };
};

pub fn BCD(comptime Backing: type) type {
    return extern struct {
        raw_value: Backing,

        pub fn format(bcd: @This(), comptime fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = opts;

            comptime var i = 2 * @sizeOf(Backing);
            inline while (i > 0) {
                i -= 1;
                try writer.print("{X:0>1}", .{@truncate(u4, bcd.raw_value >> 4 * i)});
            }
        }
    };
}

pub fn FarPtr(comptime T: type) type {
    return extern struct {
        offset: u16,
        segment: u16,

        pub fn get(fp: @This()) T {
            return @ptrFromInt(T, (@as(usize, fp.segment) << 4) + @as(usize, fp.offset));
        }

        pub fn format(fp: @This(), comptime fmt: []const u8, opts: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = opts;
            try writer.print("{X:0>4}:{X:0>4}", .{ fp.segment, fp.offset });
        }
    };
}
