const std = @import("std");
const ashet = @import("ashet");
const hdoc = @import("hyperdoc");

const agp = ashet.graphics.agp;

pub const Color = ashet.abi.Color;
pub const Point = ashet.abi.Point;
pub const Size = ashet.abi.Size;
pub const Rectangle = ashet.abi.Rectangle;

pub const Font = agp.Font;

pub const LineScanner = @import("LineScanner.zig");
pub const WordScanner = @import("WordScanner.zig");

pub const Context = struct {
    user_data: ?*anyopaque,

    measure_text_size_fn: *const fn (user_data: ?*anyopaque, agp.Font, []const u8) Size,

    fn measure_text_size(ctx: *const Context, font: agp.Font, text: []const u8) Size {
        return ctx.measure_text_size_fn(ctx.user_data, font, text);
    }
};

pub const Style = struct {
    color: ?Color = null,
};

pub const TextRenderer = struct {
    context: *const Context,
    encoder: *agp.Encoder,
    target: Rectangle,

    line_start: i16,
    text_width: u15,

    space_width: u15,
    line_height: u15,

    default_style: Style,
    font: agp.Font,

    pub fn init(
        context: *const Context,
        encoder: *agp.Encoder,
        target: Rectangle,
        font: agp.Font,
        default_style: Style,
    ) !TextRenderer {
        const space_size = context.measure_text_size(font, " ");
        std.debug.assert(space_size.width > 0); // We require a font which has a non-zero space size
        std.debug.assert(space_size.height > 0); // The measure text should return line height

        return .{
            .context = context,
            .encoder = encoder,
            .target = target,

            .font = font,

            .line_start = target.y,
            .text_width = 0,

            .space_width = std.math.cast(u15, space_size.width) orelse return error.Overflow,
            .line_height = std.math.cast(u15, space_size.height) orelse return error.Overflow,

            .default_style = .{
                .color = default_style.color orelse .black,
            },
        };
    }

    pub fn emit_word(tr: *TextRenderer, word: []const u8, style: Style) !void {
        const word_size = tr.context.measure_text_size(tr.font, word);
        std.debug.assert(word_size.height == tr.line_height);

        if (tr.text_width > 0 and tr.text_width +| word_size.width >= tr.target.width) {
            tr.new_line();
        }

        // No need to encode if we're out of bounds anyways:
        if (tr.is_out_of_bounds())
            return;

        try tr.encoder.draw_text(
            tr.target.x + tr.text_width,
            tr.line_start,
            tr.font,
            style.color orelse tr.default_style.color.?,
            word,
        );

        // advance the text cursor by both word width and a single space.
        tr.text_width +|= @intCast(word_size.width);
        tr.text_width +|= tr.space_width;
    }

    /// Moves the text renderer to the start of a new line.
    pub fn new_line(tr: *TextRenderer) void {
        tr.line_start +|= tr.line_height;
        tr.text_width = 0;
    }

    /// Returns true when the text renderer is
    pub fn is_out_of_bounds(tr: *const TextRenderer) bool {
        return tr.line_start >= tr.target.bottom();
    }
};

pub fn render_text(context: *const Context, font: agp.Font, encoder: *agp.Encoder, full_text: []const u8, target: Rectangle) !void {
    var renderer: TextRenderer = try .init(
        context,
        encoder,
        target,
        font,
        .{},
    );

    var lines: LineScanner = .init(full_text);
    while (lines.next()) |srcline| {
        var words: WordScanner = .init(srcline);
        while (words.next()) |word| {
            try renderer.emit_word(word, .{});
        }
        renderer.new_line();
        if (renderer.is_out_of_bounds())
            break;
    }
}

test {
    _ = LineScanner;
    _ = WordScanner;
}
