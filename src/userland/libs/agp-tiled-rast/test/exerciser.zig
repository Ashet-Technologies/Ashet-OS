const std = @import("std");

const agp = @import("agp");
const agp_swrast = @import("agp-swrast");
const agp_tiled_rast = @import("agp-tiled-rast");
const gif = @import("gif.zig");

const Color = agp.Color;
const Bitmap = agp.Bitmap;

const BuildFn = *const fn (agp.Encoder, *const CaseDef) anyerror!void;

const output_dir_path = "zig-out/agp-tiled-rast-exerciser";
const suite_frame_delay_cs: u16 = 75;
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
    sequence: []u8,
    reference: []Color,
    candidate: []Color,
    diff: []Color,
    comparison: Comparison,

    fn deinit(self: *CaseResult, allocator: std.mem.Allocator) void {
        allocator.free(self.sequence);
        allocator.free(self.reference);
        allocator.free(self.candidate);
        allocator.free(self.diff);
        self.* = undefined;
    }
};

const CaseRunStats = struct {
    name: []const u8,
    executed: bool,
    bad_pixels: usize = 0,
    total_pixels: usize = 0,
};

const SuiteRunStats = struct {
    name: []const u8,
    artifact_path: []const u8,
    executed_cases: usize = 0,
    failed_cases: usize = 0,
    skipped_cases: usize = 0,
    bad_pixels: usize = 0,
    total_pixels: usize = 0,
    case_stats: std.ArrayListUnmanaged(CaseRunStats) = .{},

    fn deinit(self: *SuiteRunStats, allocator: std.mem.Allocator) void {
        allocator.free(self.artifact_path);
        for (self.case_stats.items) |case_stat| {
            allocator.free(case_stat.name);
        }
        self.case_stats.deinit(allocator);
        self.* = undefined;
    }
};

const RunSummary = struct {
    executed_suites: usize = 0,
    skipped_suites: usize = 0,
    executed_cases: usize = 0,
    failed_cases: usize = 0,
    skipped_cases: usize = 0,
    bad_pixels: usize = 0,
    total_pixels: usize = 0,
};

const ResourceCatalog = struct {
    const FramebufferFixture = struct {
        pixels: []align(64) const Color,
        width: u16,
        height: u16,
        stride: u32,

        fn asReferenceImage(self: *const FramebufferFixture) agp_swrast.Image {
            return .{
                .pixels = self.pixels.ptr,
                .width = self.width,
                .height = self.height,
                .stride = self.stride,
            };
        }

        fn asCandidateImage(self: *const FramebufferFixture) agp_tiled_rast.Image {
            return .{
                .pixels = self.pixels.ptr,
                .width = self.width,
                .height = self.height,
                .stride = self.stride,
            };
        }
    };

    const mono_6_font_instance = loadFont(@embedFile("mono-6.font"), .{});
    const mono_8_font_instance = loadFont(@embedFile("mono-8.font"), .{});
    const sans_8_font_instance = loadFont(@embedFile("sans.font"), .{ .size = 8 });
    const sans_12_font_instance = loadFont(@embedFile("sans.font"), .{ .size = 12 });
    const sans_16_font_instance = loadFont(@embedFile("sans.font"), .{ .size = 16 });
    const sans_24_font_instance = loadFont(@embedFile("sans.font"), .{ .size = 24 });

    const mono_6_font: agp.Font = @ptrCast(@constCast(&mono_6_font_instance));
    const mono_8_font: agp.Font = @ptrCast(@constCast(&mono_8_font_instance));
    const sans_8_font: agp.Font = @ptrCast(@constCast(&sans_8_font_instance));
    const sans_12_font: agp.Font = @ptrCast(@constCast(&sans_12_font_instance));
    const sans_16_font: agp.Font = @ptrCast(@constCast(&sans_16_font_instance));
    const sans_24_font: agp.Font = @ptrCast(@constCast(&sans_24_font_instance));
    const sans_font: agp.Font = sans_12_font;

    const framebuffer_primary_pixels: [64 * 29]Color align(64) = makeGradientBitmapPixels(37, 29, 64, false);
    const framebuffer_secondary_pixels: [128 * 33]Color align(64) = makeGradientBitmapPixels(71, 33, 128, false);

    const framebuffer_primary_fixture: FramebufferFixture = .{
        .pixels = framebuffer_primary_pixels[0..],
        .width = 37,
        .height = 29,
        .stride = 64,
    };

    const framebuffer_secondary_fixture: FramebufferFixture = .{
        .pixels = framebuffer_secondary_pixels[0..],
        .width = 71,
        .height = 33,
        .stride = 128,
    };

    const framebuffer_primary: agp.Framebuffer = @ptrCast(@constCast(&framebuffer_primary_fixture));
    const framebuffer_secondary: agp.Framebuffer = @ptrCast(@constCast(&framebuffer_secondary_fixture));

    fn loadFont(comptime bytes: []const u8, comptime hint: agp_swrast.fonts.FontHint) agp_swrast.fonts.FontInstance {
        @setEvalBranchQuota(10_000);
        return agp_swrast.fonts.FontInstance.load(bytes, hint) catch unreachable;
    }

    fn resolveFontReference(_: *anyopaque, handle: agp.Font) ?*const agp_swrast.fonts.FontInstance {
        if (handle == mono_6_font) return &mono_6_font_instance;
        if (handle == mono_8_font) return &mono_8_font_instance;
        if (handle == sans_8_font) return &sans_8_font_instance;
        if (handle == sans_12_font) return &sans_12_font_instance;
        if (handle == sans_16_font) return &sans_16_font_instance;
        if (handle == sans_24_font) return &sans_24_font_instance;
        return null;
    }

    fn resolveFontCandidate(_: *anyopaque, handle: agp.Font) ?*const agp_tiled_rast.FontInstance {
        if (handle == mono_6_font) return @ptrCast(&mono_6_font_instance);
        if (handle == mono_8_font) return @ptrCast(&mono_8_font_instance);
        if (handle == sans_8_font) return @ptrCast(&sans_8_font_instance);
        if (handle == sans_12_font) return @ptrCast(&sans_12_font_instance);
        if (handle == sans_16_font) return @ptrCast(&sans_16_font_instance);
        if (handle == sans_24_font) return @ptrCast(&sans_24_font_instance);
        return null;
    }

    fn lookupFontInstance(handle: agp.Font) ?*const agp_swrast.fonts.FontInstance {
        if (handle == mono_6_font) return &mono_6_font_instance;
        if (handle == mono_8_font) return &mono_8_font_instance;
        if (handle == sans_8_font) return &sans_8_font_instance;
        if (handle == sans_12_font) return &sans_12_font_instance;
        if (handle == sans_16_font) return &sans_16_font_instance;
        if (handle == sans_24_font) return &sans_24_font_instance;
        return null;
    }

    fn resolveFramebufferReference(_: *anyopaque, handle: agp.Framebuffer) ?agp_swrast.Image {
        if (handle == framebuffer_primary) return framebuffer_primary_fixture.asReferenceImage();
        if (handle == framebuffer_secondary) return framebuffer_secondary_fixture.asReferenceImage();
        return null;
    }

    fn resolveFramebufferCandidate(_: *anyopaque, handle: agp.Framebuffer) ?agp_tiled_rast.Image {
        if (handle == framebuffer_primary) return framebuffer_primary_fixture.asCandidateImage();
        if (handle == framebuffer_secondary) return framebuffer_secondary_fixture.asCandidateImage();
        return null;
    }

    fn lookupFramebufferFixture(handle: agp.Framebuffer) ?*const FramebufferFixture {
        if (handle == framebuffer_primary) return &framebuffer_primary_fixture;
        if (handle == framebuffer_secondary) return &framebuffer_secondary_fixture;
        return null;
    }
};

const resource_catalog: ResourceCatalog = .{};

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

fn gradientFixtureColor(comptime x: usize, comptime y: usize) Color {
    return Color.from_u8(@intCast((x * 29 + y * 17 + ((x ^ y) * 5) + 13) & 0xff));
}

fn makeGradientBitmapPixels(
    comptime width: usize,
    comptime height: usize,
    comptime stride: usize,
    comptime transparent: bool,
) [stride * height]Color {
    @setEvalBranchQuota(stride * height * 4);

    var pixels: [stride * height]Color = undefined;

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < stride) : (x += 1) {
            const index = y * stride + x;
            pixels[index] = if (x >= width)
                .black
            else if (transparent and (((x + y) % 13 == 0) or ((x % 17) == 0 and (y % 9) < 2)))
                .magenta
            else
                gradientFixtureColor(x, y);
        }
    }

    return pixels;
}

const large_opaque_fixture_pixels = makeGradientBitmapPixels(130, 130, 132, false);
const large_transparent_fixture_pixels = makeGradientBitmapPixels(131, 129, 136, true);
const medium_opaque_fixture_pixels = makeGradientBitmapPixels(72, 72, 74, false);
const medium_transparent_fixture_pixels = makeGradientBitmapPixels(73, 71, 76, true);

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

