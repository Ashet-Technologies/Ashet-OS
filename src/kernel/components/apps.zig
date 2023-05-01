const std = @import("std");
const ashet = @import("../main.zig");
const libashet = @import("ashet");
const logger = std.log.scoped(.s);
const system_arch = @import("builtin").target.cpu.arch;

pub const AppID = struct {
    name: []const u8,

    fn getName(app: AppID) []const u8 {
        return app.name;
    }
};

pub fn startApp(app: AppID) !void {
    return startAppElf(app);
}

pub fn startAppElf(app: AppID) !void {
    const expected_elf_machine: std.elf.EM = switch (system_arch) {
        .riscv32 => .RISCV,
        .x86 => .@"386",
        else => @compileError("Unsupported machine type: " ++ @tagName(system_arch)),
    };

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

                        const reloc_area = process_memory[@intCast(usize, offset)..][0..@sizeOf(usize)];

                        const actual_added = @bitCast(u32, addend orelse std.mem.readIntLittle(i32, reloc_area)); // abusing the fact that a u32 and i32 are interchangible when doing wraparound addition
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

            const R_386_NONE = 0; //     None       None

            const R_386_32 = 1; //       word32     S + A

            const R_386_PC32 = 2; //     word32     S + A - P

            /// Computes the distance from the base of the global offset table to the symbol's global offset table entry. It also instructs the link-editor to create a global offset table.
            const R_386_GOT32 = 3; //    word32     G + A

            /// Computes the address of the symbol's procedure linkage table entry and instructs the link-editor to create a procedure linkage table.
            const R_386_PLT32 = 4; //    word32     L + A - P

            /// Created by the link-editor for dynamic executables to preserve a read-only text segment.
            /// Its offset member refers to a location in a writable segment. The symbol table index
            /// specifies a symbol that should exist both in the current object file and in a shared object.
            /// During execution, the runtime linker copies data associated with the shared object's symbol
            /// to the location specified by the offset. See Copy Relocations.
            const R_386_COPY = 5; //     None       None

            /// Used to set a global offset table entry to the address of the specified symbol. The special
            /// relocation type enable you to determine the correspondence between symbols and global offset table entries
            const R_386_GLOB_DAT = 6; // word32     S

            /// Created by the link-editor for dynamic objects to provide lazy binding. Its offset member
            /// gives the location of a procedure linkage table entry. The runtime linker modifies the
            /// procedure linkage table entry to transfer control to the designated symbol address
            const R_386_JMP_SLOT = 7; // word32     S

            /// Created by the link-editor for dynamic objects. Its offset member gives the location within
            /// a shared object that contains a value representing a relative address. The runtime linker
            /// computes the corresponding virtual address by adding the virtual address at which the shared
            /// object is loaded to the relative address. Relocation entries for this type must specify 0 for
            /// the symbol table index.
            const R_386_RELATIVE = 8; // word32     B + A

            /// Computes the difference between a symbol's value and the address of the global offset table. It also
            /// instructs the link-editor to create the global offset table.
            const R_386_GOTOFF = 9; //   word32     S + A - GOT

            /// Resembles R_386_PC32, except that it uses the address of the global offset table in its calculation.
            /// The symbol referenced in this relocation normally is _GLOBAL_OFFSET_TABLE_, which also instructs the
            /// link-editor to create the global offset table.
            const R_386_GOTPC = 10; //   word32     GOT + A - P

            const R_386_32PLT = 11; //   word32     L + A

            pub fn apply(process_base: usize, process_memory: []align(ashet.memory.page_size) u8, offset: Elf32_Addr, info: Elf32_Word, addend: ?Elf32_Sword) void {
                switch (info) {
                    // rela.R_RISCV_RELATIVE => {
                    //     // logger.err("apply rela: offset={x:0>8} addend={x}", .{ entry.r_offset, entry.r_addend });

                    //     std.mem.writeIntLittle(
                    //         usize,
                    //         process_memory[@intCast(usize, entry.r_offset)..][0..@sizeOf(usize)],
                    //         process_base +% @bitCast(u32, entry.r_addend), // abusing the fact that a u32 and i32 are interchangible when doing wraparound addition
                    //     );
                    // },

                    R_386_NONE => @panic("Implement R_386_NONE relocation"),
                    R_386_32 => @panic("Implement R_386_32 relocation"),
                    R_386_PC32 => @panic("Implement R_386_PC32 relocation"),
                    R_386_GOT32 => @panic("Implement R_386_GOT32 relocation"),
                    R_386_PLT32 => @panic("Implement R_386_PLT32 relocation"),
                    R_386_COPY => @panic("Implement R_386_COPY relocation"),
                    R_386_GLOB_DAT => @panic("Implement R_386_GLOB_DAT relocation"),
                    R_386_JMP_SLOT => @panic("Implement R_386_JMP_SLOT relocation"),
                    R_386_RELATIVE => {
                        const reloc_area = process_memory[@intCast(usize, offset)..][0..@sizeOf(usize)];

                        const actual_added = addend orelse std.mem.readIntLittle(i32, reloc_area);
                        std.mem.writeIntLittle(
                            usize,
                            reloc_area,
                            process_base +% @bitCast(u32, actual_added), // abusing the fact that a u32 and i32 are interchangible when doing wraparound addition
                        );
                    },
                    R_386_GOTOFF => @panic("Implement R_386_GOTOFF relocation"),
                    R_386_GOTPC => @panic("Implement R_386_GOTPC relocation"),
                    R_386_32PLT => @panic("Implement R_386_32PLT relocation"),

                    else => logger.err("unhandled rv32 rela: info={} offset={x:0>8} addend={?x:0>8}", .{
                        info,
                        offset,
                        addend,
                    }),
                }
            }
        },
        else => @compileError("Unsupported machine type: " ++ @tagName(system_arch)),
    };

    const elf = std.elf;

    var root_dir = try libashet.fs.Directory.openDrive(.system, "apps");
    defer root_dir.close();

    var app_dir = try root_dir.openDir(app.getName());
    defer app_dir.close();

    var file = try app_dir.openFile("code", .read_only, .open_existing);
    defer file.close();

    var header = try elf.Header.read(&file);

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

        var pheaders = header.program_header_iterator(&file);
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

            lo_addr = std.math.min(lo_addr, @intCast(usize, phdr.p_vaddr));
            hi_addr = std.math.max(hi_addr, @intCast(usize, phdr.p_vaddr + phdr.p_memsz));
        }

        break :blk hi_addr - lo_addr;
    };

    const process_memory = try ashet.memory.page_allocator.alignedAlloc(u8, ashet.memory.page_size, required_bytes);
    errdefer ashet.memory.page_allocator.free(process_memory);

    const process_base = @ptrToInt(process_memory.ptr);

    // Actually load the exe into memory
    {
        var pheaders = header.program_header_iterator(&file);
        while (try pheaders.next()) |phdr| {
            if (phdr.p_type != elf.PT_LOAD)
                continue;

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

            const section = process_memory[@intCast(usize, phdr.p_vaddr)..][0..@intCast(usize, phdr.p_memsz)];

            try file.seekableStream().seekTo(phdr.p_offset);
            try file.reader().readNoEof(section[0..@intCast(usize, phdr.p_filesz)]);
        }
    }

    {
        var sheaders = header.section_header_iterator(&file);
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
                    std.log.info("DYNAMIC shdr {}", .{shdr});
                    //
                },

                // ignore these, we don't need them
                std.elf.SHT_PROGBITS, std.elf.SHT_SYMTAB, std.elf.SHT_DYNSYM, std.elf.SHT_STRTAB => {},

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

    const entry_point = process_base + @intCast(usize, header.entry);

    logger.info("loaded {s} to address 0x{X:0>8}, entry point is 0x{X:0>8}", .{
        app.getName(),
        process_base,
        entry_point,
    });

    try spawnApp(app, process_memory, entry_point);
}

