//!
//! Links:
//! - https://refspecs.linuxbase.org/elf/elf.pdf
//!
const std = @import("std");
const libashet = @import("ashet");

const logger = std.log.scoped(.elf_loader);
const elf = std.elf;

const loader = @import("../loader.zig");
const ashet = @import("../../main.zig");
const system_arch = @import("builtin").target.cpu.arch;

fn missingSection(name: []const u8) error{BadExecutable} {
    logger.err("failed to load executable: No entry for {s} in the DYNAMIC section", .{name});
    return error.BadExecutable;
}

fn dynamic_resolver(a: u32, b: u32, c: u32, d: u32) callconv(.C) void {
    logger.info("a = {}", .{a});
    logger.info("b = {}", .{b});
    logger.info("c = {}", .{c});
    logger.info("d = {}", .{d});
    @panic("hello, dynamic code!");
}

pub fn load(file: *libashet.fs.File) !loader.LoadedExecutable {
    const expected_elf_machine: std.elf.EM = switch (system_arch) {
        .riscv32 => .RISCV,
        .x86 => .@"386",
        .arm, .thumb => .ARM,
        else => @compileError("Unsupported machine type: " ++ @tagName(system_arch)),
    };

    var header = try elf.Header.read(file);

    if (header.endian != .Little)
        return error.InvalidEndian;
    if (header.machine != expected_elf_machine)
        return error.InvalidMachine;
    if (header.is_64 == true)
        return error.InvalidBitSize;
    if (header.phnum == 0)
        return error.NoCode;

    // logger.info("elf header: {}", .{header});

    // Verify that we can load the executable
    const required_bytes: usize = blk: {
        var lo_addr: usize = 0;
        var hi_addr: usize = 0;

        var pheaders = header.program_header_iterator(file);
        while (try pheaders.next()) |phdr| {
            if (phdr.p_type != elf.PT_LOAD)
                continue;

            // logger.info("verifying read={} write={} exec={} offset=0x{X:0>8} vaddr=0x{X:0>8} paddr=0x{X:0>8} memlen={} bytes={} align={}", .{
            //     @boolToInt((phdr.p_flags & elf.PF_R) != 0),
            //     @boolToInt((phdr.p_flags & elf.PF_W) != 0),
            //     @boolToInt((phdr.p_flags & elf.PF_X) != 0),
            //     phdr.p_offset, // file offset
            //     phdr.p_vaddr, // virtual load address
            //     phdr.p_paddr, // physical load address
            //     phdr.p_memsz, // memory size
            //     phdr.p_filesz, // bytes in file
            //     phdr.p_align, // alignment
            // });

            // // check if memory is available
            // var i: usize = 0;
            // while (i < phdr.p_memsz) : (i += ashet.memory.page_size) {
            //     const page_index = ashet.memory.ptrToPage(@intToPtr(?*anyopaque, @intCast(usize, phdr.p_vaddr + i))) orelse return error.NonRamSection;

            //     if (!ashet.memory.isFree(page_index))
            //         return error.MemoryAlreadyUsed;
            // }

            lo_addr = @min(lo_addr, @as(usize, @intCast(phdr.p_vaddr)));
            hi_addr = @max(hi_addr, @as(usize, @intCast(phdr.p_vaddr + phdr.p_memsz)));
        }

        break :blk hi_addr - lo_addr;
    };

    logger.debug("Application is {d} bytes large", .{required_bytes});

    // Decode dynamic section:
    const dynamic_section: ?DynamicSection = dynamic_loader: {
        var pheaders = header.program_header_iterator(file);
        const dynamic_section: elf.Elf64_Phdr = while (try pheaders.next()) |phdr| {
            if (phdr.p_type == elf.PT_DYNAMIC)
                break phdr;
        } else {
            logger.debug("not a dynamic executable", .{});
            break :dynamic_loader null;
        };

        try file.seekableStream().seekTo(dynamic_section.p_offset);

        const ent_count: usize = @intCast(dynamic_section.p_filesz / @sizeOf(elf.Dyn));

        // logger.info("DYNAMIC: {}", .{dynamic_section});
        var dsect: DynamicSection = .{};
        loop: for (0..ent_count) |_| {
            const dyn = try file.reader().readStruct(elf.Dyn);

            switch (dyn.d_tag) {
                elf.DT_NULL => break :loop,
                elf.DT_NEEDED => dsect.needed = dyn.d_val,
                elf.DT_PLTRELSZ => dsect.pltrelsz = dyn.d_val,
                elf.DT_PLTGOT => dsect.pltgot = dyn.d_val,
                elf.DT_HASH => dsect.hash = dyn.d_val,
                elf.DT_STRTAB => dsect.strtab = dyn.d_val,
                elf.DT_SYMTAB => dsect.symtab = dyn.d_val,
                elf.DT_RELA => dsect.rela = dyn.d_val,
                elf.DT_RELASZ => dsect.relasz = dyn.d_val,
                elf.DT_RELAENT => dsect.relaent = dyn.d_val,
                elf.DT_STRSZ => dsect.strsz = dyn.d_val,
                elf.DT_SYMENT => dsect.syment = dyn.d_val,
                elf.DT_INIT => dsect.init = dyn.d_val,
                elf.DT_FINI => dsect.fini = dyn.d_val,
                elf.DT_SONAME => dsect.soname = dyn.d_val,
                elf.DT_RPATH => dsect.rpath = dyn.d_val,
                elf.DT_SYMBOLIC => dsect.symbolic = dyn.d_val,
                elf.DT_REL => dsect.rel = dyn.d_val,
                elf.DT_RELSZ => dsect.relsz = dyn.d_val,
                elf.DT_RELENT => dsect.relent = dyn.d_val,
                elf.DT_PLTREL => dsect.pltrel = dyn.d_val,
                elf.DT_DEBUG => dsect.debug = dyn.d_val,
                elf.DT_TEXTREL => dsect.textrel = dyn.d_val,
                elf.DT_JMPREL => dsect.jmprel = dyn.d_val,
                elf.DT_BIND_NOW => dsect.bind_now = dyn.d_val,
                elf.DT_INIT_ARRAY => dsect.init_array = dyn.d_val,
                elf.DT_FINI_ARRAY => dsect.fini_array = dyn.d_val,
                elf.DT_INIT_ARRAYSZ => dsect.init_arraysz = dyn.d_val,
                elf.DT_FINI_ARRAYSZ => dsect.fini_arraysz = dyn.d_val,
                elf.DT_RUNPATH => dsect.runpath = dyn.d_val,
                elf.DT_FLAGS => dsect.flags = dyn.d_val,
                elf.DT_PREINIT_ARRAY => dsect.preinit_array = dyn.d_val,
                elf.DT_PREINIT_ARRAYSZ => dsect.preinit_arraysz = dyn.d_val,
                elf.DT_SYMTAB_SHNDX => dsect.symtab_shndx = dyn.d_val,
                elf.DT_NUM => dsect.num = dyn.d_val,
                // elf.DT_LOOS => dsect.loos = dyn.d_val,
                // elf.DT_HIOS => dsect.hios = dyn.d_val,
                // elf.DT_LOPROC => dsect.loproc = dyn.d_val,
                // elf.DT_HIPROC => dsect.hiproc = dyn.d_val,
                else => {
                    logger.warn("unsupported DYNAMIC tag {} (value: {})", .{ dyn.d_tag, dyn.d_val });
                },
            }
        }
        break :dynamic_loader dsect;
    };

    const process_memory = try ashet.memory.page_allocator.alignedAlloc(u8, ashet.memory.page_size, required_bytes);
    errdefer ashet.memory.page_allocator.free(process_memory);

    const process_base = @intFromPtr(process_memory.ptr);

    logger.debug("Load application to 0x{X:0>8}", .{process_base});

    // Actually load the exe into memory
    {
        var pheaders = header.program_header_iterator(file);
        while (try pheaders.next()) |phdr| {
            if (phdr.p_type != elf.PT_LOAD) {
                logger.warn("skipping program header: {}", .{phdr});
                continue;
            }

            // logger.info("loading read={} write={} exec={} offset=0x{X:0>8} vaddr=0x{X:0>8} paddr=0x{X:0>8} memlen={} bytes={} align={}", .{
            //     @boolToInt((phdr.p_flags & elf.PF_R) != 0),
            //     @boolToInt((phdr.p_flags & elf.PF_W) != 0),
            //     @boolToInt((phdr.p_flags & elf.PF_X) != 0),
            //     phdr.p_offset, // file offset
            //     phdr.p_vaddr, // virtual load address
            //     phdr.p_paddr, // physical load address
            //     phdr.p_memsz, // memory size
            //     phdr.p_filesz, // bytes in file
            //     phdr.p_align, // alignment
            // });

            const section = process_memory[@as(usize, @intCast(phdr.p_vaddr))..][0..@as(usize, @intCast(phdr.p_memsz))];

            try file.seekableStream().seekTo(phdr.p_offset);
            try file.reader().readNoEof(section[0..@as(usize, @intCast(phdr.p_filesz))]);
        }
    }

    if (dynamic_section) |dsection| {
        logger.debug("DYNAMIC: {}", .{dsection});

        if (dsection.pltgot != null and dsection.pltrel != null) {
            const strtab = dsection.strtab orelse return missingSection("strtab");
            const strsz = dsection.strsz orelse return missingSection("strsz");

            const symtab = dsection.symtab orelse return missingSection("symtab");
            const syment = dsection.syment orelse return missingSection("syment");

            const pltgot = dsection.pltgot orelse return missingSection("pltgot");

            const pltrel = dsection.pltrel orelse return missingSection("pltrel");

            const mode: enum { rel, rela } = switch (pltrel) {
                elf.DT_REL => .rel,
                elf.DT_RELA => .rela,
                else => return error.InvalidPltRel,
            };

            logger.debug("dynamic relocations are of type {}", .{mode});

            const PltGot = extern struct {
                unused: u32,
                arg: u32,
                loader: *const fn (u32, u32, u32, u32) callconv(.C) void,
            };

            var pltgot_val: *PltGot = @ptrFromInt(process_base + pltgot);

            logger.debug("PLTGOT: {}", .{pltgot_val});

            pltgot_val.arg = 1337;
            pltgot_val.loader = dynamic_resolver;

            _ = strtab;
            _ = strsz;
            _ = symtab;
            _ = syment;
        }

        // Available right now:
        // DynamicSection{
        // relevant:
        //   .strtab = 27616,
        //   .strsz = 113,
        //
        //   .symtab = 27536,
        //   .syment = 16,
        //
        //   .pltgot = 30224,
        //   .pltrel = 17,
        //   .pltrelsz = 8,
        //
        // useful later on:
        //   .jmprel = 27732,
        //   .hash = 27592,
        //
        // not relevant:
        //   .needed = 99,
        //   .runpath = 24,
        //   .debug = 0,
        //   .flags = 8,
        // }
    }

    {
        var sheaders = header.section_header_iterator(file);
        while (try sheaders.next()) |shdr| {
            switch (shdr.sh_type) {
                elf.SHT_RELA => {
                    // Shdr{
                    //   .sh_flags = 2,
                    //   .sh_addr = 2155892500,
                    //   .sh_offset = 24340,
                    //   .sh_size = 2520,
                    //   .sh_link = 2,
                    //   .sh_info = 0,
                    //   .sh_addralign = 4,
                    //   .sh_entsize = 12,
                    // }

                    try file.seekableStream().seekTo(shdr.sh_offset);

                    var buffered_reader = std.io.bufferedReaderSize(412, file.reader());

                    var i: usize = 0;
                    while (i < shdr.sh_size / shdr.sh_entsize) : (i += 1) {
                        var entry: elf.Elf32_Rela = undefined;
                        try buffered_reader.reader().readNoEof(std.mem.asBytes(&entry));
                        rela.apply(process_base, process_memory, entry.r_offset, entry.r_info, entry.r_addend);
                    }
                },
                elf.SHT_REL => {
                    // Shdr{
                    //   .sh_flags = 3,
                    //   .sh_addr = 2155930568,
                    //   .sh_offset = 62408,
                    //   .sh_size = 112,
                    //   .sh_link = 5,
                    //   .sh_info = 0,
                    //   .sh_addralign = 4,
                    //   .sh_entsize = 8,
                    // };

                    try file.seekableStream().seekTo(shdr.sh_offset);

                    var buffered_reader = std.io.bufferedReaderSize(412, file.reader());

                    var i: usize = 0;
                    while (i < shdr.sh_size / shdr.sh_entsize) : (i += 1) {
                        var entry: elf.Elf32_Rel = undefined;
                        try buffered_reader.reader().readNoEof(std.mem.asBytes(&entry));
                        rela.apply(process_base, process_memory, entry.r_offset, entry.r_info, null);
                    }
                },
                elf.SHT_DYNAMIC => {
                    logger.info("DYNAMIC shdr {}", .{shdr});
                    //
                },

                // ignore these, we don't need them
                std.elf.SHT_PROGBITS, std.elf.SHT_SYMTAB, std.elf.SHT_DYNSYM, std.elf.SHT_STRTAB => {},

                std.elf.SHT_NOBITS => {
                    // initialize .bss section:
                    const base = @as(usize, @intCast(shdr.sh_addr));
                    const size = @as(usize, @intCast(shdr.sh_size));
                    @memset(process_memory[base .. base + size], 0);
                },

                else => logger.info("unhandled section header: {s}", .{switch (shdr.sh_type) {
                    std.elf.SHT_NULL => "SHT_NULL",
                    std.elf.SHT_PROGBITS => "SHT_PROGBITS",
                    std.elf.SHT_SYMTAB => "SHT_SYMTAB",
                    std.elf.SHT_STRTAB => "SHT_STRTAB",
                    std.elf.SHT_RELA => "SHT_RELA",
                    std.elf.SHT_HASH => "SHT_HASH",
                    std.elf.SHT_DYNAMIC => "SHT_DYNAMIC",
                    std.elf.SHT_NOTE => "SHT_NOTE",
                    std.elf.SHT_NOBITS => "SHT_NOBITS",
                    std.elf.SHT_REL => "SHT_REL",
                    std.elf.SHT_SHLIB => "SHT_SHLIB",
                    std.elf.SHT_DYNSYM => "SHT_DYNSYM",
                    std.elf.SHT_INIT_ARRAY => "SHT_INIT_ARRAY",
                    std.elf.SHT_FINI_ARRAY => "SHT_FINI_ARRAY",
                    std.elf.SHT_PREINIT_ARRAY => "SHT_PREINIT_ARRAY",
                    std.elf.SHT_GROUP => "SHT_GROUP",
                    std.elf.SHT_SYMTAB_SHNDX => "SHT_SYMTAB_SHNDX",
                    std.elf.SHT_LOOS => "SHT_LOOS",
                    std.elf.SHT_HIOS => "SHT_HIOS",
                    std.elf.SHT_LOPROC => "SHT_LOPROC",
                    std.elf.SHT_HIPROC => "SHT_HIPROC",
                    std.elf.SHT_LOUSER => "SHT_LOUSER",
                    std.elf.SHT_HIUSER => "SHT_HIUSER",
                    else => "unknown",
                }}),
            }
        }
    }

    const entry_point = process_base + @as(usize, @intCast(header.entry));

    logger.info("loaded to address 0x{X:0>8}, entry point is 0x{X:0>8}", .{
        process_base,
        entry_point,
    });

    return .{
        .process_memory = process_memory,
        .entry_point = entry_point,
    };
}