const large_opaque_fixture: Bitmap = .{
    .pixels = large_opaque_fixture_pixels[0..].ptr,
    .width = 130,
    .height = 130,
    .stride = 132,
    .transparency_key = .black,
    .has_transparency = false,
};

const large_transparent_fixture: Bitmap = .{
    .pixels = large_transparent_fixture_pixels[0..].ptr,
    .width = 131,
    .height = 129,
    .stride = 136,
    .transparency_key = .magenta,
    .has_transparency = true,
};

const medium_opaque_fixture: Bitmap = .{
    .pixels = medium_opaque_fixture_pixels[0..].ptr,
    .width = 72,
    .height = 72,
    .stride = 74,
    .transparency_key = .black,
    .has_transparency = false,
};

const medium_transparent_fixture: Bitmap = .{
    .pixels = medium_transparent_fixture_pixels[0..].ptr,
    .width = 73,
    .height = 71,
    .stride = 76,
    .transparency_key = .magenta,
    .has_transparency = true,
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
    .{ .name = "large-gradient-opaque", .canvas = .{ .width = 193, .height = 193 }, .build_fn = build_bitmap_large_gradient_opaque },
    .{ .name = "large-gradient-transparent", .canvas = .{ .width = 193, .height = 193 }, .build_fn = build_bitmap_large_gradient_transparent },
    .{ .name = "large-gradient-boundaries", .canvas = .{ .width = 193, .height = 193 }, .build_fn = build_bitmap_large_gradient_boundaries },
};

const command_focused_cases = [_]CaseDef{
    .{ .name = "clear-only", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_clear_only },
    .{ .name = "set-clip-rect-focused", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_set_clip_rect_focused },
    .{ .name = "set-pixel-only", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_set_pixel_only },
    .{ .name = "draw-line-only", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_draw_line_only },
    .{ .name = "draw-rect-only", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_draw_rect_only },
    .{ .name = "fill-rect-only", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_fill_rect_only },
    .{ .name = "blit-bitmap-only", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_blit_bitmap_only },
    .{ .name = "blit-partial-bitmap-only", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_command_blit_partial_bitmap_only },
    .{ .name = "draw-text-only", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .text = true }, .build_fn = build_command_draw_text_only },
    .{ .name = "blit-framebuffer-only", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .framebuffers = true }, .build_fn = build_command_blit_framebuffer_only },
    .{ .name = "blit-partial-framebuffer-only", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .framebuffers = true }, .build_fn = build_command_blit_partial_framebuffer_only },
};

const mixed_curated_cases = [_]CaseDef{
    .{ .name = "clip-geometry-bitmap", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_mixed_clip_geometry_bitmap },
    .{ .name = "many-tiles", .canvas = .{ .width = 193, .height = 129 }, .build_fn = build_mixed_many_tiles },
    .{ .name = "overdraw-ordering", .canvas = .{ .width = 127, .height = 95 }, .build_fn = build_mixed_overdraw_ordering },
    .{ .name = "negative-and-partial", .canvas = .{ .width = 96, .height = 72 }, .build_fn = build_mixed_negative_partial },
};

const overdraw_profile_cases = [_]CaseDef{
    .{ .name = "large-overdraw-elimination-profile", .canvas = .{ .width = 512, .height = 320 }, .build_fn = build_overdraw_elimination_profile },
};

