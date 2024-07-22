const std = @import("std");
const abi = @import("abi");
const consumer = @import("consumer");
const provider = @import("provider");

test {
    _ = abi;
    _ = consumer;
    _ = provider;
}

test "syscalls.no_operation" {
    no_operation_called = false;
    consumer.syscalls.no_operation();
    try std.testing.expectEqual(true, no_operation_called);
}

test "syscalls.arg_with_name" {
    try std.testing.expectEqual(0xEEDDCCBB, consumer.syscalls.arg_with_name(0x11223344));
}

test "syscalls.arg_without_name" {
    try std.testing.expectEqual(0xEEDDCCBB, consumer.syscalls.arg_without_name(0x11223344));
}

test "syscalls.regular_slice" {
    try std.testing.expectEqual(
        std.hash.Adler32.hash("hello, world!"),
        consumer.syscalls.regular_slice("hello, world!"),
    );
}

test "syscalls.optional_slice" {
    try std.testing.expectEqual(
        std.hash.Adler32.hash("hello, world!"),
        consumer.syscalls.optional_slice("hello, world!"),
    );
    try std.testing.expectEqual(
        0xDEADBEEF,
        consumer.syscalls.optional_slice(null),
    );
}

test "syscalls.out_slice" {
    var slice: []const u8 = undefined;
    consumer.syscalls.out_slice(0, &slice);
    try std.testing.expectEqualStrings("keins", slice);

    slice = undefined;
    consumer.syscalls.out_slice(1, &slice);
    try std.testing.expectEqualStrings("eins", slice);

    slice = undefined;
    consumer.syscalls.out_slice(2, &slice);
    try std.testing.expectEqualStrings("zwei", slice);

    slice = undefined;
    consumer.syscalls.out_slice(3, &slice);
    try std.testing.expectEqualStrings("viele", slice);
}

test "syscalls.out_optional_slice" {
    var slice: ?[]const u8 = undefined;
    consumer.syscalls.out_optional_slice(0, &slice);
    try std.testing.expectEqual(null, slice);

    slice = undefined;
    consumer.syscalls.out_optional_slice(1, &slice);
    try std.testing.expectEqualStrings("eins", slice orelse return error.WasNull);

    slice = undefined;
    consumer.syscalls.out_optional_slice(2, &slice);
    try std.testing.expectEqualStrings("zwei", slice orelse return error.WasNull);

    slice = undefined;
    consumer.syscalls.out_optional_slice(3, &slice);
    try std.testing.expectEqualStrings("viele", slice orelse return error.WasNull);
}

test "syscalls.return_plain_error" {
    try consumer.syscalls.return_plain_error(0);
    try std.testing.expectError(error.One, consumer.syscalls.return_plain_error(1));
    try std.testing.expectError(error.Two, consumer.syscalls.return_plain_error(2));
}

var no_operation_called = false;

comptime {
    _ = provider.create_exports(root);
}
const root = struct {
    pub const syscalls = struct {
        pub fn no_operation() void {
            no_operation_called = true;
        }

        pub fn arg_with_name(v: u32) u32 {
            return ~v;
        }

        pub fn arg_without_name(v: u32) u32 {
            return ~v;
        }

        pub fn regular_slice(slice: []const u8) u32 {
            return std.hash.Adler32.hash(slice);
        }

        pub fn optional_slice(maybe_slice: ?[]const u8) u32 {
            return if (maybe_slice) |slice|
                std.hash.Adler32.hash(slice)
            else
                0xDEADBEEF;
        }

        pub fn out_slice(index: u32, out: *[]const u8) void {
            out.* = switch (index) {
                0 => "keins",
                1 => "eins",
                2 => "zwei",
                else => "viele",
            };
        }

        pub fn out_optional_slice(index: u32, out: *?[]const u8) void {
            out.* = switch (index) {
                0 => null,
                1 => "eins",
                2 => "zwei",
                else => "viele",
            };
        }

        pub fn return_plain_error(index: u32) error{ One, Two }!void {
            return switch (index) {
                1 => error.One,
                2 => error.Two,
                else => {},
            };
        }
    };
};
