const std = @import("std");

const ashet = @import("../libashet.zig");

const abi = ashet.abi;

pub const VideoOutputID = abi.video.VideoOutputID;
pub const VideoMemory = abi.video.VideoMemory;
pub const BufferKind = abi.video.BufferKind;
pub const PresentMode = abi.video.PresentMode;

pub const WaitForVBlank = ashet.abi.video.WaitForVBlank;

pub const Output = opaque {
    pub fn release(out: *Output) void {
        abi.resources.release(.from_ptr(out));
    }

    pub fn get_resolution(out: *Output) !abi.Size {
        return try abi.video.get_resolution(@ptrCast(out));
    }

    // pub fn get_video_memory(out: *Output) !abi.VideoMemory {
    //     return try abi.video.get_video_memory(@ptrCast(out));
    // }
};

pub fn acquire(id: VideoOutputID) !*Output {
    return @ptrCast(
        try abi.video.acquire(id),
    );
}