const draw_text_cases = [_]CaseDef{
    .{ .name = "draw-text-placeholder", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_placeholder },
    .{ .name = "clip-bitmap-fonts", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_clip_bitmap_fonts },
    .{ .name = "clip-vector-font", .canvas = .{ .width = 127, .height = 95 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_clip_vector_font },
    .{ .name = "clip-zero-and-outside", .canvas = .{ .width = 96, .height = 72 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_clip_zero_and_outside },
    .{ .name = "clip-nested-and-reset", .canvas = .{ .width = 127, .height = 95 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_clip_nested_and_reset },
    .{ .name = "tile-boundaries-mono6", .canvas = .{ .width = 193, .height = 129 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_tile_boundaries_mono6 },
    .{ .name = "tile-boundaries-mono8", .canvas = .{ .width = 193, .height = 129 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_tile_boundaries_mono8 },
    .{ .name = "tile-boundaries-vector-sizes", .canvas = .{ .width = 193, .height = 193 }, .capabilities = .{ .text = true }, .build_fn = build_draw_text_tile_boundaries_vector_sizes },
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
    .{ .name = "command-focused", .cases = command_focused_cases[0..] },
    .{ .name = "mixed-curated", .cases = mixed_curated_cases[0..] },
    .{ .name = "overdraw-profile", .cases = overdraw_profile_cases[0..] },
    .{ .name = "draw-text", .capabilities = .{ .text = true }, .cases = draw_text_cases[0..] },
    .{ .name = "blit-framebuffer", .capabilities = .{ .framebuffers = true }, .cases = framebuffer_blit_cases[0..] },
    .{ .name = "blit-partial-framebuffer", .capabilities = .{ .framebuffers = true }, .cases = framebuffer_partial_cases[0..] },
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 3) {
        printUsage(args[0]);
        return 2;
    }

    const suite_filter = if (args.len >= 2) args[1] else null;
    const case_filter = if (args.len >= 3) args[2] else null;

    try std.fs.cwd().makePath(output_dir_path);

    var summary: RunSummary = .{};
    var suite_reports: std.ArrayListUnmanaged(SuiteRunStats) = .{};
    defer {
        for (suite_reports.items) |*suite_report| {
            suite_report.deinit(allocator);
        }
        suite_reports.deinit(allocator);
    }

    if (suite_filter) |selected_suite_name| {
        if (std.mem.eql(u8, selected_suite_name, "seeded-random")) {
            const random_stats = try run_seeded_random_suite(allocator, case_filter);
            if (case_filter != null and random_stats.executed_cases == 0 and random_stats.skipped_cases == 0) {
                std.debug.print("unknown test '{s}' in suite 'seeded-random'\n", .{case_filter.?});
                return 2;
            }
            accumulateSummary(&summary, random_stats);
            try suite_reports.append(allocator, random_stats);
        } else {
            const suite = findStaticSuite(selected_suite_name) orelse {
                std.debug.print("unknown suite '{s}'\n", .{selected_suite_name});
                printUsage(args[0]);
                return 2;
            };

            var filtered_suite = suite;
            if (case_filter) |selected_case_name| {
                const selected_case = findCaseInSuite(suite, selected_case_name) orelse {
                    std.debug.print("unknown test '{s}' in suite '{s}'\n", .{ selected_case_name, selected_suite_name });
                    return 2;
                };
                filtered_suite.cases = selected_case;
            }

            const stats = try run_static_suite(allocator, &filtered_suite);
            accumulateSummary(&summary, stats);
            try suite_reports.append(allocator, stats);
        }
    } else {
        for (static_suites) |suite| {
            const stats = try run_static_suite(allocator, &suite);
            accumulateSummary(&summary, stats);
            try suite_reports.append(allocator, stats);
        }

        const random_stats = try run_seeded_random_suite(allocator, null);
        accumulateSummary(&summary, random_stats);
        try suite_reports.append(allocator, random_stats);
    }

    printReport(summary, suite_reports.items);

    std.debug.print(
        "agp exerciser: suites={} skipped_suites={} cases={} skipped_cases={} failures={} bad_pixels={} wrong={d:.2}%\n",
        .{
            summary.executed_suites,
            summary.skipped_suites,
            summary.executed_cases,
            summary.skipped_cases,
            summary.failed_cases,
            summary.bad_pixels,
            percentValue(summary.bad_pixels, summary.total_pixels),
        },
    );

    if (summary.failed_cases != 0) {
        return 1;
    }
    return 0;
}

fn printUsage(argv0: []const u8) void {
    std.debug.print("usage: {s} [suite-name] [test-name]\n", .{argv0});
}

fn findStaticSuite(name: []const u8) ?SuiteDef {
    for (static_suites) |suite| {
        if (std.mem.eql(u8, suite.name, name)) {
            return suite;
        }
    }
    return null;
}

fn findCaseInSuite(suite: SuiteDef, name: []const u8) ?[]const CaseDef {
    for (suite.cases) |*case| {
        if (std.mem.eql(u8, case.name, name)) {
            return @as([]const CaseDef, case[0..1]);
        }
    }
    return null;
}

fn run_static_suite(allocator: std.mem.Allocator, suite: *const SuiteDef) !SuiteRunStats {
    if (!suiteSupported(suite.capabilities)) {
        std.debug.print("skip suite {s}: unsupported capabilities\n", .{suite.name});
        var stats: SuiteRunStats = .{
            .name = suite.name,
            .artifact_path = try allocator.dupe(u8, ""),
            .skipped_cases = suite.cases.len,
        };
        try appendSkippedCases(allocator, &stats, suite.cases);
        return stats;
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
        var stats: SuiteRunStats = .{
            .name = suite.name,
            .artifact_path = try allocator.dupe(u8, ""),
            .skipped_cases = suite.cases.len,
        };
        try appendSkippedCases(allocator, &stats, suite.cases);
        return stats;
    }

    var suite_path_buffer: [256]u8 = undefined;
    const suite_path = try std.fmt.bufPrint(&suite_path_buffer, "{s}/{s}.gif", .{ output_dir_path, suite.name });
    var failures_path_buffer: [256]u8 = undefined;
    const failures_path = try std.fmt.bufPrint(&failures_path_buffer, "{s}/{s}-failures.gif", .{ output_dir_path, suite.name });
    try ensureStaticSuiteDir(suite.name);

    var suite_file = try std.fs.cwd().createFile(suite_path, .{ .truncate = true });
    defer suite_file.close();

    var buffer: [8192]u8 = undefined;
    var file_writer = suite_file.writer(&buffer);

    var suite_gif = try gif.GIF_Encoder.start(
        &file_writer.interface,
        compositeWidth(max_canvas.width),
        max_canvas.height,
        suite_frame_delay_cs,
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
        .name = suite.name,
        .artifact_path = try allocator.dupe(u8, suite_path),
    };

    for (suite.cases) |case| {
        if (!suiteSupported(case.capabilities)) {
            stats.skipped_cases += 1;
            try appendCaseStat(allocator, &stats, case.name, false, 0, 0);
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
        const total_pixels = @as(usize, result.width) * @as(usize, result.height);
        stats.bad_pixels += result.comparison.mismatch_count;
        stats.total_pixels += total_pixels;
        try appendCaseStat(
            allocator,
            &stats,
            case.name,
            true,
            result.comparison.mismatch_count,
            total_pixels,
        );

        if (!result.comparison.matched()) {
            stats.failed_cases += 1;
            try writeStaticCaseArtifacts(suite.name, case.name, case.canvas, max_canvas, composite, result.sequence);
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
                failure_file = try std.fs.cwd().createFile(failures_path, .{ .truncate = true });
                failure_file_writer = failure_file.?.writer(&failure_buffer);

                failure_gif = try gif.GIF_Encoder.start(
                    &failure_file_writer.interface,
                    compositeWidth(max_canvas.width),
                    max_canvas.height,
                    suite_frame_delay_cs,
                );
            }
            try failure_gif.?.add_frame(composite);
        } else {
            try deleteStaticCaseArtifacts(suite.name, case.name);
        }
    }

    if (stats.failed_cases == 0) {
        try deleteFileIfPresent(failures_path);
    }

    return stats;
}

fn run_seeded_random_suite(allocator: std.mem.Allocator, case_filter: ?[]const u8) !SuiteRunStats {
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
    try ensureStaticSuiteDir(suite_name);

    var suite_file = try std.fs.cwd().createFile(suite_path, .{ .truncate = true });
    defer suite_file.close();

    var suite_buffer: [8192]u8 = undefined;
    var suite_file_writer = suite_file.writer(&suite_buffer);

    var suite_gif = try gif.GIF_Encoder.start(
        &suite_file_writer.interface,
        compositeWidth(max_canvas.width),
        max_canvas.height,
        suite_frame_delay_cs,
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
        .artifact_path = try allocator.dupe(u8, suite_path),
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

            if (case_filter) |selected_case_name| {
                if (!std.mem.eql(u8, case.name, selected_case_name)) {
                    continue;
                }
            }

            stats.executed_cases += 1;

            var result = run_case(allocator, &case) catch |err| blk: {
                std.debug.print("case {s}/{s} failed to execute: {s}\n", .{ suite_name, case.name, @errorName(err) });
                break :blk try make_error_result(allocator, case.canvas);
            };
            defer result.deinit(allocator);

            const composite = try compose_case_frame(allocator, max_canvas, &result);
            defer allocator.free(composite);

            try suite_gif.add_frame(composite);
            const total_pixels = @as(usize, result.width) * @as(usize, result.height);
            stats.bad_pixels += result.comparison.mismatch_count;
            stats.total_pixels += total_pixels;
            try appendCaseStat(
                allocator,
                &stats,
                case.name,
                true,
                result.comparison.mismatch_count,
                total_pixels,
            );

            if (!result.comparison.matched()) {
                stats.failed_cases += 1;
                try writeStaticCaseArtifacts(suite_name, case.name, case.canvas, max_canvas, composite, result.sequence);
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
                        suite_frame_delay_cs,
                    );
                }
                try failure_gif.?.add_frame(composite);
            } else {
                try deleteStaticCaseArtifacts(suite_name, case.name);
            }
        }
    }

    if (stats.failed_cases == 0) {
        try deleteFileIfPresent(failures_path);
    }

    return stats;
}

fn deleteFileIfPresent(path: []const u8) !void {
    std.fs.cwd().deleteFile(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn run_case(allocator: std.mem.Allocator, case: *const CaseDef) !CaseResult {
    const sequence = try build_command_stream(allocator, case);

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
        .sequence = sequence,
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

fn fillXorPrefill(pixels: []Color, width: u16, height: u16, stride: u32) void {
    for (0..height) |y| {
        const row = pixels[@as(usize, y) * @as(usize, stride) ..][0..width];
        for (row, 0..) |*pixel, x| {
            pixel.* = Color.from_u8(@intCast((x ^ y) & 0x3f));
        }
    }
}

fn render_reference(allocator: std.mem.Allocator, canvas: CanvasSize, sequence: []const u8) ![]Color {
    const pixel_count = @as(usize, canvas.width) * @as(usize, canvas.height);
    const pixels = try allocator.alloc(Color, pixel_count);
    fillXorPrefill(pixels, canvas.width, canvas.height, canvas.width);

    var rasterizer = agp_swrast.Rasterizer.init(.{
        .pixels = pixels.ptr,
        .width = canvas.width,
        .height = canvas.height,
        .stride = canvas.width,
    });

    const resolver = agp_swrast.Rasterizer.Resolver{
        .ctx = @ptrCast(@constCast(&resource_catalog)),
        .resolve_font_fn = ResourceCatalog.resolveFontReference,
        .resolve_framebuffer_fn = ResourceCatalog.resolveFramebufferReference,
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

    fillXorPrefill(backing, canvas.width, canvas.height, stride);

    var rasterizer: agp_tiled_rast.Rasterizer = .{};
    const resolver = agp_tiled_rast.Resolver{
        .ctx = @ptrCast(@constCast(&resource_catalog)),
        .vtable = &.{
            .resolve_font_fn = ResourceCatalog.resolveFontCandidate,
            .resolve_framebuffer_fn = ResourceCatalog.resolveFramebufferCandidate,
        },
    };
    try rasterizer.execute(.{
        .pixels = backing.ptr,
        .width = canvas.width,
        .height = canvas.height,
        .stride = stride,
    }, resolver, sequence);

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
    const sequence = try allocator.alloc(u8, 0);
    errdefer allocator.free(sequence);

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
        .sequence = sequence,
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

fn ensureStaticSuiteDir(suite_name: []const u8) !void {
    var path_buffer: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ output_dir_path, suite_name });
    try std.fs.cwd().makePath(path);
}

fn sanitizeFileName(buf: []u8, name: []const u8) []const u8 {
    std.debug.assert(buf.len >= name.len);

    for (name, 0..) |ch, i| {
        buf[i] = switch (ch) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => ch,
            else => '_',
        };
    }
    return buf[0..name.len];
}

fn writeStaticCaseArtifacts(
    suite_name: []const u8,
    case_name: []const u8,
    canvas: CanvasSize,
    max_canvas: CanvasSize,
    composite: []const agp.Color,
    sequence: []const u8,
) !void {
    var path_buffer: [512]u8 = undefined;
    const path = try staticCaseRenderPath(&path_buffer, suite_name, case_name);
    try gif.write_to_file_path(std.fs.cwd(), path, compositeWidth(max_canvas.width), max_canvas.height, composite);

    var dump_path_buffer: [512]u8 = undefined;
    const dump_path = try staticCaseDumpPath(&dump_path_buffer, suite_name, case_name);
    try writeCaseCommandDumpToPath(dump_path, canvas, sequence);
}

fn deleteStaticCaseArtifacts(suite_name: []const u8, case_name: []const u8) !void {
    var path_buffer: [512]u8 = undefined;
    const path = try staticCaseRenderPath(&path_buffer, suite_name, case_name);
    std.fs.cwd().deleteFile(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    var dump_path_buffer: [512]u8 = undefined;
    const dump_path = try staticCaseDumpPath(&dump_path_buffer, suite_name, case_name);
    std.fs.cwd().deleteFile(dump_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn staticCaseRenderPath(path_buffer: []u8, suite_name: []const u8, case_name: []const u8) ![]const u8 {
    var file_name_buffer: [160]u8 = undefined;
    const file_name = sanitizeFileName(&file_name_buffer, case_name);
    return std.fmt.bufPrint(path_buffer, "{s}/{s}/{s}.gif", .{ output_dir_path, suite_name, file_name });
}

fn staticCaseDumpPath(path_buffer: []u8, suite_name: []const u8, case_name: []const u8) ![]const u8 {
    var file_name_buffer: [160]u8 = undefined;
    const file_name = sanitizeFileName(&file_name_buffer, case_name);
    return std.fmt.bufPrint(path_buffer, "{s}/{s}/{s}.txt", .{ output_dir_path, suite_name, file_name });
}

fn writeCaseCommandDumpToPath(path: []const u8, canvas: CanvasSize, sequence: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [8192]u8 = undefined;
    var file_writer = file.writer(&buffer);
    try writeCaseCommandDump(&file_writer.interface, canvas, sequence);
    try file_writer.interface.flush();
}

fn writeCaseCommandDump(writer: *std.Io.Writer, canvas: CanvasSize, sequence: []const u8) !void {
    var decoder: agp.BufferDecoder = .init(sequence);
    var optimizing_state = agp.OptimizingEncoder.State.initForImage(canvas.width, canvas.height);
    while (try decoder.next()) |cmd| {
        const emission = optimizing_state.classify(cmd);
        try writer.print("{s} ", .{@tagName(emission)});
        try dumpCommand(writer, cmd);
        try writer.writeByte('\n');
    }
}

fn dumpCommand(writer: *std.Io.Writer, cmd: agp.Command) !void {
    switch (cmd) {
        .clear => |item| {
            try writer.writeAll("clear(");
            try writer.writeAll("color=");
            try formatColor(writer, item.color);
            try writer.writeAll(")");
        },
        .set_clip_rect => |item| {
            try writer.print(
                "set_clip_rect(x={}, y={}, width={}, height={})",
                .{ item.x, item.y, item.width, item.height },
            );
        },
        .set_pixel => |item| {
            try writer.print("set_pixel(x={}, y={}, color=", .{ item.x, item.y });
            try formatColor(writer, item.color);
            try writer.writeAll(")");
        },
        .draw_line => |item| {
            try writer.print("draw_line(x1={}, y1={}, x2={}, y2={}, color=", .{
                item.x1,
                item.y1,
                item.x2,
                item.y2,
            });
            try formatColor(writer, item.color);
            try writer.writeAll(")");
        },
        .draw_rect => |item| {
            try writer.print("draw_rect(x={}, y={}, width={}, height={}, color=", .{
                item.x,
                item.y,
                item.width,
                item.height,
            });
            try formatColor(writer, item.color);
            try writer.writeAll(")");
        },
        .fill_rect => |item| {
            try writer.print("fill_rect(x={}, y={}, width={}, height={}, color=", .{
                item.x,
                item.y,
                item.width,
                item.height,
            });
            try formatColor(writer, item.color);
            try writer.writeAll(")");
        },
        .draw_text => |item| {
            try writer.print("draw_text(x={}, y={}, font=", .{ item.x, item.y });
            try formatFont(writer, item.font);
            try writer.writeAll(", color=");
            try formatColor(writer, item.color);
            try writer.print(", text=\"{f}\")", .{std.zig.fmtString(item.text)});
        },
        .blit_bitmap => |item| {
            try writer.print("blit_bitmap(x={}, y={}, bitmap=", .{ item.x, item.y });
            try formatBitmap(writer, &item.bitmap);
            try writer.writeAll(")");
        },
        .blit_framebuffer => |item| {
            try writer.print("blit_framebuffer(x={}, y={}, framebuffer=", .{ item.x, item.y });
            try formatFramebuffer(writer, item.framebuffer);
            try writer.writeAll(")");
        },
        .blit_partial_bitmap => |item| {
            try writer.print(
                "blit_partial_bitmap(x={}, y={}, width={}, height={}, src_x={}, src_y={}, bitmap=",
                .{ item.x, item.y, item.width, item.height, item.src_x, item.src_y },
            );
            try formatBitmap(writer, &item.bitmap);
            try writer.writeAll(")");
        },
        .blit_partial_framebuffer => |item| {
            try writer.print(
                "blit_partial_framebuffer(x={}, y={}, width={}, height={}, src_x={}, src_y={}, framebuffer=",
                .{ item.x, item.y, item.width, item.height, item.src_x, item.src_y },
            );
            try formatFramebuffer(writer, item.framebuffer);
            try writer.writeAll(")");
        },
    }
}

fn formatColor(writer: *std.Io.Writer, color: Color) !void {
    const rgb = color.to_rgb888();
    try writer.print("#{x:0>2}{x:0>2}{x:0>2}[{x:0>2}]", .{
        rgb.r,
        rgb.g,
        rgb.b,
        @as(u8, @bitCast(color)),
    });
}

fn formatBitmap(writer: *std.Io.Writer, bitmap: *const Bitmap) !void {
    try writer.print("Bmp({}x{}/{})", .{ bitmap.width, bitmap.height, bitmap.stride });
    if (bitmap.has_transparency) {
        try writer.writeAll(", ");
        try formatColor(writer, bitmap.transparency_key);
    }
}

fn formatFont(writer: *std.Io.Writer, handle: agp.Font) !void {
    const font = ResourceCatalog.lookupFontInstance(handle) orelse {
        try writer.print("Font(unknown/0x{x}, ?px)", .{@intFromPtr(handle)});
        return;
    };

    try writer.print("Font({s}/0x{x}, {}px)", .{
        switch (font.*) {
            .bitmap => "bitmap",
            .vector => "vector",
        },
        @intFromPtr(handle),
        font.line_height(),
    });
}

fn formatFramebuffer(writer: *std.Io.Writer, handle: agp.Framebuffer) !void {
    const fixture = ResourceCatalog.lookupFramebufferFixture(handle) orelse {
        try writer.print("FrameBuf(0x{x})", .{@intFromPtr(handle)});
        return;
    };

    try writer.print("FrameBuf(0x{x}, {}x{}/{})", .{
        @intFromPtr(handle),
        fixture.width,
        fixture.height,
        fixture.stride,
    });
}

fn alignStride(width: u16) u32 {
    const tile = agp_tiled_rast.tile_size;
    return @intCast(std.mem.alignForward(usize, width, tile));
}

fn suiteSupported(required: Capabilities) bool {
    _ = required;
    return true;
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
    summary.bad_pixels += stats.bad_pixels;
    summary.total_pixels += stats.total_pixels;
}

fn appendSkippedCases(allocator: std.mem.Allocator, stats: *SuiteRunStats, cases: []const CaseDef) !void {
    for (cases) |case| {
        try appendCaseStat(allocator, stats, case.name, false, 0, 0);
    }
}

fn appendCaseStat(
    allocator: std.mem.Allocator,
    stats: *SuiteRunStats,
    name: []const u8,
    executed: bool,
    bad_pixels: usize,
    total_pixels: usize,
) !void {
    try stats.case_stats.append(allocator, .{
        .name = try allocator.dupe(u8, name),
        .executed = executed,
        .bad_pixels = bad_pixels,
        .total_pixels = total_pixels,
    });
}

fn percentValue(bad_pixels: usize, total_pixels: usize) f64 {
    if (total_pixels == 0)
        return 0.0;
    return @as(f64, @floatFromInt(bad_pixels)) * 100.0 / @as(f64, @floatFromInt(total_pixels));
}

fn printSpaces(count: usize) void {
    for (0..count) |_| {
        std.debug.print(" ", .{});
    }
}

fn printDashes(count: usize) void {
    for (0..count) |_| {
        std.debug.print("-", .{});
    }
}

fn printCell(text: []const u8, width: usize, right_align: bool) void {
    const padding = width - text.len;
    if (right_align) {
        printSpaces(padding);
        std.debug.print("{s}", .{text});
    } else {
        std.debug.print("{s}", .{text});
        printSpaces(padding);
    }
}

fn printTableBorder(widths: []const usize) void {
    std.debug.print("+", .{});
    for (widths) |width| {
        printDashes(width + 2);
        std.debug.print("+", .{});
    }
    std.debug.print("\n", .{});
}

fn printTableRow(texts: []const []const u8, widths: []const usize, right_align: []const bool) void {
    std.debug.print("|", .{});
    for (texts, widths, right_align) |text, width, align_right| {
        std.debug.print(" ", .{});
        printCell(text, width, align_right);
        std.debug.print(" |", .{});
    }
    std.debug.print("\n", .{});
}

fn formatUsize(buf: []u8, value: usize) []const u8 {
    return std.fmt.bufPrint(buf, "{}", .{value}) catch unreachable;
}

fn formatPercent(buf: []u8, bad_pixels: usize, total_pixels: usize) []const u8 {
    return std.fmt.bufPrint(buf, "{d:.2}%", .{percentValue(bad_pixels, total_pixels)}) catch unreachable;
}

fn printReport(summary: RunSummary, suites: []const SuiteRunStats) void {
    const suite_widths = [_]usize{ 24, 8, 4, 4, 4, 10, 7 };
    const suite_align_right = [_]bool{ false, false, true, true, true, true, true };
    const case_widths = [_]usize{ 40, 8, 10, 7 };
    const case_align_right = [_]bool{ false, false, true, true };

    std.debug.print("\nSuite Summary\n", .{});
    printTableBorder(&suite_widths);
    printTableRow(
        &.{ "suite", "status", "exec", "skip", "fail", "bad px", "wrong %" },
        &suite_widths,
        &suite_align_right,
    );
    printTableBorder(&suite_widths);
    for (suites) |suite| {
        const status = if (suite.executed_cases == 0) "skipped" else if (suite.failed_cases == 0) "ok" else "mismatch";
        var exec_buf: [32]u8 = undefined;
        var skip_buf: [32]u8 = undefined;
        var fail_buf: [32]u8 = undefined;
        var bad_buf: [32]u8 = undefined;
        var pct_buf: [32]u8 = undefined;
        printTableRow(
            &.{
                suite.name,
                status,
                formatUsize(&exec_buf, suite.executed_cases),
                formatUsize(&skip_buf, suite.skipped_cases),
                formatUsize(&fail_buf, suite.failed_cases),
                formatUsize(&bad_buf, suite.bad_pixels),
                formatPercent(&pct_buf, suite.bad_pixels, suite.total_pixels),
            },
            &suite_widths,
            &suite_align_right,
        );
    }
    printTableBorder(&suite_widths);

    var total_exec_buf: [32]u8 = undefined;
    var total_skip_buf: [32]u8 = undefined;
    var total_fail_buf: [32]u8 = undefined;
    var total_bad_buf: [32]u8 = undefined;
    var total_pct_buf: [32]u8 = undefined;
    printTableRow(
        &.{
            "TOTAL",
            if (summary.failed_cases == 0) "ok" else "mismatch",
            formatUsize(&total_exec_buf, summary.executed_cases),
            formatUsize(&total_skip_buf, summary.skipped_cases),
            formatUsize(&total_fail_buf, summary.failed_cases),
            formatUsize(&total_bad_buf, summary.bad_pixels),
            formatPercent(&total_pct_buf, summary.bad_pixels, summary.total_pixels),
        },
        &suite_widths,
        &suite_align_right,
    );
    printTableBorder(&suite_widths);

    for (suites) |suite| {
        std.debug.print("\nSuite: {s}\n", .{suite.name});
        if (suite.executed_cases > 0) {
            std.debug.print("Artifact: {s}\n", .{suite.artifact_path});
            std.debug.print("Static: {s}/{s}/\n", .{ output_dir_path, suite.name });
        }
        printTableBorder(&case_widths);
        printTableRow(
            &.{ "case", "status", "bad px", "wrong %" },
            &case_widths,
            &case_align_right,
        );
        printTableBorder(&case_widths);
        for (suite.case_stats.items) |case_stat| {
            const status = if (!case_stat.executed) "skipped" else if (case_stat.bad_pixels == 0) "ok" else "mismatch";
            if (!case_stat.executed) {
                printTableRow(
                    &.{ case_stat.name, status, "-", "-" },
                    &case_widths,
                    &case_align_right,
                );
            } else {
                var case_bad_buf: [32]u8 = undefined;
                var case_pct_buf: [32]u8 = undefined;
                printTableRow(
                    &.{
                        case_stat.name,
                        status,
                        formatUsize(&case_bad_buf, case_stat.bad_pixels),
                        formatPercent(&case_pct_buf, case_stat.bad_pixels, case_stat.total_pixels),
                    },
                    &case_widths,
                    &case_align_right,
                );
            }
        }
        printTableBorder(&case_widths);
    }
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

fn build_bitmap_large_gradient_opaque(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(6));
    try enc.blit_bitmap(1, 1, &large_opaque_fixture);
}

fn build_bitmap_large_gradient_transparent(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(10));
    try enc.fill_rect(0, 0, 193, 193, .from_gray(14));
    try enc.blit_bitmap(1, 1, &large_transparent_fixture);
}

fn build_bitmap_large_gradient_boundaries(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);

    // Exact tile hits and misses with 63/64/65 extents.
    try enc.blit_partial_bitmap(0, 0, 63, 63, 0, 0, &medium_opaque_fixture);
    try enc.blit_partial_bitmap(64, 0, 64, 64, 1, 1, &medium_opaque_fixture);
    try enc.blit_partial_bitmap(128, 0, 65, 65, 2, 2, &medium_opaque_fixture);

    try enc.blit_partial_bitmap(-1, 64, 65, 63, 3, 3, &medium_opaque_fixture);
    try enc.blit_partial_bitmap(63, 128, 64, 65, 4, 4, &medium_transparent_fixture);

    // Negative and out-of-image placement while still spanning multiple tiles.
    try enc.blit_partial_bitmap(64, -1, 65, 64, 5, 5, &medium_transparent_fixture);
}

fn build_command_clear_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(24));
}

fn build_command_set_clip_rect_focused(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(5));
    try enc.set_clip_rect(18, 12, 44, 28);
    try enc.fill_rect(0, 0, 96, 72, .yellow);
    try enc.set_clip_rect(32, 24, 24, 16);
    try enc.fill_rect(0, 0, 96, 72, .blue);
    try enc.set_clip_rect(0, 0, 96, 72);
}

fn build_command_set_pixel_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.set_pixel(0, 0, .white);
    try enc.set_pixel(95, 0, .red);
    try enc.set_pixel(0, 71, .green);
    try enc.set_pixel(95, 71, .blue);
    try enc.set_pixel(63, 31, .yellow);
    try enc.set_pixel(64, 32, .cyan);
    try enc.set_pixel(-1, 10, .purple);
    try enc.set_pixel(96, 10, .magenta);
}

