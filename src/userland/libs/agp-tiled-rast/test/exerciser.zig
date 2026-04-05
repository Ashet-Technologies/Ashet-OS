const std = @import("std");

const agp = @import("agp");
const agp_swrast = @import("agp-swrast");
const agp_tiled_rast = @import("agp-tiled-rast");
const gif = @import("gif.zig");

const Color = agp.Color;
const Bitmap = agp.Bitmap;

const BuildFn = *const fn (agp.Encoder, *const CaseDef) anyerror!void;

const output_dir_path = "zig-out/agp-tiled-rast-exerciser";
const initial_color: Color = .from_u8(0x11);
const panel_fill_color: Color = .from_gray(6);
const separator_color: Color = .from_gray(28);
const error_candidate_color: Color = .magenta;
const diff_match_color: Color = .black;
const diff_mismatch_color: Color = .red;

const CanvasSize = struct {
    width: u16,
    height: u16,
};

const Capabilities = packed struct {
    text: bool = false,
    framebuffers: bool = false,
};

const CaseDef = struct {
    name: []const u8,
    canvas: CanvasSize,
    capabilities: Capabilities = .{},
    seed: ?u64 = null,
    build_fn: BuildFn,
};

const SuiteDef = struct {
    name: []const u8,
    capabilities: Capabilities = .{},
    cases: []const CaseDef,
};

const Point = struct {
    x: u16,
    y: u16,
};

const Bounds = struct {
    min_x: u16,
    min_y: u16,
    max_x: u16,
    max_y: u16,
};

const Comparison = struct {
    mismatch_count: usize = 0,
    first_mismatch: ?Point = null,
    bounds: ?Bounds = null,

    fn matched(self: Comparison) bool {
        return self.mismatch_count == 0;
    }
};

const CaseResult = struct {
    width: u16,
    height: u16,
    reference: []Color,
    candidate: []Color,
    diff: []Color,
    comparison: Comparison,

    fn deinit(self: *CaseResult, allocator: std.mem.Allocator) void {
        allocator.free(self.reference);
        allocator.free(self.candidate);
        allocator.free(self.diff);
        self.* = undefined;
    }
};

const SuiteRunStats = struct {
    name: []const u8,
    artifact_path: []const u8,
    executed_cases: usize = 0,
    failed_cases: usize = 0,
    skipped_cases: usize = 0,
};

const RunSummary = struct {
    executed_suites: usize = 0,
    skipped_suites: usize = 0,
    executed_cases: usize = 0,
    failed_cases: usize = 0,
    skipped_cases: usize = 0,
};

const NullResolver = struct {
    fn resolveFont(_: *anyopaque, _: agp.Font) ?*const agp_swrast.fonts.FontInstance {
        return null;
    }

    fn resolveFramebuffer(_: *anyopaque, _: agp.Framebuffer) ?agp_swrast.Image {
        return null;
    }
};

const opaque_fixture_pixels = [_]Color{
    .red,   .white,  .blue,   .yellow,
    .green, .cyan,   .purple, .magenta,
    .blue,  .yellow, .green,  .white,
    .cyan,  .purple, .red,    .black,
};

const transparent_fixture_pixels = [_]Color{
    .magenta, .blue,    .magenta, .green,
    .yellow,  .magenta, .cyan,    .magenta,
    .magenta, .red,     .magenta, .white,
};

const strided_fixture_pixels = [_]Color{
    .red,    .green,  .blue,   .black, .white,
    .yellow, .cyan,   .purple, .black, .white,
    .white,  .purple, .cyan,   .black, .white,
    .blue,   .yellow, .green,  .black, .white,
};

const opaque_fixture: Bitmap = .{
    .pixels = opaque_fixture_pixels[0..].ptr,
    .width = 4,
    .height = 4,
    .stride = 4,
    .transparency_key = .black,
    .has_transparency = false,
};

const transparent_fixture: Bitmap = .{
    .pixels = transparent_fixture_pixels[0..].ptr,
    .width = 4,
    .height = 3,
    .stride = 4,
    .transparency_key = .magenta,
    .has_transparency = true,
};

const strided_fixture: Bitmap = .{
    .pixels = strided_fixture_pixels[0..].ptr,
    .width = 3,
    .height = 4,
    .stride = 5,
    .transparency_key = .black,
    .has_transparency = false,
};

const geometry_core_cases = [_]CaseDef{
    .{ .name = "clear-and-pixels", .canvas = .{ .width = 65, .height = 65 }, .build_fn = build_geometry_clear_and_pixels },
    .{ .name = "line-octants", .canvas = .{ .width = 65, .height = 65 }, .build_fn = build_geometry_line_octants },
    .{ .name = "rect-sizes", .canvas = .{ .width = 96, .height = 80 }, .build_fn = build_geometry_rect_sizes },
    .{ .name = "fill-rect-sizes", .canvas = .{ .width = 96, .height = 80 }, .build_fn = build_geometry_fill_sizes },
    .{ .name = "geometry-all", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_geometry_all },
};

