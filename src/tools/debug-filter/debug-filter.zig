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

const BitWidth = enum { bits32, bits64 };

const DebugSections = struct {
    debug_info: ?[]const u8 = null,
    debug_abbrev: ?[]const u8 = null,
    debug_str: ?[]const u8 = null,
    debug_str_offsets: ?[]const u8 = null,
    debug_line: ?[]const u8 = null,
    debug_line_str: ?[]const u8 = null,
    debug_ranges: ?[]const u8 = null,
    debug_loclists: ?[]const u8 = null,
    debug_rnglists: ?[]const u8 = null,
    debug_addr: ?[]const u8 = null,
    debug_names: ?[]const u8 = null,
    debug_frame: ?[]const u8 = null,
};

const SymbolEntry = struct {
    name: []const u8,
    value: u64,
    size: u64,
    info: u8,
};

const SectionEntry = struct {
    name: []const u8,
    addr: u64,
    size: u64,
};

const ReloadableLookup = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    lookup: *Lookup,
    mutex: std.Thread.Mutex = .{},
    last_stat: ?std.fs.File.Stat,
    last_stat_check_ms: ?i64 = null,
    last_error_ms: ?i64 = null,

    const check_interval_ms: i64 = 200;
    const error_interval_ms: i64 = 1_000;

    pub fn create(allocator: std.mem.Allocator, path: []const u8) !*ReloadableLookup {
        const path_copy = try allocator.dupe(u8, path);
        errdefer allocator.free(path_copy);

        const lookup = try Lookup.create(allocator, path);
        errdefer lookup.destroy();

        const self = try allocator.create(ReloadableLookup);
        self.* = .{
            .allocator = allocator,
            .path = path_copy,
            .lookup = lookup,
            .last_stat = std.fs.cwd().statFile(path) catch null,
        };
        return self;
    }

    pub fn destroy(self: *ReloadableLookup) void {
        self.lookup.destroy();
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    pub fn lock(self: *ReloadableLookup) void {
        self.mutex.lock();
    }

    pub fn unlock(self: *ReloadableLookup) void {
        self.mutex.unlock();
    }

    pub fn refreshLocked(self: *ReloadableLookup, force: bool) !void {
        const now_ms = std.time.milliTimestamp();

        if (!force) {
            if (self.last_stat_check_ms) |last| {
                if (now_ms - last < check_interval_ms)
                    return;
            }
        }
        self.last_stat_check_ms = now_ms;

        const stat = std.fs.cwd().statFile(self.path) catch |err| {
            self.logReloadIssue(now_ms, "stat", err);
            self.last_stat = null;
            return;
        };

        if (self.last_stat) |last| {
            if (!statsDiffer(last, stat))
                return;
        }

        const new_lookup = Lookup.create(self.allocator, self.path) catch |err| {
            switch (err) {
                error.OutOfMemory => return err,
                else => {
                    self.logReloadIssue(now_ms, "read", err);
                    return;
                },
            }
        };
        errdefer new_lookup.destroy();

        const old_lookup = self.lookup;
        self.lookup = new_lookup;
        self.last_stat = stat;
        self.last_error_ms = null;
        old_lookup.destroy();
    }

    fn statsDiffer(previous: std.fs.File.Stat, current: std.fs.File.Stat) bool {
        return previous.inode != current.inode or
            previous.size != current.size or
            previous.mtime != current.mtime;
    }

    fn logReloadIssue(self: *ReloadableLookup, now_ms: i64, action: []const u8, err: anyerror) void {
        if (self.last_error_ms) |last| {
            if (now_ms - last < error_interval_ms)
                return;
        }

        self.last_error_ms = now_ms;
        std.log.warn("failed to {s} elf \"{s}\"; keeping existing debug info: {s}", .{ action, self.path, @errorName(err) });
    }
};

const ElfFile = struct {
    const max_name_len: usize = 128;

    name: []const u8,
    path: []const u8,

    lookup: *ReloadableLookup,

    // file: std.fs.File,
    // dwarf: dwarf.DwarfInfo,
    // mem: MapResult,
};

const max_suffix_len = 3 + 8 * 2; // ":0x" + 8 hex encoded bytes

const ElfSet = std.StringArrayHashMap(ElfFile);

