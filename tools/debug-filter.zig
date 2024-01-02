const std = @import("std");
const args_parser = @import("args");

// REWORK:
//
//  debug-filter \
//   --elf kernel=<kernel-elf> \
//   --elf wiki=<wiki-elf> \
//   …
//   -- applicaation arg a arb b arg c …
//

const ElfFile = struct {
    name: []const u8,
    path: []const u8,

    file: std.fs.File,
    dwarf: dwarf.DwarfInfo,
};

const ElfSet = std.StringArrayHashMap(ElfFile);

fn processLine(allocator: std.mem.Allocator, elves: ElfSet, output: std.fs.File, line: []const u8) !void {
    var out_line_buffer = std.io.bufferedWriter(output.writer());
    const writer = out_line_buffer.writer();

    {
        var str_index: usize = 0;
        while (str_index < line.len) {
            var earliest_elf: ?*ElfFile = null;
            var elf_pos: usize = std.math.maxInt(usize);
            var elf_addr: u64 = 0;

            // first, determine the first occurrance of an elf index:

            for (elves.values()) |*elf| {
                var prefix_buf: [64]u8 = undefined;
                const prefix = try std.fmt.bufPrint(&prefix_buf, "{s}:0x", .{elf.name});

                if (std.mem.indexOfPos(u8, line, str_index, prefix)) |start| {
                    if (start > elf_pos)
                        continue;

                    // basic bounds check
                    if (start + prefix.len + 8 > line.len) {
                        continue;
                    }

                    const int_str = line[start..][prefix.len..][0..8];
                    for (int_str) |c| {
                        if (!std.ascii.isHex(c))
                            continue;
                    }

                    elf_addr = std.fmt.parseInt(u64, int_str, 16) catch unreachable;
                    elf_pos = start;
                    earliest_elf = elf;
                }
            }

            if (earliest_elf) |elf| {
                try writer.writeAll(elf.name);
                try writer.writeAll(":0x");
                try writer.print("{X:0>8}", .{elf_addr});
                str_index = elf_pos + elf.name.len + 11; // ":0x" + 8 digits

                if (getSymbolFromDwarf(u32, allocator, elf_addr, &elf.dwarf)) |symbol_info| {
                    defer symbol_info.deinit(allocator);

                    if (symbol_info.line_info) |line_info| {
                        try writer.print("[{s}:{d},{s}]", .{ line_info.file_name, line_info.line, symbol_info.symbol_name });
                    } else if (!std.mem.eql(u8, symbol_info.symbol_name, "???")) {
                        try writer.print("[{s}]", .{symbol_info.symbol_name});
                    }
                } else |err| {
                    try writer.print("[ERROR:{s}]", .{@errorName(err)});
                }
            } else {
                try writer.writeAll(line[str_index..]);
                break;
            }
        }
        try writer.writeAll("\n");
    }
    try out_line_buffer.flush();
}

fn consumePollResult(
    allocator: std.mem.Allocator,
    elves: ElfSet,
    output: std.fs.File,
    line_buffer: *std.ArrayList(u8),
    fifo: *std.io.PollFifo,
) !void {
    while (true) {
        const input_len = fifo.readableLength();

        if (input_len == 0)
            return;

        const base = line_buffer.items.len;
        try line_buffer.resize(base + input_len);

        const new_bytes = line_buffer.items[base..];
        std.debug.assert(new_bytes.len == input_len);

        const consumed_len = fifo.read(new_bytes);
        std.debug.assert(consumed_len == input_len);

        while (std.mem.indexOfScalar(u8, line_buffer.items, '\n')) |line_end| {
            const line = line_buffer.items[0..line_end];

            try processLine(allocator, elves, output, line);

            try line_buffer.replaceRange(0, line_end + 1, ""); // drop this line

        }
    }
}

pub fn main() !u8 {
    const allocator = std.heap.c_allocator;

    var elves = ElfSet.init(allocator);
    defer elves.deinit();

    const argv = try std.process.argsAlloc(allocator);
    errdefer std.process.argsFree(allocator, argv);

    const app_argv = blk: {
        var i: usize = 1;
        while (i < argv.len) {
            if (!std.mem.eql(u8, argv[i], "--elf"))
                break;

            if (i + 1 >= argv.len) {
                @panic("invalid argument!");
            }

            const app_spec = argv[i + 1];

            const splitter = std.mem.indexOfScalar(u8, app_spec, '=') orelse @panic("bad app spec");

            const app_name = app_spec[0..splitter];
            const app_path = app_spec[splitter + 1 ..];

            const prev = try elves.fetchPut(app_name, ElfFile{
                .name = app_name,
                .path = app_path,

                .file = undefined,
                .dwarf = undefined,
            });
            if (prev != null)
                @panic("duplicate app!");

            i += 2;
        }

        break :blk argv[i..];
    };

    if (app_argv.len == 0) {
        @panic("missing application cli!");
    }

    for (elves.values()) |*value| {
        value.file = try std.fs.cwd().openFile(value.path, .{});
        value.dwarf = try readElfDebugInfo(allocator, value.file);
    }

    {
        var proc = std.ChildProcess.init(app_argv, allocator);

        proc.stdin_behavior = .Inherit;
        proc.stdout_behavior = .Pipe;
        proc.stderr_behavior = .Pipe;

        try proc.spawn();
        {
            var poller = std.io.poll(allocator, enum { stdout, stderr }, .{
                .stdout = proc.stdout.?,
                .stderr = proc.stderr.?,
            });
            defer poller.deinit();

            var stdout_line_buffer = std.ArrayList(u8).init(allocator);
            defer stdout_line_buffer.deinit();

            var stderr_line_buffer = std.ArrayList(u8).init(allocator);
            defer stderr_line_buffer.deinit();

            while (try poller.poll()) {
                try consumePollResult(
                    allocator,
                    elves,
                    std.io.getStdOut(),
                    &stdout_line_buffer,
                    poller.fifo(.stdout),
                );
                try consumePollResult(
                    allocator,
                    elves,
                    std.io.getStdErr(),
                    &stderr_line_buffer,
                    poller.fifo(.stderr),
                );
            }

            if (stdout_line_buffer.items.len > 0) {
                try processLine(allocator, elves, std.io.getStdOut(), stdout_line_buffer.items);
            }
            if (stderr_line_buffer.items.len > 0) {
                try processLine(allocator, elves, std.io.getStdErr(), stderr_line_buffer.items);
            }
        }

        const result = try proc.wait();

        if (result != .Exited)
            @panic("bad process result");

        return result.Exited;
    }

    return 0;
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
