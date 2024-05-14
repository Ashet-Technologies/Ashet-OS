const std = @import("std");
const abi = @import("abi");

fn syscall_stub() callconv(.C) void {}

comptime {
    for (@typeInfo(abi.syscalls).Struct.decls) |decl| {
        @export(syscall_stub, std.builtin.ExportOptions{
            .name = decl.name,
        });
    }
}