/// Writes symbol, source location, and section information for the given address.
fn render_elf_data(elf_addr: u64, elf: *ElfFile, output: *std.io.BufferedWriter(4096, std.fs.File.Writer)) !void {
    const writer = output.writer();
    var path_buf: [4096]u8 = undefined;
    var symbol_buf: [4096]u8 = undefined;
    const resource = elf.lookup;

    resource.lock();
    defer resource.unlock();

    try resource.refreshLocked(false);
    const lookup = resource.lookup;

    const maybe_symbol = lookup.get_symbol(&symbol_buf, elf_addr);
    const maybe_location = lookup.get_location(&path_buf, elf_addr);
    const maybe_section = lookup.get_section(elf_addr);

    if (maybe_symbol == null and maybe_location == null and maybe_section == null) {
        try writer.writeAll("[???]");
        return;
    }

    try writer.writeAll("[");

    var wrote_anything = false;

    if (maybe_location) |location| {
        if (location.file) |file| {
            try writer.print("{s}", .{file});
        }
        if (location.line) |line| {
            if (location.file != null) {
                try writer.writeAll(":");
            }
            try writer.print("{}", .{line});
            if (location.column) |column| {
                try writer.print(":{}", .{column});
            }
        }
        wrote_anything = true;
    }

    if (maybe_symbol) |symbol| {
        if (wrote_anything) try writer.writeAll(" ");
        try writer.print("\"{}\"", .{std.zig.fmtEscapes(symbol)});
        wrote_anything = true;
    }

    if (maybe_section) |section| {
        if (wrote_anything) try writer.writeAll(" ");
        try writer.print("in \"{}\"", .{std.zig.fmtEscapes(section)});
        wrote_anything = true;
    }

    try writer.writeAll("]");
}

const ParseOut = struct {
    elf: *ElfFile,
    addr: u64,
};

/// Tries to parse the trailing `:<addr>` portion from the buffered line output.
fn parse_poll_result(
    elves: ElfSet,
    line_buffer: RingBuffer,
    bit_width: BitWidth,
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

    try std.testing.expect(parse_poll_result(empty_elves, rb, .bits32) == null);
    try std.testing.expect(parse_poll_result(empty_elves, rb, .bits64) == null);
}

test "parsePollResult bits32 hit" {
    var empty_elves = ElfSet.init(std.testing.allocator);
    defer empty_elves.deinit();

    try empty_elves.put("basic", .{
        .name = "basic",
        .path = undefined,
        .lookup = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("basic:0xAABBCCDD");

    const bits32_result = parse_poll_result(empty_elves, rb, .bits32);
    const bits64_result = parse_poll_result(empty_elves, rb, .bits64);

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
        .path = undefined,
        .lookup = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("basic:0xAABBCCDD00112233");

    const bits32_result = parse_poll_result(empty_elves, rb, .bits32);
    const bits64_result = parse_poll_result(empty_elves, rb, .bits64);

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
        .path = undefined,
        .lookup = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("bas1c:0xAABBCCDD");

    const bits32_result = parse_poll_result(empty_elves, rb, .bits32);
    const bits64_result = parse_poll_result(empty_elves, rb, .bits64);

    try std.testing.expect(bits32_result == null);
    try std.testing.expect(bits64_result == null);
}

test "parsePollResult bits64 missing" {
    var empty_elves = ElfSet.init(std.testing.allocator);
    defer empty_elves.deinit();

    try empty_elves.put("basic", .{
        .name = "basic",
        .path = undefined,
        .lookup = undefined,
    });

    var rb = RingBuffer{};
    rb.push_slice("bas1ic:0xAABBCCDD00112233");

    const bits32_result = parse_poll_result(empty_elves, rb, .bits32);
    const bits64_result = parse_poll_result(empty_elves, rb, .bits64);

    try std.testing.expect(bits32_result == null);
    try std.testing.expect(bits64_result == null);
}

/// Reads poller output, forwards it, and augments recognized addresses with metadata.
fn consume_poll_result(
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

            if (parse_poll_result(elves, line_buffer.*, .bits32)) |result| {
                try render_elf_data(result.addr, result.elf, output);
            } else if (parse_poll_result(elves, line_buffer.*, .bits64)) |result| {
                try render_elf_data(result.addr, result.elf, output);
            }
        }
    }
}

