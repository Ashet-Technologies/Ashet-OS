const std = @import("std");

const elf = std.elf;

const CliOptions = struct {
    bits: enum { @"32", @"64" } = .@"32",
    base: ?u64 = null,
    limit: ?u64 = null,
    output: []const u8 = "-",
};

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);

    const allocator = arena.allocator();

    const cli_options: CliOptions = .{
        .bits = .@"32",
        .base = 0x1000_0000,
        .limit = 0x1200_0000,
    };

    if (cli_options.output.len == 0) {
        return usage_error("--output file must be a non-empty path or - for stdout.");
    }

    // const address_range: AddrRange = .{
    //     .base = cli_options.base orelse switch (cli_options.bits) {
    //         .@"32" => std.math.minInt(u32),
    //         .@"64" => return usage_error("--base and --limit must both be given for a 64 bit analysis."),
    //     },
    //     .limit = cli_options.limit orelse switch (cli_options.bits) {
    //         .@"32" => std.math.maxInt(u32),
    //         .@"64" => return usage_error("--base and --limit must both be given for a 64 bit analysis."),
    //     },
    // };

    // if (address_range.base > address_range.limit) {
    //     return usage_error("--base must not be higher than --limit.");
    // }

    var input_file = try std.fs.cwd().openFile("zig-out/arm-ashet-hc/kernel.elf", .{});
    defer input_file.close();

    const output_to_stdout = std.mem.eql(u8, cli_options.output, "-");
    var output_disk_file: std.fs.AtomicFile = undefined;
    const svg: SvgWriter = if (output_to_stdout)
        .{ .writer = std.io.getStdOut().writer() }
    else blk: {
        output_disk_file = try std.fs.cwd().atomicFile(cli_options.output, .{});
        break :blk .{ .writer = output_disk_file.file.writer() };
    };

    defer if (output_to_stdout)
        output_disk_file.deinit();

    var header = try elf.Header.read(&input_file);

    switch (cli_options.bits) {
        .@"32" => if (header.is_64) {
            std.log.err("elf file encodes 64 bit, but a 32 bit file was expected!", .{});
            return 1;
        },
        .@"64" => if (!header.is_64) {
            std.log.err("elf file encodes 32 bit, but a 64 bit file was expected!", .{});
            return 1;
        },
    }

    // const plow: u64, const phigh: u64 = blk: {
    //     var pgm_headers = header.program_header_iterator(&input_file);
    //     var low: u64 = std.math.maxInt(u64);
    //     var high: u64 = std.math.minInt(u64);
    //     while (try pgm_headers.next()) |pgm_header| {
    //         if (pgm_header.p_type != elf.PT_LOAD)
    //             continue;
    //         low = @min(low, pgm_header.p_paddr);
    //         high = @max(high, pgm_header.p_paddr + pgm_header.p_memsz);
    //     }
    //     break :blk .{ low, high };
    // };

    const layout: [memories.len]LayoutInfo, const height: u32 = blk: {
        var layout: [memories.len]LayoutInfo = undefined;
        var top: f64 = 0;

        for (&layout, 0..) |*dst, i| {
            const mem = memories[i];

            dst.* = .{
                .memory = mem,
                .header = top,
                .top = top + LayoutInfo.header_size,
                .height = LayoutInfo.raw_to_pixels(mem.size(), mem.bytes_per_pixel),
            };

            std.log.info("[{}] = \"{s}\" B=0x{X:0>8} L=0x{X:0>8} T={d} H={d}", .{
                i,
                mem.name,
                mem.begin,
                mem.size(),
                dst.top,
                dst.height,
            });

            top = @ceil(top + LayoutInfo.header_size + dst.height);
        }
        break :blk .{ layout, @intFromFloat(top) };
    };

    try svg.write_header(300, height);

    for (layout) |item| {
        try svg.text(
            item.memory.name,
            50,
            item.top - 1,
            .{
                .vertical_alignment = .bottom,
                .horizontal_alignment = .center,
                .font_size = 10,
            },
        );

        try svg.rect(.{
            .x = 0,
            .y = item.top,
            .width = 100,
            .height = item.height,
            .color = "#EEEEEE",
        });

        try svg.text(
            item.memory.name,
            250,
            item.top - 1,
            .{
                .vertical_alignment = .bottom,
                .horizontal_alignment = .center,
                .font_size = 10,
            },
        );

        try svg.rect(.{
            .x = 200,
            .y = item.top,
            .width = 100,
            .height = item.height,
            .color = "#EEEEEE",
        });
    }

    const color_lut: []const []const u8 = &.{
        "#FF0000",
        "#00BFFF",
        "#FF7F00",
        "#003FFF",
        "#FEFF00",
        "#3F00FF",
        "#7FFF00",
        "#BF00FF",
        "#00FF00",
        "#FF00BF",
        "#00FF7F",
        "#FF003F",
        "#00FEFF",
        "#FF3F00",
        "#007FFF",
        "#FFBF00",
        "#0000FF",
        "#BFFF00",
        "#7F00FF",
        "#3FFF00",
        "#FF00FE",
        "#00FF3F",
        "#FF007F",
        "#00FFBF",
    };

    var program_headers: std.ArrayList(elf.Elf64_Phdr) = .init(allocator);

    var pgm_headers = header.program_header_iterator(&input_file);
    while (try pgm_headers.next()) |pgm_header| {
        if (pgm_header.p_type != elf.PT_LOAD)
            continue;

        const current_id = program_headers.items.len;
        for (program_headers.items, 0..) |previous, i| {
            if (range_overlap_check(pgm_header.p_paddr, pgm_header.p_filesz, previous.p_paddr, previous.p_filesz)) {
                std.log.err("program headers {} and {} overlap in physical memory", .{
                    i, program_headers.items.len,
                });
            }
            if (range_overlap_check(pgm_header.p_vaddr, pgm_header.p_memsz, previous.p_vaddr, previous.p_memsz)) {
                std.log.err("program headers {} and {} overlap in virtual memory", .{
                    i, program_headers.items.len,
                });
            }
        }

        try program_headers.append(pgm_header);

        var title_buf: [1024]u8 = undefined;

        const flag_x = has_flag(pgm_header.p_flags, elf.PF_X);
        const flag_w = has_flag(pgm_header.p_flags, elf.PF_W);
        const flag_r = has_flag(pgm_header.p_flags, elf.PF_R);

        const vaddr = pgm_header.p_vaddr;
        const paddr = pgm_header.p_paddr;
        const filesz = pgm_header.p_filesz;
        const memsz = pgm_header.p_memsz;

        var color_buf: [16]u8 = undefined;
        const color = try std.fmt.bufPrint(&color_buf, "{s}80", .{
            color_lut[current_id % color_lut.len],
        });

        std.log.info("vmem=0x{X:0>8}…0x{X:0>8} pmem=0x{X:0>8}…0x{X:0>8} init=0x{X:0>8} size=0x{X:0>8} R={} W={} X={}", .{
            vaddr,
            vaddr + memsz,
            paddr,
            paddr + filesz,
            filesz,
            memsz,

            @intFromBool(flag_r),
            @intFromBool(flag_w),
            @intFromBool(flag_x),
        });

        try svg.comment("vmem=0x{X:0>8}…0x{X:0>8} pmem=0x{X:0>8}…0x{X:0>8} init=0x{X:0>8} size=0x{X:0>8} R={} W={} X={}", .{
            vaddr,
            vaddr + memsz,
            paddr,
            paddr + filesz,
            filesz,
            memsz,

            @intFromBool(flag_r),
            @intFromBool(flag_w),
            @intFromBool(flag_x),
        });

        const x0b = 100;
        const x0a = 130;
        const x1b = 200;
        const x1a = 170;

        const v_index, _ = find_memory(vaddr) orelse {
            std.log.err("memory address 0x{X:0>8} is not contained in a memory!", .{vaddr});
            continue;
        };
        const v_layout = layout[v_index];

        const v_top = v_layout.addr_to_pixels(vaddr);
        const v_full_height = @ceil(v_layout.size_to_pixels(memsz));
        const v_load_height = @ceil(v_layout.size_to_pixels(filesz));
        try svg.rect(.{
            .x = x1b,
            .y = v_top,
            .width = 80,
            .height = v_full_height,
            .color = color,
            .title = try std.fmt.bufPrint(&title_buf, "offset: 0x{X:0>8}\nsize:    0x{X:0>8} ({d:.2})\n", .{
                vaddr,
                memsz,
                std.fmt.fmtIntSizeBin(memsz),
            }),
        });

        if (filesz > 0) {
            // Only render "physical" placement if the data is actually present

            const p_index, _ = find_memory(paddr) orelse {
                std.log.err("memory address 0x{X:0>8} is not contained in a memory!", .{paddr});
                continue;
            };
            const p_layout = layout[p_index];

            const p_top = p_layout.addr_to_pixels(paddr);
            const p_height = @ceil(p_layout.size_to_pixels(filesz));
            try svg.rect(.{
                .x = 10,
                .y = p_top,
                .width = x0b - 10,
                .height = p_height,
                .color = color,
                .title = try std.fmt.bufPrint(&title_buf, "offset: 0x{X:0>8}\nsize:    0x{X:0>8} ({d:.2})\n", .{
                    paddr,
                    filesz,
                    std.fmt.fmtIntSizeBin(filesz),
                }),
            });

            var path_buffer: [256]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buffer, "M {[x0b]} {[y0t]}" ++
                " C {[x0a]} {[y0t]} {[x1a]} {[y1t]} {[x1b]} {[y1t]}" ++
                " V {[y1b]}" ++
                " C {[x1a]} {[y1b]} {[x0a]} {[y0b]} {[x0b]} {[y0b]}" ++
                " Z", .{
                .y0t = p_top,
                .y0b = p_top + p_height,
                .y1t = v_top,
                .y1b = v_top + v_load_height,
                .x0b = x0b,
                .x0a = x0a,
                .x1b = x1b,
                .x1a = x1a,
            });
            try svg.path(path, .{
                .fill = color,
                .stroke = "none",
                .title = try std.fmt.bufPrint(&title_buf, "from: 0x{X:0>8}\nto:      0x{X:0>8}\nsize:  0x{X:0>8} ({d:.2})\n", .{
                    paddr,
                    vaddr,
                    filesz,
                    std.fmt.fmtIntSizeBin(filesz),
                }),
            });

            const path_top = try std.fmt.bufPrint(&path_buffer, "M {[x0b]} {[y0t]}" ++
                " C {[x0a]} {[y0t]} {[x1a]} {[y1t]} {[x1b]} {[y1t]}", .{
                .y0t = p_top,
                .y1t = v_top,
                .x0b = x0b,
                .x0a = x0a,
                .x1b = x1b,
                .x1a = x1a,
            });
            try svg.path(path_top, .{
                .fill = "none",
                .stroke = "black",
                .stroke_width = 0.1,
            });
            const path_bot = try std.fmt.bufPrint(&path_buffer, "M {[x1b]} {[y1b]}" ++
                " C {[x1a]} {[y1b]} {[x0a]} {[y0b]} {[x0b]} {[y0b]}", .{
                .y0b = p_top + p_height,
                .y1b = v_top + v_load_height,
                .x0b = x0b,
                .x0a = x0a,
                .x1b = x1b,
                .x1a = x1a,
            });
            try svg.path(path_bot, .{
                .fill = "none",
                .stroke = "black",
                .stroke_width = 0.1,
            });
        }
    }

    try svg.write_footer();

    if (!output_to_stdout) {
        try output_disk_file.finish();
    }

    return 0;
}

