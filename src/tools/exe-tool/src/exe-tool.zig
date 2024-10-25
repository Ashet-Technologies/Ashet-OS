const std = @import("std");
const args_parser = @import("args");
const ashex = @import("ashex.zig");

const logger = std.log;
const elf = std.elf;

const PF_ASHETOS_NOLOAD = 0x0_01_00000;

comptime {
    std.debug.assert((PF_ASHETOS_NOLOAD & ~@as(elf.Elf32_Addr, elf.PF_MASKOS)) == 0);
}

const CliOptions = struct {
    help: bool = false,
    verbose: bool = true,
    output: []const u8 = "",
    icon: ?[]const u8 = null,

    pub const shorthands = .{
        .o = "output",
        .h = "help",
    };

    pub const meta = .{
        .usage_summary = "[-h] -o <output> [--icon <path>] <elf file>",
        .full_text =
        \\Converts an ELF file that contains an executable for Ashet OS into a Ashet Executable (.ashex) file.
        \\
        \\Can additionally embed an icon.
        ,
        .option_docs = .{
            .output = "Defines the output path of the generated .ashex file.",
            .help = "Prints this help to stdout",
            .icon = "Path to a Ashet Bitmap File (.abm) which contains the application icon.",
            .verbose = "Prints debugging information",
        },
    };
};

pub const std_options = std.Options{
    .logFn = write_log,
};

var verbose_logging: bool = false;

pub fn write_log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    switch (message_level) {
        .debug, .info => if (!verbose_logging)
            return,
        .warn, .err => {},
    }
    std.log.defaultLog(message_level, scope, format, args);
}

fn print_usage(exe_name: ?[]const u8, target: std.fs.File) !void {
    try args_parser.printHelp(
        CliOptions,
        exe_name orelse "ashet-exe",
        target.writer(),
    );
}

pub fn main() !u8 {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();

    const allocator = arena_allocator.allocator();

    var cli_args = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli_args.deinit();

    verbose_logging = cli_args.options.verbose;

    if (cli_args.options.help) {
        try print_usage(cli_args.executable_name, std.io.getStdOut());
        return 0;
    }

    if (cli_args.positionals.len != 1) {
        try print_usage(cli_args.executable_name, std.io.getStdErr());
        return 1;
    }

    if (cli_args.options.output.len == 0) {
        try print_usage(cli_args.executable_name, std.io.getStdErr());
        return 1;
    }

    const input_file_path = cli_args.positionals[0];
    const icon_file_path = cli_args.options.icon;
    const output_file_path = cli_args.options.output;

    const input_file_data = try std.fs.cwd().readFileAlloc(
        allocator,
        input_file_path,
        @min(std.math.maxInt(usize), 4 << 30), // We can't support more than 4 GiB anyways
    );

    const icon_file_data = if (icon_file_path) |path|
        try std.fs.cwd().readFileAlloc(
            allocator,
            path,
            @min(std.math.maxInt(usize), 1 << 20), // 1 MiB should be enough for everyone!
        )
    else
        null;

    const ashex_file = try parse_elf_file(allocator, input_file_data);

    // Optimize relocation size
    for (ashex_file.relocations) |*reloc| {
        if (reloc.type.addend != .unused and reloc.addend == 0) {
            reloc.type.addend = .unused;
        }
    }

    logger.info("platform:      {s}", .{@tagName(ashex_file.platform)});
    logger.info("virtual size:  0x{X:0>8}", .{ashex_file.vmem_size});
    logger.info("entry point:   0x{X:0>8}", .{ashex_file.entry_point});
    logger.info("relocations:   {d}", .{ashex_file.relocations.len});
    for (ashex_file.relocations) |relocation| {
        logger.info("  - {}", .{relocation});
    }
    logger.info("bss sections:  {d}", .{ashex_file.bss_headers.len});
    for (ashex_file.bss_headers) |load_hdr| {
        logger.info("  - offset=0x{X:0>8}, size=0x{X:0>8}", .{
            load_hdr.vmem_offset,
            load_hdr.length,
        });
    }
    logger.info("load sections: {d}", .{ashex_file.load_headers.len});
    for (ashex_file.load_headers) |load_hdr| {
        logger.info("  - offset=0x{X:0>8}, size=0x{X:0>8}", .{
            load_hdr.vmem_offset,
            load_hdr.data.len,
        });
    }
    logger.info("syscalls:      {d}", .{ashex_file.syscalls.len});
    for (ashex_file.syscalls) |syscall| {
        logger.info("  - {s}", .{syscall});
    }

    {
        var file = try std.fs.cwd().createFile(output_file_path, .{});
        defer file.close();

        try write_ashex_file(
            file,
            ashex_file,
            icon_file_data,
        );
    }

    return 0;
}