const Elf32_Addr = std.elf.Elf32_Addr;
const Elf32_Word = std.elf.Elf32_Word;
const Elf32_Sword = std.elf.Elf32_Sword;

const rela: type = switch (system_arch) {
    .riscv32 => struct {
        // https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-elf.adoc
        // A - Addend field in the relocation entry associated with the symbol
        // B - Base address of a shared object loaded into memory
        const R_RISCV_NONE = 0;
        const R_RISCV_32 = 1;
        const R_RISCV_64 = 2;
        const R_RISCV_RELATIVE = 3; // B + A Relocation against a local symbol in a shared object,

        pub fn apply(process_base: usize, process_memory: []align(ashet.memory.page_size) u8, offset: Elf32_Addr, info: Elf32_Word, addend: ?Elf32_Sword) void {
            switch (info) {
                R_RISCV_RELATIVE => {
                    // logger.err("apply rela: offset={x:0>8} addend={x}", .{ entry.r_offset, entry.r_addend });

                    const reloc_area = process_memory[@as(usize, @intCast(offset))..][0..@sizeOf(usize)];

                    const actual_added = @as(u32, @bitCast(addend orelse std.mem.readIntLittle(i32, reloc_area))); // abusing the fact that a u32 and i32 are interchangible when doing wraparound addition
                    std.mem.writeIntLittle(
                        usize,
                        reloc_area,
                        process_base +% actual_added,
                    );
                },

                else => logger.err("unhandled rv32 rela: info={} offset={x:0>8} addend={?x:0>8}", .{
                    info,
                    offset,
                    addend,
                }),
            }
        }
    },
    .x86 => struct {
        //! https://docs.oracle.com/cd/E19683-01/817-3677/chapter6-26/index.html

        const RelocationType = enum(u8) {
            none = 0, //     None       None

            @"32" = 1, //    word32     S + A

            pc32 = 2, //     word32     S + A - P

            /// Computes the distance from the base of the global offset table to the symbol's global offset table entry. It also instructs the link-editor to create a global offset table.
            got32 = 3, //    word32     G + A

            /// Computes the address of the symbol's procedure linkage table entry and instructs the link-editor to create a procedure linkage table.
            plt32 = 4, //    word32     L + A - P

            /// Created by the link-editor for dynamic executables to preserve a read-only text segment.
            /// Its offset member refers to a location in a writable segment. The symbol table index
            /// specifies a symbol that should exist both in the current object file and in a shared object.
            /// During execution, the runtime linker copies data associated with the shared object's symbol
            /// to the location specified by the offset. See Copy Relocations.
            copy = 5, //     None       None

            /// Used to set a global offset table entry to the address of the specified symbol. The special
            /// relocation type enable you to determine the correspondence between symbols and global offset table entries
            glob_dat = 6, // word32     S

            /// Created by the lirocednk-editor for dynamic objects to provide lazy binding. Its offset member
            /// gives the location of a pure linkage table entry. The runtime linker modifies the
            /// procedure linkage table entry to transfer control to the designated symbol address
            jmp_slot = 7, // word32     S

            /// Created by the link-editor for dynamic objects. Its offset member gives the location within
            /// a shared object that contains a value representing a relative address. The runtime linker
            /// computes the corresponding virtual address by adding the virtual address at which the shared
            /// object is loaded to the relative address. Relocation entries for this type must specify 0 for
            /// the symbol table index.
            relative = 8, // word32     B + A

            /// Computes the difference between a symbol's value and the address of the global offset table. It also
            /// instructs the link-editor to create the global offset table.
            gotoff = 9, //   word32     S + A - GOT

            /// Resembles R_386_PC32, except that it uses the address of the global offset table in its calculation.
            /// The symbol referenced in this relocation normally is _GLOBAL_OFFSET_TABLE_, which also instructs the
            /// link-editor to create the global offset table.
            gotpc = 10, //   word32     GOT + A - P

            @"32plt" = 11, //   word32     L + A

            _,
        };

        pub fn apply(process_base: usize, process_memory: []align(ashet.memory.page_size) u8, offset: Elf32_Addr, _info: Elf32_Word, addend: ?Elf32_Sword) void {
            const Info = packed struct(Elf32_Word) {
                type: RelocationType,
                symbol: u24,
            };

            const info: Info = @bitCast(_info);

            logger.debug("applying rela type={}, symbol={} to 0x{X:0>8}, added={?}", .{ info.type, info.symbol, offset, addend });

            const reloc_memory: *anyopaque = &process_memory[@as(usize, @intCast(offset))];
            switch (info.type) {
                .none => logger.warn("Found invalid R_386_NONE relocation", .{}),

                .@"32" => @panic("Implement R_386_32 relocation"),
                .pc32 => @panic("Implement R_386_PC32 relocation"),
                .got32 => @panic("Implement R_386_GOT32 relocation"),
                .plt32 => @panic("Implement R_386_PLT32 relocation"),
                .copy => @panic("Implement R_386_COPY relocation"),
                .glob_dat => @panic("Implement R_386_GLOB_DAT relocation"),
                .relative => {
                    const value: *isize = @ptrCast(@alignCast(reloc_memory));
                    const actual_added = addend orelse value.*;
                    value.* = @bitCast(
                        process_base +% @as(usize, @bitCast(actual_added)), // abusing the fact that a u32 and i32 are interchangible when doing wraparound addition
                    );
                },
                .gotoff => @panic("Implement R_386_GOTOFF relocation"),
                .gotpc => @panic("Implement R_386_GOTPC relocation"),
                .@"32plt" => @panic("Implement R_386_32PLT relocation"),

                .jmp_slot => { // word32 S
                    // The link editor creates this relocation type for dynamic linking. Its offset
                    // member gives the location of a procedure linkage table entry. The dynamic
                    // linker modifies the procedure linkage table entry to transfer control to the
                    // designated symbol's address [see "Procedure Linkage Table'' below].
                    // @panic("implement jmp_slot rela");
                },

                _ => logger.err("undefined x86 rela: type={} symbol={} offset={x:0>8} addend={?x:0>8}", .{
                    @intFromEnum(info.type),
                    info.symbol,
                    offset,
                    addend,
                }),
            }
        }
    },

    .thumb => @panic("TODO: Implement app loading on arm!"),

    else => @compileError("Unsupported machine type: " ++ @tagName(system_arch)),
};

