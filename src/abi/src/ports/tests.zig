const std = @import("std");
const abi = @import("abi");

const Color = abi.Color;

fn expect_eql_color(expected: Color, actual: Color) error{TestExpectedEqual}!void {
    const eql = (expected.hue == actual.hue) and (expected.value == actual.value) and (expected.saturation == actual.saturation);
    if (eql)
        return;

    std.debug.print("Expected {f} (H={}, S={}, V={}), found {f} (H={}, S={}, V={})\n", .{
        expected, expected.hue, expected.saturation, expected.value,
        actual,   actual.hue,   actual.saturation,   actual.value,
    });

    return error.TestExpectedEqual;
}

test "color rgb to hsv conversion" {
    // test grayscales (special case):
    try expect_eql_color(.{ .hue = 0, .value = 0, .saturation = 0 }, .from_rgb(0, 0, 0));
    try expect_eql_color(.{ .hue = 0, .value = 2, .saturation = 0 }, .from_rgb(64, 64, 64));
    try expect_eql_color(.{ .hue = 0, .value = 4, .saturation = 0 }, .from_rgb(128, 128, 128));
    try expect_eql_color(.{ .hue = 0, .value = 6, .saturation = 0 }, .from_rgb(192, 192, 192));
    try expect_eql_color(.{ .hue = 7, .value = 7, .saturation = 0 }, .from_rgb(255, 255, 255));

    // test value conversion:
    try expect_eql_color(.{ .hue = 0, .value = 0, .saturation = 0 }, .from_rgb(0x05, 0, 0)); //   0.0%
    try expect_eql_color(.{ .hue = 0, .value = 0, .saturation = 3 }, .from_rgb(0x1F, 0, 0)); //  12.5%
    try expect_eql_color(.{ .hue = 0, .value = 1, .saturation = 3 }, .from_rgb(0x3F, 0, 0)); //  25.0%
    try expect_eql_color(.{ .hue = 0, .value = 2, .saturation = 3 }, .from_rgb(0x5F, 0, 0)); //  37.5%
    try expect_eql_color(.{ .hue = 0, .value = 3, .saturation = 3 }, .from_rgb(0x7F, 0, 0)); //  50.0%
    try expect_eql_color(.{ .hue = 0, .value = 4, .saturation = 3 }, .from_rgb(0x9F, 0, 0)); //  62.5%
    try expect_eql_color(.{ .hue = 0, .value = 5, .saturation = 3 }, .from_rgb(0xBF, 0, 0)); //  75.0%
    try expect_eql_color(.{ .hue = 0, .value = 6, .saturation = 3 }, .from_rgb(0xDF, 0, 0)); //  87.5%
    try expect_eql_color(.{ .hue = 0, .value = 7, .saturation = 3 }, .from_rgb(0xFF, 0, 0)); // 100.0%

    // test hue conversion:
    try expect_eql_color(.{ .hue = 0, .value = 7, .saturation = 3 }, .from_rgb(255, 0, 0));
    try expect_eql_color(.{ .hue = 1, .value = 7, .saturation = 3 }, .from_rgb(255, 191, 0));
    try expect_eql_color(.{ .hue = 2, .value = 7, .saturation = 3 }, .from_rgb(127, 255, 0));
    try expect_eql_color(.{ .hue = 3, .value = 7, .saturation = 3 }, .from_rgb(0, 255, 63));
    try expect_eql_color(.{ .hue = 4, .value = 7, .saturation = 3 }, .from_rgb(0, 255, 255));
    try expect_eql_color(.{ .hue = 5, .value = 7, .saturation = 3 }, .from_rgb(0, 63, 255));
    try expect_eql_color(.{ .hue = 6, .value = 7, .saturation = 3 }, .from_rgb(127, 0, 255));
    try expect_eql_color(.{ .hue = 7, .value = 7, .saturation = 3 }, .from_rgb(255, 0, 191));

    // test some random color values (using the "palette" indices from GIMP):
    try expect_eql_color(@bitCast(@as(u8, 20)), .from_rgb(0x51, 0x51, 0x51));
    try expect_eql_color(@bitCast(@as(u8, 42)), .from_rgb(0xAA, 0xAA, 0xAA));
    try expect_eql_color(@bitCast(@as(u8, 99)), .from_rgb(0x6A, 0x9F, 0x77));
    try expect_eql_color(@bitCast(@as(u8, 119)), .from_rgb(0xDF, 0x94, 0xCC));
    try expect_eql_color(@bitCast(@as(u8, 164)), .from_rgb(0x35, 0x9F, 0x9F));
    try expect_eql_color(@bitCast(@as(u8, 233)), .from_rgb(0xBF, 0x8F, 0x00));
    try expect_eql_color(@bitCast(@as(u8, 255)), .from_rgb(0xFF, 0x00, 0xBF));
}

fn expect_eql_rgb(expected: Color.RGB888, actual: Color) error{TestExpectedEqual}!void {
    const actual_rgb = actual.to_rgb888();

    const eql = (expected.r == actual_rgb.r) and (expected.g == actual_rgb.g) and (expected.b == actual_rgb.b);
    if (eql)
        return;

    std.debug.print("Expected {f}, found {f} (H={}, S={}, V={})\n", .{
        expected,
        actual_rgb,
        actual.hue,
        actual.saturation,
        actual.value,
    });

    return error.TestExpectedEqual;
}

