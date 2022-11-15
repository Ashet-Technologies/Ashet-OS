const std = @import("std");
const sdl = @import("sdl2");
const abi = @import("ashet-abi");
const ashet = @import("ashet");

const screen_size = .{
    .width = 400,
    .height = 300,
    .scale = 3,
};

pub fn main() !void {
    if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) != 0)
        return error.SdlFailure;
    errdefer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        "",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        screen_size.scale * screen_size.width,
        screen_size.scale * screen_size.height,
        sdl.SDL_WINDOW_SHOWN,
    ) orelse @panic("sdl");

    framebuffer_renderer = sdl.SDL_CreateRenderer(
        window,
        -1,
        sdl.SDL_RENDERER_ACCELERATED,
    ) orelse @panic("sdl");

    framebuffer_texture = sdl.SDL_CreateTexture(
        framebuffer_renderer,
        sdl.SDL_PIXELFORMAT_XBGR8888,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        screen_size.width,
        screen_size.height,
    ) orelse @panic("sdl");

    app_loop: while (true) {
        var e: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&e) != 0) {
            if (e.type == sdl.SDL_QUIT)
                break :app_loop;
        }

        swapBuffers();
    }
}

pub const video = struct {
    pub const memory: []align(4096) u8 = &framebuffer_memory;
    pub const palette = &framebuffer_palette;
};

var framebuffer_renderer: *sdl.SDL_Renderer = undefined;
var framebuffer_texture: *sdl.SDL_Texture = undefined;
var framebuffer_border: u8 = ashet.video.defaults.border;
var framebuffer_memory: [120_000]u8 align(4096) = ashet.video.defaults.splash_screen ++ [1]u8{0} ** (120_000 - ashet.video.defaults.splash_screen.len);
var framebuffer_palette: [256]u16 = ashet.video.defaults.palette;

var framebuffer_mode: abi.VideoMode = .graphics;
var framebuffer_width: u16 = 256;
var framebuffer_height: u16 = 128;

fn expandColor(index: u8) u32 {
    return @bitCast(abi.Color, framebuffer_palette[index]).toRgb32();
}

fn swapBuffers() void {
    var framebuffer_rgba: [screen_size.width * screen_size.height]u32 = undefined;

    switch (framebuffer_mode) {
        .text => {
            std.mem.set(u32, &framebuffer_rgba, expandColor(framebuffer_border));

            const font = ashet.video.defaults.font;

            const w = 64;
            const h = 32;

            const gw = 6;
            const gh = 8;

            const dx = (screen_size.width - gw * w) / 2;
            const dy = (screen_size.height - gh * h) / 2;

            var i: usize = 0;
            while (i < w * h) : (i += 1) {
                const cx = i % w;
                const cy = i / w;

                const char = framebuffer_memory[2 * i + 0];
                const attr = abi.CharAttributes.fromByte(framebuffer_memory[2 * i + 1]);

                const glyph = font[char];

                var x: usize = 0;
                while (x < gw) : (x += 1) {
                    var bits = glyph[x];

                    comptime var y: usize = 0;
                    inline while (y < gh) : (y += 1) {
                        const index = if ((bits & (1 << y)) != 0)
                            attr.fg
                        else
                            attr.bg;
                        framebuffer_rgba[screen_size.width * (dy + gh * cy + y) + (dx + gw * cx + x)] = expandColor(index);
                    }
                }
            }
        },

        .graphics => {
            const dx = (screen_size.width - framebuffer_width) / 2;
            const dy = (screen_size.height - framebuffer_height) / 2;

            {
                var i: usize = 0;
                while (i < screen_size.width * screen_size.height) : (i += 1) {
                    const x = i % screen_size.width;
                    const y = i / screen_size.width;

                    if (x < dx or x >= dx + framebuffer_width or y < dy or y >= dy + framebuffer_height) {
                        framebuffer_rgba[i] = expandColor(framebuffer_border);
                    }
                }
            }

            const pixel_count = @as(usize, framebuffer_width) * @as(usize, framebuffer_height);

            for (framebuffer_memory[0..pixel_count]) |index, i| {
                const x = dx + i % framebuffer_width;
                const y = dy + i / framebuffer_width;

                framebuffer_rgba[screen_size.width * y + x] = expandColor(index);
            }
        },
    }

    _ = sdl.SDL_UpdateTexture(framebuffer_texture, null, &framebuffer_rgba, 4 * screen_size.width);

    _ = sdl.SDL_RenderCopy(framebuffer_renderer, framebuffer_texture, null, null);
    sdl.SDL_RenderPresent(framebuffer_renderer);
}

var abi_interface: abi.SystemCallInterface = .{
    //
};
