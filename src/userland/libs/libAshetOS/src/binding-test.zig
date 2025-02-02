const std = @import("std");

export fn _start() void {
    resources_get_type();
    resources_release();
    resources_destroy();
}

extern fn resources_get_type() void;
extern fn resources_release() void;
extern fn resources_destroy() void;
