const std = @import("std");

const c = @cImport({
    @cInclude("xcb/xcb.h");
});

pub fn init() !void {

    // Open the connection to the X server. Use the DISPLAY environment variable

    var screenNum: c_int = 0;
    const connection: *c.xcb_connection_t = c.xcb_connect(null, &screenNum) orelse return error.FailedToConnectToX11;

    // Get the screen whose number is screenNum

    const setup = c.xcb_get_setup(connection) orelse return error.FailedToGetXcbSetup;
    var iter: c.xcb_screen_iterator_t = c.xcb_setup_roots_iterator(setup);

    // we want the screen at index screenNum of the iterator
    for (0..@intCast(screenNum)) |_| {
        c.xcb_screen_next(&iter);
    }

    const screen: *c.xcb_screen_t = iter.data orelse return error.NoScreen;

    // report

    std.debug.print("\n", .{});
    std.debug.print("Informations of screen {}:\n", .{screen.root});
    std.debug.print("  width.........: {}\n", .{screen.width_in_pixels});
    std.debug.print("  height........: {}\n", .{screen.height_in_pixels});
    std.debug.print("  white pixel...: {}\n", .{screen.white_pixel});
    std.debug.print("  black pixel...: {}\n", .{screen.black_pixel});
    std.debug.print("\n", .{});
}