const clip_interactions_cases = [_]CaseDef{
    .{ .name = "nested-clips", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_clip_nested },
    .{ .name = "zero-and-outside", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_clip_zero_and_outside },
    .{ .name = "clear-under-clip", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_clip_clear_sequences },
    .{ .name = "crossing-geometry", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_clip_crossing_geometry },
};

const bitmap_blits_cases = [_]CaseDef{
    .{ .name = "opaque-basic", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_bitmap_opaque_basic },
    .{ .name = "transparent-basic", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_bitmap_transparent_basic },
    .{ .name = "strided-bitmap", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_bitmap_strided },
    .{ .name = "partial-clipped", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_bitmap_partial_clipped },
    .{ .name = "tile-crossing", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_bitmap_tile_crossing },
};

const mixed_curated_cases = [_]CaseDef{
    .{ .name = "clip-geometry-bitmap", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_mixed_clip_geometry_bitmap },
    .{ .name = "many-tiles", .canvas = .{ .width = 193, .height = 129 }, .build_fn = build_mixed_many_tiles },
    .{ .name = "overdraw-ordering", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_mixed_overdraw_ordering },
    .{ .name = "negative-and-partial", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_mixed_negative_partial },
};

const draw_text_cases = [_]CaseDef{
    .{ .name = "draw-text-placeholder", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_placeholder },
};

const framebuffer_blit_cases = [_]CaseDef{
    .{ .name = "framebuffer-blit-placeholder", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .framebuffers = true }, .build_fn = build_framebuffer_blit_placeholder },
};

const framebuffer_partial_cases = [_]CaseDef{
    .{ .name = "framebuffer-partial-placeholder", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .framebuffers = true }, .build_fn = build_framebuffer_partial_placeholder },
};

const static_suites = [_]SuiteDef{
    .{ .name = "geometry-core", .cases = geometry_core_cases[0..] },
    .{ .name = "clip-interactions", .cases = clip_interactions_cases[0..] },
    .{ .name = "bitmap-blits", .cases = bitmap_blits_cases[0..] },
    .{ .name = "mixed-curated", .cases = mixed_curated_cases[0..] },
    .{ .name = "draw-text", .capabilities = .{ .text = true }, .cases = draw_text_cases[0..] },
    .{ .name = "blit-framebuffer", .capabilities = .{ .framebuffers = true }, .cases = framebuffer_blit_cases[0..] },
    .{ .name = "blit-partial-framebuffer", .capabilities = .{ .framebuffers = true }, .cases = framebuffer_partial_cases[0..] },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try std.fs.cwd().makePath(output_dir_path);

    var summary: RunSummary = .{};

    for (static_suites) |suite| {
        const stats = try run_static_suite(allocator, &suite);
        accumulateSummary(&summary, stats);
    }

    const random_stats = try run_seeded_random_suite(allocator);
    accumulateSummary(&summary, random_stats);

    std.debug.print(
        "agp exerciser: suites={} skipped_suites={} cases={} skipped_cases={} failures={}\n",
        .{
            summary.executed_suites,
            summary.skipped_suites,
            summary.executed_cases,
            summary.skipped_cases,
            summary.failed_cases,
        },
    );

    if (summary.failed_cases != 0) {
        return error.CaseMismatch;
    }
}

