const std = @import("std");
const astd = @import("ashet-std");
const gui = @import("ashet-gui");
const logger = std.log.scoped(.ui);
const ashet = @import("../main.zig");
const system_assets = @import("system-assets");
const libashet = @import("ashet");

const Bitmap = gui.Bitmap;
const Framebuffer = gui.Framebuffer;

// offsets for well-known palette items
const framebuffer_wallpaper_shift = 255 - 15;
const framebuffer_default_icon_shift = 0; // framebuffer_wallpaper_shift - 15;