pub fn startAppBinary(app: AppID) !void {
    var path_buffer: [ashet.abi.max_path]u8 = undefined;
    const app_path = try std.fmt.bufPrint(&path_buffer, "SYS:/apps/{s}/code", .{app.getName()});

    const stat = try ashet.filesystem.stat(app_path);

    const proc_byte_size = stat.size;
    const proc_page_size = std.mem.alignForward(proc_byte_size, ashet.memory.page_size);
    const proc_page_count = ashet.memory.getRequiredPages(proc_page_size);

    const app_pages = try ashet.memory.allocPages(proc_page_count);
    errdefer ashet.memory.freePages(app_pages, proc_page_count);

    const process_memory = @ptrCast([*]align(ashet.memory.page_size) u8, ashet.memory.pageToPtr(app_pages))[0..proc_page_size];

    logger.info("process {s} will be loaded at {*} with {d} bytes size ({d} pages at {d})", .{
        app.getName(),
        process_memory,
        proc_page_size,
        proc_page_count,
        app_pages,
    });

    {
        var file = try ashet.filesystem.open(app_path, .read_only, .open_existing);
        defer ashet.filesystem.close(file);

        const len = try ashet.filesystem.read(file, process_memory[0..proc_byte_size]);
        if (len != proc_byte_size)
            @panic("could not read all bytes on one go!");
    }

    try spawnApp(app, process_memory, @ptrToInt(process_memory.ptr));
}

fn spawnApp(app: AppID, process_memory: []align(ashet.memory.page_size) u8, entry_point: usize) !void {
    const process = try ashet.multi_tasking.Process.spawn(
        app.getName(),
        process_memory,
        @intToPtr(ashet.scheduler.ThreadFunction, entry_point),
        null,
        .{ .stack_size = 512 * 1024 },
    );
    errdefer process.kill();
}