fn run_static_suite(allocator: std.mem.Allocator, suite: *const SuiteDef) !SuiteRunStats {
    if (!suiteSupported(suite.capabilities)) {
        std.debug.print("skip suite {s}: unsupported capabilities\n", .{suite.name});
        return .{
            .name = suite.name,
            .artifact_path = "",
            .skipped_cases = suite.cases.len,
        };
    }

    var max_canvas = CanvasSize{ .width = 0, .height = 0 };
    var executable_cases: usize = 0;
    for (suite.cases) |case| {
        if (!suiteSupported(case.capabilities)) continue;
        executable_cases += 1;
        max_canvas.width = @max(max_canvas.width, case.canvas.width);
        max_canvas.height = @max(max_canvas.height, case.canvas.height);
    }

    if (executable_cases == 0) {
        std.debug.print("skip suite {s}: no executable cases\n", .{suite.name});
        return .{
            .name = suite.name,
            .artifact_path = "",
            .skipped_cases = suite.cases.len,
        };
    }

    var suite_path_buffer: [256]u8 = undefined;
    const suite_path = try std.fmt.bufPrint(&suite_path_buffer, "{s}/{s}.gif", .{ output_dir_path, suite.name });
    var failures_path_buffer: [256]u8 = undefined;
    const failures_path = try std.fmt.bufPrint(&failures_path_buffer, "{s}/{s}-failures.gif", .{ output_dir_path, suite.name });

    var suite_file = try std.fs.cwd().createFile(suite_path, .{ .truncate = true });
    defer suite_file.close();

    var buffer: [8192]u8 = undefined;
    var file_writer = suite_file.writer(&buffer);

    var suite_gif = try gif.GIF_Encoder.start(
        &file_writer.interface,
        compositeWidth(max_canvas.width),
        max_canvas.height,
        0,
    );
    defer suite_gif.end() catch {};

    var failure_file: ?std.fs.File = null;
    var failure_gif: ?gif.GIF_Encoder = null;
    defer {
        if (failure_gif) |*enc| enc.end() catch {};
        if (failure_file) |*file| file.close();
    }

    var stats = SuiteRunStats{
        .name = suite.name,
        .artifact_path = "",
    };

    for (suite.cases) |case| {
        if (!suiteSupported(case.capabilities)) {
            stats.skipped_cases += 1;
            std.debug.print("skip case {s}/{s}: unsupported capabilities\n", .{ suite.name, case.name });
            continue;
        }

        stats.executed_cases += 1;

        var result = run_case(allocator, &case) catch |err| blk: {
            std.debug.print("case {s}/{s} failed to execute: {s}\n", .{ suite.name, case.name, @errorName(err) });
            break :blk try make_error_result(allocator, case.canvas);
        };
        defer result.deinit(allocator);

        const composite = try compose_case_frame(allocator, max_canvas, &result);
        defer allocator.free(composite);

        try suite_gif.add_frame(composite);

        if (!result.comparison.matched()) {
            stats.failed_cases += 1;
            std.debug.print(
                "mismatch {s}/{s}: count={} first={any} bounds={any} artifact={s}\n",
                .{
                    suite.name,
                    case.name,
                    result.comparison.mismatch_count,
                    result.comparison.first_mismatch,
                    result.comparison.bounds,
                    suite_path,
                },
            );

            if (failure_gif == null) {
                var tmp_buffer: [8192]u8 = undefined;

                failure_file = try std.fs.cwd().createFile(failures_path, .{ .truncate = true });
                var failure_file_writer = failure_file.?.writer(&tmp_buffer);

                failure_gif = try gif.GIF_Encoder.start(
                    &failure_file_writer.interface,
                    compositeWidth(max_canvas.width),
                    max_canvas.height,
                    0,
                );
            }
            try failure_gif.?.add_frame(composite);
        }
    }

    return stats;
}

fn run_seeded_random_suite(allocator: std.mem.Allocator) !SuiteRunStats {
    const suite_name = "seeded-random";
    const seeds = [_]u64{
        0x0000_0000_0000_0001,
        0x0000_0000_0000_1337,
        0x0000_0000_0042_4242,
        0x0000_0000_C0DE_CAFE,
        0x0000_1234_5678_9ABC,
        0x0000_9876_5432_1001,
        0x00AA_55AA_F0F0_0F0F,
        0x0BAD_F00D_1234_5678,
    };
    const canvases = [_]CanvasSize{
        .{ .width = 17, .height = 17 },
        .{ .width = 65, .height = 33 },
        .{ .width = 127, .height = 95 },
        .{ .width = 193, .height = 129 },
    };

    const max_canvas = CanvasSize{ .width = 193, .height = 129 };

    var suite_path_buffer: [256]u8 = undefined;
    const suite_path = try std.fmt.bufPrint(&suite_path_buffer, "{s}/{s}.gif", .{ output_dir_path, suite_name });
    var failures_path_buffer: [256]u8 = undefined;
    const failures_path = try std.fmt.bufPrint(&failures_path_buffer, "{s}/{s}-failures.gif", .{ output_dir_path, suite_name });

    var suite_file = try std.fs.cwd().createFile(suite_path, .{ .truncate = true });
    defer suite_file.close();

    var suite_buffer: [8192]u8 = undefined;
    var suite_file_writer = suite_file.writer(&suite_buffer);

    var suite_gif = try gif.GIF_Encoder.start(
        &suite_file_writer.interface,
        compositeWidth(max_canvas.width),
        max_canvas.height,
        0,
    );
    defer suite_gif.end() catch {};

    var failure_file: ?std.fs.File = null;
    var failure_gif: ?gif.GIF_Encoder = null;
    var failure_buffer: [8192]u8 = undefined;
    var failure_file_writer: std.fs.File.Writer = undefined;
    defer {
        if (failure_gif) |*enc| enc.end() catch {};
        if (failure_file) |*file| file.close();
    }

    var stats = SuiteRunStats{
        .name = suite_name,
        .artifact_path = "",
    };

    for (seeds) |seed| {
        for (canvases) |canvas| {
            var case_name_buffer: [96]u8 = undefined;
            const case_name = try std.fmt.bufPrint(
                &case_name_buffer,
                "seed-{x:0>16}-{}x{}",
                .{ seed, canvas.width, canvas.height },
            );

            const case = CaseDef{
                .name = case_name,
                .canvas = canvas,
                .seed = seed,
                .build_fn = build_seeded_random_case,
            };

            stats.executed_cases += 1;

            var result = run_case(allocator, &case) catch |err| blk: {
                std.debug.print("case {s}/{s} failed to execute: {s}\n", .{ suite_name, case.name, @errorName(err) });
                break :blk try make_error_result(allocator, case.canvas);
            };
            defer result.deinit(allocator);

            const composite = try compose_case_frame(allocator, max_canvas, &result);
            defer allocator.free(composite);

            try suite_gif.add_frame(composite);

            if (!result.comparison.matched()) {
                stats.failed_cases += 1;
                std.debug.print(
                    "mismatch {s}/{s}: count={} first={any} bounds={any} artifact={s}\n",
                    .{
                        suite_name,
                        case.name,
                        result.comparison.mismatch_count,
                        result.comparison.first_mismatch,
                        result.comparison.bounds,
                        suite_path,
                    },
                );

                if (failure_gif == null) {
                    failure_file = try std.fs.cwd().createFile(failures_path, .{ .truncate = true });
                    failure_file_writer = failure_file.?.writer(&failure_buffer);
                    failure_gif = try gif.GIF_Encoder.start(
                        &failure_file_writer.interface,
                        compositeWidth(max_canvas.width),
                        max_canvas.height,
                        0,
                    );
                }
                try failure_gif.?.add_frame(composite);
            }
        }
    }

    return stats;
}

