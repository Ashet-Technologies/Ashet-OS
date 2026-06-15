const std = @import("std");
const ashet = @import("ashet");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

const textured_mode = false;
const tau = std.math.tau;

const Point = ashet.abi.Point;
const Size = ashet.abi.Size;
const Rectangle = ashet.abi.Rectangle;
const Color = ashet.abi.Color;
const Bitmap = ashet.graphics.Bitmap;

fn load_texture(asset_dir: ashet.fs.Directory, name: []const u8) !Bitmap {
    var file = try asset_dir.openFile(name, .read_only, .open_existing);
    defer file.close();

    return try ashet.graphics.load_bitmap_file(ashet.process.mem.allocator(), file);
}

fn sample_texture(bmp: Bitmap, x: usize, y: usize) Color {
    const ux: u16 = @intCast(x & (64 - 1));
    const uy: u16 = @intCast(~y & (64 - 1));

    std.debug.assert(ux <= bmp.width);
    std.debug.assert(uy <= bmp.height);

    const index = uy * bmp.stride + ux;

    return bmp.pixels[index];
}

fn splat_range(range: []Color, bmp: Bitmap, y: usize) void {
    if (range.len == 0)
        return;

    for (range, 0..) |*dst, x| {
        dst.* = sample_texture(
            bmp,
            (bmp.width - 1) * x / (range.len - 1),
            y,
        );
    }
}

const sin_sin_sin: [256]f32 = blk: {
    var lut: [256]f32 = undefined;
    for (&lut, 0..) |*f, i| {
        f.* = @sin(std.math.tau * @as(f32, i) / (lut.len - 1));
    }
    break :blk lut;
};

fn sin(v: f32) f32 {
    const f = @mod(v, std.math.tau);

    const i_f = @mod(sin_sin_sin.len * f / std.math.tau, sin_sin_sin.len);
    const i: usize = @intFromFloat(i_f);

    return sin_sin_sin[i];
}

fn cos(v: f32) f32 {
    return sin(v + std.math.pi / 2.0);
}

fn flt_eq(a: f32, b: f32) void {
    if (@abs(a - b) > 0.02)
        @compileError(std.fmt.comptimePrint("{d:.5} != {d:.5}", .{ a, b }));
}

comptime {
    flt_eq(sin(0), 0);
    flt_eq(sin(std.math.pi), 0);
    flt_eq(sin(std.math.tau), 0);
}

pub fn main() !void {
    var asset_dir: ashet.fs.Directory = try .openDrive(.system, "etc/revision");
    defer asset_dir.close();

    const bricks_texture = try load_texture(asset_dir, "bricks.abm");
    const metal_texture = try load_texture(asset_dir, "metal.abm");
    const stones_texture = try load_texture(asset_dir, "stones.abm");
    const tiles_texture = try load_texture(asset_dir, "tiles.abm");

    if (false) {
        _ = .{
            bricks_texture,
            metal_texture,
            stones_texture,
            tiles_texture,
        };
    }

    const video_output = try ashet.video.acquire(.primary);
    defer video_output.release();

    const video_fb = try ashet.graphics.create_video_framebuffer(video_output);
    defer video_fb.release();

    const vmem = try ashet.graphics.get_framebuffer_memory(video_fb);

    var loop: u32 = 0;
    var time: f32 = 0.0;

    while (true) {
        var scanline: [*]Color = vmem.base;
        for (0..vmem.height) |y| {
            for (scanline[0..vmem.width], 0..) |*pixel, x| {
                pixel.* = Color.from_u8(@as(u8, @truncate(x ^ y + loop)));
            }
            scanline += vmem.stride;
        }

        if (true or ashet.abi.get_demo_mode() == 0) {
            scanline = vmem.base;
            const spinner_center: f32 = 640 / 2 + 100 * sin(1.2 * time) - 50 * cos(2 * time);
            const spinner_width = 64;
            for (0..vmem.height) |y| {
                const fy: f32 = @floatFromInt(y);

                const a = 3.3 * time + 0.010 * fy + 0.02 * (sin(time)) * fy + 1.2 * sin(time);

                // time for a sine table
                const p1: u32 = @intFromFloat(spinner_center + spinner_width / 2 * sin(a + 0.25 * tau));
                const p2: u32 = @intFromFloat(spinner_center + spinner_width / 2 * sin(a + 0.50 * tau));
                const p3: u32 = @intFromFloat(spinner_center + spinner_width / 2 * sin(a + 0.75 * tau));
                const p4: u32 = @intFromFloat(spinner_center + spinner_width / 2 * sin(a + 1.00 * tau));

                std.debug.assert(p1 < 640);
                std.debug.assert(p2 < 640);
                std.debug.assert(p3 < 640);
                std.debug.assert(p4 < 640);

                // std.log.err("y = {}, scanline = {*}", .{ y, scanline });

                if (p1 < p2) {
                    const range = scanline[p1 .. p2 + 1];
                    if (textured_mode)
                        splat_range(range, bricks_texture, y)
                    else
                        @memset(range, Color.red);
                }
                if (p2 < p3) {
                    const range = scanline[p2 .. p3 + 1];
                    if (textured_mode)
                        splat_range(range, metal_texture, y)
                    else
                        @memset(range, Color.blue);
                }
                if (p3 < p4) {
                    const range = scanline[p3 .. p4 + 1];
                    if (textured_mode)
                        splat_range(range, stones_texture, y)
                    else
                        @memset(range, Color.lime);
                }
                if (p4 < p1) {
                    const range = scanline[p4 .. p1 + 1];
                    if (textured_mode)
                        splat_range(range, tiles_texture, y)
                    else
                        @memset(range, Color.purple);
                }

                scanline += vmem.stride;
            }
        }

        try ashet.abi.draw.invalidate_framebuffer(video_fb, .everything);

        ashet.process.thread.yield();

        _ = try ashet.overlapped.performOne(ashet.video.WaitForVBlank, .{
            .output = @ptrCast(video_output),
        });

        loop +%= 1;
        time += 0.016;
    }
}