fn build_command_draw_line_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.draw_line(0, 0, 95, 71, .white);
    try enc.draw_line(95, 0, 0, 71, .red);
    try enc.draw_line(0, 35, 95, 35, .green);
    try enc.draw_line(48, 0, 48, 71, .blue);
    try enc.draw_line(-8, 60, 40, 10, .yellow);
}

fn build_command_draw_rect_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.draw_rect(0, 0, 1, 1, .white);
    try enc.draw_rect(2, 2, 20, 12, .red);
    try enc.draw_rect(31, 7, 33, 25, .green);
    try enc.draw_rect(62, 18, 34, 21, .blue);
    try enc.draw_rect(-4, 48, 18, 14, .yellow);
}

fn build_command_fill_rect_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.fill_rect(0, 0, 1, 1, .white);
    try enc.fill_rect(4, 4, 18, 10, .red);
    try enc.fill_rect(28, 10, 36, 16, .green);
    try enc.fill_rect(60, 26, 36, 20, .blue);
    try enc.fill_rect(-6, 52, 20, 18, .yellow);
}

fn build_command_blit_bitmap_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(7));
    try enc.blit_bitmap(0, 0, &opaque_fixture);
    try enc.blit_bitmap(31, 12, &opaque_fixture);
    try enc.blit_bitmap(63, 31, &strided_fixture);
    try enc.blit_bitmap(92, 68, &transparent_fixture);
}

