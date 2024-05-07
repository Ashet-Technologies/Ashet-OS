const std = @import("std");
const sdl2 = @import("SDL2.zig");
const logger = std.log.scoped(.sdl_display);

const ashet = @import("../../../main.zig");

const VNC_Server = @This();

allocator: std.mem.Allocator,

screen: ashet.drivers.video.Host_SDL_Output,
input: ashet.drivers.input.Host_SDL_Input,

pub fn init(
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
) !*VNC_Server {
    const server = try allocator.create(VNC_Server);
    errdefer allocator.destroy(server);

    server.* = .{
        .allocator = allocator,
        .screen = try ashet.drivers.video.Host_SDL_Output.init(width, height),
        .input = ashet.drivers.input.Host_SDL_Input.init(),
    };

    return server;
}