fn usage_error(reason: []const u8) !u8 {
    try std.io.getStdErr().writer().print("usage error: {s}\n", .{reason});
    return 1;
}

fn has_flag(mask: anytype, flag: @TypeOf(mask)) bool {
    return (mask & flag) != 0;
}

const LayoutInfo = struct {
    const header_size = 16;

    memory: Memory,
    header: f64,
    top: f64,
    height: f64,

    pub fn addr_to_pixels(range: LayoutInfo, addr: i66) f64 {
        return range.top + raw_to_pixels(addr - @as(i65, range.memory.begin), range.memory.bytes_per_pixel);
    }

    pub fn size_to_pixels(range: LayoutInfo, size: i66) f64 {
        return @min(range.height, raw_to_pixels(size, range.memory.bytes_per_pixel));
    }

    fn raw_to_pixels(size: i66, bytes_per_pixel: u64) f64 {
        const substeps = 16; // 1024 subpixels possible
        const precision = @divExact(bytes_per_pixel, substeps);

        const size_prec: f64 = @floatFromInt(@divFloor(size, precision));

        return size_prec / substeps;
    }
};

const SvgWriter = struct {
    writer: std.fs.File.Writer,

    pub fn write_header(svg: SvgWriter, width: u32, height: u32) !void {
        try svg.writer.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" width="{[width]}" height="{[height]}" viewBox="0 0 {[width]} {[height]}" font-family="sans-serif">
            \\<rect x="0" y="0" width="{[width]}" height="{[height]}" fill="#fff"/>
        , .{
            .width = width,
            .height = height,
        });
    }

    pub fn write_footer(svg: SvgWriter) !void {
        try svg.writer.writeAll(
            \\</svg>
            \\
        );
    }

    pub fn comment(svg: SvgWriter, comptime fmt: []const u8, args: anytype) !void {
        try svg.writer.print("<!-- " ++ fmt ++ " -->\n", args);
    }

    pub fn rect(svg: SvgWriter, options: struct {
        x: f64,
        y: f64,
        width: f64,
        height: f64,
        color: []const u8,
        title: []const u8 = "",
    }) !void {
        const title = std.mem.trim(u8, options.title, " \r\n");
        if (title.len > 0) {
            try svg.writer.print(
                \\<rect x="{d}" y="{d}" width="{d}" height="{d}" fill="{s}">
                \\  <title>{s}</title>
                \\</rect>
                \\
            , .{
                options.x, options.y, options.width, options.height, options.color, title,
            });
        } else {
            try svg.writer.print(
                \\<rect x="{d}" y="{d}" width="{d}" height="{d}" fill="{s}"/>
                \\
            , .{
                options.x, options.y, options.width, options.height, options.color,
            });
        }
    }

    pub fn path(svg: SvgWriter, nodes: []const u8, options: struct {
        fill: []const u8,
        stroke: []const u8,
        stroke_width: f64 = 0.0,
        title: []const u8 = "",
    }) !void {
        const title = std.mem.trim(u8, options.title, " \r\n");
        if (title.len > 0) {
            try svg.writer.print(
                \\<path fill="{s}" stroke="{s}" stroke-width="{d}" d="{s}">
                \\  <title>{s}</title>
                \\</path>
                \\
            , .{
                options.fill, options.stroke, options.stroke_width, nodes, title,
            });
        } else {
            try svg.writer.print(
                \\<path fill="{s}" stroke="{s}" stroke-width="{d}" d="{s}"/>
                \\
            , .{
                options.fill, options.stroke, options.stroke_width, nodes,
            });
        }
    }

    pub fn text(svg: SvgWriter, str: []const u8, x: f64, y: f64, options: struct {
        font_size: u32,
        color: []const u8 = "#000",
        horizontal_alignment: enum { left, center, right },
        vertical_alignment: enum { top, center, bottom },
    }) !void {
        try svg.writer.print(
            \\<text x="{[x]d}" y="{[y]d}" font-size="{[fontsize]d}" text-anchor="{[anchor]s}" alignment-baseline="{[baseline]s}" fill="{[color]s}">{[text]s}</text>
            \\
        , .{
            .x = x,
            .y = y,
            .text = str,

            .fontsize = options.font_size,
            .color = options.color,
            .anchor = switch (options.horizontal_alignment) {
                .left => "start",
                .center => "middle",
                .right => "end",
            },
            .baseline = switch (options.vertical_alignment) {
                .top => "hanging",
                .center => "middle",
                .bottom => "baseline",
            },
        });
    }
};