fn build_command_blit_partial_bitmap_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(9));
    try enc.blit_partial_bitmap(0, 0, 8, 8, 0, 0, &opaque_fixture);
    try enc.blit_partial_bitmap(22, 14, 16, 10, 1, 1, &strided_fixture);
    try enc.blit_partial_bitmap(62, 30, 18, 18, 0, 0, &transparent_fixture);
    try enc.blit_partial_bitmap(88, 64, 16, 16, 0, 0, &opaque_fixture);
}

fn build_command_draw_text_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.draw_text(6, 14, ResourceCatalog.mono_6_font, .white, "mono6");
    try enc.draw_text(6, 32, ResourceCatalog.mono_8_font, .yellow, "mono8");
    try enc.draw_text(6, 56, ResourceCatalog.sans_font, .cyan, "sans");
}

fn build_command_blit_framebuffer_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.blit_framebuffer(6, 8, ResourceCatalog.framebuffer_primary);
    try enc.blit_framebuffer(28, 26, ResourceCatalog.framebuffer_secondary);
}

fn build_command_blit_partial_framebuffer_only(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.blit_partial_framebuffer(12, 10, 20, 16, 2, 1, ResourceCatalog.framebuffer_primary);
    try enc.blit_partial_framebuffer(58, 28, 30, 22, 17, 5, ResourceCatalog.framebuffer_secondary);
    try enc.blit_partial_framebuffer(-5, 50, 20, 18, 3, 2, ResourceCatalog.framebuffer_primary);
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
            try enc.fill_rect(
                x - 3,
                y - 2,
                20,
                14,
                Color.from_rgb(
                    wrap_u8_from_i16(x + 32),
                    wrap_u8_from_i16(y + 48),
                    wrap_u8_from_i16(x + y + 12),
                ),
            );
            try enc.draw_rect(x, y, 65, 33, .white);
            try enc.blit_bitmap(x + 12, y + 7, &opaque_fixture);
        }
    }
    try enc.draw_line(0, 0, 192, 128, .yellow);
    try enc.draw_line(192, 0, 0, 128, .cyan);
}

