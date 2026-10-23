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

    pub fn create_mapping(out: *Output, kind: BufferKind) !*BufferMapping {
        return @ptrCast(try abi.video.create_buffer_mapping(@ptrCast(out), kind));
    }
};

pub const BufferMapping = opaque {
    pub fn release(mapping: *BufferMapping) void {
        abi.resources.release(.from_ptr(mapping));
    }

    pub fn get_video_memory(mapping: *BufferMapping) !abi.video.VideoMemory {
        return try ashet.abi.video.get_video_memory(@ptrCast(mapping));
    }

    pub fn present(mapping: *BufferMapping, mode: PresentMode) !void {
        _ = try ashet.overlapped.performOne(ashet.abi.video.Present, .{
            .buffer = @ptrCast(mapping),
            .mode = mode,
        });
    }
};

pub fn acquire(id: VideoOutputID) !*Output {
    return @ptrCast(
        try abi.video.acquire(id),
    );
}
