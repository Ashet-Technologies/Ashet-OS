const std = @import("std");
const ashet = @import("root");

pub const page_size = 4096;

pub const scheduler = struct {
    //
};

pub const start = struct {
    // TODO: Implement
};

pub inline fn getStackPointer() usize {
    return asm (""
        : [sp] "={sp}" (-> usize),
    );
}