fn wrap_u8_from_i16(value: i16) u8 {
    return @truncate(@as(u16, @bitCast(value)));
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

fn build_overdraw_elimination_profile(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;

    const tile: i16 = agp_tiled_rast.tile_size;
    const image_w: i16 = 8 * tile;
    const image_h: i16 = 5 * tile;

    try enc.clear(.black);

    // Large clears that exercise full-image, partial-image, and off-image clip handling.
    try enc.set_clip_rect(-tile, -tile, @intCast(image_w + 2 * tile), @intCast(image_h + 2 * tile));
    try enc.clear(.from_gray(8));

    try enc.set_clip_rect(tile, tile, @intCast(image_w - 2 * tile), @intCast(image_h - 2 * tile));
    try enc.clear(.from_gray(16));

    try enc.set_clip_rect(-tile, tile, @intCast(2 * tile), @intCast(2 * tile));
    try enc.clear(.red);

    try enc.set_clip_rect(7 * tile, 4 * tile, @intCast(2 * tile), @intCast(2 * tile));
    try enc.clear(.blue);

    try enc.set_clip_rect(2 * tile, -tile, @intCast(4 * tile), @intCast(2 * tile));
    try enc.clear(.green);

    try enc.set_clip_rect(0, 0, @intCast(image_w), @intCast(image_h));

    // Wide opaque rectangles covering large image regions with heavy overlap.
    var row: i16 = -tile;
    while (row <= image_h) : (row += tile / 2) {
        var col: i16 = -tile - tile / 2;
        while (col <= image_w) : (col += tile - 12) {
            try enc.fill_rect(
                col,
                row,
                @intCast(2 * tile + 24),
                @intCast(tile + 20),
                profiling_color(col, row, 1),
            );
            col += tile / 3;
        }
    }

    // Frame-like rectangles that cross tile boundaries and leave islands of visibility.
    var band_y: i16 = -tile / 2;
    while (band_y < image_h + tile / 2) : (band_y += tile - 9) {
        var band_x: i16 = -tile;
        while (band_x < image_w + tile) : (band_x += tile - 7) {
            try enc.draw_rect(
                band_x,
                band_y,
                @intCast(2 * tile + 5),
                @intCast(tile + 11),
                profiling_color(band_x, band_y, 2),
            );
        }
    }

    // Partially and fully out-of-image rectangles on all sides.
    try enc.fill_rect(-2 * tile, 2 * tile, @intCast(tile + 12), @intCast(2 * tile), .yellow);
    try enc.fill_rect(image_w - tile / 2, tile / 2, @intCast(2 * tile), @intCast(2 * tile), .cyan);
    try enc.fill_rect(tile, -2 * tile, @intCast(3 * tile), @intCast(tile + 12), .purple);
    try enc.fill_rect(3 * tile, image_h - tile / 3, @intCast(3 * tile), @intCast(2 * tile), .magenta);
    try enc.fill_rect(image_w + tile / 2, image_h + tile / 2, @intCast(tile), @intCast(tile), .white);

    // Opaque image placements at and beyond tile edges.
    const opaque_points = [_][2]i16{
        .{ -tile, -tile },
        .{ -1, -1 },
        .{ tile - 1, tile - 1 },
        .{ tile, tile },
        .{ 3 * tile - 2, 2 * tile - 1 },
        .{ 7 * tile - 3, 4 * tile - 2 },
        .{ image_w - 2, image_h - 2 },
        .{ image_w + 1, image_h / 2 },
    };
    for (opaque_points) |point| {
        try enc.blit_bitmap(point[0], point[1], &opaque_fixture);
    }

    // Transparent image placements targeting corners, seams, and off-image tiles.
    const transparent_points = [_][2]i16{
        .{ -tile, tile - 1 },
        .{ tile - 1, -tile },
        .{ 2 * tile - 1, 0 },
        .{ 4 * tile - 2, 2 * tile - 1 },
        .{ 6 * tile - 1, 3 * tile - 2 },
        .{ image_w - tile / 2, image_h - tile / 2 },
        .{ image_w + tile / 2, -tile / 2 },
        .{ -tile / 2, image_h + tile / 2 },
    };
    for (transparent_points) |point| {
        try enc.blit_bitmap(point[0], point[1], &transparent_fixture);
    }

    // Partial bitmap blits with oversized targets and clipped source regions.
    const partial_specs = [_]struct {
        dst_x: i16,
        dst_y: i16,
        width: u16,
        height: u16,
        src_x: i16,
        src_y: i16,
        bitmap: *const Bitmap,
    }{
        .{ .dst_x = -tile, .dst_y = 0, .width = @intCast(tile + 20), .height = @intCast(tile), .src_x = 0, .src_y = 0, .bitmap = &transparent_fixture },
        .{ .dst_x = tile - 2, .dst_y = tile - 2, .width = @intCast(tile + 8), .height = @intCast(tile + 8), .src_x = 1, .src_y = 1, .bitmap = &strided_fixture },
        .{ .dst_x = 4 * tile - 4, .dst_y = 2 * tile - 6, .width = @intCast(2 * tile), .height = @intCast(tile + 16), .src_x = 0, .src_y = 0, .bitmap = &opaque_fixture },
        .{ .dst_x = image_w - tile / 2, .dst_y = image_h - tile / 2, .width = @intCast(2 * tile), .height = @intCast(2 * tile), .src_x = 0, .src_y = 0, .bitmap = &transparent_fixture },
        .{ .dst_x = image_w + 3, .dst_y = tile, .width = @intCast(tile), .height = @intCast(tile), .src_x = 0, .src_y = 0, .bitmap = &opaque_fixture },
        .{ .dst_x = tile, .dst_y = image_h + 5, .width = @intCast(tile), .height = @intCast(tile), .src_x = 0, .src_y = 0, .bitmap = &strided_fixture },
    };
    for (partial_specs) |spec| {
        try enc.blit_partial_bitmap(
            spec.dst_x,
            spec.dst_y,
            spec.width,
            spec.height,
            spec.src_x,
            spec.src_y,
            spec.bitmap,
        );
    }

    // Final clears under selective clips to create obvious candidate overdraw-elimination wins.
    try enc.set_clip_rect(tile / 2, tile / 2, @intCast(2 * tile), @intCast(2 * tile));
    try enc.clear(.from_gray(28));
    try enc.set_clip_rect(5 * tile, 2 * tile, @intCast(2 * tile), @intCast(2 * tile));
    try enc.clear(.from_gray(36));
    try enc.set_clip_rect(0, 0, @intCast(image_w), @intCast(image_h));
}

fn profiling_color(x: i16, y: i16, phase: i16) Color {
    return Color.from_rgb(
        wrap_u8_from_i16(x * 3 + phase * 17 + 29),
        wrap_u8_from_i16(y * 5 + phase * 23 + 41),
        wrap_u8_from_i16(x + y * 2 + phase * 31 + 7),
    );
}

fn build_draw_text_placeholder(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(4));
    try enc.draw_text(4, 14, ResourceCatalog.mono_6_font, .white, "tiny bitmap");
    try enc.draw_text(4, 30, ResourceCatalog.mono_8_font, .yellow, "bigger bitmap");
    try enc.set_clip_rect(0, 36, 96, 32);
    try enc.draw_text(4, 54, ResourceCatalog.sans_font, .cyan, "vector font");
}

fn build_draw_text_clip_bitmap_fonts(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(3));
    try enc.fill_rect(0, 0, 96, 72, .from_gray(7));

    try enc.set_clip_rect(6, 8, 34, 10);
    try enc.draw_text(4, 14, ResourceCatalog.mono_6_font, .white, "clip mono6");

    try enc.set_clip_rect(42, 10, 28, 14);
    try enc.draw_text(34, 18, ResourceCatalog.mono_8_font, .yellow, "mono8 edge");

    try enc.set_clip_rect(68, 22, 20, 18);
    try enc.draw_text(62, 30, ResourceCatalog.mono_8_font, .cyan, "tail");

    try enc.set_clip_rect(0, 44, 22, 10);
    try enc.draw_text(-6, 50, ResourceCatalog.mono_6_font, .red, "left");

    try enc.set_clip_rect(0, 0, 96, 72);
    try enc.draw_rect(5, 7, 35, 11, .red);
    try enc.draw_rect(41, 9, 29, 15, .green);
    try enc.draw_rect(67, 21, 21, 19, .blue);
    try enc.draw_rect(0, 43, 22, 11, .magenta);
}

