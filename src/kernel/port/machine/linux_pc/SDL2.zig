const std = @import("std");
const logger = std.log.scoped(.sdl2);
const sdl = @cImport(@cInclude("SDL.h"));

pub usingnamespace sdl;

pub fn panic() noreturn {
    const string_ptr = @as(?[*:0]const u8, sdl.SDL_GetError()) orelse "no error text";

    const string = std.mem.sliceTo(string_ptr, 0);

    logger.err("{s}", .{string});
    std.os.exit(1);
}

pub fn assert(err: c_int) void {
    if (err != 0) {
        panic();
    }
}
