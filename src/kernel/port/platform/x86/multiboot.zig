const std = @import("std");

pub const Header = extern struct {
    /// The field ‘magic’ is the magic number identifying the header, which must be the hexadecimal value 0x1BADB002.
    magic: u32 = 0x1BADB002,

    flags: Flags,

    /// The field ‘checksum’ is a 32-bit unsigned value which, when added to the other magic fields (i.e. ‘magic’ and ‘flags’), must have a 32-bit unsigned sum of zero.
    checksum: u32 = undefined,

    /// Contains the address corresponding to the beginning of the Multiboot header — the physical memory location at which the magic value is supposed to be loaded. This field serves to synchronize the mapping between OS image offsets and physical memory addresses.
    header_addr: u32,

    /// Contains the physical address of the beginning of the text segment. The offset in the OS image file at which to start loading is defined by the offset at which the header was found, minus (header_addr - load_addr). load_addr must be less than or equal to header_addr.
    load_addr: u32,

    /// Contains the physical address of the end of the data segment. (load_end_addr - load_addr) specifies how much data to load. This implies that the text and data segments must be consecutive in the OS image; this is true for existing a.out executable formats. If this field is zero, the boot loader assumes that the text and data segments occupy the whole OS image file.
    load_end_addr: u32,

    /// Contains the physical address of the end of the bss segment. The boot loader initializes this area to zero, and reserves the memory it occupies to avoid placing boot modules and other data relevant to the operating system in that area. If this field is zero, the boot loader assumes that no bss segment is present.
    bss_end_addr: u32,

    /// The physical address to which the boot loader should jump in order to start running the operating system.
    entry_addr: u32,

    /// Contains ‘0’ for linear graphics mode or ‘1’ for EGA-standard text mode. Everything else is reserved for future expansion. Note that the boot loader may set a text mode even if this field contains ‘0’, or set a video mode even if this field contains ‘1’.
    mode_type: VideoMode,

    /// Contains the number of the columns. This is specified in pixels in a graphics mode, and in characters in a text mode. The value zero indicates that the OS image has no preference.
    width: u32,

    /// Contains the number of the lines. This is specified in pixels in a graphics mode, and in characters in a text mode. The value zero indicates that the OS image has no preference.
    height: u32,

    /// Contains the number of bits per pixel in a graphics mode, and zero in a text mode. The value zero indicates that the OS image has no preference.
    depth: u32,

    const Flags = packed struct(u32) {
        /// If bit 0 in the ‘flags’ word is set, then all boot modules loaded along with the operating system must be aligned on page (4KB) boundaries. Some operating systems expect to be able to map the pages containing boot modules directly into a paged address space during startup, and thus need the boot modules to be page-aligned.
        req_modules_align_4k: bool,

        /// If bit 1 in the ‘flags’ word is set, then information on available memory via at least the ‘mem_*’ fields of the Multiboot information structure (see Boot information format) must be included. If the boot loader is capable of passing a memory map (the ‘mmap_*’ fields) and one exists, then it may be included as well.
        req_mem_info: bool,

        /// If bit 2 in the ‘flags’ word is set, information about the video mode table (see Boot information format) must be available to the kernel.
        req_video_mode: bool,
        padding0: u13 = 0,

        /// If bit 16 in the ‘flags’ word is set, then the fields at offsets 12-28 in the Multiboot header are valid, and the boot loader should use them instead of the fields in the actual executable header to calculate where to load the OS image. This information does not need to be provided if the kernel image is in ELF format, but it must be provided if the images is in a.out format or in some other format. Compliant boot loaders must be able to load images that either are in ELF format or contain the load address information embedded in the Multiboot header; they may also directly support other executable formats, such as particular a.out variants, but are not required to.
        hint_use_embedded_offsets: bool,
        padding1: u15 = 0,
    };

    const VideoMode = enum(u32) {
        linear_fb = 0,
        ega_text_mode = 1,
        _,
    };

    pub fn withChecksum(mb: Header) Header {
        var copy = mb;
        copy.checksum = 0 -% mb.magic -% @as(u32, @bitCast(mb.flags));
        return copy;
    }
};

