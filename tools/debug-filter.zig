const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const argv = try std.process.argsAlloc(allocator);
    errdefer std.process.argsFree(allocator, argv);

    if (argv.len != 2) {
        @panic("debug-filter <elf>");
    }

    var file = try std.fs.cwd().openFile(argv[1], .{});

    var debug_info = try readElfDebugInfo(allocator, file);

    var stdin = std.io.getStdIn();
    const line_reader = stdin.reader();

    var stdout = std.io.getStdOut();

    while (true) {
        var line_buffer: [4096]u8 = undefined;

        const line_or_null = try line_reader.readUntilDelimiterOrEof(&line_buffer, '\n');

        const line = line_or_null orelse break;

        errdefer |e| std.log.err("failed to parse line {s}: {s}", .{ line, @errorName(e) });

        // process line
        var out_line_buffer = std.io.bufferedWriter(stdout.writer());
        const writer = out_line_buffer.writer();
        {
            var index: usize = 0;
            walk: while (index < line.len) {
                // search for "0x????????" in the output stream
                if (std.mem.indexOfPos(u8, line, index, "0x")) |start| outer_scan: {
                    scan: {

                        // basic bounds check
                        if (start + 10 > line.len)
                            break :scan;
                        for (line[start + 2 .. start + 10]) |c| {
                            if (!std.ascii.isHex(c))
                                break :scan;
                        }

                        const address = std.fmt.parseInt(u32, line[start + 2 .. start + 10], 16) catch break :scan;

                        try writer.writeAll(line[index .. start + 10]);
                        index = start + 10;

                        var symbol_info = getSymbolFromDwarf(u32, allocator, address, &debug_info) catch break :outer_scan;
                        defer symbol_info.deinit(allocator);

                        if (symbol_info.line_info) |line_info| {
                            try writer.print("[{s}:{d},{s}]", .{ line_info.file_name, line_info.line, symbol_info.symbol_name });
                        } else if (!std.mem.eql(u8, symbol_info.symbol_name, "???")) {
                            try writer.print("[{s}]", .{symbol_info.symbol_name});
                        }

                        continue :walk;
                    }

                    try writer.writeAll(line[index .. start + 2]);
                    index = start + 2;
                    continue :walk;
                } else {
                    try writer.writeAll(line[index..]);
                    break;
                }
            }
            try writer.writeAll("\n");
        }
        try out_line_buffer.flush();
    }
}

const dwarf = @import("lib/adjusted-dwarf.zig");

fn mapWholeFile(file: std.fs.File) ![]align(std.mem.page_size) const u8 {
    nosuspend {
        defer file.close();

        const file_len = std.math.cast(usize, try file.getEndPos()) orelse std.math.maxInt(usize);
        const mapped_mem = try std.os.mmap(
            null,
            file_len,
            std.os.PROT.READ,
            std.os.MAP.SHARED,
            file.handle,
            0,
        );
        errdefer std.os.munmap(mapped_mem);

        return mapped_mem;
    }
}

