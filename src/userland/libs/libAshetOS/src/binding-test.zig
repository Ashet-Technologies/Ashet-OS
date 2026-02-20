const std = @import("std");

export fn _start() void {
    ashet_syscalls_resources_get_type();
    ashet_syscalls_resources_release();
    ashet_syscalls_resources_destroy();
}

extern fn ashet_syscalls_resources_get_type() void;
extern fn ashet_syscalls_resources_release() void;
extern fn ashet_syscalls_resources_destroy() void;
