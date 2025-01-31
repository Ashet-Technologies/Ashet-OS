//!
//! Links:
//! - https://refspecs.linuxbase.org/elf/elf.pdf
//!
const std = @import("std");
const libashet = @import("ashet");
const ashex = @import("ashex");

const logger = std.log.scoped(.ashex_loader);
const elf = std.elf;

const loader = @import("../loader.zig");
const ashet = @import("../../main.zig");
const system_arch = @import("builtin").target.cpu.arch;

const max_syscall_name_length = blk: {
    var len: usize = 0;
    for (std.enums.values(ashet.syscalls.SystemCall)) |val| {
        len = @max(len, @tagName(val).len);
    }
    break :blk len;
};

const max_syscall_count = std.enums.values(ashet.syscalls.SystemCall).len;

pub fn load(file: *libashet.fs.File, allocator: std.mem.Allocator) !loader.LoadedExecutable {
    const expected_machine: ashex.FileType, const expected_platform: ashex.Platform = switch (system_arch) {
        .riscv32 => .{ .machine32_le, .riscv32 },
        .x86 => .{ .machine32_le, .x86 },
        .arm, .thumb => .{ .machine32_le, .arm32 },
        else => @compileError("Unsupported machine type: " ++ @tagName(system_arch)),
    };

    const header = blk: {
        var header_chunk: [512]u8 = undefined;

        if (try file.read(0, &header_chunk) != 512)
            return error.InvalidAshexExecutable;

        var header_fbs = std.io.fixedBufferStream(&header_chunk);

        logger.info("ashex header: {}", .{std.fmt.fmtSliceHexUpper(&header_chunk)});

        const reader = header_fbs.reader();

        var magic: [4]u8 = undefined;
        try reader.readNoEof(&magic);
        if (!std.mem.eql(u8, &magic, &ashex.file_magic))
            return error.InvalidAshexExecutable;

        const file_version = try reader.readInt(u8, .little);
        if (file_version != 0) {
            logger.err("version mismatch. expected {}, but found {}", .{
                0,
                file_version,
            });
            return error.AshexUnsupportedVersion;
        }

        const file_type = try reader.readInt(u8, .little);
        if (file_type != @intFromEnum(expected_machine)) {
            logger.err("machine mismatch. expected {}, but found {}", .{
                @intFromEnum(expected_machine),
                file_type,
            });
            return error.AshexMachineMismatch;
        }

        const file_platform = try reader.readInt(u8, .little);
        if (file_platform != @intFromEnum(expected_platform)) {
            logger.err("platform mismatch. expected {}, but found {}", .{
                @intFromEnum(expected_platform),
                file_platform,
            });
            return error.AshexPlatformMismatch;
        }

        try reader.skipBytes(1, .{});

        const header: ashex.Header = .{
            .icon_size = try reader.readInt(u32, .little),
            .icon_offset = try reader.readInt(u32, .little),

            .vmem_size = try reader.readInt(u32, .little),
            .entry_point = try reader.readInt(u32, .little),

            .syscall_offset = try reader.readInt(u32, .little),
            .syscall_count = try reader.readInt(u32, .little),

            .load_header_offset = try reader.readInt(u32, .little),
            .load_header_count = try reader.readInt(u32, .little),

            .bss_header_offset = try reader.readInt(u32, .little),
            .bss_header_count = try reader.readInt(u32, .little),

            .relocation_offset = try reader.readInt(u32, .little),
            .relocation_count = try reader.readInt(u32, .little),
        };

        const actual_checksum: u32 = std.hash.Crc32.hash(header_chunk[0..508]);
        const header_checksum: u32 = std.mem.readInt(u32, header_chunk[508..512], .little);

        if (actual_checksum != header_checksum) {
            logger.err("checksum mismatch! header encodes 0x{X:0>8}, but header block has checksum 0x{X:0>8}", .{
                header_checksum,
                actual_checksum,
            });
            return error.InvalidAshexExecutable;
        }
        logger.debug("computed checksum: 0x{X:0>8}, stored checksum: 0x{X:0>8}", .{ actual_checksum, header_checksum });

        break :blk header;
    };

    logger.debug("vmem_size   = 0x{X:0>8}", .{header.vmem_size});
    logger.debug("entry_point = 0x{X:0>8}", .{header.entry_point});
    logger.debug("syscalls:     offset=0x{X:0>8}, count={}", .{
        header.syscall_offset, header.syscall_count,
    });
    logger.debug("load headers: offset=0x{X:0>8}, count={}", .{
        header.load_header_offset, header.load_header_count,
    });
    logger.debug("bss headers:  offset=0x{X:0>8}, count={}", .{
        header.bss_header_offset, header.bss_header_count,
    });
    logger.debug("relocations:  offset=0x{X:0>8}, count={}", .{
        header.relocation_offset, header.relocation_count,
    });
    logger.debug("icon:         offset=0x{X:0>8}, size={}", .{
        header.icon_offset, header.icon_size,
    });

    const process_memory = try allocator.alignedAlloc(u8, ashet.memory.page_size, header.vmem_size);
    errdefer allocator.free(process_memory);

    const process_base = @intFromPtr(process_memory.ptr);

    if (header.load_header_count == 0)
        return error.AshexNoData;

    {
        try file.seekableStream().seekTo(header.load_header_offset);

        var buffered_reader = std.io.bufferedReaderSize(512, file.reader());
        const reader = buffered_reader.reader();

        for (0..header.load_header_count) |_| {
            const vmem_offset = try reader.readInt(u32, .little);
            const size = try reader.readInt(u32, .little);

            if (vmem_offset + size > process_memory.len)
                return error.AshexCorruptedFile;

            try reader.readNoEof(process_memory[vmem_offset..][0..size]);
        }
    }

    if (header.bss_header_count > 0) {
        try file.seekableStream().seekTo(header.bss_header_offset);

        var buffered_reader = std.io.bufferedReaderSize(512, file.reader());
        const reader = buffered_reader.reader();

        for (0..header.bss_header_count) |_| {
            const vmem_offset = try reader.readInt(u32, .little);
            const size = try reader.readInt(u32, .little);

            if (vmem_offset + size > process_memory.len)
                return error.AshexCorruptedFile;

            @memset(process_memory[vmem_offset..][0..size], 0);
        }
    }

    var syscall_mapping_buffer: [max_syscall_count]usize = undefined;
    const syscall_mapping = syscall_mapping_buffer[0..header.syscall_count];
    if (syscall_mapping.len > 0) {
        try file.seekableStream().seekTo(header.syscall_offset);

        var buffered_reader = std.io.bufferedReaderSize(512, file.reader());
        const reader = buffered_reader.reader();

        for (syscall_mapping) |*function_addr| {
            var syscall_name_buffer: [max_syscall_name_length]u8 = undefined;

            const name_len = try reader.readInt(u16, .little);
            if (name_len > syscall_name_buffer.len)
                return error.AshexUnsupportedSyscall;

            const name = syscall_name_buffer[0..name_len];
            try reader.readNoEof(name);

            const syscall_id = std.meta.stringToEnum(ashet.syscalls.SystemCall, name) orelse {
                logger.err("could not find syscall '{}'", .{
                    std.zig.fmtEscapes(name),
                });
                return error.AshexUnsupportedSyscall;
            };

            function_addr.* = ashet.syscalls.get_address(syscall_id);
        }
    }

    if (header.relocation_count > 0) {
        try file.seekableStream().seekTo(header.relocation_offset);

        var buffered_reader = std.io.bufferedReaderSize(512, file.reader());
        const reader = buffered_reader.reader();

        for (0..header.relocation_count) |_| {
            // Fetch fields:
            const offset: u32 = try reader.readInt(u32, .little);
            const raw_type = try reader.readInt(u16, .little);
            const reloc_type: ashex.RelocationType = @bitCast(raw_type);

            const syscall_index: u16 = if (reloc_type.syscall != .unused)
                try reader.readInt(u16, .little)
            else
                0;

            const addend: i32 = if (reloc_type.addend != .unused)
                try reader.readInt(i32, .little)
            else
                0;

            // Preprocess fields:
            const syscall_addr: usize = if (reloc_type.syscall != .unused)
                if (syscall_index < syscall_mapping.len)
                    syscall_mapping[syscall_index]
                else
                    return error.AshexInvalidSyscallIndex
            else
                0;

            switch (reloc_type.size) {
                .word8 => @panic(".word8 not supported yet!"),
                .word16 => @panic(".word16 not supported yet!"),
                .word64 => @panic(".word64 not supported yet!"),

                inline else => |size| {
                    const T = switch (size) {
                        .word8 => u8,
                        .word16 => u16,
                        .word32 => u32,
                        .word64 => u64,
                    };

                    const self = if (reloc_type.self != .unused)
                        read(process_memory, T, offset)
                    else
                        0;

                    if (offset + @sizeOf(T) > process_memory.len)
                        return error.AshexInvalidRelocation;

                    var value: T = 0;

                    value = apply(value, reloc_type.self, self);
                    value = apply(value, reloc_type.addend, @intCast(addend));
                    value = apply(value, reloc_type.base, @intCast(process_base));
                    value = apply(value, reloc_type.offset, @intCast(offset));
                    value = apply(value, reloc_type.syscall, @intCast(syscall_addr));

                    logger.info("{{{s}}}0x{X:0>8}/0x{X:0>8} = 0x{X:0>8} (was: {X:0>8})", .{
                        @typeName(T),
                        @intFromPtr(process_memory.ptr) + offset,
                        offset,
                        value,
                        read(process_memory, T, offset),
                    });

                    write(process_memory, T, offset, value);
                },
            }
        }
    }

    return .{
        .process_memory = process_memory,
        .entry_point = process_base + header.entry_point,
    };
}

fn expand(comptime T: type, src: anytype) std.meta.Int(@typeInfo(@TypeOf(src)).Int.signedness, @bitSizeOf(T)) {
    return src;
}

fn apply(input: anytype, field: ashex.RelocationField, value: @TypeOf(input)) @TypeOf(input) {
    return switch (field) {
        .unused => input,
        .add => input +% value,
        .subtract => input -% value,
    };
}

fn read(memory: []u8, comptime T: type, offset: usize) T {
    return @bitCast(memory[offset..][0..@sizeOf(T)].*);
}

fn write(memory: []u8, comptime T: type, offset: usize, value: T) void {
    memory[offset..][0..@sizeOf(T)].* = @bitCast(value);
}
