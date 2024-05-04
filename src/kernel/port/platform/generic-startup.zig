const std = @import("std");
const kernel = @import("kernel");

comptime {
    _ = kernel;
}

pub const std_options = kernel.std_options;
