const std = @import("std");
const args_parser = @import("args");

const is_windows = @import("builtin").os.tag == .windows;

// REWORK:
//
//  debug-filter \
//   --elf kernel=<kernel-elf> \
//   --elf wiki=<wiki-elf> \
//   …
//   -- applicaation arg a arb b arg c …
//

const page_size = std.heap.page_size_min;

const ElfFile = struct {
    const max_name_len: usize = 128;

    name: []const u8,
    path: []const u8,

    file: std.fs.File,
    dwarf: dwarf.DwarfInfo,
    mem: MapResult,
};

const max_suffix_len = 3 + 8 * 2; // ":0x" + 8 hex encoded bytes

const ElfSet = std.StringArrayHashMap(ElfFile);

fn renderElfData(allocator: std.mem.Allocator, elf_addr: u64, elf: *ElfFile, output: *std.io.BufferedWriter(4096, std.fs.File.Writer)) !void {
    const writer = output.writer();

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
}

const ParseOut = struct {
    elf: *ElfFile,
    addr: u64,
};

fn parsePollResult(
    elves: ElfSet,
    line_buffer: RingBuffer,
    bit_width: enum { bits32, bits64 },
) ?ParseOut {
    var suffix: [RingBuffer.max_item_count]u8 = undefined;
    line_buffer.copy_to(&suffix); // will be filled back to front!

    const addrLen: usize = switch (bit_width) {
        .bits32 => 8, // nibbles,
        .bits64 => 16, // nibbles
    };

    for (suffix[suffix.len - addrLen ..]) |byte| {
        if (!std.ascii.isHex(byte))
            return null; // last digits not hex
    }

    if (suffix[suffix.len - addrLen - 1] != 'x')
        return null;
    if (suffix[suffix.len - addrLen - 2] != '0')
        return null;
    if (suffix[suffix.len - addrLen - 3] != ':')
        return null;

    const elf_addr = std.fmt.parseInt(u64, suffix[suffix.len - addrLen ..], 16) catch unreachable;

    const matched_elf = for (elves.values()) |*elf| {
        const name_prefix_pos = suffix.len - addrLen - 3 - elf.name.len;

        const prefix = suffix[name_prefix_pos..][0..elf.name.len];

        if (std.mem.eql(u8, elf.name, prefix))
            break elf;
    } else return null;

    return .{
        .addr = elf_addr,
        .elf = matched_elf,
    };
}

test "parsePollResult empty ring" {
    var empty_elves = ElfSet.init(std.testing.allocator);
    defer empty_elves.deinit();

    const rb = RingBuffer{};

    try std.testing.expect(parsePollResult(empty_elves, rb, .bits32) == null);
    try std.testing.expect(parsePollResult(empty_elves, rb, .bits64) == null);
}