fn run_case(allocator: std.mem.Allocator, case: *const CaseDef) !CaseResult {
    const sequence = try build_command_stream(allocator, case);
    defer allocator.free(sequence);

    const reference = try render_reference(allocator, case.canvas, sequence);
    errdefer allocator.free(reference);

    const candidate = try render_candidate(allocator, case.canvas, sequence);
    errdefer allocator.free(candidate);

    const diff = try allocator.alloc(Color, reference.len);
    errdefer allocator.free(diff);

    const comparison = compare_images(reference, candidate, diff, case.canvas.width, case.canvas.height);

    return .{
        .width = case.canvas.width,
        .height = case.canvas.height,
        .reference = reference,
        .candidate = candidate,
        .diff = diff,
        .comparison = comparison,
    };
}

fn build_command_stream(allocator: std.mem.Allocator, case: *const CaseDef) ![]u8 {
    var stream: std.Io.Writer.Allocating = .init(allocator);
    defer stream.deinit();

    const enc = agp.encoder(&stream.writer);
    try case.build_fn(enc, case);

    return try stream.toOwnedSlice();
}

fn render_reference(allocator: std.mem.Allocator, canvas: CanvasSize, sequence: []const u8) ![]Color {
    const pixel_count = @as(usize, canvas.width) * @as(usize, canvas.height);
    const pixels = try allocator.alloc(Color, pixel_count);
    @memset(pixels, initial_color);

    var rasterizer = agp_swrast.Rasterizer.init(.{
        .pixels = pixels.ptr,
        .width = canvas.width,
        .height = canvas.height,
        .stride = canvas.width,
    });

    const resolver = agp_swrast.Rasterizer.Resolver{
        .ctx = @ptrFromInt(1),
        .resolve_font_fn = NullResolver.resolveFont,
        .resolve_framebuffer_fn = NullResolver.resolveFramebuffer,
    };

    var decoder: agp.BufferDecoder = .init(sequence);
    while (try decoder.next()) |cmd| {
        rasterizer.execute(cmd, resolver);
    }

    return pixels;
}

fn render_candidate(allocator: std.mem.Allocator, canvas: CanvasSize, sequence: []const u8) ![]Color {
    const stride = alignStride(canvas.width);
    const backing = try allocator.alignedAlloc(
        Color,
        .fromByteUnits(agp_tiled_rast.tile_size),
        @as(usize, stride) * @as(usize, canvas.height),
    );
    defer allocator.free(backing);

    @memset(backing, initial_color);

    var rasterizer: agp_tiled_rast.Rasterizer = .{};
    try rasterizer.execute(.{
        .pixels = backing.ptr,
        .width = canvas.width,
        .height = canvas.height,
        .stride = stride,
    }, sequence);

    const tight = try allocator.alloc(Color, @as(usize, canvas.width) * @as(usize, canvas.height));
    for (0..canvas.height) |y| {
        const src = backing[@as(usize, y) * @as(usize, stride) ..][0..canvas.width];
        const dst = tight[@as(usize, y) * @as(usize, canvas.width) ..][0..canvas.width];
        @memcpy(dst, src);
    }
    return tight;
}