pub fn find_memory(addr: u64) ?struct { usize, Memory } {
    for (memories, 0..) |mem, i| {
        if (mem.contains(addr)) return .{ i, mem };
    }
    return null;
}

const memories: []const Memory = &.{
    .{ .begin = 0x1000_0000, .end = 0x11FF_FFFF, .bytes_per_pixel = 0x0001_0000, .name = "XIP 1" },
    .{ .begin = 0x1100_0000, .end = 0x12FF_FFFF, .bytes_per_pixel = 0x0001_0000, .name = "XIP 2" },
    .{ .begin = 0x2000_0000, .end = 0x2003_FFFF, .bytes_per_pixel = 0x0000_0400, .name = "SRAM Bank 0" },
    .{ .begin = 0x2004_0000, .end = 0x2007_FFFF, .bytes_per_pixel = 0x0000_0400, .name = "SRAM Bank 1" },
    .{ .begin = 0x2008_0000, .end = 0x2008_0FFF, .bytes_per_pixel = 0x0000_0020, .name = "SRAM Bank 2" },
    .{ .begin = 0x2008_1000, .end = 0x2008_1FFF, .bytes_per_pixel = 0x0000_0020, .name = "SRAM Bank 3" },
};

pub const Memory = struct {
    name: []const u8,
    begin: u64,
    end: u64,
    bytes_per_pixel: u64, // bytes per pixel

    fn contains(mem: Memory, addr: u64) bool {
        return addr >= mem.begin and addr <= mem.end;
    }

    fn size(mem: Memory) u65 {
        return mem.end + @as(u65, 1) - mem.begin;
    }
};

fn range_overlap_check(start0: u64, len0: u64, start1: u64, len1: u64) bool {
    const end0 = start0 + len0;
    const end1 = start1 + len1;

    if (end0 > start1 and end0 <= end1)
        return true;
    if (end1 > start0 and end1 <= end0)
        return true;

    return false;
}
