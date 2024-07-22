const std = @import("std");
const abi = @import("abi");
const consumer = @import("consumer");
const provider = @import("provider");

test {
    _ = abi;
    _ = consumer;
    _ = provider;
}

test {
    no_operation_called = false;
    consumer.syscalls.no_operation();
    try std.testing.expectEqual(true, no_operation_called);
}

comptime {
    _ = provider.create_exports(root);
}

var no_operation_called = false;

const root = struct {
    pub const syscalls = struct {
        pub fn no_operation() void {
            no_operation_called = true;
        }
    };
};