fn compare_images(reference: []const Color, candidate: []const Color, diff: []Color, width: u16, height: u16) Comparison {
    std.debug.assert(reference.len == candidate.len);
    std.debug.assert(reference.len == diff.len);

    var comparison: Comparison = .{};

    for (reference, candidate, diff, 0..) |exp, act, *out, idx| {
        if (Color.eql(exp, act)) {
            out.* = diff_match_color;
            continue;
        }

        out.* = diff_mismatch_color;
        comparison.mismatch_count += 1;

        const x: u16 = @intCast(idx % width);
        const y: u16 = @intCast(idx / width);

        if (comparison.first_mismatch == null) {
            comparison.first_mismatch = .{ .x = x, .y = y };
            comparison.bounds = .{
                .min_x = x,
                .min_y = y,
                .max_x = x,
                .max_y = y,
            };
        } else {
            comparison.bounds.?.min_x = @min(comparison.bounds.?.min_x, x);
            comparison.bounds.?.min_y = @min(comparison.bounds.?.min_y, y);
            comparison.bounds.?.max_x = @max(comparison.bounds.?.max_x, x);
            comparison.bounds.?.max_y = @max(comparison.bounds.?.max_y, y);
        }
    }

    _ = height;
    return comparison;
}

fn make_error_result(allocator: std.mem.Allocator, canvas: CanvasSize) !CaseResult {
    const pixel_count = @as(usize, canvas.width) * @as(usize, canvas.height);

    const reference = try allocator.alloc(Color, pixel_count);
    errdefer allocator.free(reference);
    const candidate = try allocator.alloc(Color, pixel_count);
    errdefer allocator.free(candidate);
    const diff = try allocator.alloc(Color, pixel_count);
    errdefer allocator.free(diff);

    @memset(reference, initial_color);
    @memset(candidate, error_candidate_color);
    @memset(diff, diff_mismatch_color);

    return .{
        .width = canvas.width,
        .height = canvas.height,
        .reference = reference,
        .candidate = candidate,
        .diff = diff,
        .comparison = .{
            .mismatch_count = pixel_count,
            .first_mismatch = .{ .x = 0, .y = 0 },
            .bounds = .{
                .min_x = 0,
                .min_y = 0,
                .max_x = canvas.width - 1,
                .max_y = canvas.height - 1,
            },
        },
    };
}

fn compose_case_frame(allocator: std.mem.Allocator, max_canvas: CanvasSize, result: *const CaseResult) ![]Color {
    const width = compositeWidth(max_canvas.width);
    const height = max_canvas.height;
    const frame = try allocator.alloc(Color, @as(usize, width) * @as(usize, height));
    @memset(frame, panel_fill_color);

    for (0..height) |y| {
        frame[@as(usize, y) * @as(usize, width) + @as(usize, max_canvas.width)] = separator_color;
        frame[@as(usize, y) * @as(usize, width) + @as(usize, max_canvas.width) * 2 + 1] = separator_color;
    }

    blitPanel(frame, width, 0, max_canvas.width, result.width, result.height, result.reference);
    blitPanel(frame, width, max_canvas.width + 1, max_canvas.width, result.width, result.height, result.candidate);
    blitPanel(frame, width, max_canvas.width * 2 + 2, max_canvas.width, result.width, result.height, result.diff);

    return frame;
}

fn blitPanel(frame: []Color, frame_width: u16, panel_x: u16, panel_width: u16, src_width: u16, src_height: u16, src: []const Color) void {
    _ = panel_width;
    for (0..src_height) |y| {
        const dst = frame[@as(usize, y) * @as(usize, frame_width) + @as(usize, panel_x) ..][0..src_width];
        const row = src[@as(usize, y) * @as(usize, src_width) ..][0..src_width];
        @memcpy(dst, row);
    }
}

fn compositeWidth(canvas_width: u16) u16 {
    return canvas_width * 3 + 2;
}

fn alignStride(width: u16) u32 {
    const tile = agp_tiled_rast.tile_size;
    return @intCast(std.mem.alignForward(usize, width, tile));
}

fn suiteSupported(required: Capabilities) bool {
    return !required.text and !required.framebuffers;
}

fn accumulateSummary(summary: *RunSummary, stats: SuiteRunStats) void {
    if (stats.executed_cases == 0) {
        summary.skipped_suites += 1;
    } else {
        summary.executed_suites += 1;
    }
    summary.executed_cases += stats.executed_cases;
    summary.failed_cases += stats.failed_cases;
    summary.skipped_cases += stats.skipped_cases;
}