fn build_draw_text_clip_vector_font(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.black);
    try enc.fill_rect(0, 0, 127, 95, .from_gray(5));

    try enc.set_clip_rect(12, 12, 44, 22);
    try enc.draw_text(6, 28, ResourceCatalog.sans_font, .white, "vector");

    try enc.set_clip_rect(52, 18, 34, 26);
    try enc.draw_text(38, 36, ResourceCatalog.sans_font, .yellow, "slice");

    try enc.set_clip_rect(86, 30, 28, 34);
    try enc.draw_text(76, 52, ResourceCatalog.sans_font, .cyan, "edge");

    try enc.set_clip_rect(0, 56, 40, 24);
    try enc.draw_text(-8, 74, ResourceCatalog.sans_font, .green, "left");

    try enc.set_clip_rect(0, 0, 127, 95);
    try enc.draw_rect(11, 11, 45, 23, .red);
    try enc.draw_rect(51, 17, 35, 27, .green);
    try enc.draw_rect(85, 29, 29, 35, .blue);
    try enc.draw_rect(0, 55, 40, 25, .magenta);
}

fn build_draw_text_clip_zero_and_outside(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(4));
    try enc.fill_rect(0, 0, 96, 72, .from_gray(8));

    try enc.set_clip_rect(12, 12, 0, 18);
    try enc.draw_text(4, 24, ResourceCatalog.mono_8_font, .white, "zero");

    try enc.set_clip_rect(-20, -16, 8, 8);
    try enc.draw_text(2, 16, ResourceCatalog.mono_6_font, .yellow, "off");

    try enc.set_clip_rect(92, 64, 12, 12);
    try enc.draw_text(80, 70, ResourceCatalog.mono_6_font, .cyan, "corner");

    try enc.set_clip_rect(0, 28, 18, 12);
    try enc.draw_text(-10, 34, ResourceCatalog.mono_8_font, .red, "neg");

    try enc.set_clip_rect(74, 0, 22, 16);
    try enc.draw_text(88, 12, ResourceCatalog.mono_6_font, .green, "right");

    try enc.set_clip_rect(0, 0, 96, 72);
    try enc.draw_rect(91, 63, 5, 9, .white);
    try enc.draw_rect(0, 27, 18, 13, .magenta);
    try enc.draw_rect(73, 0, 23, 16, .blue);
}

fn build_draw_text_clip_nested_and_reset(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(2));
    try enc.fill_rect(0, 0, 127, 95, .from_gray(6));

    try enc.set_clip_rect(10, 10, 96, 62);
    try enc.draw_text(6, 22, ResourceCatalog.mono_8_font, .white, "outer clip");

    try enc.set_clip_rect(22, 22, 44, 18);
    try enc.draw_text(12, 34, ResourceCatalog.mono_6_font, .yellow, "inner slice");

    try enc.set_clip_rect(70, 18, 28, 42);
    try enc.draw_text(60, 44, ResourceCatalog.sans_font, .cyan, "tall");

    try enc.set_clip_rect(36, 48, 20, 10);
    try enc.draw_text(28, 56, ResourceCatalog.mono_8_font, .green, "thin");

    try enc.set_clip_rect(0, 0, 127, 95);
    try enc.draw_text(4, 82, ResourceCatalog.mono_6_font, .red, "reset full clip");

    try enc.draw_rect(9, 9, 97, 63, .red);
    try enc.draw_rect(21, 21, 45, 19, .green);
    try enc.draw_rect(69, 17, 29, 43, .blue);
    try enc.draw_rect(35, 47, 21, 11, .magenta);
}

fn draw_text_tile_guides(enc: agp.Encoder, width: u16, height: u16) !void {
    const tile: i16 = agp_tiled_rast.tile_size;
    const dark_a: Color = .from_gray(4);
    const dark_b: Color = .from_gray(8);

    try enc.clear(dark_a);

    var tile_y: i16 = 0;
    while (tile_y < height) : (tile_y += tile) {
        var tile_x: i16 = 0;
        while (tile_x < width) : (tile_x += tile) {
            const tile_ix = @divFloor(tile_x, tile);
            const tile_iy = @divFloor(tile_y, tile);
            try enc.fill_rect(
                tile_x,
                tile_y,
                @intCast(@min(tile, @as(i16, @intCast(height)) - tile_y)),
                @intCast(@min(tile, @as(i16, @intCast(width)) - tile_x)),
                if (@mod(tile_ix + tile_iy, 2) == 0) dark_a else dark_b,
            );
        }
    }
}

fn build_draw_text_tile_boundaries_mono6(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try draw_text_tile_guides(enc, 193, 129);

    try enc.draw_text(58, 14, ResourceCatalog.mono_6_font, .white, "x63");
    try enc.draw_text(64, 14, ResourceCatalog.mono_6_font, .yellow, "x64");
    try enc.draw_text(122, 14, ResourceCatalog.mono_6_font, .cyan, "x127");
    try enc.draw_text(128, 14, ResourceCatalog.mono_6_font, .green, "x128");

    try enc.draw_text(6, 60, ResourceCatalog.mono_6_font, .red, "y63");
    try enc.draw_text(70, 60, ResourceCatalog.mono_6_font, .magenta, "cross y63");
    try enc.draw_text(6, 64, ResourceCatalog.mono_6_font, .blue, "y64");
    try enc.draw_text(70, 64, ResourceCatalog.mono_6_font, .purple, "cross y64");

    try enc.draw_text(-4, 126, ResourceCatalog.mono_6_font, .white, "neg x");
    try enc.draw_text(124, 126, ResourceCatalog.mono_6_font, .yellow, "tail");
}

fn build_draw_text_tile_boundaries_mono8(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try draw_text_tile_guides(enc, 193, 129);

    try enc.draw_text(54, 18, ResourceCatalog.mono_8_font, .white, "mono8@63");
    try enc.draw_text(64, 18, ResourceCatalog.mono_8_font, .yellow, "mono8@64");
    try enc.draw_text(118, 18, ResourceCatalog.mono_8_font, .cyan, "mono8@127");
    try enc.draw_text(128, 18, ResourceCatalog.mono_8_font, .green, "mono8@128");

    try enc.draw_text(8, 58, ResourceCatalog.mono_8_font, .red, "row63");
    try enc.draw_text(72, 58, ResourceCatalog.mono_8_font, .magenta, "cross-63");
    try enc.draw_text(8, 64, ResourceCatalog.mono_8_font, .blue, "row64");
    try enc.draw_text(72, 64, ResourceCatalog.mono_8_font, .purple, "cross-64");

    try enc.draw_text(-6, 120, ResourceCatalog.mono_8_font, .white, "left spill");
    try enc.draw_text(126, 120, ResourceCatalog.mono_8_font, .yellow, "right spill");
}

fn build_draw_text_tile_boundaries_vector_sizes(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try draw_text_tile_guides(enc, 193, 193);

    try enc.draw_text(56, 18, ResourceCatalog.sans_8_font, .white, "v8 x63");
    try enc.draw_text(122, 18, ResourceCatalog.sans_8_font, .yellow, "v8 x127");

    try enc.draw_text(44, 60, ResourceCatalog.sans_12_font, .cyan, "v12 at 64");
    try enc.draw_text(116, 60, ResourceCatalog.sans_12_font, .green, "v12 at 128");

    try enc.draw_text(18, 92, ResourceCatalog.sans_16_font, .red, "v16 row64");
    try enc.draw_text(90, 92, ResourceCatalog.sans_16_font, .magenta, "v16 cross");

    try enc.draw_text(-8, 148, ResourceCatalog.sans_24_font, .blue, "v24 left");
    try enc.draw_text(94, 148, ResourceCatalog.sans_24_font, .purple, "v24 seam 128");
}

fn build_framebuffer_blit_placeholder(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(3));
    try enc.blit_framebuffer(8, 8, ResourceCatalog.framebuffer_primary);
    try enc.blit_framebuffer(20, 28, ResourceCatalog.framebuffer_secondary);
}

fn build_framebuffer_partial_placeholder(enc: agp.Encoder, case: *const CaseDef) !void {
    _ = case;
    try enc.clear(.from_gray(5));
    try enc.blit_partial_framebuffer(8, 8, 16, 16, 2, 2, ResourceCatalog.framebuffer_primary);
    try enc.blit_partial_framebuffer(36, 18, 40, 24, 11, 4, ResourceCatalog.framebuffer_secondary);
    try enc.blit_partial_framebuffer(72, 40, 24, 20, 45, 8, ResourceCatalog.framebuffer_secondary);
}

const optimizing_encoder_test_bitmap_pixels = [_]Color{
    .red,  .green,
    .blue, .white,
};

const optimizing_encoder_test_bitmap: Bitmap = .{
    .pixels = optimizing_encoder_test_bitmap_pixels[0..].ptr,
    .width = 2,
    .height = 2,
    .stride = 2,
    .transparency_key = .black,
    .has_transparency = false,
};

fn encodeRegularCommands(allocator: std.mem.Allocator, commands: []const agp.Command) ![]u8 {
    var stream: std.Io.Writer.Allocating = .init(allocator);
    defer stream.deinit();

    const enc = agp.encoder(&stream.writer);
    for (commands) |cmd| {
        try enc.encode(cmd);
    }

    return try stream.toOwnedSlice();
}

