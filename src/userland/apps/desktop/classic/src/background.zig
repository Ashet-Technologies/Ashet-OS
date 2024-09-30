const wallpaper = struct {
    const raw = @embedFile("../data/ui/wallpaper.img");

    const pixels = blk: {
        @setEvalBranchQuota(4 * 400 * 300);

        const data = @as([400 * 300]ColorIndex, @bitCast(raw[0 .. 400 * 300].*));

        for (data) |*c| {
            c.* = c.shift(framebuffer_wallpaper_shift - 1);
        }

        break :blk data;
    };
    const palette = @as([15]Color, @bitCast(@as([]const u8, raw)[400 * 300 .. 400 * 300 + 15 * @sizeOf(Color)].*));

    const bitmap = Bitmap{
        .width = 400,
        .height = 300,
        .stride = 400,
        .pixels = &pixels,
        .transparent = null,
    };
};