fn biased_coord(rng: std.Random, dim: u16) i16 {
    const edge: i16 = @intCast(dim);
    return switch (rng.uintLessThan(u8, 12)) {
        0 => -1,
        1 => 0,
        2 => 1,
        3 => 62,
        4 => 63,
        5 => 64,
        6 => 65,
        7 => edge - 1,
        8 => edge,
        9 => edge + 1,
        10 => edge - 2,
        else => rng.intRangeAtMost(i16, -2, edge + 2),
    };
}

fn biased_size(rng: std.Random, dim: u16) u16 {
    const edge: u16 = dim;
    return switch (rng.uintLessThan(u8, 10)) {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        4 => 63,
        5 => 64,
        6 => 65,
        7 => edge,
        8 => edge +| 1,
        else => rng.intRangeAtMost(u16, 0, edge +| 2),
    };
}

fn choose_bitmap(rng: std.Random) *const Bitmap {
    return switch (rng.uintLessThan(u8, 3)) {
        0 => &opaque_fixture,
        1 => &transparent_fixture,
        else => &strided_fixture,
    };
}

const RandomOp = enum {
    clear,
    set_clip_rect,
    set_pixel,
    draw_line,
    draw_rect,
    fill_rect,
    blit_bitmap,
    blit_partial_bitmap,
    extra_set_pixel,
    extra_draw_line,
    extra_blit_bitmap,
};

fn emit_random_op(enc: agp.Encoder, rng: std.Random, canvas: CanvasSize, op: RandomOp) !void {
    switch (op) {
        .clear => try enc.clear(Color.from_u8(rng.int(u8))),
        .set_clip_rect => try enc.set_clip_rect(
            biased_coord(rng, canvas.width),
            biased_coord(rng, canvas.height),
            biased_size(rng, canvas.width),
            biased_size(rng, canvas.height),
        ),
        .set_pixel, .extra_set_pixel => try enc.set_pixel(
            biased_coord(rng, canvas.width),
            biased_coord(rng, canvas.height),
            Color.from_u8(rng.int(u8)),
        ),
        .draw_line, .extra_draw_line => try enc.draw_line(
            biased_coord(rng, canvas.width),
            biased_coord(rng, canvas.height),
            biased_coord(rng, canvas.width),
            biased_coord(rng, canvas.height),
            Color.from_u8(rng.int(u8)),
        ),
        .draw_rect => try enc.draw_rect(
            biased_coord(rng, canvas.width),
            biased_coord(rng, canvas.height),
            biased_size(rng, canvas.width),
            biased_size(rng, canvas.height),
            Color.from_u8(rng.int(u8)),
        ),
        .fill_rect => try enc.fill_rect(
            biased_coord(rng, canvas.width),
            biased_coord(rng, canvas.height),
            biased_size(rng, canvas.width),
            biased_size(rng, canvas.height),
            Color.from_u8(rng.int(u8)),
        ),
        .blit_bitmap, .extra_blit_bitmap => {
            const bitmap = choose_bitmap(rng);
            try enc.blit_bitmap(
                biased_coord(rng, canvas.width),
                biased_coord(rng, canvas.height),
                bitmap,
            );
        },
        .blit_partial_bitmap => {
            const bitmap = choose_bitmap(rng);
            try enc.blit_partial_bitmap(
                biased_coord(rng, canvas.width),
                biased_coord(rng, canvas.height),
                biased_size(rng, canvas.width),
                biased_size(rng, canvas.height),
                biased_coord(rng, bitmap.width),
                biased_coord(rng, bitmap.height),
                bitmap,
            );
        },
    }
}

fn build_seeded_random_case(enc: agp.Encoder, case: *const CaseDef) !void {
    var prng = std.Random.DefaultPrng.init(case.seed.?);
    const rng = prng.random();

    var block_index: usize = 0;
    while (block_index < 4) : (block_index += 1) {
        var ops = [_]RandomOp{
            .clear,
            .set_clip_rect,
            .set_pixel,
            .draw_line,
            .draw_rect,
            .fill_rect,
            .blit_bitmap,
            .blit_partial_bitmap,
            .extra_set_pixel,
            .extra_draw_line,
            .extra_blit_bitmap,
        };
        rng.shuffle(RandomOp, &ops);
        for (ops) |op| {
            try emit_random_op(enc, rng, case.canvas, op);
        }
    }
}