pub const Info = extern struct {
    /// The first longword indicates the presence and validity of other fields in the Multiboot information structure. All as-yet-undefined bits must be set to zero by the boot loader. Any set bits that the operating system does not understand should be ignored. Thus, the ‘flags’ field also functions as a version indicator, allowing the Multiboot information structure to be expanded in the future without breaking anything.
    flags: Flags,

    /// If bit 0 in the ‘flags’ word is set, then the ‘mem_*’ fields are valid. ‘mem_lower’ and ‘mem_upper’ indicate the amount of lower and upper memory, respectively, in kilobytes. Lower memory starts at address 0, and upper memory starts at address 1 megabyte. The maximum possible value for lower memory is 640 kilobytes. The value returned for upper memory is maximally the address of the first upper memory hole minus 1 megabyte. It is not guaranteed to be this value.
    mem: Memory,

    /// If bit 1 in the ‘flags’ word is set, then the ‘boot_device’ field is valid, and indicates which BIOS disk device the boot loader loaded the OS image from. If the OS image was not loaded from a BIOS disk, then this field must not be present (bit 3 must be clear). The operating system may use this field as a hint for determining its own root device, but is not required to. The ‘boot_device’ field is laid out in four one-byte subfields as follows:
    ///
    /// +-------+-------+-------+-------+
    /// | part3 | part2 | part1 | drive |
    /// +-------+-------+-------+-------+
    /// Least significant             Most significant
    /// The most significant byte contains the BIOS drive number as understood by the BIOS INT 0x13 low-level disk interface: e.g. 0x00 for the first floppy disk or 0x80 for the first hard disk.
    ///
    /// The three remaining bytes specify the boot partition. ‘part1’ specifies the top-level partition number, ‘part2’ specifies a sub-partition in the top-level partition, etc. Partition numbers always start from zero. Unused partition bytes must be set to 0xFF. For example, if the disk is partitioned using a simple one-level DOS partitioning scheme, then ‘part1’ contains the DOS partition number, and ‘part2’ and ‘part3’ are both 0xFF. As another example, if a disk is partitioned first into DOS partitions, and then one of those DOS partitions is subdivided into several BSD partitions using BSD’s disklabel strategy, then ‘part1’ contains the DOS partition number, ‘part2’ contains the BSD sub-partition within that DOS partition, and ‘part3’ is 0xFF.
    ///
    /// DOS extended partitions are indicated as partition numbers starting from 4 and increasing, rather than as nested sub-partitions, even though the underlying disk layout of extended partitions is hierarchical in nature. For example, if the boot loader boots from the second extended partition on a disk partitioned in conventional DOS style, then ‘part1’ will be 5, and ‘part2’ and ‘part3’ will both be 0xFF.
    boot_device: u32,

    /// If bit 2 of the ‘flags’ longword is set, the ‘cmdline’ field is valid, and contains the physical address of the command line to be passed to the kernel. The command line is a normal C-style zero-terminated string. The exact format of command line is left to OS developpers. General-purpose boot loaders should allow user a complete control on command line independently of other factors like image name. Boot loaders with specific payload in mind may completely or partially generate it algorithmically.
    cmdline: [*:0]u8,

    /// If bit 3 of the ‘flags’ is set, then the ‘mods’ fields indicate to the kernel what boot modules were loaded along with the kernel image, and where they can be found. ‘mods_count’ contains the number of modules loaded; ‘mods_addr’ contains the physical address of the first module structure. ‘mods_count’ may be zero, indicating no boot modules were loaded, even if bit 3 of ‘flags’ is set. Each module structure is formatted as follows:
    ///
    ///         +-------------------+
    /// 0       | mod_start         |
    /// 4       | mod_end           |
    ///         +-------------------+
    /// 8       | string            |
    ///         +-------------------+
    /// 12      | reserved (0)      |
    ///         +-------------------+
    /// The first two fields contain the start and end addresses of the boot module itself. The ‘string’ field provides an arbitrary string to be associated with that particular boot module; it is a zero-terminated ASCII string, just like the kernel command line. The ‘string’ field may be 0 if there is no string associated with the module. Typically the string might be a command line (e.g. if the operating system treats boot modules as executable programs), or a pathname (e.g. if the operating system treats boot modules as files in a file system), but its exact use is specific to the operating system. The ‘reserved’ field must be set to 0 by the boot loader and ignored by the operating system.
    mods: Modules,

    /// Caution: Bits 4 & 5 are mutually exclusive.
    ///
    /// If bit 4 in the ‘flags’ word is set, then the following fields in the Multiboot information structure starting at byte 28 are valid:
    ///
    ///         +-------------------+
    /// 28      | tabsize           |
    /// 32      | strsize           |
    /// 36      | addr              |
    /// 40      | reserved (0)      |
    ///         +-------------------+
    /// These indicate where the symbol table from an a.out kernel image can be found. ‘addr’ is the physical address of the size (4-byte unsigned long) of an array of a.out format nlist structures, followed immediately by the array itself, then the size (4-byte unsigned long) of a set of zero-terminated ASCII strings (plus sizeof(unsigned long) in this case), and finally the set of strings itself. ‘tabsize’ is equal to its size parameter (found at the beginning of the symbol section), and ‘strsize’ is equal to its size parameter (found at the beginning of the string section) of the following string table to which the symbol table refers. Note that ‘tabsize’ may be 0, indicating no symbols, even if bit 4 in the ‘flags’ word is set.
    ///
    /// If bit 5 in the ‘flags’ word is set, then the following fields in the Multiboot information structure starting at byte 28 are valid:
    ///
    ///         +-------------------+
    /// 28      | num               |
    /// 32      | size              |
    /// 36      | addr              |
    /// 40      | shndx             |
    ///         +-------------------+
    /// These indicate where the section header table from an ELF kernel is, the size of each entry, number of entries, and the string table used as the index of names. They correspond to the ‘shdr_*’ entries (‘shdr_num’, etc.) in the Executable and Linkable Format (ELF) specification in the program header. All sections are loaded, and the physical address fields of the ELF section header then refer to where the sections are in memory (refer to the i386 ELF documentation for details as to how to read the section header(s)). Note that ‘shdr_num’ may be 0, indicating no symbols, even if bit 5 in the ‘flags’ word is set.
    syms: SymbolInfo,

    /// If bit 6 in the ‘flags’ word is set, then the ‘mmap_*’ fields are valid, and indicate the address and length of a buffer containing a memory map of the machine provided by the BIOS. ‘mmap_addr’ is the address, and ‘mmap_length’ is the total size of the buffer. The buffer consists of one or more of the following size/structure pairs (‘size’ is really used for skipping to the next pair):
    ///
    ///         +-------------------+
    /// -4      | size              |
    ///         +-------------------+
    /// 0       | base_addr         |
    /// 8       | length            |
    /// 16      | type              |
    ///         +-------------------+
    /// where ‘size’ is the size of the associated structure in bytes, which can be greater than the minimum of 20 bytes. ‘base_addr’ is the starting address. ‘length’ is the size of the memory region in bytes. ‘type’ is the variety of address range represented, where a value of 1 indicates available RAM, value of 3 indicates usable memory holding ACPI information, value of 4 indicates reserved memory which needs to be preserved on hibernation, value of 5 indicates a memory which is occupied by defective RAM modules and all other values currently indicated a reserved area.
    ///
    /// The map provided is guaranteed to list all standard RAM that should be available for normal use.
    mmap: MemoryMap,

    /// If bit 7 in the ‘flags’ is set, then the ‘drives_*’ fields are valid, and indicate the address of the physical address of the first drive structure and the size of drive structures. ‘drives_addr’ is the address, and ‘drives_length’ is the total size of drive structures. Note that ‘drives_length’ may be zero. Each drive structure is formatted as follows:
    ///
    ///         +-------------------+
    /// 0       | size              |
    ///         +-------------------+
    /// 4       | drive_number      |
    ///         +-------------------+
    /// 5       | drive_mode        |
    ///         +-------------------+
    /// 6       | drive_cylinders   |
    /// 8       | drive_heads       |
    /// 9       | drive_sectors     |
    ///         +-------------------+
    /// 10 - xx | drive_ports       |
    ///         +-------------------+
    /// The ‘size’ field specifies the size of this structure. The size varies, depending on the number of ports. Note that the size may not be equal to (10 + 2 * the number of ports), because of an alignment.
    ///
    /// The ‘drive_number’ field contains the BIOS drive number. The ‘drive_mode’ field represents the access mode used by the boot loader. Currently, the following modes are defined:
    ///
    /// ‘0’
    /// CHS mode (traditional cylinder/head/sector addressing mode).
    ///
    /// ‘1’
    /// LBA mode (Logical Block Addressing mode).
    ///
    /// The three fields, ‘drive_cylinders’, ‘drive_heads’ and ‘drive_sectors’, indicate the geometry of the drive detected by the BIOS. ‘drive_cylinders’ contains the number of the cylinders. ‘drive_heads’ contains the number of the heads. ‘drive_sectors’ contains the number of the sectors per track.
    ///
    /// The ‘drive_ports’ field contains the array of the I/O ports used for the drive in the BIOS code. The array consists of zero or more unsigned two-bytes integers, and is terminated with zero. Note that the array may contain any number of I/O ports that are not related to the drive actually (such as DMA controller’s ports).
    drives: Drives,

    /// If bit 8 in the ‘flags’ is set, then the ‘config_table’ field is valid, and indicates the address of the ROM configuration table returned by the GET CONFIGURATION BIOS call. If the BIOS call fails, then the size of the table must be zero.
    config_table: u32,

    /// If bit 9 in the ‘flags’ is set, the ‘boot_loader_name’ field is valid, and contains the physical address of the name of a boot loader booting the kernel. The name is a normal C-style zero-terminated string.
    boot_loader_name: [*:0]u8,

    /// If bit 10 in the ‘flags’ is set, the ‘apm_table’ field is valid, and contains the physical address of an APM table defined as below:
    ///
    ///         +----------------------+
    /// 0       | version              |
    /// 2       | cseg                 |
    /// 4       | offset               |
    /// 8       | cseg_16              |
    /// 10      | dseg                 |
    /// 12      | flags                |
    /// 14      | cseg_len             |
    /// 16      | cseg_16_len          |
    /// 18      | dseg_len             |
    ///         +----------------------+
    /// The fields ‘version’, ‘cseg’, ‘offset’, ‘cseg_16’, ‘dseg’, ‘flags’, ‘cseg_len’, ‘cseg_16_len’, ‘dseg_len’ indicate the version number, the protected mode 32-bit code segment, the offset of the entry point, the protected mode 16-bit code segment, the protected mode 16-bit data segment, the flags, the length of the protected mode 32-bit code segment, the length of the protected mode 16-bit code segment, and the length of the protected mode 16-bit data segment, respectively. Only the field ‘offset’ is 4 bytes, and the others are 2 bytes. See Advanced Power Management (APM) BIOS Interface Specification, for more information.
    apm_table: u32,

    /// If bit 11 in the ‘flags’ is set, the VBE table is available.
    vbe: VesaBiosExtensions,

    /// If bit 12 in the ‘flags’ is set, the FRAMEBUFFER table is available.
    framebuffer: Framebuffer,

    pub const Flags = packed struct(u32) {
        mem: bool,
        boot_device: bool,
        cmdline: bool,
        mods: bool,
        syms_v1: bool,
        syms_v2: bool,
        mmap: bool,
        drives: bool,
        config_table: bool,
        boot_loader_name: bool,
        apm_table: bool,
        vbe: bool,
        framebuffer: bool,
        padding: u19,
    };

    pub const SymbolInfo = extern union {
        v1: Version1,
        v2: Version2,
        pub const Version1 = extern struct {
            tabsize: u32,
            strsize: u32,
            addr: u32,
            reserved: u32,
        };
        pub const Version2 = extern struct {
            num: u32,
            size: u32,
            addr: u32,
            shndx: u32,
        };
    };

    pub const Modules = extern struct {
        mods_count: u32,
        mods_addr: u32,
    };

    pub const Memory = extern struct {
        lower: u32,
        upper: u32,
    };

    pub const MemoryMap = extern struct {
        mmap_length: u32,
        mmap_addr: u32,

        const Type = enum(u32) {
            available = 1,
            reserved = 2,
            acpi = 3,
            reservedForHibernation = 4,
            defectiveRAM = 5,
        };

        const Entry = packed struct {
            size: u32,
            baseAddress: u64,
            length: u64,
            type: Type,
        };

        const Iterator = struct {
            end_pos: u32,
            current_pos: u32,

            pub fn next(this: *Iterator) ?*const Entry {
                // official multiboot documentation is bad here :(
                // this is the right way to iterate over the multiboot structure
                if (this.current_pos >= this.end_pos) {
                    return null;
                } else {
                    const current = @as(*const Entry, @ptrFromInt(this.current_pos));
                    this.current_pos += (current.size + 0x04);
                    return current;
                }
            }
        };

        pub fn iterator(this: MemoryMap) Iterator {
            return Iterator{
                .end_pos = this.mmap_addr + this.mmap_length,
                .current_pos = this.mmap_addr,
            };
        }
    };

    pub const Drives = extern struct {
        drives_length: u32,
        drives_addr: u32,
    };

    pub const VesaBiosExtensions = extern struct {
        //! The fields ‘control_info’ and ‘mode_info’ contain the physical addresses of
        //! VBE control information returned by the VBE Function 00h and VBE mode information
        //! returned by the VBE Function 01h, respectively.
        //!
        //! The field `mode’ indicates current video mode in the format specified in VBE 3.0.
        //!
        //! The rest fields ‘interface_seg’, ‘interface_off’, and ‘interface_len’ contain the
        //! table of a protected mode interface defined in VBE 2.0+. If this information is
        //! not available, those fields contain zero. Note that VBE 3.0 defines another
        //! protected mode interface which is incompatible with the old one. If you want to
        //! use the new protected mode interface, you will have to find the table yourself.
        //! The fields for the graphics table are designed for VBE, but Multiboot boot
        //! loaders may simulate VBE on non-VBE modes, as if they were VBE modes.

        control_info: u32,
        mode_info: u32,

        mode: u16,

        interface_seg: u16,
        interface_off: u16,
        interface_len: u16,
    };

    pub const Framebuffer = extern struct {
        //! The field ‘framebuffer_addr’ contains framebuffer physical address. This field is 64-bit wide but bootloader should set it under 4 GiB if possible for compatibility with kernels which aren’t aware of PAE or AMD64. The field ‘framebuffer_pitch’ contains the framebuffer pitch in bytes. The fields ‘framebuffer_width’, ‘framebuffer_height’ contain the framebuffer dimensions in pixels. The field ‘framebuffer_bpp’ contains the number of bits per pixel. If ‘framebuffer_type’ is set to ‘0’ it means indexed color will be used. In this case color_info is defined as follows:
        //!
        //!         +----------------------------------+
        //! 110     | framebuffer_palette_addr         |
        //! 114     | framebuffer_palette_num_colors   |
        //!         +----------------------------------+
        //! ‘framebuffer_palette_addr’ contains the address of the color palette, which is an array of color descriptors. Each color descriptor has the following structure:
        //!
        //!         +-------------+
        //! 0       | red_value   |
        //! 1       | green_value |
        //! 2       | blue_value  |
        //!         +-------------+
        //! If ‘framebuffer_type’ is set to ‘1’ it means direct RGB color will be used. Then color_type is defined as follows:
        //!
        //!         +----------------------------------+
        //! 110     | framebuffer_red_field_position   |
        //! 111     | framebuffer_red_mask_size        |
        //! 112     | framebuffer_green_field_position |
        //! 113     | framebuffer_green_mask_size      |
        //! 114     | framebuffer_blue_field_position  |
        //! 115     | framebuffer_blue_mask_size       |
        //!         +----------------------------------+
        //! If ‘framebuffer_type’ is set to ‘2’ it means EGA-standard text mode will be used. In this case ‘framebuffer_width’ and ‘framebuffer_height’ are expressed in characters instead of pixels. ‘framebuffer_bpp’ is equal to 16 (bits per character) and ‘framebuffer_pitch’ is expressed in bytes per text line. All further values of ‘framebuffer_type’ are reserved for future expansion.

        addr_low: u32,
        addr_high: u32,
        pitch: u32,
        width: u32,
        height: u32,
        bpp: u8,
        type: u8,
        color_info: [5]u8,
    };

    comptime {
        std.debug.assert(@offsetOf(@This(), "mem") == 4);
        std.debug.assert(@offsetOf(@This(), "vbe") == 72);
        std.debug.assert(@offsetOf(@This(), "framebuffer") == 88);
    }

    pub fn format(value: Info, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll("MultibootInfo{");

        if (value.flags.mem) {
            try writer.print("mem={}, ", .{value.mem});
        }
        if (value.flags.boot_device) {
            try writer.print("boot_device={}, ", .{value.boot_device});
        }
        if (value.flags.cmdline) {
            try writer.print("cmdline='{s}', ", .{std.mem.sliceTo(value.cmdline, 0)});
        }
        if (value.flags.mods) {
            try writer.print("mods={}, ", .{value.mods});
        }
        if (value.flags.syms_v1) {
            try writer.print("syms(v1)={}, ", .{value.syms.v1});
        }
        if (value.flags.syms_v2) {
            try writer.print("syms(v2)={}, ", .{value.syms.v2});
        }
        if (value.flags.mmap) {
            try writer.print("mmap={}, ", .{value.mmap});
        }
        if (value.flags.drives) {
            try writer.print("drives={}, ", .{value.drives});
        }
        if (value.flags.config_table) {
            try writer.print("config_table={}, ", .{value.config_table});
        }
        if (value.flags.boot_loader_name) {
            try writer.print("boot_loader_name='{s}', ", .{std.mem.sliceTo(value.boot_loader_name, 0)});
        }
        if (value.flags.apm_table) {
            try writer.print("{}", .{value.apm_table});
            try writer.writeAll(", ");
        }
        if (value.flags.vbe) {
            try writer.print("{}", .{value.vbe});
            try writer.writeAll(", ");
        }
        if (value.flags.framebuffer) {
            try writer.print("{}", .{value.framebuffer});
            try writer.writeAll(", ");
        }

        try writer.writeAll("}");
    }
};
