const std = @import("std");
const ashet = @import("ashet");
const hdoc = @import("hyperdoc");

const agp = ashet.graphics.agp;

pub const Point = ashet.abi.Point;
pub const Size = ashet.abi.Size;
pub const Rectangle = ashet.abi.Rectangle;

pub const Font = agp.Font;

pub const LineScanner = @import("LineScanner.zig");
pub const WordScanner = @import("WordScanner.zig");

pub const Context = struct {
    user_data: ?*anyopaque,

    default_font: agp.Font,

    measure_text_size_fn: *const fn (user_data: ?*anyopaque, agp.Font, []const u8) Size,

    fn measure_text_size(ctx: *const Context, font: agp.Font, text: []const u8) Size {
        return ctx.measure_text_size_fn(ctx.user_data, font, text);
    }
};

pub fn render_text(context: *const Context, encoder: *agp.Encoder, full_text: []const u8, position: Point, max_width: u16) !void {
    const font = context.default_font;

    const space_size = context.measure_text_size(font, " ");
    std.debug.assert(space_size.width > 0); // We require a font which has a non-zero space size
    std.debug.assert(space_size.height > 0); // The measure text should return line height

    const line_height: u15 = @intCast(space_size.height);

    var line_start: i16 = position.y;

    var lines: LineScanner = .init(full_text);
    line_loop: while (lines.next()) |srcline| {
        std.log.info("src line: \"{f}\"", .{std.zig.fmtString(srcline)});

        var text_width: u15 = 0;

        var words: WordScanner = .init(srcline);
        while (words.next()) |word| {
            const word_size = context.measure_text_size(font, word);
            std.debug.assert(word_size.height == line_height);

            if (text_width > 0 and text_width +| word_size.width >= max_width) {
                text_width = 0;
                line_start = std.math.add(i16, line_start, line_height) catch break :line_loop;
            }

            try encoder.draw_text(position.x + text_width, line_start, context.default_font, .black, word);

            text_width +|= @intCast(word_size.width);
            text_width +|= @intCast(space_size.width);
        }

        line_start, const overflow = @addWithOverflow(line_start, line_height);
        if (overflow != 0)
            break;
    }
}

test {
    _ = LineScanner;
    _ = WordScanner;
}