fn build_geometry_clear_and_pixels(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.set_pixel(0, 0, .white);
    try enc.set_pixel(64, 64, .red);
    try enc.set_pixel(63, 0, .green);
    try enc.set_pixel(0, 63, .blue);
    try enc.set_pixel(-1, 0, .yellow);
    try enc.set_pixel(0, -1, .cyan);
    try enc.set_pixel(65, 65, .magenta);
    try enc.set_clip_rect(1, 1, 63, 63);
    try enc.clear(.from_gray(18));
    try enc.set_pixel(1, 1, .white);
    try enc.set_clip_rect(0, 0, 65, 65);
}

fn build_geometry_line_octants(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.draw_line(0, 0, 64, 64, .white);
    try enc.draw_line(64, 0, 0, 64, .red);
    try enc.draw_line(32, 0, 32, 64, .green);
    try enc.draw_line(0, 32, 64, 32, .blue);
    try enc.draw_line(5, 60, 25, 10, .yellow);
    try enc.draw_line(60, 5, 10, 25, .cyan);
    try enc.draw_line(10, 10, 10, 10, .magenta);
    try enc.draw_line(-5, 20, 30, 20, .purple);
    try enc.draw_line(20, -5, 20, 30, .from_gray(40));
}

fn build_geometry_rect_sizes(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(4));
    try enc.draw_rect(0, 0, 1, 1, .white);
    try enc.draw_rect(3, 3, 2, 2, .red);
    try enc.draw_rect(8, 4, 63, 63, .green);
    try enc.draw_rect(10, 6, 64, 64, .blue);
    try enc.draw_rect(12, 8, 65, 65, .yellow);
    try enc.draw_rect(-4, 20, 15, 9, .cyan);
    try enc.draw_rect(50, -3, 20, 11, .magenta);
    try enc.draw_rect(20, 20, 0, 8, .purple);
}

fn build_geometry_fill_sizes(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.fill_rect(0, 0, 1, 1, .white);
    try enc.fill_rect(2, 2, 2, 2, .red);
    try enc.fill_rect(5, 5, 63, 8, .green);
    try enc.fill_rect(7, 16, 64, 8, .blue);
    try enc.fill_rect(9, 27, 65, 8, .yellow);
    try enc.fill_rect(-2, 40, 10, 10, .cyan);
    try enc.fill_rect(50, -2, 10, 10, .magenta);
    try enc.fill_rect(20, 20, 0, 0, .purple);
}

fn build_geometry_all(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(3));
    try enc.fill_rect(0, 0, 127, 12, .blue);
    try enc.draw_rect(1, 1, 125, 93, .white);
    try enc.draw_line(0, 94, 126, 0, .yellow);
    try enc.draw_line(0, 0, 126, 94, .green);
    try enc.set_clip_rect(32, 16, 64, 48);
    try enc.fill_rect(20, 8, 80, 60, .purple);
    try enc.draw_rect(31, 15, 66, 50, .cyan);
    try enc.set_clip_rect(0, 0, 127, 95);
    try enc.set_pixel(63, 47, .red);
    try enc.set_pixel(126, 94, .white);
}

fn build_clip_nested(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.set_clip_rect(8, 8, 60, 40);
    try enc.fill_rect(0, 0, 96, 72, .blue);
    try enc.set_clip_rect(16, 16, 24, 20);
    try enc.fill_rect(0, 0, 96, 72, .yellow);
    try enc.draw_rect(0, 0, 96, 72, .white);
    try enc.set_clip_rect(0, 0, 96, 72);
    try enc.draw_rect(7, 7, 62, 42, .red);
}

fn build_clip_zero_and_outside(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(4));
    try enc.set_clip_rect(10, 10, 0, 30);
    try enc.fill_rect(0, 0, 96, 72, .red);
    try enc.set_clip_rect(-20, -20, 8, 8);
    try enc.fill_rect(0, 0, 96, 72, .green);
    try enc.set_clip_rect(90, 60, 16, 16);
    try enc.fill_rect(0, 0, 96, 72, .blue);
    try enc.set_clip_rect(0, 0, 96, 72);
    try enc.draw_line(-5, 71, 95, -5, .white);
}

fn build_clip_clear_sequences(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.fill_rect(0, 0, 127, 95, .from_gray(15));
    try enc.set_clip_rect(20, 20, 40, 30);
    try enc.clear(.green);
    try enc.set_clip_rect(40, 10, 50, 70);
    try enc.clear(.blue);
    try enc.set_clip_rect(0, 0, 127, 95);
    try enc.draw_rect(19, 19, 41, 31, .white);
    try enc.draw_rect(39, 9, 51, 71, .red);
}

fn build_clip_crossing_geometry(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.set_clip_rect(24, 18, 70, 40);
    try enc.draw_line(-10, 10, 120, 70, .yellow);
    try enc.draw_line(60, -10, 60, 100, .cyan);
    try enc.fill_rect(10, 10, 80, 30, .purple);
    try enc.draw_rect(-5, 16, 110, 44, .white);
    try enc.set_clip_rect(0, 0, 127, 95);
    try enc.draw_rect(23, 17, 71, 41, .red);
}

