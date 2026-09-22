const std = @import("std");
const ashet = @import("ashet");
const agp = @import("agp");

const Size = ashet.Size;

pub fn main() !void {

    //

}

const GpuOptions = struct {
    /// Number of bytes of video memory
    vmem: usize,

    outputs: std.ArrayListUnmanaged(Output),

    const Output = struct {
        size: Size,
    };
};
