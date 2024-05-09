const std = @import("std");
const sdl = @import("SDL2.zig");
const logger = std.log.scoped(.sdl_display);

const ashet = @import("../../../main.zig");

const SDL_Display = @This();

const SDL_WINDOW_USERDATA_SLUG = "AshetOS.SDL_DisplayPointer";

allocator: std.mem.Allocator,
index: usize,

window: *sdl.SDL_Window,
renderer: *sdl.SDL_Renderer,
screen: ashet.drivers.video.Host_SDL_Output,
input: ashet.drivers.input.Host_SDL_Input,

pub fn from_window(window: *sdl.SDL_Window) ?*SDL_Display {
    return @ptrCast(@alignCast(
        sdl.SDL_GetWindowData(window, SDL_WINDOW_USERDATA_SLUG),
    ));
}

pub fn init(
    allocator: std.mem.Allocator,
    index: usize,
    width: u16,
    height: u16,
) !*SDL_Display {
    const server = try allocator.create(SDL_Display);
    errdefer allocator.destroy(server);

    var window_title_buf: [32]u8 = undefined;
    const window_title = try std.fmt.bufPrintZ(
        &window_title_buf,
        "Ashet OS Screen {}",
        .{index},
    );

    const window = sdl.SDL_CreateWindow(
        window_title.ptr,
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        width,
        height,
        sdl.SDL_WINDOW_SHOWN,
    ) orelse sdl.panic();

    _ = sdl.SDL_SetWindowData(
        window,
        SDL_WINDOW_USERDATA_SLUG,
        server,
    );

    const renderer = sdl.SDL_CreateRenderer(
        window,
        -1,
        sdl.SDL_RENDERER_ACCELERATED,
    ) orelse sdl.panic();

    const backbuffer_texture = sdl.SDL_CreateTexture(
        renderer,
        sdl.SDL_PIXELFORMAT_BGR565,
        sdl.SDL_TEXTUREACCESS_STREAMING,
        width,
        height,
    ) orelse sdl.panic();

    server.* = .{
        .allocator = allocator,
        .index = index,

        .window = window,
        .renderer = renderer,

        .screen = try ashet.drivers.video.Host_SDL_Output.init(
            renderer,
            backbuffer_texture,
        ),
        .input = ashet.drivers.input.Host_SDL_Input.init(),
    };

    return server;
}