const DynamicSection = struct {
    //! https://refspecs.linuxbase.org/elf/gabi4+/ch5.dynamic.html

    /// This element holds the string table offset of a null-terminated string, giving the name of a needed library. The offset is an index into the table recorded in the DT_STRTAB code. See ``Shared Object Dependencies'' for more information about these names. The dynamic array may contain multiple entries with this type. These entries' relative order is significant, though their relation to entries of other types is not.
    needed: ?usize = null,

    /// This element holds the total size, in bytes, of the relocation entries associated with the procedure linkage table. If an entry of type DT_JMPREL is present, a DT_PLTRELSZ must accompany it.
    pltrelsz: ?usize = null,

    /// This element holds an address associated with the procedure linkage table and/or the global offset table. See this section in the processor supplement for details.
    pltgot: ?usize = null,

    /// This element holds the address of the symbol hash table, described in ``Hash Table''. This hash table refers to the symbol table referenced by the DT_SYMTAB element.
    hash: ?usize = null,

    /// This element holds the address of the string table, described in Chapter 4. Symbol names, library names, and other strings reside in this table.
    strtab: ?usize = null,

    /// This element holds the address of the symbol table, described in the first part of this chapter, with Elf32_Sym entries for the 32-bit class of files and Elf64_Sym entries for the 64-bit class of files.
    symtab: ?usize = null,

    /// This element holds the address of a relocation table, described in Chapter 4. Entries in the table have explicit addends, such as Elf32_Rela for the 32-bit file class or Elf64_Rela for the 64-bit file class. An object file may have multiple relocation sections. When building the relocation table for an executable or shared object file, the link editor catenates those sections to form a single table. Although the sections remain independent in the object file, the dynamic linker sees a single table. When the dynamic linker creates the process image for an executable file or adds a shared object to the process image, it reads the relocation table and performs the associated actions. If this element is present, the dynamic structure must also have DT_RELASZ and DT_RELAENT elements. When relocation is ``mandatory'' for a file, either DT_RELA or DT_REL may occur (both are permitted but not required).
    rela: ?usize = null,

    /// This element holds the total size, in bytes, of the DT_RELA relocation table.
    relasz: ?usize = null,

    /// This element holds the size, in bytes, of the DT_RELA relocation entry.
    relaent: ?usize = null,

    /// This element holds the size, in bytes, of the string table.
    strsz: ?usize = null,

    /// This element holds the size, in bytes, of a symbol table entry.
    syment: ?usize = null,

    /// This element holds the address of the initialization function, discussed in ``Initialization and Termination Functions'' below.
    init: ?usize = null,

    /// This element holds the address of the termination function, discussed in ``Initialization and Termination Functions'' below.
    fini: ?usize = null,

    /// This element holds the string table offset of a null-terminated string, giving the name of the shared object. The offset is an index into the table recorded in the DT_STRTAB entry. See ``Shared Object Dependencies'' below for more information about these names.
    soname: ?usize = null,

    /// This element holds the string table offset of a null-terminated search library search path string discussed in ``Shared Object Dependencies''. The offset is an index into the table recorded in the DT_STRTAB entry. This entry is at level 2. Its use has been superseded by DT_RUNPATH.
    rpath: ?usize = null,

    /// This element's presence in a shared object library alters the dynamic linker's symbol resolution algorithm for references within the library. Instead of starting a symbol search with the executable file, the dynamic linker starts from the shared object itself. If the shared object fails to supply the referenced symbol, the dynamic linker then searches the executable file and other shared objects as usual. This entry is at level 2. Its use has been superseded by the DF_SYMBOLIC flag.
    symbolic: ?usize = null,

    // This element is similar to DT_RELA, except its table has implicit addends, such as Elf32_Rel for the 32-bit file class or Elf64_Rel for the 64-bit file class. If this element is present, the dynamic structure must also have DT_RELSZ and DT_RELENT elements.
    rel: ?usize = null,

    /// This element holds the total size, in bytes, of the DT_REL relocation table.
    relsz: ?usize = null,

    /// This element holds the size, in bytes, of the DT_REL relocation entry.
    relent: ?usize = null,

    /// This member specifies the type of relocation entry to which the procedure linkage table refers. The d_val member holds DT_REL or DT_RELA, as appropriate. All relocations in a procedure linkage table must use the same relocation.
    pltrel: ?usize = null,

    /// This member is used for debugging. Its contents are not specified for the ABI; programs that access this entry are not ABI-conforming.
    debug: ?usize = null,

    /// This member's absence signifies that no relocation entry should cause a modification to a non-writable segment, as specified by the segment permissions in the program header table. If this member is present, one or more relocation entries might request modifications to a non-writable segment, and the dynamic linker can prepare accordingly. This entry is at level 2. Its use has been superseded by the DF_TEXTREL flag.
    textrel: ?usize = null,

    /// If present, this entry's d_ptr member holds the address of relocation entries associated solely with the procedure linkage table. Separating these relocation entries lets the dynamic linker ignore them during process initialization, if lazy binding is enabled. If this entry is present, the related entries of types DT_PLTRELSZ and DT_PLTREL must also be present.
    jmprel: ?usize = null,

    /// If present in a shared object or executable, this entry instructs the dynamic linker to process all relocations for the object containing this entry before transferring control to the program. The presence of this entry takes precedence over a directive to use lazy binding for this object when specified through the environment or via dlopen(BA_LIB). This entry is at level 2. Its use has been superseded by the DF_BIND_NOW flag.
    bind_now: ?usize = null,

    /// This element holds the address of the array of pointers to initialization functions, discussed in ``Initialization and Termination Functions'' below.
    init_array: ?usize = null,

    /// This element holds the address of the array of pointers to termination functions, discussed in ``Initialization and Termination Functions'' below.
    fini_array: ?usize = null,

    /// This element holds the size in bytes of the array of initialization functions pointed to by the DT_INIT_ARRAY entry. If an object has a DT_INIT_ARRAY entry, it must also have a DT_INIT_ARRAYSZ entry.
    init_arraysz: ?usize = null,

    /// This element holds the size in bytes of the array of termination functions pointed to by the DT_FINI_ARRAY entry. If an object has a DT_FINI_ARRAY entry, it must also have a DT_FINI_ARRAYSZ entry.
    fini_arraysz: ?usize = null,

    /// This element holds the string table offset of a null-terminated library search path string discussed in ``Shared Object Dependencies''. The offset is an index into the table recorded in the DT_STRTAB entry.
    runpath: ?usize = null,

    /// This element holds flag values specific to the object being loaded. Each flag value will have the name DF_flag_name. Defined values and their meanings are described below. All other values are reserved.
    flags: ?usize = null,

    /// This element holds the address of the array of pointers to pre-initialization functions, discussed in ``Initialization and Termination Functions'' below. The DT_PREINIT_ARRAY table is processed only in an executable file; it is ignored if contained in a shared object.
    preinit_array: ?usize = null,

    /// This element holds the size in bytes of the array of pre-initialization functions pointed to by the DT_PREINIT_ARRAY entry. If an object has a DT_PREINIT_ARRAY entry, it must also have a DT_PREINIT_ARRAYSZ entry. As with DT_PREINIT_ARRAY, this entry is ignored if it appears in a shared object.
    preinit_arraysz: ?usize = null,

    ///
    symtab_shndx: ?usize = null,

    ///
    num: ?usize = null,

    // ///
    // loos: ?usize = null,

    // ///
    // hios: ?usize = null,

    // ///
    // loproc: ?usize = null,

    // ///
    // hiproc: ?usize = null,
};
