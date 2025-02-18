const std = @import("std");
const libwin = @import("window");

pub fn main() !void {
    try libwin.init(.{});
    defer libwin.deinit();

    const window = try libwin.Window.create(.{
        .title = "libwindow Example",
        .size = libwin.Size.new(800, 480),
    });
    defer window.destroy();

    while (true) {
        const maybe_event = try libwin.pollEvent();
        if (maybe_event) |event| {
            switch (event.data) {
                //
            }
        }
    }
}
