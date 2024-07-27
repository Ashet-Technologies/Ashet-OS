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

test "syscalls.return_error_union" {
    try std.testing.expectError(error.Domain, consumer.syscalls.return_error_union(-5));
    try std.testing.expectError(error.TooLarge, consumer.syscalls.return_error_union(1e8));
    try std.testing.expectApproxEqAbs(0.0, try consumer.syscalls.return_error_union(0), 0.01);
    try std.testing.expectApproxEqAbs(1.41, try consumer.syscalls.return_error_union(2), 0.01);
}

test "syscalls.slice_asserts.basic" {
    consumer.syscalls.slice_asserts.basic(global_slice);
}

test "optional" {
    expect_null = false;
    consumer.syscalls.slice_asserts.optional(global_slice);

    expect_null = true;
    consumer.syscalls.slice_asserts.optional(null);
}

test "out_basic" {
    var slice: []const u8 = undefined;
    consumer.syscalls.slice_asserts.out_basic(&slice);
    try std.testing.expectEqual(global_slice, slice);
}

test "out_optional" {
    var slice: ?[]const u8 = undefined;

    provide_null = false;
    slice = undefined;
    consumer.syscalls.slice_asserts.out_optional(&slice);
    try std.testing.expectEqual(@as(?[]const u8, global_slice), slice);

    provide_null = true;
    slice = undefined;
    consumer.syscalls.slice_asserts.out_optional(&slice);
    try std.testing.expectEqual(@as(?[]const u8, null), slice);
}

test "inout_basic" {
    var slice: []const u8 = global_slice;
    consumer.syscalls.slice_asserts.inout_basic(&slice);
    try std.testing.expectEqual(global_slice[4..9], slice);
}

test "inout_optional" {
    var slice: ?[]const u8 = &.{};

    expect_null = false;
    provide_null = false;
    slice = global_slice;
    consumer.syscalls.slice_asserts.inout_optional(&slice);
    try std.testing.expectEqual(@as(?[]const u8, global_slice[4..9]), slice);

    expect_null = true;
    provide_null = false;
    slice = null;
    consumer.syscalls.slice_asserts.inout_optional(&slice);
    try std.testing.expectEqual(@as(?[]const u8, global_slice[4..9]), slice);

    expect_null = false;
    provide_null = true;
    slice = global_slice;
    consumer.syscalls.slice_asserts.inout_optional(&slice);
    try std.testing.expectEqual(@as(?[]const u8, null), slice);

    expect_null = true;
    provide_null = true;
    slice = null;
    consumer.syscalls.slice_asserts.inout_optional(&slice);
    try std.testing.expectEqual(@as(?[]const u8, null), slice);
}

var expect_null = false;
var provide_null = false;
var no_operation_called = false;

var global_slice_memory: [17]u8 align(4) = undefined;

const global_slice = global_slice_memory[3..14];

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

        pub fn return_error_union(square: f32) error{ Domain, TooLarge }!f32 {
            if (square > 256.0)
                return error.TooLarge;
            if (square < 0)
                return error.Domain;
            return @sqrt(square);
        }

        pub const slice_asserts = struct {
            pub fn basic(slice: []const u8) void {
                std.debug.assert(global_slice.ptr == slice.ptr);
                std.debug.assert(global_slice.len == slice.len);
            }

            pub fn optional(slice: ?[]const u8) void {
                if (expect_null) {
                    std.debug.assert(slice == null);
                } else {
                    std.debug.assert(global_slice.ptr == slice.?.ptr);
                    std.debug.assert(global_slice.len == slice.?.len);
                }
            }

            pub fn out_basic(slice: *[]const u8) void {
                slice.* = global_slice;
            }

            pub fn out_optional(slice: *?[]const u8) void {
                if (provide_null) {
                    slice.* = null;
                } else {
                    slice.* = global_slice;
                }
            }

            pub fn inout_basic(slice: *[]const u8) void {
                std.debug.assert(global_slice.ptr == slice.ptr);
                std.debug.assert(global_slice.len == slice.len);

                slice.* = global_slice[4..9];
            }

            pub fn inout_optional(slice: *?[]const u8) void {
                if (expect_null) {
                    std.debug.assert(slice.* == null);
                } else {
                    std.debug.assert(global_slice.ptr == slice.*.?.ptr);
                    std.debug.assert(global_slice.len == slice.*.?.len);
                }

                if (provide_null) {
                    slice.* = null;
                } else {
                    slice.* = global_slice[4..9];
                }
            }
        };
    };
};