test "parsePollResult bits32 hit" {
    var empty_elves = ElfSet.init(std.testing.allocator);
    defer empty_elves.deinit();

    try empty_elves.put("basic", .{
        .name = "basic",
        .mem = undefined,
        .dwarf = undefined,
        .file = undefined,
        .path = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("basic:0xAABBCCDD");

    const bits32_result = parsePollResult(empty_elves, rb, .bits32);
    const bits64_result = parsePollResult(empty_elves, rb, .bits64);

    try std.testing.expect(bits32_result != null);
    try std.testing.expect(bits64_result == null);

    try std.testing.expectEqual(empty_elves.getPtr("basic").?, bits32_result.?.elf);
    try std.testing.expectEqual(@as(u64, 0xAABBCCDD), bits32_result.?.addr);
}

test "parsePollResult bits64 hit" {
    var empty_elves = ElfSet.init(std.testing.allocator);
    defer empty_elves.deinit();

    try empty_elves.put("basic", .{
        .name = "basic",
        .dwarf = undefined,
        .mem = undefined,
        .file = undefined,
        .path = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("basic:0xAABBCCDD00112233");

    const bits32_result = parsePollResult(empty_elves, rb, .bits32);
    const bits64_result = parsePollResult(empty_elves, rb, .bits64);

    try std.testing.expect(bits32_result == null);
    try std.testing.expect(bits64_result != null);

    try std.testing.expectEqual(empty_elves.getPtr("basic").?, bits64_result.?.elf);
    try std.testing.expectEqual(@as(u64, 0xAABBCCDD00112233), bits64_result.?.addr);
}

test "parsePollResult bits32 missing" {
    var empty_elves = ElfSet.init(std.testing.allocator);
    defer empty_elves.deinit();

    try empty_elves.put("basic", .{
        .name = "basic",
        .dwarf = undefined,
        .mem = undefined,
        .file = undefined,
        .path = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("bas1c:0xAABBCCDD");

    const bits32_result = parsePollResult(empty_elves, rb, .bits32);
    const bits64_result = parsePollResult(empty_elves, rb, .bits64);

    try std.testing.expect(bits32_result == null);
    try std.testing.expect(bits64_result == null);
}

test "parsePollResult bits64 missing" {
    var empty_elves = ElfSet.init(std.testing.allocator);
    defer empty_elves.deinit();

    try empty_elves.put("basic", .{
        .name = "basic",
        .dwarf = undefined,
        .mem = undefined,
        .file = undefined,
        .path = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("bas1ic:0xAABBCCDD00112233");

    const bits32_result = parsePollResult(empty_elves, rb, .bits32);
    const bits64_result = parsePollResult(empty_elves, rb, .bits64);

    try std.testing.expect(bits32_result == null);
    try std.testing.expect(bits64_result == null);
}

fn consumePollResult(
    allocator: std.mem.Allocator,
    elves: ElfSet,
    output: *std.io.BufferedWriter(4096, std.fs.File.Writer),
    line_buffer: *RingBuffer,
    fifo: *std.io.PollFifo,
) !void {
    var chunk: [64]u8 = undefined;
    while (true) {
        const input_len = fifo.read(&chunk);
        if (input_len == 0)
            return;

        for (chunk[0..input_len]) |byte| {
            line_buffer.push(byte);
            try output.writer().writeByte(byte);

            if (byte == '\n') {
                try output.flush();
                continue;
            }

            if (!std.ascii.isHex(byte)) {
                continue;
            }

            if (parsePollResult(elves, line_buffer.*, .bits32)) |result| {
                try renderElfData(allocator, result.addr, result.elf, output);
            } else if (parsePollResult(elves, line_buffer.*, .bits64)) |result| {
                try renderElfData(allocator, result.addr, result.elf, output);
            }
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

            if (app_name.len > ElfFile.max_name_len) {
                @panic("elf name out of bounds");
            }

            const prev = try elves.fetchPut(app_name, .{
                .name = app_name,
                .path = app_path,

                .file = undefined,
                .dwarf = undefined,
                .mem = undefined,
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

        const mem, const info = try readElfDebugInfo(allocator, value.file);
        value.dwarf = info;
        value.mem = mem;
    }
    defer {
        for (elves.values()) |*value| {
            value.dwarf.deinit(allocator);
            if (is_windows) {
                value.mem.deinit();
                value.file.close();
            } else {
                std.posix.munmap(value.mem);
            }
        }
    }

    // Backup termios settings so the a crashing or force-killed application
    // might not fuck up our terminal session:
    const terminal_config_backup = try Termios.read();
    defer terminal_config_backup.apply() catch |err| std.log.err("failed to re-apply terminal settings: {}", .{err});

    const term = try spawnAndFilterSubprocess(elves, app_argv, allocator);
    switch (term) {
        .Exited => |code| return code,
        .Signal => |signal| {
            std.log.err("process died with signal {d}", .{signal});
            return 1;
        },
        .Stopped => |code| {
            std.log.err("process was stopped: 0x{X:0>8}", .{code});
            return 1;
        },
        .Unknown => |code| {
            std.log.err("process had an unknown exit reason (0x{X:0>8})", .{code});
            return 1;
        },
    }

    return 0;
}

fn spawnAndFilterSubprocess(elves: ElfSet, app_argv: []const []const u8, allocator: std.mem.Allocator) !std.process.Child.Term {
    var proc = std.process.Child.init(app_argv, allocator);

    proc.stdin_behavior = .Inherit;
    proc.stdout_behavior = .Pipe;
    proc.stderr_behavior = .Pipe;

    try proc.spawn();

    filterAndForwardStdio(allocator, elves, &proc) catch |err| {
        std.log.err("failed to forward stdio: {}", .{err});
        return try proc.kill();
    };

    return try proc.wait();
}

fn filterAndForwardStdio(allocator: std.mem.Allocator, elves: ElfSet, proc: *std.process.Child) !void {
    var poller = std.io.poll(allocator, enum { stdout, stderr }, .{
        .stdout = proc.stdout.?,
        .stderr = proc.stderr.?,
    });
    defer poller.deinit();

    var stdout_line_buffer = RingBuffer{};
    var stderr_line_buffer = RingBuffer{};

    var stdout_buffered_writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    var stderr_buffered_writer = std.io.bufferedWriter(std.io.getStdErr().writer());

    while (try poller.poll()) {
        try consumePollResult(
            allocator,
            elves,
            &stdout_buffered_writer,
            &stdout_line_buffer,
            poller.fifo(.stdout),
        );
        try consumePollResult(
            allocator,
            elves,
            &stderr_buffered_writer,
            &stderr_line_buffer,
            poller.fifo(.stderr),
        );
    }

    try stdout_buffered_writer.flush();
    try stderr_buffered_writer.flush();
}

const RingBuffer = struct {
    const max_item_count = ElfFile.max_name_len + max_suffix_len;

    data: [max_item_count]u8 = .{0} ** max_item_count,
    next_element: usize = 0,

    pub fn push(rb: *RingBuffer, byte: u8) void {
        rb.data[rb.next_element] = byte;
        rb.next_element += 1;
        if (rb.next_element >= rb.data.len) {
            rb.next_element = 0;
        }
    }

    pub fn push_slice(rb: *RingBuffer, slice: []const u8) void {
        for (slice) |byte| {
            rb.push(byte);
        }
    }

    /// Returns the `index`th last element
    pub fn get(rb: RingBuffer, index: usize) u8 {
        std.debug.assert(index < rb.data.len);
        const actual_index = (rb.data.len + rb.next_element - 1 - index) % rb.data.len;
        return rb.data[actual_index];
    }

    /// Copy the ring buffer to the `slice` with the latest element in the ring is
    /// the last element in the slice.
    pub fn copy_to(rb: RingBuffer, array: *[max_item_count]u8) void {
        for (0..rb.data.len) |i| {
            const rb_index = (rb.next_element + i) % rb.data.len;
            const byte = rb.data[rb_index];
            array[i] = byte;
        }
    }
};

test "RingBuffer get" {
    var rb = RingBuffer{};

    try std.testing.expect(rb.get(0) == 0);
    try std.testing.expect(rb.get(1) == 0);
    try std.testing.expect(rb.get(2) == 0);
    try std.testing.expect(rb.get(3) == 0);

    rb.push(10);

    try std.testing.expect(rb.get(0) == 10);
    try std.testing.expect(rb.get(1) == 0);
    try std.testing.expect(rb.get(2) == 0);
    try std.testing.expect(rb.get(3) == 0);

    rb.push(20);

    try std.testing.expect(rb.get(0) == 20);
    try std.testing.expect(rb.get(1) == 10);
    try std.testing.expect(rb.get(2) == 0);
    try std.testing.expect(rb.get(3) == 0);

    rb.push_slice(&.{ 30, 40 });

    try std.testing.expect(rb.get(0) == 40);
    try std.testing.expect(rb.get(1) == 30);
    try std.testing.expect(rb.get(2) == 20);
    try std.testing.expect(rb.get(3) == 10);
}

test "RingBuffer copy_to" {
    var rb = RingBuffer{};

    rb.push_slice(&.{ 10, 20, 30, 40, 50, 60, 70, 80 });

    var out: [RingBuffer.max_item_count]u8 = undefined;
    rb.copy_to(&out);

    try std.testing.expectEqualSlices(u8, &.{ 10, 20, 30, 40, 50, 60, 70, 80 }, out[out.len - 8 ..]);
}

const dwarf = @import("lib/adjusted-dwarf.zig");

const windows = struct {
    const win = std.os.windows;

    extern "kernel32" fn CreateFileMappingA(
        hFile: win.HANDLE,
        lpFileMappingAttributes: ?*anyopaque,
        flProtect: win.DWORD,
        dwMaximumSizeHigh: win.DWORD,
        dwMaximumSizeLow: win.DWORD,
        lpName: ?win.LPCSTR,
    ) ?win.HANDLE;

    extern "kernel32" fn MapViewOfFile(
        hFileMappingObject: win.HANDLE,
        dwDesiredAccess: win.DWORD,
        dwFileOffsetHigh: win.DWORD,
        dwFileOffsetLow: win.DWORD,
        dwNumberOfBytesToMap: win.SIZE_T,
    ) ?win.LPVOID;

    extern "kernel32" fn UnmapViewOfFile(
        lpBaseAddress: win.LPCVOID,
    ) win.BOOL;

    const Handle = win.HANDLE;

    fn createMapping(file: std.fs.File) !Handle {
        const mapping = CreateFileMappingA(
            file.handle,
            null,
            win.PAGE_READONLY,
            0,
            0,
            null,
        );
        if (mapping == null) return error.MappingFailed;
        return mapping.?;
    }

    const FILE_MAP_READ = 4;

    fn mapView(mapping: Handle, size: usize) !*anyopaque {
        const view = MapViewOfFile(
            mapping,
            FILE_MAP_READ,
            0,
            0,
            size,
        );
        if (view == null) return error.ViewFailed;
        return view.?;
    }

    fn unmapView(addr: *const anyopaque) !void {
        const res = UnmapViewOfFile(addr);
        if (res == 0) return error.UnmapFailed;
    }
};

const MapResult = if (is_windows) struct {
    mapping_handle: windows.Handle,
    mem: []align(page_size) const u8,

    fn deinit(self: MapResult) void {
        windows.unmapView(@ptrCast(self.mem.ptr)) catch {};
        std.os.windows.CloseHandle(self.mapping_handle);
    }
} else []align(page_size) const u8;

fn mapWholeFile(file: std.fs.File) !MapResult {
    {
        const file_len = std.math.cast(usize, try file.getEndPos()) orelse std.math.maxInt(usize);
        if (is_windows) {
            const mapping = try windows.createMapping(file);
            const mapped_view = try windows.mapView(mapping, file_len);
            const mapped_mem = @as([*]align(page_size) const u8, @ptrCast(@alignCast(mapped_view)))[0..file_len];
            return .{
                .mapping_handle = mapping,
                .mem = mapped_mem,
            };
        } else {
            defer file.close();

            const mapped_mem = try std.posix.mmap(
                null,
                file_len,
                std.posix.PROT.READ,
                .{ .TYPE = .SHARED },
                file.handle,
                0,
            );
            errdefer std.posix.munmap(mapped_mem);

            return mapped_mem;
        }
    }
}

pub fn readElfDebugInfo(allocator: std.mem.Allocator, elf_file: std.fs.File) !struct { MapResult, dwarf.DwarfInfo } {
    const elf = std.elf;
    {
        const map_result = try mapWholeFile(elf_file);
        const mapped_mem = if (is_windows) map_result.mem else map_result;
        const hdr: *const elf.Elf32_Ehdr = @ptrCast(&mapped_mem[0]);
        if (!std.mem.eql(u8, hdr.e_ident[0..4], elf.MAGIC)) return error.InvalidElfMagic;
        if (hdr.e_ident[elf.EI_VERSION] != 1) return error.InvalidElfVersion;

        const endian: std.builtin.Endian = switch (hdr.e_ident[elf.EI_DATA]) {
            elf.ELFDATA2LSB => .little,
            elf.ELFDATA2MSB => .big,
            else => return error.InvalidElfEndian,
        };
        std.debug.assert(endian == .little); // this is our own debug info

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

        var di: dwarf.DwarfInfo = .{
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

        return .{ map_result, di };
    }
}

const SymbolInfo = struct {
    symbol_name: []const u8 = "",
    compile_unit_name: []const u8 = "???",
    line_info: ?dwarf.LineInfo = null,

    fn deinit(si: SymbolInfo, allocator: std.mem.Allocator) void {
        _ = allocator;
        _ = si;
    }
};

fn getSymbolFromDwarf(comptime Address: type, allocator: std.mem.Allocator, address: u64, di: *dwarf.DwarfInfo) !SymbolInfo {
    if (di.findCompileUnit(address)) |compile_unit| {
        return .{
            .symbol_name = di.getSymbolName(address) orelse "???",
            .compile_unit_name = compile_unit.die.getAttrString(di, dwarf.AT.name, di.debug_str, compile_unit.*) catch |err| switch (err) {
                error.MissingDebugInfo, error.InvalidDebugInfo => "???",
            },
            .line_info = di.getLineNumberInfo(Address, allocator, compile_unit.*, address) catch |err| switch (err) {
                error.MissingDebugInfo, error.InvalidDebugInfo => null,
                else => return err,
            },
        };
    } else |err| switch (err) {
        error.MissingDebugInfo, error.InvalidDebugInfo => {
            return .{};
        },
        else => return err,
    }
}

fn chopSlice(ptr: []const u8, offset: u64, size: u64) error{Overflow}![]const u8 {
    const start = std.math.cast(usize, offset) orelse return error.Overflow;
    const end = start + (std.math.cast(usize, size) orelse return error.Overflow);
    return ptr[start..end];
}

const Termios = if (@import("builtin").os.tag == .windows)
    WindowsTermios
else
    PosixTermios;

const WindowsTermios = struct {
    pub fn read() !Termios {
        return .{};
    }

    pub fn apply(ios: Termios) !void {
        _ = ios;
    }
};

const PosixTermios = struct {
    settings: [3]?std.posix.termios,

    pub fn read() !Termios {
        return .{
            .settings = .{
                std.posix.tcgetattr(std.posix.STDIN_FILENO) catch |err| switch (err) {
                    error.NotATerminal => null,
                    error.Unexpected => |e| return e,
                },
                std.posix.tcgetattr(std.posix.STDOUT_FILENO) catch |err| switch (err) {
                    error.NotATerminal => null,
                    error.Unexpected => |e| return e,
                },
                std.posix.tcgetattr(std.posix.STDERR_FILENO) catch |err| switch (err) {
                    error.NotATerminal => null,
                    error.Unexpected => |e| return e,
                },
            },
        };
    }
    pub fn apply(ios: Termios) !void {
        var result: std.posix.TermiosSetError!void = {};

        if (ios.settings[0]) |attrs| {
            std.posix.tcsetattr(std.posix.STDIN_FILENO, std.posix.TCSA.NOW, attrs) catch |err| {
                result = err;
            };
        }
        if (ios.settings[1]) |attrs| {
            std.posix.tcsetattr(std.posix.STDOUT_FILENO, std.posix.TCSA.NOW, attrs) catch |err| {
                result = err;
            };
        }
        if (ios.settings[2]) |attrs| {
            std.posix.tcsetattr(std.posix.STDERR_FILENO, std.posix.TCSA.NOW, attrs) catch |err| {
                result = err;
            };
        }

        return result;
    }
};