fn encodeOptimizedCommands(allocator: std.mem.Allocator, commands: []const agp.Command) ![]u8 {
    var stream: std.Io.Writer.Allocating = .init(allocator);
    defer stream.deinit();

    var base = agp.encoder(&stream.writer);
    var enc = agp.optimizingEncoder(&base);
    for (commands) |cmd| {
        _ = try enc.encode(cmd);
    }

    return try stream.toOwnedSlice();
}

fn encodeOptimizedCommandsForImage(
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    commands: []const agp.Command,
) ![]u8 {
    var stream: std.Io.Writer.Allocating = .init(allocator);
    defer stream.deinit();

    var base = agp.encoder(&stream.writer);
    var enc = agp.optimizingEncoderForImage(&base, width, height);
    for (commands) |cmd| {
        _ = try enc.encode(cmd);
    }

    return try stream.toOwnedSlice();
}

fn encodeOptimizedDirect(
    allocator: std.mem.Allocator,
    comptime build_fn: *const fn (*agp.OptimizingEncoder) anyerror!void,
) ![]u8 {
    var stream: std.Io.Writer.Allocating = .init(allocator);
    defer stream.deinit();

    var base = agp.encoder(&stream.writer);
    var enc = agp.optimizingEncoder(&base);
    try build_fn(&enc);

    return try stream.toOwnedSlice();
}

test "writeCaseCommandDump marks off-image commands as skipped" {
    const commands = [_]agp.Command{
        .{ .set_pixel = .{ .x = 1, .y = 1, .color = .white } },
        .{ .set_pixel = .{ .x = 7, .y = 7, .color = .red } },
    };

    const sequence = try encodeRegularCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(sequence);

    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();

    try writeCaseCommandDump(&writer.writer, .{ .width = 4, .height = 4 }, sequence);

    try std.testing.expectEqualStrings(
        \\emitted set_pixel(x=1, y=1, color=#ffffff[3f])
        \\skipped set_pixel(x=7, y=7, color=#ff0000[f8])
        \\
    , writer.written());
}

test "OptimizingEncoder inside command passes through" {
    const commands = [_]agp.Command{
        .{ .set_pixel = .{ .x = 4, .y = 5, .color = .white } },
        .{ .draw_rect = .{ .x = 1, .y = 2, .width = 8, .height = 6, .color = .red } },
        .{ .fill_rect = .{ .x = 3, .y = 4, .width = 5, .height = 4, .color = .green } },
        .{ .draw_line = .{ .x1 = 0, .y1 = 0, .x2 = 9, .y2 = 9, .color = .blue } },
        .{ .blit_bitmap = .{ .x = 7, .y = 8, .bitmap = optimizing_encoder_test_bitmap } },
    };

    const regular = try encodeRegularCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(regular);

    const optimized = try encodeOptimizedCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(optimized);

    try std.testing.expectEqualSlices(u8, regular, optimized);
}

test "OptimizingEncoder outside command is dropped after clip" {
    const commands = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 10, .y = 10, .width = 4, .height = 4 } },
        .{ .set_pixel = .{ .x = 0, .y = 0, .color = .white } },
        .{ .draw_rect = .{ .x = 0, .y = 0, .width = 4, .height = 4, .color = .red } },
        .{ .fill_rect = .{ .x = 1, .y = 1, .width = 3, .height = 3, .color = .green } },
        .{ .draw_line = .{ .x1 = 0, .y1 = 0, .x2 = 4, .y2 = 4, .color = .blue } },
        .{ .blit_bitmap = .{ .x = 1, .y = 1, .bitmap = optimizing_encoder_test_bitmap } },
        .{ .blit_partial_framebuffer = .{
            .x = 0,
            .y = 0,
            .width = 2,
            .height = 2,
            .src_x = 0,
            .src_y = 0,
            .framebuffer = @ptrFromInt(2),
        } },
    };

    const expected = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 10, .y = 10, .width = 4, .height = 4 } },
    };

    const optimized = try encodeOptimizedCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(optimized);

    const regular_expected = try encodeRegularCommands(std.testing.allocator, &expected);
    defer std.testing.allocator.free(regular_expected);

    try std.testing.expectEqualSlices(u8, regular_expected, optimized);
}

test "OptimizingEncoder partially overlapping command is preserved" {
    const commands = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 4, .y = 4, .width = 8, .height = 8 } },
        .{ .draw_rect = .{ .x = 0, .y = 0, .width = 8, .height = 8, .color = .white } },
        .{ .draw_line = .{ .x1 = 0, .y1 = 10, .x2 = 10, .y2 = 10, .color = .red } },
        .{ .blit_bitmap = .{ .x = 11, .y = 11, .bitmap = optimizing_encoder_test_bitmap } },
    };

    const regular = try encodeRegularCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(regular);

    const optimized = try encodeOptimizedCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(optimized);

    try std.testing.expectEqualSlices(u8, regular, optimized);
}

test "OptimizingEncoder clear under empty clip is dropped" {
    const commands = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 3, .y = 3, .width = 0, .height = 0 } },
        .{ .clear = .{ .color = .white } },
    };

    const expected = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 3, .y = 3, .width = 0, .height = 0 } },
    };

    const optimized = try encodeOptimizedCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(optimized);

    const regular_expected = try encodeRegularCommands(std.testing.allocator, &expected);
    defer std.testing.allocator.free(regular_expected);

    try std.testing.expectEqualSlices(u8, regular_expected, optimized);
}

test "OptimizingEncoder set_clip_rect resets absolute clip" {
    const commands = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 } },
        .{ .set_clip_rect = .{ .x = 10, .y = 10, .width = 2, .height = 2 } },
        .{ .set_pixel = .{ .x = 10, .y = 10, .color = .white } },
    };

    const regular = try encodeRegularCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(regular);

    const optimized = try encodeOptimizedCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(optimized);

    try std.testing.expectEqualSlices(u8, regular, optimized);
}

test "OptimizingEncoder unknown-bounds commands pass through" {
    const commands = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 } },
        .{ .draw_text = .{
            .x = 4,
            .y = 5,
            .font = @ptrFromInt(1),
            .color = .white,
            .text = "text",
        } },
        .{ .blit_framebuffer = .{
            .x = 7,
            .y = 8,
            .framebuffer = @ptrFromInt(2),
        } },
    };

    const regular = try encodeRegularCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(regular);

    const optimized = try encodeOptimizedCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(optimized);

    try std.testing.expectEqualSlices(u8, regular, optimized);
}

test "OptimizingEncoder image bounds drop off-image commands" {
    const commands = [_]agp.Command{
        .{ .set_pixel = .{ .x = 2, .y = 2, .color = .white } },
        .{ .set_pixel = .{ .x = 9, .y = 9, .color = .red } },
        .{ .fill_rect = .{ .x = 6, .y = 1, .width = 4, .height = 2, .color = .green } },
        .{ .draw_line = .{ .x1 = -3, .y1 = 1, .x2 = -1, .y2 = 1, .color = .blue } },
        .{ .draw_text = .{
            .x = 20,
            .y = 20,
            .font = @ptrFromInt(1),
            .color = .yellow,
            .text = "unknown stays",
        } },
    };

    const expected = [_]agp.Command{
        .{ .set_pixel = .{ .x = 2, .y = 2, .color = .white } },
        .{ .fill_rect = .{ .x = 6, .y = 1, .width = 4, .height = 2, .color = .green } },
        .{ .draw_text = .{
            .x = 20,
            .y = 20,
            .font = @ptrFromInt(1),
            .color = .yellow,
            .text = "unknown stays",
        } },
    };

    const optimized = try encodeOptimizedCommandsForImage(std.testing.allocator, 8, 8, &commands);
    defer std.testing.allocator.free(optimized);

    const regular_expected = try encodeRegularCommands(std.testing.allocator, &expected);
    defer std.testing.allocator.free(regular_expected);

    try std.testing.expectEqualSlices(u8, regular_expected, optimized);
}

test "OptimizingEncoder encode Command matches direct methods" {
    const commands = [_]agp.Command{
        .{ .set_clip_rect = .{ .x = 3, .y = 3, .width = 2, .height = 2 } },
        .{ .set_pixel = .{ .x = 4, .y = 4, .color = .white } },
        .{ .set_pixel = .{ .x = 9, .y = 9, .color = .red } },
        .{ .draw_text = .{
            .x = 1,
            .y = 1,
            .font = @ptrFromInt(1),
            .color = .green,
            .text = "x",
        } },
    };

    const encoded = try encodeOptimizedCommands(std.testing.allocator, &commands);
    defer std.testing.allocator.free(encoded);

    const direct = try encodeOptimizedDirect(std.testing.allocator, struct {
        fn build(enc: *agp.OptimizingEncoder) !void {
            _ = try enc.set_clip_rect(3, 3, 2, 2);
            _ = try enc.set_pixel(4, 4, .white);
            _ = try enc.set_pixel(9, 9, .red);
            _ = try enc.draw_text(1, 1, @ptrFromInt(1), .green, "x");
        }
    }.build);
    defer std.testing.allocator.free(direct);

    try std.testing.expectEqualSlices(u8, encoded, direct);
}