test "color hsv to rgb conversion" {
    const rgb = Color.RGB888.init;

    // test grayscales (special case):
    try expect_eql_rgb(rgb(0, 0, 0), .{ .hue = 0, .value = 0, .saturation = 0 });
    try expect_eql_rgb(rgb(65, 65, 65), .{ .hue = 0, .value = 2, .saturation = 0 });
    try expect_eql_rgb(rgb(130, 130, 130), .{ .hue = 0, .value = 4, .saturation = 0 });
    try expect_eql_rgb(rgb(195, 195, 195), .{ .hue = 0, .value = 6, .saturation = 0 });
    try expect_eql_rgb(rgb(255, 255, 255), .{ .hue = 7, .value = 7, .saturation = 0 });

    // test value conversion:
    try expect_eql_rgb(rgb(0x00, 0, 0), .{ .hue = 0, .value = 0, .saturation = 0 }); //   0.0%
    try expect_eql_rgb(rgb(0x1F, 0, 0), .{ .hue = 0, .value = 0, .saturation = 3 }); //  12.5%
    try expect_eql_rgb(rgb(0x3F, 0, 0), .{ .hue = 0, .value = 1, .saturation = 3 }); //  25.0%
    try expect_eql_rgb(rgb(0x5F, 0, 0), .{ .hue = 0, .value = 2, .saturation = 3 }); //  37.5%
    try expect_eql_rgb(rgb(0x7F, 0, 0), .{ .hue = 0, .value = 3, .saturation = 3 }); //  50.0%
    try expect_eql_rgb(rgb(0x9F, 0, 0), .{ .hue = 0, .value = 4, .saturation = 3 }); //  62.5%
    try expect_eql_rgb(rgb(0xBF, 0, 0), .{ .hue = 0, .value = 5, .saturation = 3 }); //  75.0%
    try expect_eql_rgb(rgb(0xDF, 0, 0), .{ .hue = 0, .value = 6, .saturation = 3 }); //  87.5%
    try expect_eql_rgb(rgb(0xFF, 0, 0), .{ .hue = 0, .value = 7, .saturation = 3 }); // 100.0%

    // test hue conversion:
    try expect_eql_rgb(rgb(255, 0, 0), .{ .hue = 0, .value = 7, .saturation = 3 });
    try expect_eql_rgb(rgb(255, 191, 0), .{ .hue = 1, .value = 7, .saturation = 3 });
    try expect_eql_rgb(rgb(127, 255, 0), .{ .hue = 2, .value = 7, .saturation = 3 });
    try expect_eql_rgb(rgb(0, 255, 63), .{ .hue = 3, .value = 7, .saturation = 3 });
    try expect_eql_rgb(rgb(0, 255, 255), .{ .hue = 4, .value = 7, .saturation = 3 });
    try expect_eql_rgb(rgb(0, 63, 255), .{ .hue = 5, .value = 7, .saturation = 3 });
    try expect_eql_rgb(rgb(127, 0, 255), .{ .hue = 6, .value = 7, .saturation = 3 });
    try expect_eql_rgb(rgb(255, 0, 191), .{ .hue = 7, .value = 7, .saturation = 3 });

    // test some random color values (using the "palette" indices from GIMP):
    try expect_eql_rgb(rgb(0x51, 0x51, 0x51), @bitCast(@as(u8, 20)));
    try expect_eql_rgb(rgb(0xAA, 0xAA, 0xAA), @bitCast(@as(u8, 42)));
    try expect_eql_rgb(rgb(0x6A, 0x9F, 0x77), @bitCast(@as(u8, 99)));
    try expect_eql_rgb(rgb(0xDF, 0x94, 0xCC), @bitCast(@as(u8, 119)));
    try expect_eql_rgb(rgb(0x35, 0x9F, 0x9F), @bitCast(@as(u8, 164)));
    try expect_eql_rgb(rgb(0xBF, 0x8F, 0x00), @bitCast(@as(u8, 233)));
    try expect_eql_rgb(rgb(0xFF, 0x00, 0xBF), @bitCast(@as(u8, 255)));
}

test "color from_rgb, to_rgb bijection" {
    for (0..256) |index| {
        const before: Color = @bitCast(@as(u8, @intCast(index)));

        const rgb = before.to_rgb888();

        // std.debug.print("index: {}, color: {}, rgb: {}\n", .{ index, before, rgb });

        const after = Color.from_rgb(rgb.r, rgb.g, rgb.b);

        expect_eql_color(before, after) catch |err| {
            std.debug.print("index={}, rgb={f}, before={f}, after={f}\n", .{
                index,
                rgb,
                before,
                after,
            });
            return err;
        };
    }
}

test "fuzz Color.from_rgb" {
    const Test = struct {
        fn fuzz(_: void, input: []const u8) !void {
            if (input.len != 3)
                return;

            _ = Color.from_rgb(input[0], input[1], input[2]);
        }
    };

    try std.testing.fuzz({}, Test.fuzz, .{});
}