/// Entry point for the debug-filter executable.
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

                .lookup = undefined,
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

    var created_lookups = std.ArrayList(*ReloadableLookup).init(allocator);
    defer created_lookups.deinit();
    defer {
        for (created_lookups.items) |lookup| {
            lookup.destroy();
        }
    }

    for (elves.values()) |*value| {
        const lookup = try ReloadableLookup.create(allocator, value.path);
        errdefer lookup.destroy();
        try created_lookups.append(lookup);
        value.lookup = lookup;
    }

    // Backup termios settings so the a crashing or force-killed application
    // might not fuck up our terminal session:
    const terminal_config_backup = try Termios.read();
    defer terminal_config_backup.apply() catch |err| std.log.err("failed to re-apply terminal settings: {}", .{err});

    const term = try spawn_and_filter_subprocess(elves, app_argv, allocator);
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

/// Runs the target process and streams its stdio through the filter pipeline.
fn spawn_and_filter_subprocess(elves: ElfSet, app_argv: []const []const u8, allocator: std.mem.Allocator) !std.process.Child.Term {
    var proc = std.process.Child.init(app_argv, allocator);

    proc.stdin_behavior = .Inherit;
    proc.stdout_behavior = .Pipe;
    proc.stderr_behavior = .Pipe;

    try proc.spawn();

    filter_and_forward_stdio(allocator, elves, &proc) catch |err| {
        std.log.err("failed to forward stdio: {}", .{err});
        return try proc.kill();
    };

    return try proc.wait();
}

/// Polls the child process output streams and forwards them to stdout/stderr.
fn filter_and_forward_stdio(allocator: std.mem.Allocator, elves: ElfSet, proc: *std.process.Child) !void {
    var poller = std.io.poll(allocator, enum { stdout, stderr }, .{
        .stdout = proc.stdout.?,
        .stderr = proc.stderr.?,
    });
    defer poller.deinit();

    var stdout_line_buffer = RingBuffer{};
    var stderr_line_buffer = RingBuffer{};

    var stdout_buffered_writer = std.io.bufferedWriter(std.io.getStdOut().writer());
    var stderr_buffered_writer = std.io.bufferedWriter(std.io.getStdErr().writer());

    try refresh_all_elves(elves);

    while (try poller.poll()) {
        try refresh_all_elves(elves);
        try consume_poll_result(
            elves,
            &stdout_buffered_writer,
            &stdout_line_buffer,
            poller.fifo(.stdout),
        );
        try consume_poll_result(
            elves,
            &stderr_buffered_writer,
            &stderr_line_buffer,
            poller.fifo(.stderr),
        );
    }

    try stdout_buffered_writer.flush();
    try stderr_buffered_writer.flush();
}

fn refresh_all_elves(elves: ElfSet) !void {
    for (elves.values()) |value| {
        const resource = value.lookup;
        resource.lock();
        resource.refreshLocked(false) catch |err| {
            resource.unlock();
            return err;
        };
        resource.unlock();
    }
}

