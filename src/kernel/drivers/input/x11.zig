const std = @import("std");

const ashet = @import("../../main.zig");

pub fn keyFromKeySym(val: u32) ?ashet.abi.KeyUsageCode {
    // This table was creatively derived from
    // https://www.cl.cam.ac.uk/~mgk25/ucs/keysymdef.h
    return switch (val) {
        0xff08 => .backspace,
        0xff09 => .tab,
        0xff0d => .enter,
        0xff1b => .escape,
        0xff63 => .insert,
        0xffff => .delete,
        0xff50 => .home,
        0xff57 => .end,
        0xff55 => .page_up,
        0xff56 => .page_down,
        0xff51 => .left_arrow,
        0xff52 => .up_arrow,
        0xff53 => .right_arrow,
        0xff54 => .down_arrow,
        0xffbe => .f1,
        0xffbf => .f2,
        0xffc0 => .f3,
        0xffc1 => .f4,
        0xffc2 => .f5,
        0xffc3 => .f6,
        0xffc4 => .f7,
        0xffc5 => .f8,
        0xffc6 => .f9,
        0xffc7 => .f10,
        0xffc8 => .f11,
        0xffc9 => .f12,
        0xffe1 => .left_shift,
        0xffe2 => .right_shift,
        0xffe3 => .left_control,
        0xffe4 => .right_control,
        0xffe7 => .left_gui,
        0xffe8 => .right_gui,
        0xffe9 => .left_alt,
        0xffea => .right_alt,

        else => null,
    };
}