fn parse_elf_file(
    allocator: std.mem.Allocator,
    elf_binary_data: []const u8,
) !AshexFile {
    var elf_stream_obj = std.io.fixedBufferStream(elf_binary_data);
    const elf_stream = &elf_stream_obj;

    const header = try elf.Header.read(elf_stream);

    if (header.endian != .little)
        return error.InvalidEndian;
    if (header.is_64 == true)
        return error.InvalidBitSize;
    if (header.phnum == 0)
        return error.NoCode;

    const platform: ashex.Platform = switch (header.machine) {
        .RISCV => .riscv32,
        .@"386" => .x86,
        .ARM => .arm32,
        else => return error.UnsupportedMachine,
    };

    const ProgramHeader = struct {
        type: enum(elf.Elf32_Word) {
            null = elf.PT_NULL,
            load = elf.PT_LOAD,
            dynamic = elf.PT_DYNAMIC,
            interp = elf.PT_INTERP,
            note = elf.PT_NOTE,
            shlib = elf.PT_SHLIB,
            phdr = elf.PT_PHDR,
            tls = elf.PT_TLS,
            num = elf.PT_NUM,

            gnu_eh_frame = elf.PT_GNU_EH_FRAME,
            gnu_stack = elf.PT_GNU_STACK,
            gnu_relro = elf.PT_GNU_RELRO,
            sunwbss = elf.PT_SUNWBSS,
            sunwstack = elf.PT_SUNWSTACK,

            _,
        },
        flags: packed struct(elf.Elf32_Off) {
            executable: bool, // 1
            writable: bool, // 2
            readable: bool, // 4
            _reserved: u17 = 0,
            os: u8,
            proc: u4,
        },
        offset: elf.Elf32_Addr,
        vaddr: elf.Elf32_Addr,
        paddr: elf.Elf32_Word,
        filesz: elf.Elf32_Word,
        memsz: elf.Elf32_Word,

        memory: []const u8,
    };

    var phdrs = std.ArrayList(ProgramHeader).init(allocator);
    defer phdrs.deinit();

    // Fetch the headers:
    var load_headers = std.ArrayList(LoadHeader).init(allocator);
    defer load_headers.deinit();

    const required_bytes: usize = blk: {
        var lo_addr: usize = 0;
        var hi_addr: usize = 0;

        var pheaders = header.program_header_iterator(elf_stream);
        while (try pheaders.next()) |phdr| {
            try phdrs.append(.{
                .type = @enumFromInt(@as(u32, @intCast(phdr.p_type))),
                .flags = @bitCast(@as(u32, @intCast(phdr.p_flags))),
                .offset = @intCast(phdr.p_offset),
                .vaddr = @intCast(phdr.p_vaddr),
                .paddr = @intCast(phdr.p_paddr),
                .filesz = @intCast(phdr.p_filesz),
                .memsz = @intCast(phdr.p_memsz),

                .memory = elf_binary_data[phdr.p_offset..][0..phdr.p_filesz],
            });

            switch (phdr.p_type) {
                elf.PT_LOAD => {},

                elf.PT_DYNAMIC => continue,
                else => {
                    logger.warn("skipping program header: {}", .{phdr});
                    continue;
                },
            }

            logger.info("verifying read={} write={} exec={} flags=0x{X:0>8} offset=0x{X:0>8} vaddr=0x{X:0>8} paddr=0x{X:0>8} memlen={} bytes={} align={}", .{
                @intFromBool((phdr.p_flags & elf.PF_R) != 0),
                @intFromBool((phdr.p_flags & elf.PF_W) != 0),
                @intFromBool((phdr.p_flags & elf.PF_X) != 0),
                phdr.p_flags,
                phdr.p_offset, // file offset
                phdr.p_vaddr, // virtual load address
                phdr.p_paddr, // physical load address
                phdr.p_memsz, // memory size
                phdr.p_filesz, // bytes in file
                phdr.p_align, // alignment
            });

            if ((phdr.p_flags & PF_ASHETOS_NOLOAD) != 0) {
                logger.info("skipping phdr...", .{});
                continue;
            }

            // // check if memory is available
            // var i: usize = 0;
            // while (i < phdr.p_memsz) : (i += ashet.memory.page_size) {
            //     const page_index = ashet.memory.ptrToPage(@intToPtr(?*anyopaque, @intCast(usize, phdr.p_vaddr + i))) orelse return error.NonRamSection;

            //     if (!ashet.memory.isFree(page_index))
            //         return error.MemoryAlreadyUsed;
            // }

            lo_addr = @min(lo_addr, @as(usize, @intCast(phdr.p_vaddr)));
            hi_addr = @max(hi_addr, @as(usize, @intCast(phdr.p_vaddr + phdr.p_memsz)));

            if (phdr.p_memsz < phdr.p_filesz)
                return error.InvalidElfFile;

            const length: u32 = @intCast(phdr.p_filesz);

            const file_chunk = try load_headers.addOne();
            file_chunk.* = .{
                .vmem_offset = @intCast(phdr.p_vaddr),
                .data = try allocator.alloc(u8, length),
            };

            std.debug.assert(file_chunk.data.len == phdr.p_filesz);

            try elf_stream.seekableStream().seekTo(phdr.p_offset);
            try elf_stream.reader().readNoEof(file_chunk.data);
        }

        break :blk hi_addr - lo_addr;
    };

    logger.debug("Application is {d} bytes large", .{required_bytes});

    const dynamic_section: ?DynamicSection = dynamic_loader: {
        var pheaders = header.program_header_iterator(elf_stream);
        const dynamic_section: elf.Elf64_Phdr = while (try pheaders.next()) |phdr| {
            if (phdr.p_type == elf.PT_DYNAMIC)
                break phdr;
        } else {
            logger.debug("not a dynamic executable", .{});
            break :dynamic_loader null;
        };

        try elf_stream.seekableStream().seekTo(dynamic_section.p_offset);

        const ent_count: usize = @intCast(dynamic_section.p_filesz / @sizeOf(elf.Elf32_Dyn));

        // logger.info("DYNAMIC: {}", .{dynamic_section});
        var dsect: DynamicSection = .{};
        loop: for (0..ent_count) |_| {
            const dyn = try elf_stream.reader().readStruct(elf.Elf32_Dyn);

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

                elf.DT_VALRNGLO => dsect.valrnglo = dyn.d_val,
                elf.DT_GNU_PRELINKED => dsect.gnu_prelinked = dyn.d_val,
                elf.DT_GNU_CONFLICTSZ => dsect.gnu_conflictsz = dyn.d_val,
                elf.DT_GNU_LIBLISTSZ => dsect.gnu_liblistsz = dyn.d_val,
                elf.DT_CHECKSUM => dsect.checksum = dyn.d_val,
                elf.DT_PLTPADSZ => dsect.pltpadsz = dyn.d_val,
                elf.DT_MOVEENT => dsect.moveent = dyn.d_val,
                elf.DT_MOVESZ => dsect.movesz = dyn.d_val,
                elf.DT_FEATURE_1 => dsect.feature_1 = dyn.d_val,
                elf.DT_POSFLAG_1 => dsect.posflag_1 = dyn.d_val,

                elf.DT_VERSYM => dsect.versym = dyn.d_val,
                elf.DT_RELACOUNT => dsect.relacount = dyn.d_val,
                elf.DT_RELCOUNT => dsect.relcount = dyn.d_val,
                elf.DT_FLAGS_1 => dsect.flags_1 = dyn.d_val,
                elf.DT_VERDEF => dsect.verdef = dyn.d_val,
                elf.DT_VERDEFNUM => dsect.verdefnum = dyn.d_val,
                elf.DT_VERNEED => dsect.verneed = dyn.d_val,
                elf.DT_VERNEEDNUM => dsect.verneednum = dyn.d_val,
                elf.DT_AUXILIARY => dsect.auxiliary = dyn.d_val,
                elf.DT_FILTER => dsect.filter = dyn.d_val,

                else => {
                    if (dyn.d_tag >= elf.DT_LOOS and dyn.d_tag <= elf.DT_HIOS) {
                        logger.warn("unsupported DYNAMIC OS tag 0x{X:0>8} (value: {d})", .{ dyn.d_tag, dyn.d_val });
                    } else if (dyn.d_tag >= elf.DT_LOPROC and dyn.d_tag <= elf.DT_HIPROC) {
                        logger.warn("unsupported DYNAMIC PROC tag 0x{X:0>8} (value: {d})", .{ dyn.d_tag, dyn.d_val });
                    } else {
                        logger.err("unsupported DYNAMIC tag {d} (value: {d})", .{ dyn.d_tag, dyn.d_val });
                    }
                },
            }
        }
        break :dynamic_loader dsect;
    };

    logger.info("dynamic section: {?}", .{dynamic_section});

    var bss_headers = std.ArrayList(BssHeader).init(allocator);
    defer bss_headers.deinit();

    var relocations = std.ArrayList(Relocation).init(allocator);
    defer relocations.deinit();

    var syscalls = SyscallAllocator.init(allocator);

    {
        const strtab_buf = if (dynamic_section) |dsect|
            if (dsect.strtab) |dynstr_addr|
                for (phdrs.items) |phdr| {
                    if (dynstr_addr >= phdr.vaddr and dynstr_addr < phdr.vaddr + phdr.filesz)
                        break phdr.memory[dynstr_addr - phdr.vaddr ..];
                } else null
            else
                null
        else
            null;

        const symtab_buf = if (dynamic_section) |dsect|
            if (dsect.symtab) |symtab_addr|
                for (phdrs.items) |phdr| {
                    if (symtab_addr >= phdr.vaddr and symtab_addr < phdr.vaddr + phdr.filesz)
                        break phdr.memory[symtab_addr - phdr.vaddr ..];
                } else null
            else
                null
        else
            null;

        const reloc_env = Environment{
            .elf_data = elf_binary_data,
            .dynamic = dynamic_section,
            .syscalls = &syscalls,
            .strtab_buf = strtab_buf,
            .symtab_buf = symtab_buf,
        };

        var sheaders = header.section_header_iterator(elf_stream);
        while (try sheaders.next()) |shdr| {
            logger.info("{}", .{shdr});
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

                    try elf_stream.seekableStream().seekTo(shdr.sh_offset);

                    var buffered_reader = std.io.bufferedReaderSize(512, elf_stream.reader());

                    const count = @divExact(shdr.sh_size, shdr.sh_entsize);
                    for (0..count) |_| {
                        const entry = try buffered_reader.reader().readStruct(elf.Elf32_Rela);
                        logger.info("  {}", .{entry});

                        const rela_handler = try RelocationHandler.fromRelA(platform, entry);
                        const rela = try rela_handler.resolve(reloc_env);

                        std.debug.assert(rela.offset <= required_bytes);

                        try relocations.append(rela);
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

                    try elf_stream.seekableStream().seekTo(shdr.sh_offset);
                    var buffered_reader = std.io.bufferedReaderSize(512, elf_stream.reader());

                    const count = @divExact(shdr.sh_size, shdr.sh_entsize);
                    for (0..count) |_| {
                        const entry = try buffered_reader.reader().readStruct(elf.Elf32_Rel);
                        logger.info("  {}", .{entry});

                        const rel_handler = try RelocationHandler.fromRel(platform, entry);
                        const rel = try rel_handler.resolve(reloc_env);

                        std.debug.assert(rel.offset <= required_bytes);

                        try relocations.append(rel);
                    }
                },
                elf.SHT_DYNAMIC => {
                    logger.info("DYNAMIC shdr {}", .{shdr});
                    //
                },

                // ignore these, we don't need them
                std.elf.SHT_PROGBITS, std.elf.SHT_SYMTAB, std.elf.SHT_DYNSYM, std.elf.SHT_STRTAB => {},

                std.elf.SHT_NOBITS => {
                    if (shdr.sh_size > 0) {
                        const bss = try bss_headers.addOne();
                        bss.* = .{
                            .vmem_offset = @intCast(shdr.sh_addr),
                            .length = @intCast(shdr.sh_size),
                        };

                        std.debug.assert(bss.vmem_offset + bss.length <= required_bytes);
                    }
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

    for (0.., syscalls.lut.values()) |index, value| {
        std.debug.assert(index == value); // assert retained insertion order
    }

    return AshexFile{
        .platform = platform,
        .vmem_size = @intCast(required_bytes),
        .entry_point = @intCast(header.entry),

        .syscalls = syscalls.lut.keys(),
        .load_headers = try load_headers.toOwnedSlice(),
        .bss_headers = try bss_headers.toOwnedSlice(),
        .relocations = try relocations.toOwnedSlice(),
    };
}

const AshexFile = struct {
    platform: ashex.Platform,

    vmem_size: u32,
    entry_point: u32,
    syscalls: []const []const u8,
    load_headers: []LoadHeader,
    bss_headers: []BssHeader,
    relocations: []Relocation,
};

fn write_ashex_file(
    file: std.fs.File,
    exe: AshexFile,
    icon_data: ?[]const u8,
) !void {
    const endian: std.builtin.Endian = .little;
    const ashex_version = 0;

    std.debug.assert(0 == try file.getPos());

    var syscalls_offset_pos: u64 = 0;
    var syscalls_offset: u64 = 0;

    var load_headers_offset_pos: u64 = 0;
    var load_headers_offset: u64 = 0;

    var bss_headers_offset_pos: u64 = 0;
    var bss_headers_offset: u64 = 0;

    var relocations_offset_pos: u64 = 0;
    var relocations_offset: u64 = 0;

    {
        var buffered_writer = std.io.bufferedWriter(file.writer());
        var counting_writer = std.io.countingWriter(buffered_writer.writer());
        const writer = counting_writer.writer();

        // Write header
        {
            try writer.writeAll(&ashex.file_magic);
            try writer.writeInt(u8, ashex_version, endian);
            try writer.writeInt(u8, @intFromEnum(ashex.FileType.machine32_le), endian);
            try writer.writeInt(u8, @intFromEnum(exe.platform), endian);
            try writer.writeByteNTimes(0x00, 1); // padding

            if (icon_data) |icon| {
                try writer.writeInt(u32, @intCast(icon.len), endian);
                try writer.writeInt(u32, 0xAABBCCDD, endian); // TODO(fqu): Add patch and write data later!
            } else {
                try writer.writeInt(u32, 0, endian);
                try writer.writeInt(u32, 0, endian);
            }

            try writer.writeInt(u32, exe.vmem_size, endian);
            try writer.writeInt(u32, exe.entry_point, endian);

            syscalls_offset_pos = counting_writer.bytes_written;
            try writer.writeInt(u32, 0x55AA55AA, endian);
            try writer.writeInt(u32, @intCast(exe.syscalls.len), endian);

            load_headers_offset_pos = counting_writer.bytes_written;
            try writer.writeInt(u32, 0x55AA55AA, endian);
            try writer.writeInt(u32, @intCast(exe.load_headers.len), endian);

            bss_headers_offset_pos = counting_writer.bytes_written;
            try writer.writeInt(u32, 0x55AA55AA, endian);
            try writer.writeInt(u32, @intCast(exe.bss_headers.len), endian);

            relocations_offset_pos = counting_writer.bytes_written;
            try writer.writeInt(u32, 0x55AA55AA, endian);
            try writer.writeInt(u32, @intCast(exe.relocations.len), endian);
        }

        // Write load headers
        {
            try align_writer(&counting_writer, 512);
            load_headers_offset = counting_writer.bytes_written;
            for (exe.load_headers) |load_header| {
                try writer.writeInt(u32, load_header.vmem_offset, endian);
                try writer.writeInt(u32, @intCast(load_header.data.len), endian);
                try writer.writeAll(load_header.data);
            }
        }

        // Write BSS headers
        {
            try align_writer(&counting_writer, 512);
            bss_headers_offset = counting_writer.bytes_written;
            for (exe.bss_headers) |bss_header| {
                try writer.writeInt(u32, bss_header.vmem_offset, endian);
                try writer.writeInt(u32, bss_header.length, endian);
            }
        }

        // Write system calls:
        {
            try align_writer(&counting_writer, 512);
            syscalls_offset = counting_writer.bytes_written;
            for (exe.syscalls) |syscall| {
                try writer.writeInt(u16, @intCast(syscall.len), endian);
                try writer.writeAll(syscall);
            }
        }

        // Write relocations
        {
            try align_writer(&counting_writer, 512);
            relocations_offset = counting_writer.bytes_written;
            for (exe.relocations) |reloc| {
                try writer.writeInt(u32, reloc.offset, endian);
                try writer.writeInt(u16, @bitCast(reloc.type), endian);
                if (reloc.type.syscall != .unused) {
                    try writer.writeInt(u16, reloc.syscall, endian);
                }
                if (reloc.type.addend != .unused) {
                    try writer.writeInt(i32, reloc.addend, endian);
                }
            }
        }

        if (icon_data) |icon| {
            try align_writer(&counting_writer, 512);
            try writer.writeAll(icon);
        }

        try buffered_writer.flush();
    }

    if (syscalls_offset != 0) {
        try file.seekTo(syscalls_offset_pos);
        try file.writer().writeInt(u32, @intCast(syscalls_offset), endian);
    }
    if (load_headers_offset != 0) {
        try file.seekTo(load_headers_offset_pos);
        try file.writer().writeInt(u32, @intCast(load_headers_offset), endian);
    }
    if (bss_headers_offset != 0) {
        try file.seekTo(bss_headers_offset_pos);
        try file.writer().writeInt(u32, @intCast(bss_headers_offset), endian);
    }
    if (relocations_offset != 0) {
        try file.seekTo(relocations_offset_pos);
        try file.writer().writeInt(u32, @intCast(relocations_offset), endian);
    }
}

fn align_writer(counting_writer: anytype, alignment: u32) !void {
    try counting_writer.writer().writeByteNTimes(0xFF, alignment - (counting_writer.bytes_written % alignment));
}

const SyscallAllocator = struct {
    next_int: u16 = 0,
    lut: std.StringArrayHashMap(u16),

    pub fn init(allocator: std.mem.Allocator) SyscallAllocator {
        return .{
            .lut = std.StringArrayHashMap(u16).init(allocator),
        };
    }

    pub fn get_syscall_index(sca: *SyscallAllocator, name: []const u8) !usize {
        const gop = try sca.lut.getOrPut(name);
        if (!gop.found_existing) {
            gop.value_ptr.* = sca.next_int;
            sca.next_int += 1;
        }
        return gop.value_ptr.*;
    }
};

const LoadHeader = struct {
    vmem_offset: u32,
    data: []u8,
};

const BssHeader = struct {
    vmem_offset: u32,
    length: u32,
};

const Relocation = ashex.Relocation;

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

    // Extensions:
    valrnglo: ?usize = null,
    gnu_prelinked: ?usize = null,
    gnu_conflictsz: ?usize = null,
    gnu_liblistsz: ?usize = null,
    checksum: ?usize = null,
    pltpadsz: ?usize = null,
    moveent: ?usize = null,
    movesz: ?usize = null,
    feature_1: ?usize = null,
    posflag_1: ?usize = null,

    versym: ?usize = null,
    relacount: ?usize = null,
    relcount: ?usize = null,
    flags_1: ?usize = null,
    verdef: ?usize = null,
    verdefnum: ?usize = null,
    verneed: ?usize = null,
    verneednum: ?usize = null,
    auxiliary: ?usize = null,
    filter: ?usize = null,
};

const Environment = struct {
    dynamic: ?DynamicSection,
    syscalls: *SyscallAllocator,
    elf_data: []const u8,

    strtab_buf: ?[]const u8,
    symtab_buf: ?[]const u8,

    pub fn resolveSymbol(env: Environment, index: usize) !u16 {
        // logger.debug("resolve symbol {}", .{index});
        const dynamic = env.dynamic orelse return error.NoDynamicSection;

        const syment = dynamic.syment orelse return error.NoSymEnt;

        std.debug.assert(syment >= @sizeOf(elf.Elf32_Sym));

        const offset = syment * index;

        var sym: elf.Elf32_Sym = undefined;
        @memcpy(std.mem.asBytes(&sym), env.symtab_buf.?[offset..][0..@sizeOf(elf.Elf32_Sym)]);

        // const sym: *const elf.Elf32_Sym = @ptrCast(@alignCast(.ptr));
        logger.info("=> sym: {}", .{sym});

        const info: SymbolInfo = @bitCast(sym.st_info);

        var symname: []const u8 = env.strtab_buf.?[sym.st_name..];
        symname = symname[0..std.mem.indexOfScalar(u8, symname, 0).?];

        logger.debug(
            \\resolve symbol(name={}/'{}', value={}, size={}, shndx={}, type={}, bind={}
        , .{
            sym.st_name,
            std.zig.fmtEscapes(symname),
            sym.st_value,
            sym.st_size,
            sym.st_shndx,
            info.type,
            info.bind,
        });

        // Only search function symbols:
        if (info.type == .func) {
            const prefix = "ashet_";
            if (std.mem.startsWith(u8, symname, prefix)) {
                const syscall_index = try env.syscalls.get_syscall_index(symname[prefix.len..]);

                return @intCast(syscall_index);
            } else {
                logger.err("unsupported symbol name: '{s}'", .{symname});
                return error.BadSymbol;
            }

            // const exports = ashet.syscalls.exports;
            // inline for (@typeInfo(exports).Struct.decls) |decl| {
            //     if (std.mem.eql(u8, decl.name, symname)) {
            //         const func_ptr: usize = @intFromPtr(
            //             // just provide the internally linked versions:
            //             &@field(exports, decl.name),
            //         );
            //         return func_ptr;
            //     }
            // }
        }

        var buf: [4]u8 = undefined;
        logger.warn("Symbol '{}' ({s}) could not be resolved. Does that syscall really exist?", .{
            std.zig.fmtEscapes(symname),
            switch (info.type) {
                .notype, .object, .func, .section, .file, .common, .tls, .num, .loos, .hios, .loproc, .hiproc => @tagName(info.type),
                _ => try std.fmt.bufPrint(&buf, "{}", .{@intFromEnum(info.type)}),
            },
        });

        return error.MissingSymbol;
    }

    const SymbolType = enum(u4) {
        notype = elf.STT_NOTYPE,
        object = elf.STT_OBJECT,
        func = elf.STT_FUNC,
        section = elf.STT_SECTION,
        file = elf.STT_FILE,
        common = elf.STT_COMMON,
        tls = elf.STT_TLS,
        num = elf.STT_NUM,
        loos = elf.STT_LOOS,
        hios = elf.STT_HIOS,
        loproc = elf.STT_LOPROC,
        hiproc = elf.STT_HIPROC,
        _,
    };

    const SymbolInfo = packed struct(u8) {
        type: SymbolType,
        bind: enum(u4) {
            local = elf.STB_LOCAL,
            global = elf.STB_GLOBAL,
            weak = elf.STB_WEAK,
            num = elf.STB_NUM,
            loos = elf.STB_LOOS,
            hios = elf.STB_HIOS,
            loproc = elf.STB_LOPROC,
            hiproc = elf.STB_HIPROC,
            _,
        },
    };
};

const Elf32_Addr = std.elf.Elf32_Addr;
const Elf32_Word = std.elf.Elf32_Word;
const Elf32_Sword = std.elf.Elf32_Sword;

const word8 = u8;
const word16 = u16;
const word32 = u32;
const word64 = u64;
const wordclass = usize;

const RelocationHandler = struct {
    offset: Elf32_Addr,
    type: ashex.RelocationType,
    symbol: u24,
    addend: ?Elf32_Sword,

    pub fn fromRelA(platform: ashex.Platform, rela: elf.Elf32_Rela) !RelocationHandler {
        const info: ElfRelaInfo = @bitCast(rela.r_info);
        return .{
            .offset = rela.r_offset,
            .type = try RelocationType.from_elf(platform, info.type, .addend),
            .symbol = info.symbol,
            .addend = rela.r_addend,
        };
    }

    pub fn fromRel(platform: ashex.Platform, rel: elf.Elf32_Rel) !RelocationHandler {
        const info: ElfRelaInfo = @bitCast(rel.r_info);
        return .{
            .offset = rel.r_offset,
            .type = try RelocationType.from_elf(platform, info.type, .self),
            .symbol = info.symbol,
            .addend = null,
        };
    }

    pub fn resolve(rela: RelocationHandler, env: Environment) !Relocation {
        var relocation: Relocation = .{
            .type = rela.type,
            .addend = rela.addend orelse 0,
            .offset = rela.offset,
            .syscall = 0,
        };

        if (relocation.type.syscall != .unused) {
            relocation.syscall = try env.resolveSymbol(rela.symbol);
        }

        return relocation;
    }

    fn expand(comptime T: type, src: anytype) std.meta.Int(@typeInfo(@TypeOf(src)).Int.signedness, @bitSizeOf(T)) {
        return src;
    }

    const ElfRelaInfo = packed struct(Elf32_Word) {
        type: u8,
        symbol: u24,
    };
};

const RelocationType = struct {
    const AddendMapping = enum { addend, self };

    pub fn init(comptime addend_map: AddendMapping, comptime T: type, comptime script: []const u8) !ashex.RelocationType {
        const size: ashex.RelocationSize = switch (T) {
            word8 => .word8,
            word16 => .word16,
            word32 => .word32,
            word64 => .word64,
            else => @compileError(@typeName(T) ++ " "),
        };

        var reloc = ashex.RelocationType{
            .size = size,
            .self = .unused,
            .addend = .unused,
            .base = .unused,
            .offset = .unused,
            .syscall = .unused,
        };
        const opcodes = comptime ScriptEngine.parse(script);
        inline for (opcodes) |opcode| {
            const field_value: ashex.RelocationField = switch (opcode.operator) {
                .add => .add,
                .sub => .subtract,
            };
            const field_name = switch (opcode.target) {
                .addend => switch (addend_map) {
                    .addend => "addend",
                    .self => "self",
                },
                .base => "base",
                .got_offset => return error.UnsupportedRelocation,
                .got => return error.UnsupportedRelocation,
                .plt_offset => return error.UnsupportedRelocation,
                .offset => "offset",
                .symbol => "syscall",
            };

            @field(reloc, field_name) = field_value;
        }

        return reloc;
    }

    pub fn from_elf(platform: ashex.Platform, type_id: u8, comptime variant: AddendMapping) error{UnsupportedRelocation}!ashex.RelocationType {
        return switch (platform) {
            .x86 => switch (type_id) {
                // https://docs.oracle.com/cd/E19683-01/817-3677/chapter6-26/index.html

                0 => {
                    logger.warn("Found invalid R_386_NONE relocation", .{});
                    return error.UnsupportedRelocation;
                },

                // "32"     word32     S + A
                1 => try init(variant, word32, "S+A"),

                // pc32     word32     S + A - P
                2 => try init(variant, word32, "S+A-P"),

                //         /// Computes the distance from the base of the global offset table to the symbol's global offset table entry. It also instructs the link-editor to create a global offset table.
                //         got32 = 3, //    word32     G + A
                3 => try init(variant, word32, "G+A"),

                //         /// Computes the address of the symbol's procedure linkage table entry and instructs the link-editor to create a procedure linkage table.
                //         plt32 = 4, //    word32     L + A - P
                4 => try init(variant, word32, "L+A-P"),

                //         /// Created by the link-editor for dynamic executables to preserve a read-only text segment.
                //         /// Its offset member refers to a location in a writable segment. The symbol table index
                //         /// specifies a symbol that should exist both in the current object file and in a shared object.
                //         /// During execution, the runtime linker copies data associated with the shared object's symbol
                //         /// to the location specified by the offset. See Copy Relocations.
                //         copy = 5, //     None       None
                5 => @panic("Implement R_386_COPY relocation"),

                //         /// Used to set a global offset table entry to the address of the specified symbol. The special
                //         /// relocation type enable you to determine the correspondence between symbols and global offset table entries
                //         glob_dat = 6, // word32     S
                6 => try init(variant, word32, "S"),

                //         /// Created by the lirocednk-editor for dynamic objects to provide lazy binding. Its offset member
                //         /// gives the location of a pure linkage table entry. The runtime linker modifies the
                //         /// procedure linkage table entry to transfer control to the designated symbol address
                //         jmp_slot = 7, // word32     S
                7 => try init(variant, word32, "S"),

                //         /// Created by the link-editor for dynamic objects. Its offset member gives the location within
                //         /// a shared object that contains a value representing a relative address. The runtime linker
                //         /// computes the corresponding virtual address by adding the virtual address at which the shared
                //         /// object is loaded to the relative address. Relocation entries for this type must specify 0 for
                //         /// the symbol table index.
                //         relative = 8, // word32     B + A
                8 => try init(variant, word32, "B+A"),

                //         /// Computes the difference between a symbol's value and the address of the global offset table. It also
                //         /// instructs the link-editor to create the global offset table.
                //         gotoff = 9, //   word32     S + A - GOT
                9 => try init(variant, word32, "S+A-GOT"),

                //         /// Resembles R_386_PC32, except that it uses the address of the global offset table in its calculation.
                //         /// The symbol referenced in this relocation normally is _GLOBAL_OFFSET_TABLE_, which also instructs the
                //         /// link-editor to create the global offset table.
                //         gotpc = 10, //   word32     GOT + A - P
                10 => try init(variant, word32, "GOT+A-P"),

                //         @"32plt" = 11, //   word32     L + A
                11 => try init(variant, word32, "L+A"),

                else => return error.UnsupportedRelocation,
            },

            .riscv32 => switch (type_id) {

                //         // https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-elf.adoc
                //         // A - Addend field in the relocation entry associated with the symbol
                //         // B - Base address of a shared object loaded into memory

                0 => {
                    logger.warn("Found invalid R_386_NONE relocation", .{});
                    return error.UnsupportedRelocation;
                },

                //         @"32" = 1, // word32 : S + A, 32-bit relocation
                1 => try init(variant, word32, "S+A"),

                //         @"64" = 2, // word64 : S + A, 64-bit relocation
                2 => try init(variant, word64, "S+A"),

                //         relative = 3, // wordclass : B + A, Adjust a link address (A) to its load address (B + A)
                3 => try init(variant, word32, "B+A"),

                //         copy = 4,
                4 => @panic("R_RV32_COPY not implemented yet!"),

                //         jump_slot = 5, // wordclass : S, Indicates the symbol associated with a PLT entry
                5 => try init(variant, word32, "S"),

                else => return error.UnsupportedRelocation,
            },

            .arm32 => @panic("TODO: Implement .thumb platform relocations!"),

            //     .thumb => enum(u8) {
            //         none = 0,

            //         _,

            //         pub fn apply(reloc_type: @This(), relocation: Relocation, env: Environment) !void {
            //             _ = reloc_type;
            //             _ = relocation;
            //             _ = env;
            //             @panic("TODO: Implement Arm relocations!");
            //             // switch (reloc_type) {
            //             //     else => return error.UnsupportedRelocation,
            //             // }
            //         }
            //     },
        };
    }
};
const ScriptEngine = struct {
    const Operator = enum(u8) { add = '+', sub = '-' };
    const Target = enum(u8) {
        /// A This means the addend used to compute the value of the relocatable field.
        addend = 'A',

        /// This means the base address at which a shared object has been loaded into memory
        /// during execution. Generally, a shared object file is built with a 0 base virtual address,
        /// but the execution address will be different.
        base = 'B',

        /// This means the offset into the global offset table at which the address of the
        /// relocation entry's symbol will reside during execution. See "Global Offset Table''
        /// below for more information
        got_offset = 'G',

        // This means the address of the global offset table. See "Global Offset Table'' below
        // for more information.
        got = 'g', // ACTUALLY ENCODED AS "GOT"

        /// This means the place (section offset or address) of the procedure linkage table entry
        /// for a symbol. A procedure linkage table entry redirects a function call to the proper
        /// destination. The link editor builds the initial procedure linkage table, and the
        /// dynamic linker modifies the entries during execution. See "Procedure Linkage
        /// Table'' below for more information.
        plt_offset = 'L',

        /// This means the place (section offset or address) of the storage unit being relocated
        /// (computed using r_offset ).
        offset = 'P',

        /// This means the value of the symbol whose index resides in the relocation entry.
        symbol = 'S',
    };

    const Opcode = struct {
        operator: Operator,
        target: Target,
    };

    fn parse(comptime script: []const u8) []const Opcode {
        // @setEvalBranchQuota(10_000);

        var code: []const Opcode = &.{};

        var operator: Operator = .add;
        var start = 0;
        var run = 0;
        while (start < script.len) : (run += 1) {
            const next_operator: Operator = if (run < script.len)
                switch (script[run]) {
                    '+' => .add,
                    '-' => .sub,
                    else => continue,
                }
            else
                undefined;
            defer operator = next_operator;

            const item = script[start..run];
            defer start = run + 1;

            const target: Target = if (item.len != 1)
                if (std.mem.eql(u8, item, "GOT"))
                    .got
                else
                    @compileError("Found invalid symbol: " ++ item)
            else
                @enumFromInt(item[0]);

            code = code ++ &[1]Opcode{
                .{ .target = target, .operator = operator },
            };
        }

        return code;
    }
};