const RingBuffer = struct {
    const max_item_count = ElfFile.max_name_len + max_suffix_len;

    data: [max_item_count]u8 = .{0} ** max_item_count,
    next_element: usize = 0,

    /// Stores a single byte in the ring buffer.
    pub fn push(rb: *RingBuffer, byte: u8) void {
        rb.data[rb.next_element] = byte;
        rb.next_element += 1;
        if (rb.next_element >= rb.data.len) {
            rb.next_element = 0;
        }
    }

    /// Stores all bytes from the provided slice in FIFO order.
    pub fn push_slice(rb: *RingBuffer, slice: []const u8) void {
        for (slice) |byte| {
            rb.push(byte);
        }
    }

    /// Returns the `index`th most recent element.
    pub fn get(rb: RingBuffer, index: usize) u8 {
        std.debug.assert(index < rb.data.len);
        const actual_index = (rb.data.len + rb.next_element - 1 - index) % rb.data.len;
        return rb.data[actual_index];
    }

    /// Copies the ring contents into `array`, placing the newest element last.
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

    /// Declares the Windows API for creating a file mapping.
    extern "kernel32" fn CreateFileMappingA(
        hFile: win.HANDLE,
        lpFileMappingAttributes: ?*anyopaque,
        flProtect: win.DWORD,
        dwMaximumSizeHigh: win.DWORD,
        dwMaximumSizeLow: win.DWORD,
        lpName: ?win.LPCSTR,
    ) ?win.HANDLE;

    /// Declares the Windows API for mapping a view of a file.
    extern "kernel32" fn MapViewOfFile(
        hFileMappingObject: win.HANDLE,
        dwDesiredAccess: win.DWORD,
        dwFileOffsetHigh: win.DWORD,
        dwFileOffsetLow: win.DWORD,
        dwNumberOfBytesToMap: win.SIZE_T,
    ) ?win.LPVOID;

    /// Declares the Windows API for unmapping a view of a file.
    extern "kernel32" fn UnmapViewOfFile(
        lpBaseAddress: win.LPCVOID,
    ) win.BOOL;

    const Handle = win.HANDLE;

    /// Creates a read-only mapping for the provided file.
    fn create_mapping(file: std.fs.File) !Handle {
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

    /// Maps a read-only view of the file mapping into memory.
    fn map_view(mapping: Handle, size: usize) !*anyopaque {
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

    /// Unmaps a previously mapped view from memory.
    fn unmap_view(addr: *const anyopaque) !void {
        const res = UnmapViewOfFile(addr);
        if (res == 0) return error.UnmapFailed;
    }
};

const MapResult = if (is_windows) struct {
    mapping_handle: windows.Handle,
    mem: []align(page_size) const u8,

    /// Releases the memory mapping and associated OS handle.
    fn deinit(self: MapResult) void {
        windows.unmap_view(@ptrCast(self.mem.ptr)) catch {};
        std.os.windows.CloseHandle(self.mapping_handle);
    }
} else []align(page_size) const u8;

/// Maps the entire file into memory and returns the mapping result.
fn map_whole_file(file: std.fs.File) !MapResult {
    const file_len = std.math.cast(usize, try file.getEndPos()) orelse std.math.maxInt(usize);
    defer file.close();

    if (is_windows) {
        const mapping = try windows.create_mapping(file);
        const mapped_view = try windows.map_view(mapping, file_len);
        const mapped_mem = @as([*]align(page_size) const u8, @ptrCast(@alignCast(mapped_view)))[0..file_len];
        return .{
            .mapping_handle = mapping,
            .mem = mapped_mem,
        };
    }

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

/// Loads DWARF debug information and symbol metadata from the provided ELF file.
pub fn read_elf_debug_info(allocator: std.mem.Allocator, elf_file: std.fs.File) !struct {
    map_result: MapResult,
    dwarf_info: dwarf.DwarfInfo,
    address_width: BitWidth,
    symbols: []SymbolEntry,
    sections: []SectionEntry,
} {
    const elf = std.elf;
    const map_result = try map_whole_file(elf_file);
    errdefer {
        if (is_windows) {
            map_result.deinit();
        } else {
            std.posix.munmap(map_result);
        }
    }

    const mapped_mem: []align(page_size) const u8 = if (is_windows) map_result.mem else map_result;
    if (mapped_mem.len < elf.EI_NIDENT) return error.InvalidElfMagic;
    if (!std.mem.eql(u8, mapped_mem[0..4], elf.MAGIC)) return error.InvalidElfMagic;
    if (mapped_mem[elf.EI_VERSION] != 1) return error.InvalidElfVersion;

    const endian: std.builtin.Endian = switch (mapped_mem[elf.EI_DATA]) {
        elf.ELFDATA2LSB => .little,
        elf.ELFDATA2MSB => .big,
        else => return error.InvalidElfEndian,
    };

    var sections = DebugSections{};
    var width: BitWidth = undefined;
    var symbol_entries = std.ArrayList(SymbolEntry).init(allocator);
    errdefer symbol_entries.deinit();
    var section_entries = std.ArrayList(SectionEntry).init(allocator);
    errdefer section_entries.deinit();

    switch (mapped_mem[elf.EI_CLASS]) {
        elf.ELFCLASS32 => {
            width = .bits32;
            const hdr: *const elf.Elf32_Ehdr = @ptrCast(@alignCast(mapped_mem.ptr));
            try populate_sections32(mapped_mem, hdr, &sections, &symbol_entries, &section_entries);
        },
        elf.ELFCLASS64 => {
            width = .bits64;
            const hdr: *const elf.Elf64_Ehdr = @ptrCast(@alignCast(mapped_mem.ptr));
            try populate_sections64(mapped_mem, hdr, &sections, &symbol_entries, &section_entries);
        },
        else => return error.InvalidElfClass,
    }

    std.debug.assert(endian == .little); // this is our own debug info

    var di: dwarf.DwarfInfo = .{
        .endian = endian,
        .debug_info = sections.debug_info orelse return error.MissingDebugInfo,
        .debug_abbrev = sections.debug_abbrev orelse return error.MissingDebugInfo,
        .debug_str = sections.debug_str orelse return error.MissingDebugInfo,
        .debug_str_offsets = sections.debug_str_offsets,
        .debug_line = sections.debug_line orelse return error.MissingDebugInfo,
        .debug_line_str = sections.debug_line_str,
        .debug_ranges = sections.debug_ranges,
        .debug_loclists = sections.debug_loclists,
        .debug_rnglists = sections.debug_rnglists,
        .debug_addr = sections.debug_addr,
        .debug_names = sections.debug_names,
        .debug_frame = sections.debug_frame,
    };

    switch (width) {
        .bits32 => try dwarf.openDwarfDebugInfo(&di, u32, allocator),
        .bits64 => try dwarf.openDwarfDebugInfo(&di, u64, allocator),
    }

    const symbols_slice = try symbol_entries.toOwnedSlice();
    const sections_slice = try section_entries.toOwnedSlice();

    return .{
        .map_result = map_result,
        .dwarf_info = di,
        .address_width = width,
        .symbols = symbols_slice,
        .sections = sections_slice,
    };
}

const SymbolInfo = struct {
    symbol_name: []const u8 = "",
    compile_unit_name: []const u8 = "???",
    line_info: ?dwarf.LineInfo = null,
};

/// Retrieves symbol and line information for the given address.
fn get_symbol_from_dwarf(comptime Address: type, allocator: std.mem.Allocator, address: u64, di: *dwarf.DwarfInfo) !SymbolInfo {
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

/// Returns a slice starting at `offset` with the provided `size`.
fn chop_slice(ptr: []const u8, offset: u64, size: u64) error{Overflow}![]const u8 {
    const start = std.math.cast(usize, offset) orelse return error.Overflow;
    const end = start + (std.math.cast(usize, size) orelse return error.Overflow);
    return ptr[start..end];
}

/// Gathers debug sections and symbols from the 32-bit ELF header.
fn populate_sections32(
    mapped_mem: []const u8,
    hdr: *const std.elf.Elf32_Ehdr,
    sections: *DebugSections,
    symbol_entries: *std.ArrayList(SymbolEntry),
    section_entries: *std.ArrayList(SectionEntry),
) !void {
    const shoff = std.math.cast(usize, hdr.e_shoff) orelse return error.Overflow;
    const shnum = std.math.cast(usize, hdr.e_shnum) orelse return error.Overflow;
    const shentsize = std.math.cast(usize, hdr.e_shentsize) orelse return error.Overflow;
    if (shentsize != @sizeOf(std.elf.Elf32_Shdr)) return error.InvalidDebugInfo;
    const sh_table_size = std.math.mul(usize, shentsize, shnum) catch return error.Overflow;
    if (shoff > mapped_mem.len or shoff + sh_table_size > mapped_mem.len) return error.InvalidDebugInfo;

    const shdrs = @as([*]const std.elf.Elf32_Shdr, @ptrCast(@alignCast(mapped_mem[shoff..].ptr)))[0..shnum];

    if (hdr.e_shstrndx >= shdrs.len) return error.InvalidDebugInfo;
    const str_hdr = shdrs[hdr.e_shstrndx];
    const header_strings = try chop_slice(mapped_mem, @as(u64, str_hdr.sh_offset), @as(u64, str_hdr.sh_size));

    try populate_sections_common(std.elf.Elf32_Shdr, mapped_mem, header_strings, sections, symbol_entries, section_entries, shdrs);
}

/// Gathers debug sections and symbols from the 64-bit ELF header.
fn populate_sections64(
    mapped_mem: []const u8,
    hdr: *const std.elf.Elf64_Ehdr,
    sections: *DebugSections,
    symbol_entries: *std.ArrayList(SymbolEntry),
    section_entries: *std.ArrayList(SectionEntry),
) !void {
    const shoff = std.math.cast(usize, hdr.e_shoff) orelse return error.Overflow;
    const shnum = std.math.cast(usize, hdr.e_shnum) orelse return error.Overflow;
    const shentsize = std.math.cast(usize, hdr.e_shentsize) orelse return error.Overflow;
    if (shentsize != @sizeOf(std.elf.Elf64_Shdr)) return error.InvalidDebugInfo;
    const sh_table_size = std.math.mul(usize, shentsize, shnum) catch return error.Overflow;
    if (shoff > mapped_mem.len or shoff + sh_table_size > mapped_mem.len) return error.InvalidDebugInfo;

    const shdrs = @as([*]const std.elf.Elf64_Shdr, @ptrCast(@alignCast(mapped_mem[shoff..].ptr)))[0..shnum];

    if (hdr.e_shstrndx >= shdrs.len) return error.InvalidDebugInfo;
    const str_hdr = shdrs[hdr.e_shstrndx];
    const header_strings = try chop_slice(mapped_mem, str_hdr.sh_offset, str_hdr.sh_size);

    try populate_sections_common(std.elf.Elf64_Shdr, mapped_mem, header_strings, sections, symbol_entries, section_entries, shdrs);
}

/// Shared implementation for extracting sections and symbols from the section headers.
fn populate_sections_common(
    comptime ShdrType: type,
    mapped_mem: []const u8,
    header_strings: []const u8,
    sections: *DebugSections,
    symbol_entries: *std.ArrayList(SymbolEntry),
    section_entries: *std.ArrayList(SectionEntry),
    shdrs: []const ShdrType,
) !void {
    for (shdrs) |shdr| {
        if (shdr.sh_type == std.elf.SHT_NULL) continue;

        const name_off = std.math.cast(usize, shdr.sh_name) orelse return error.InvalidDebugInfo;
        if (name_off >= header_strings.len) return error.InvalidDebugInfo;

        const name = std.mem.sliceTo(header_strings[name_off..], 0);
        const addr = std.math.cast(u64, shdr.sh_addr) orelse return error.Overflow;
        const size = std.math.cast(u64, shdr.sh_size) orelse return error.Overflow;

        if ((shdr.sh_flags & std.elf.SHF_ALLOC) != 0 and size != 0) {
            try section_entries.append(.{
                .name = name,
                .addr = addr,
                .size = size,
            });
        }

        const has_file_data = shdr.sh_type != std.elf.SHT_NOBITS;
        const slice = if (has_file_data)
            try chop_slice(mapped_mem, std.math.cast(u64, shdr.sh_offset) orelse return error.Overflow, size)
        else
            null;

        if (std.mem.eql(u8, name, ".debug_info")) {
            if (slice) |data| sections.debug_info = data;
        } else if (std.mem.eql(u8, name, ".debug_abbrev")) {
            if (slice) |data| sections.debug_abbrev = data;
        } else if (std.mem.eql(u8, name, ".debug_str")) {
            if (slice) |data| sections.debug_str = data;
        } else if (std.mem.eql(u8, name, ".debug_str_offsets")) {
            if (slice) |data| sections.debug_str_offsets = data;
        } else if (std.mem.eql(u8, name, ".debug_line")) {
            if (slice) |data| sections.debug_line = data;
        } else if (std.mem.eql(u8, name, ".debug_line_str")) {
            if (slice) |data| sections.debug_line_str = data;
        } else if (std.mem.eql(u8, name, ".debug_ranges")) {
            if (slice) |data| sections.debug_ranges = data;
        } else if (std.mem.eql(u8, name, ".debug_loclists")) {
            if (slice) |data| sections.debug_loclists = data;
        } else if (std.mem.eql(u8, name, ".debug_rnglists")) {
            if (slice) |data| sections.debug_rnglists = data;
        } else if (std.mem.eql(u8, name, ".debug_addr")) {
            if (slice) |data| sections.debug_addr = data;
        } else if (std.mem.eql(u8, name, ".debug_names")) {
            if (slice) |data| sections.debug_names = data;
        } else if (std.mem.eql(u8, name, ".debug_frame")) {
            if (slice) |data| sections.debug_frame = data;
        } else if (shdr.sh_type == std.elf.SHT_SYMTAB or shdr.sh_type == std.elf.SHT_DYNSYM) {
            if (slice) |data| try collect_symbol_entries(mapped_mem, shdrs, shdr, data, symbol_entries);
        }
    }
}

/// Collects symbol table entries and stores them in `symbol_entries`.
fn collect_symbol_entries(
    mapped_mem: []const u8,
    shdrs: anytype,
    shdr: anytype,
    section_data: []const u8,
    symbol_entries: *std.ArrayList(SymbolEntry),
) !void {
    if (comptime @TypeOf(shdr) == std.elf.Elf32_Shdr) {
        try collect_symbol_entries_typed(mapped_mem, shdrs, shdr, section_data, symbol_entries, std.elf.Elf32_Sym);
    } else {
        try collect_symbol_entries_typed(mapped_mem, shdrs, shdr, section_data, symbol_entries, std.elf.Elf64_Sym);
    }
}

/// Type-specific implementation for copying symbol table data into memory.
fn collect_symbol_entries_typed(
    mapped_mem: []const u8,
    shdrs: anytype,
    shdr: anytype,
    section_data: []const u8,
    symbol_entries: *std.ArrayList(SymbolEntry),
    comptime SymType: type,
) !void {
    const entsize = std.math.cast(usize, shdr.sh_entsize) orelse return error.InvalidDebugInfo;
    if (entsize == 0 or entsize != @sizeOf(SymType)) return error.InvalidDebugInfo;

    const symbol_count = std.math.cast(usize, shdr.sh_size / shdr.sh_entsize) orelse return error.InvalidDebugInfo;
    if (symbol_count == 0) return;

    if (section_data.len < symbol_count * entsize) return error.InvalidDebugInfo;

    const raw_symbols = @as([*]const SymType, @ptrCast(@alignCast(section_data.ptr)))[0..symbol_count];

    const str_index = std.math.cast(usize, shdr.sh_link) orelse return error.InvalidDebugInfo;
    if (str_index >= shdrs.len) return error.InvalidDebugInfo;
    const str_hdr = shdrs[str_index];
    const str_offset = std.math.cast(u64, str_hdr.sh_offset) orelse return error.Overflow;
    const str_size = std.math.cast(u64, str_hdr.sh_size) orelse return error.Overflow;
    const strings = try chop_slice(mapped_mem, str_offset, str_size);

    for (raw_symbols) |sym| {
        if (sym.st_shndx == std.elf.SHN_UNDEF) continue;

        const name_off = std.math.cast(usize, sym.st_name) orelse continue;
        if (name_off >= strings.len) continue;

        const name = std.mem.sliceTo(strings[name_off..], 0);
        if (name.len == 0) continue;

        const value = std.math.cast(u64, sym.st_value) orelse continue;
        const size = std.math.cast(u64, sym.st_size) orelse continue;

        try symbol_entries.append(.{
            .name = name,
            .value = value,
            .size = size,
            .info = sym.st_info,
        });
    }
}

const Termios = if (@import("builtin").os.tag == .windows)
    WindowsTermios
else
    PosixTermios;

const WindowsTermios = struct {
    /// Returns a placeholder terminal configuration on Windows.
    pub fn read() !Termios {
        return .{};
    }

    /// No-ops for terminal configuration on Windows.
    pub fn apply(ios: Termios) !void {
        _ = ios;
    }
};

const PosixTermios = struct {
    settings: [3]?std.posix.termios,

    /// Captures stdin/stdout/stderr terminal settings if available.
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

    /// Restores previously captured terminal state where possible.
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

pub const Lookup = struct {
    allocator: std.mem.Allocator,
    map_result: MapResult,
    dwarf_info: dwarf.DwarfInfo,
    address_width: BitWidth,
    symbols: []SymbolEntry,
    sections: []SectionEntry,

    pub const Location = struct {
        file: ?[]const u8,
        line: ?u32,
        column: ?u32,
    };

    /// Loads an ELF debug lookup from the given file path.
    pub fn create(allocator: std.mem.Allocator, path: []const u8) !*Lookup {
        var elf_info = blk: {
            const file = try std.fs.cwd().openFile(path, .{});
            break :blk try read_elf_debug_info(allocator, file);
        };
        errdefer allocator.free(elf_info.symbols);
        errdefer allocator.free(elf_info.sections);
        errdefer elf_info.dwarf_info.deinit(allocator);
        errdefer if (is_windows) {
            elf_info.map_result.deinit();
        } else {
            std.posix.munmap(elf_info.map_result);
        };

        const self = try allocator.create(Lookup);
        self.* = .{
            .allocator = allocator,
            .map_result = elf_info.map_result,
            .dwarf_info = elf_info.dwarf_info,
            .address_width = elf_info.address_width,
            .symbols = elf_info.symbols,
            .sections = elf_info.sections,
        };
        return self;
    }

    /// Releases all resources associated with the lookup.
    pub fn destroy(self: *Lookup) void {
        self.allocator.free(self.symbols);
        self.allocator.free(self.sections);
        self.dwarf_info.deinit(self.allocator);
        if (is_windows) {
            self.map_result.deinit();
        } else {
            std.posix.munmap(self.map_result);
        }
        self.allocator.destroy(self);
    }

    /// Resolves a source location for an address, storing the file path in `path_buf`.
    pub fn get_location(self: *Lookup, path_buf: []u8, addr: u64) ?Location {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const local_allocator = arena.allocator();

        const symbol_info = switch (self.address_width) {
            .bits32 => get_symbol_from_dwarf(u32, local_allocator, addr, &self.dwarf_info),
            .bits64 => get_symbol_from_dwarf(u64, local_allocator, addr, &self.dwarf_info),
        } catch |err| switch (err) {
            error.MissingDebugInfo, error.InvalidDebugInfo => return null,
            else => return null,
        };

        const line_info = symbol_info.line_info orelse return null;
        if (line_info.file_name.len > path_buf.len) return null;

        @memcpy(path_buf[0..line_info.file_name.len], line_info.file_name);
        const file_slice = path_buf[0..line_info.file_name.len];

        var line_opt: ?u32 = null;
        if (line_info.line != 0) {
            if (std.math.cast(u32, line_info.line)) |line| {
                line_opt = line;
            }
        }

        var column_opt: ?u32 = null;
        if (line_info.column != 0) {
            if (std.math.cast(u32, line_info.column)) |column| {
                column_opt = column;
            }
        }

        return .{
            .file = if (file_slice.len != 0) file_slice else null,
            .line = line_opt,
            .column = column_opt,
        };
    }

    /// Resolves the best matching symbol name for the given address.
    pub fn get_symbol(self: *Lookup, sym_buf: []u8, addr: u64) ?[]u8 {
        if (self.dwarf_info.getSymbolName(addr)) |name| {
            if (name.len > sym_buf.len) return null;
            @memcpy(sym_buf[0..name.len], name);
            return sym_buf[0..name.len];
        }

        if (self.find_symbol_name(addr)) |fallback_name| {
            if (fallback_name.len > sym_buf.len) return null;
            @memcpy(sym_buf[0..fallback_name.len], fallback_name);
            return sym_buf[0..fallback_name.len];
        }

        return null;
    }

    /// Resolves the section name containing the given address.
    pub fn get_section(self: *Lookup, addr: u64) ?[]const u8 {
        return self.find_section_name(addr);
    }

    /// Finds the closest symbol based on address ordering and type.
    fn find_symbol_name(self: *Lookup, addr: u64) ?[]const u8 {
        var best_index: ?usize = null;
        var best_value: u64 = 0;
        var best_is_func = false;

        for (self.symbols, 0..) |entry, idx| {
            if (entry.value == 0) continue;
            if (addr < entry.value) continue;

            var range_end: u64 = std.math.maxInt(u64);
            if (entry.size != 0) {
                range_end = std.math.add(u64, entry.value, entry.size) catch continue;
            } else {
                var next_value: ?u64 = null;
                for (self.symbols) |other| {
                    if (other.value <= entry.value) continue;
                    next_value = if (next_value) |current|
                        if (other.value < current) other.value else current
                    else
                        other.value;
                }
                range_end = next_value orelse std.math.add(u64, entry.value, 1) catch std.math.maxInt(u64);
            }

            if (addr >= range_end) continue;

            const entry_type = entry.info & 0x0f;
            const is_func = entry_type == std.elf.STT_FUNC;

            if (best_index == null or
                (is_func and !best_is_func) or
                (is_func == best_is_func and entry.value > best_value))
            {
                best_index = idx;
                best_value = entry.value;
                best_is_func = is_func;
            }
        }

        if (best_index) |idx| {
            return self.symbols[idx].name;
        }
        return null;
    }

    /// Finds the section containing the specified address.
    fn find_section_name(self: *Lookup, addr: u64) ?[]const u8 {
        var best_index: ?usize = null;
        var best_addr: u64 = 0;

        for (self.sections, 0..) |entry, idx| {
            const start = entry.addr;
            const size = entry.size;

            if (size == 0) {
                if (addr != start) continue;
            } else {
                const end = std.math.add(u64, start, size) catch continue;
                if (addr < start or addr >= end) continue;
            }

            if (best_index == null or start > best_addr) {
                best_index = idx;
                best_addr = start;
            }
        }

        if (best_index) |idx| {
            return self.sections[idx].name;
        }
        return null;
    }
};
