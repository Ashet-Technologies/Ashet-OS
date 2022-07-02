const std = @import("std");

pub const abi = @import("ashet-abi");

pub const syscalls = abi.SysCallInterface.get;

export fn _start() linksection(".entry_point") callconv(.C) u32 {
    const res = @import("root").main();
    const Res = @TypeOf(res);

    if (@typeInfo(Res) == .ErrorUnion) {
        if (res) |unwrapped_res| {
            const UnwrappedRes = @TypeOf(unwrapped_res);

            if (UnwrappedRes == u32) {
                return unwrapped_res;
            } else if (UnwrappedRes == void) {
                return abi.ExitCode.success;
            } else {
                @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
            }
        } else |err| {
            std.log.err("main() returned the following error code: {s}", .{@errorName(err)});
            return abi.ExitCode.failure;
        }
    } else if (Res == u32) {
        return res;
    } else if (Res == void) {
        return abi.ExitCode.success;
    } else {
        @compileError("Return type of main must either be void, u32 or an error union that unwraps to void or u32!");
    }

    unreachable;
}