pub fn readElfDebugInfo(allocator: std.mem.Allocator, elf_file: std.fs.File) !dwarf.DwarfInfo {
    const elf = std.elf;
    nosuspend {
        const mapped_mem = try mapWholeFile(elf_file);
        const hdr: *const elf.Elf32_Ehdr = @ptrCast(&mapped_mem[0]);
        if (!std.mem.eql(u8, hdr.e_ident[0..4], elf.MAGIC)) return error.InvalidElfMagic;
        if (hdr.e_ident[elf.EI_VERSION] != 1) return error.InvalidElfVersion;

        const endian: std.builtin.Endian = switch (hdr.e_ident[elf.EI_DATA]) {
            elf.ELFDATA2LSB => .Little,
            elf.ELFDATA2MSB => .Big,
            else => return error.InvalidElfEndian,
        };
        std.debug.assert(endian == .Little); // this is our own debug info

        const shoff = hdr.e_shoff;
        const str_section_off = shoff + @as(u64, hdr.e_shentsize) * @as(u64, hdr.e_shstrndx);
        const str_shdr = @as(*const elf.Elf32_Shdr, @ptrCast(@alignCast(&mapped_mem[std.math.cast(usize, str_section_off) orelse return error.Overflow])));
        const header_strings = mapped_mem[str_shdr.sh_offset .. str_shdr.sh_offset + str_shdr.sh_size];
        const shdrs = @as([*]const elf.Elf32_Shdr, @ptrCast(@alignCast(&mapped_mem[shoff])))[0..hdr.e_shnum];

        var opt_debug_info: ?[]const u8 = null;
        var opt_debug_abbrev: ?[]const u8 = null;
        var opt_debug_str: ?[]const u8 = null;
        var opt_debug_str_offsets: ?[]const u8 = null;
        var opt_debug_line: ?[]const u8 = null;
        var opt_debug_line_str: ?[]const u8 = null;
        var opt_debug_ranges: ?[]const u8 = null;
        var opt_debug_loclists: ?[]const u8 = null;
        var opt_debug_rnglists: ?[]const u8 = null;
        var opt_debug_addr: ?[]const u8 = null;
        var opt_debug_names: ?[]const u8 = null;
        var opt_debug_frame: ?[]const u8 = null;

        for (shdrs) |*shdr| {
            if (shdr.sh_type == elf.SHT_NULL) continue;

            const name = std.mem.sliceTo(header_strings[shdr.sh_name..], 0);
            if (std.mem.eql(u8, name, ".debug_info")) {
                opt_debug_info = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_abbrev")) {
                opt_debug_abbrev = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_str")) {
                opt_debug_str = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_str_offsets")) {
                opt_debug_str_offsets = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_line")) {
                opt_debug_line = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_line_str")) {
                opt_debug_line_str = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_ranges")) {
                opt_debug_ranges = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_loclists")) {
                opt_debug_loclists = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_rnglists")) {
                opt_debug_rnglists = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_addr")) {
                opt_debug_addr = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_names")) {
                opt_debug_names = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            } else if (std.mem.eql(u8, name, ".debug_frame")) {
                opt_debug_frame = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            }
        }

        var di = dwarf.DwarfInfo{
            .endian = endian,
            .debug_info = opt_debug_info orelse return error.MissingDebugInfo,
            .debug_abbrev = opt_debug_abbrev orelse return error.MissingDebugInfo,
            .debug_str = opt_debug_str orelse return error.MissingDebugInfo,
            .debug_str_offsets = opt_debug_str_offsets,
            .debug_line = opt_debug_line orelse return error.MissingDebugInfo,
            .debug_line_str = opt_debug_line_str,
            .debug_ranges = opt_debug_ranges,
            .debug_loclists = opt_debug_loclists,
            .debug_rnglists = opt_debug_rnglists,
            .debug_addr = opt_debug_addr,
            .debug_names = opt_debug_names,
            .debug_frame = opt_debug_frame,
        };

        try dwarf.openDwarfDebugInfo(&di, u32, allocator);

        return di;
    }
}

fn getSymbolFromDwarf(comptime Address: type, allocator: std.mem.Allocator, address: u64, di: *dwarf.DwarfInfo) !std.debug.SymbolInfo {
    if (nosuspend di.findCompileUnit(address)) |compile_unit| {
        return std.debug.SymbolInfo{
            .symbol_name = nosuspend di.getSymbolName(address) orelse "???",
            .compile_unit_name = compile_unit.die.getAttrString(di, dwarf.AT.name, di.debug_str, compile_unit.*) catch |err| switch (err) {
                error.MissingDebugInfo, error.InvalidDebugInfo => "???",
            },
            .line_info = nosuspend di.getLineNumberInfo(Address, allocator, compile_unit.*, address) catch |err| switch (err) {
                error.MissingDebugInfo, error.InvalidDebugInfo => null,
                else => return err,
            },
        };
    } else |err| switch (err) {
        error.MissingDebugInfo, error.InvalidDebugInfo => {
            return std.debug.SymbolInfo{};
        },
        else => return err,
    }
}

fn chopSlice(ptr: []const u8, offset: u64, size: u64) error{Overflow}![]const u8 {
    const start = std.math.cast(usize, offset) orelse return error.Overflow;
    const end = start + (std.math.cast(usize, size) orelse return error.Overflow);
    return ptr[start..end];
}