fn build_bitmap_opaque_basic(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.blit_bitmap(0, 0, &opaque_fixture);
    try enc.blit_bitmap(62, 10, &opaque_fixture);
    try enc.blit_bitmap(70, 40, &opaque_fixture);
}

fn build_bitmap_transparent_basic(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(8));
    try enc.fill_rect(8, 8, 48, 32, .blue);
    try enc.blit_bitmap(12, 12, &transparent_fixture);
    try enc.blit_bitmap(60, 20, &transparent_fixture);
    try enc.blit_bitmap(-2, 30, &transparent_fixture);
}

fn build_bitmap_strided(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.blit_bitmap(10, 10, &strided_fixture);
    try enc.blit_bitmap(63, 0, &strided_fixture);
    try enc.blit_partial_bitmap(30, 24, 6, 6, 1, 1, &strided_fixture);
}

fn build_bitmap_partial_clipped(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(7));
    try enc.fill_rect(0, 0, 127, 95, .from_gray(9));
    try enc.blit_partial_bitmap(5, 5, 8, 8, 0, 0, &opaque_fixture);
    try enc.blit_partial_bitmap(60, 10, 10, 10, 2, 1, &transparent_fixture);
    try enc.blit_partial_bitmap(-3, 40, 12, 12, 1, 1, &strided_fixture);
    try enc.blit_partial_bitmap(120, 90, 8, 8, 0, 0, &opaque_fixture);
}

fn build_bitmap_tile_crossing(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.blit_bitmap(63, 63, &opaque_fixture);
    try enc.blit_bitmap(64, 64, &transparent_fixture);
    try enc.blit_bitmap(61, 62, &strided_fixture);
    try enc.blit_partial_bitmap(62, 30, 7, 12, 0, 0, &strided_fixture);
    try enc.blit_partial_bitmap(30, 62, 12, 7, 0, 0, &transparent_fixture);
}

fn build_mixed_clip_geometry_bitmap(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(2));
    try enc.draw_rect(0, 0, 127, 95, .white);
    try enc.set_clip_rect(16, 16, 80, 48);
    try enc.fill_rect(0, 0, 127, 95, .green);
    try enc.draw_line(-10, 20, 120, 70, .yellow);
    try enc.blit_bitmap(62, 32, &transparent_fixture);
    try enc.set_clip_rect(0, 0, 127, 95);
    try enc.blit_partial_bitmap(90, 50, 20, 20, 0, 0, &strided_fixture);
}

fn build_mixed_many_tiles(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    var y: i16 = 0;
    while (y < 129) : (y += 31) {
        var x: i16 = 0;
        while (x < 193) : (x += 47) {
            try enc.fill_rect(x - 3, y - 2, 20, 14, Color.from_rgb(@intCast(x + 32), @intCast(y + 48), @intCast(x + y + 12)));
            try enc.draw_rect(x, y, 65, 33, .white);
            try enc.blit_bitmap(x + 12, y + 7, &opaque_fixture);
        }
    }
    try enc.draw_line(0, 0, 192, 128, .yellow);
    try enc.draw_line(192, 0, 0, 128, .cyan);
}

fn build_mixed_overdraw_ordering(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(5));
    try enc.fill_rect(10, 10, 50, 50, .red);
    try enc.fill_rect(20, 20, 50, 50, .green);
    try enc.fill_rect(30, 30, 50, 50, .blue);
    try enc.draw_rect(9, 9, 72, 72, .white);
    try enc.blit_bitmap(24, 24, &transparent_fixture);
    try enc.blit_bitmap(48, 48, &opaque_fixture);
}

fn build_mixed_negative_partial(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.set_clip_rect(4, 4, 88, 60);
    try enc.fill_rect(-8, -8, 40, 40, .purple);
    try enc.draw_line(-10, 35, 100, 35, .yellow);
    try enc.blit_partial_bitmap(-6, 20, 18, 14, 1, 0, &transparent_fixture);
    try enc.blit_partial_bitmap(40, -3, 18, 14, 0, 1, &strided_fixture);
    try enc.set_clip_rect(0, 0, 96, 72);
    try enc.draw_rect(3, 3, 89, 61, .white);
}

fn build_draw_text_placeholder(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.draw_text(4, 16, @ptrFromInt(1), .white, "text");
}

fn build_framebuffer_blit_placeholder(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.blit_framebuffer(8, 8, @ptrFromInt(1));
}

fn build_framebuffer_partial_placeholder(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.blit_partial_framebuffer(8, 8, 16, 16, 2, 2, @ptrFromInt(1));
}
