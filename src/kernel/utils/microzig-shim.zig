const std = @import("std");
const kernel = @import("kernel");

pub const mmio = struct {
    pub fn Mmio(comptime Reg: type) type {
        return kernel.utils.mmio.MmioRegister(Reg, .{});
    }
};

pub const interrupt = struct {
    pub const Handler = kernel.platform.profile.FunctionPointer;

    fn unhandled() callconv(.C) void {
        @panic("unhandled unknown interrupt");
    }
};
