const std = @import("std");
const ashet = @import("../main.zig");
const libashet = @import("ashet");
const logger = std.log.scoped(.s);

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
    // https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-elf.adoc
    // A - Addend field in the relocation entry associated with the symbol
    // B - Base address of a shared object loaded into memory

    // const R_RISCV_NONE = 0;
    // const R_RISCV_32 = 1;
    // const R_RISCV_64 = 2;
    const R_RISCV_RELATIVE = 3; // B + A Relocation against a local symbol in a shared object

    const elf = std.elf;

    var path_buffer: [ashet.abi.max_path]u8 = undefined;
    const app_path = try std.fmt.bufPrint(&path_buffer, "SYS:/apps/{s}/code", .{app.getName()});

    var file = try libashet.fs.File.open(app_path, .read_only, .open_existing);
    defer file.close();

    var header = try elf.Header.read(&file);

    if (header.endian != .Little)
        return error.InvalidEndian;
    if (header.machine != .RISCV)
        return error.InvalidMachine;
    if (header.is_64 == true)
        return error.InvalidBitSize;
    if (header.phnum == 0)
        return error.NoCode;

    logger.info("elf header: {}", .{header});

    // Verify that we can load the executable
    const required_pages: usize = blk: {
        var lo_addr: usize = 0;
        var hi_addr: usize = 0;

        var pheaders = header.program_header_iterator(&file);
        while (try pheaders.next()) |phdr| {
            if (phdr.p_type != elf.PT_LOAD)
                continue;

            logger.info("verifying read={} write={} exec={} offset=0x{X:0>8} vaddr=0x{X:0>8} paddr=0x{X:0>8} memlen={} bytes={} align={}", .{
                @boolToInt((phdr.p_flags & elf.PF_R) != 0),
                @boolToInt((phdr.p_flags & elf.PF_W) != 0),
                @boolToInt((phdr.p_flags & elf.PF_X) != 0),
                phdr.p_offset, // file offset
                phdr.p_vaddr, // virtual load address
                phdr.p_paddr, // physical load address
                phdr.p_memsz, // memory size
                phdr.p_filesz, // bytes in file
                phdr.p_align, // alignment
            });

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

        const byte_count = hi_addr - lo_addr;

        logger.info("{s} requires {} bytes of RAM", .{ app.getName(), byte_count });

        break :blk ashet.memory.getRequiredPages(byte_count);
    };

    const required_bytes = ashet.memory.page_count * required_pages;

    const base_page = try ashet.memory.allocPages(required_pages);
    errdefer ashet.memory.freePages(base_page, required_pages);

    const process_memory = @ptrCast([*]u8, ashet.memory.pageToPtr(base_page).?)[0..required_bytes];
    const process_base = @ptrToInt(process_memory.ptr);

    // Actually load the exe into memory
    {
        var pheaders = header.program_header_iterator(&file);
        while (try pheaders.next()) |phdr| {
            if (phdr.p_type != elf.PT_LOAD)
                continue;

            logger.info("loading read={} write={} exec={} offset=0x{X:0>8} vaddr=0x{X:0>8} paddr=0x{X:0>8} memlen={} bytes={} align={}", .{
                @boolToInt((phdr.p_flags & elf.PF_R) != 0),
                @boolToInt((phdr.p_flags & elf.PF_W) != 0),
                @boolToInt((phdr.p_flags & elf.PF_X) != 0),
                phdr.p_offset, // file offset
                phdr.p_vaddr, // virtual load address
                phdr.p_paddr, // physical load address
                phdr.p_memsz, // memory size
                phdr.p_filesz, // bytes in file
                phdr.p_align, // alignment
            });

            const section = process_memory[@intCast(usize, phdr.p_vaddr)..][0..@intCast(usize, phdr.p_memsz)];

            try file.seekTo(phdr.p_offset);
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

                    try file.seekTo(shdr.sh_offset);
                    var i: usize = 0;
                    while (i < shdr.sh_size / shdr.sh_entsize) : (i += 1) {
                        var entry: elf.Elf32_Rela = undefined;
                        try file.reader().readNoEof(std.mem.asBytes(&entry));

                        switch (entry.r_info) {
                            R_RISCV_RELATIVE => {
                                logger.err("apply rela: offset={x:0>8} addend={x}", .{ entry.r_offset, entry.r_addend });

                                std.mem.writeIntLittle(
                                    usize,
                                    process_memory[@intCast(usize, entry.r_offset)..][0..@sizeOf(usize)],
                                    process_base +% @bitCast(u32, entry.r_addend), // abusing the fact that a u32 and i32 are interchangible when doing wraparound addition
                                );
                            },
                            else => logger.err("unhandled rela: info={} offset={x:0>8} addend={x}", .{
                                entry.r_info,
                                entry.r_offset,
                                entry.r_addend,
                            }),
                        }
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
                },
                elf.SHT_DYNAMIC => {
                    //
                },

                else => {}, // logger.info("unhandled section = {}", .{shdr}),
            }
        }
    }

    const entry_point = process_base + @intCast(usize, header.entry);

    logger.info("loaded {s} to address 0x{X:0>8}, entry point is 0x{X:0>8}", .{
        app.getName(),
        process_base,
        entry_point,
    });

    try spawnApp(app, entry_point);
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

    const process_memory = @ptrCast([*]u8, ashet.memory.pageToPtr(app_pages))[0..proc_page_size];

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

    try spawnApp(app, @ptrToInt(process_memory.ptr));
}

fn spawnApp(app: AppID, entry_point: usize) !void {
    const process = try ashet.multi_tasking.Process.spawn(
        app.getName(),
        @intToPtr(ashet.scheduler.ThreadFunction, entry_point),
        null,
        .{},
    );
    errdefer process.kill();
}
