const std = @import("std");
const ashet = @import("../main.zig");
const tinyusb = @import("usb/tinyusb.zig");

comptime {
    // Ensure TinyUSB glue is compiled:
    _ = tinyusb;
}
