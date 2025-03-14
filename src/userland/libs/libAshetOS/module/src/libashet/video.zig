const std = @import("std");

const ashet = @import("../libashet.zig");

const abi = ashet.abi;
const syscalls = ashet.userland;

pub const WaitForVBlank = ashet.abi.video.WaitForVBlank;

pub const Output = opaque {
    pub fn release(out: *Output) void {
        _ = out;
    }

    pub fn get_resolution(out: *Output) !abi.Size {
        return try syscalls.video.get_resolution(@ptrCast(out));
    }

    pub fn get_video_memory(out: *Output) !abi.VideoMemory {
        return try syscalls.video.get_video_memory(@ptrCast(out));
    }
};

pub fn acquire(id: abi.VideoOutputID) !*Output {
    return @ptrCast(
        try syscalls.video.acquire(id),
    );
}
