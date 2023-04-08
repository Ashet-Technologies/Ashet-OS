const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const ui_layout = @import("ui-layout");

const sdl = @cImport({
    @cInclude("SDL.h");
});

const default_palette = [_][]const u8{
    "000000",
    "2d1a71",
    "3e32d5",
    "af102e",
    "e4162b",
    "0e3e12",
    "38741a",
    "8d4131",
    "ffff40",
    "505d6d",
    "7b95a0",
    "a6cfd0",
    "b44cef",
    "e444c3",
    "00bc9f",
    "ffffff",
    "afe356",
    "2f3143",
    "fbc800",
    "6cb328",
    "0c101b",
    "0d384c",
    "140e1e",
    "177578",
    "190c12",
    "3257be",
    "353234",
    "409def",
    "480e55",
    "491d1e",
    "492917",
    "550e2b",
    "652bbc",
    "665d5b",
    "6becbd",
    "6e6aff",
    "70dbff",
    "941887",
    "97530f",
    "998d86",
    "9c2b3b",
    "a6adff",
    "aa2c1e",
    "bfffff",
    "c9fccc",
    "cb734d",
    "cdbfb3",
    "d8e0ff",
    "dd8c00",
    "dfeae4",
    "e45761",
    "e4fca2",
    "eae6da",
    "ec8cff",
    "efaf79",
    "f66d1e",
    "ff424f",
    "ff91e2",
    "ff9792",
    "ffae68",
    "ffcdff",
    "ffd5cf",
    "ffe1b5",
    "fff699",
};

pub fn main() !void {
    if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) != 0)
        @panic("sdl error");
    defer _ = sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        "Ashet OS UI Layout Tester",
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        400,
        300,
        sdl.SDL_WINDOW_SHOWN | sdl.SDL_WINDOW_RESIZABLE,
    ) orelse @panic("err");
    defer sdl.SDL_DestroyWindow(window);

    const renderer = sdl.SDL_CreateRenderer(
        window,
        -1,
        sdl.SDL_RENDERER_ACCELERATED,
    ) orelse @panic("error");
    defer sdl.SDL_DestroyRenderer(renderer);

    var width: c_int = 0;
    var height: c_int = 0;

    var texture: ?*sdl.SDL_Texture = null;

    const allocator = std.heap.c_allocator;

    var rgba_buf: [][4]u8 = undefined;
    var index_buf: []ashet.abi.ColorIndex = undefined;

    const palette: [256][4]u8 = blk: {
        var pal = std.mem.zeroes([256][4]u8);

        for (pal[0..default_palette.len], default_palette) |*dst, src| {
            dst.* = @bitCast([4]u8, @byteSwap(try std.fmt.parseInt(u32, src, 16)));
        }
        for (pal[default_palette.len..], 0..) |*dst, index| {
            dst.* = @bitCast([4]u8, std.hash.CityHash32.hash(std.mem.asBytes(&@intCast(u32, index))));
        }

        break :blk pal;
    };

    var event: sdl.SDL_Event = undefined;
    main_loop: while (true) {
        while (sdl.SDL_PollEvent(&event) != 0) {
            if (event.type == sdl.SDL_QUIT)
                break :main_loop;
        }

        const old_width = width;
        const old_height = height;

        sdl.SDL_GetWindowSize(window, &width, &height);

        if (old_width != width or old_height != height) {
            if (texture) |tex| {
                sdl.SDL_DestroyTexture(tex);
                allocator.free(rgba_buf);
                allocator.free(index_buf);
            }
            texture = sdl.SDL_CreateTexture(
                renderer,
                sdl.SDL_PIXELFORMAT_RGBX8888,
                sdl.SDL_TEXTUREACCESS_STREAMING,
                width,
                height,
            ) orelse @panic("oof");

            const size = @intCast(usize, width * height);

            rgba_buf = try allocator.alloc([4]u8, size);
            index_buf = try allocator.alloc(ashet.abi.ColorIndex, size);
        }

        var fb = gui.Framebuffer{
            .width = @intCast(u15, width),
            .height = @intCast(u15, height),
            .stride = @intCast(u15, width),
            .pixels = index_buf.ptr,
        };

        var win = ashet.abi.Window{
            .pixels = undefined,
            .stride = undefined,
            .client_rectangle = .{
                .x = 0,
                .y = 0,
                .width = @intCast(u16, width),
                .height = @intCast(u16, height),
            },
            .min_size = undefined,
            .max_size = undefined,
            .title = undefined,
            .flags = undefined,
        };

        ui_layout.layout(&win);

        ui_layout.interface.paint(fb);

        for (index_buf, rgba_buf) |index, *rgba| {
            const i = @enumToInt(index);
            rgba.* = palette[i];
        }

        _ = sdl.SDL_UpdateTexture(texture, null, rgba_buf.ptr, 4 * width);

        _ = sdl.SDL_RenderClear(renderer);

        _ = sdl.SDL_RenderCopy(renderer, texture, null, null);

        sdl.SDL_RenderPresent(renderer);
    }
}
