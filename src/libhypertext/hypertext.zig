const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const hdoc = @import("hyperdoc");

pub const Color = ashet.abi.ColorIndex;
pub const Point = ashet.abi.Point;
pub const Size = ashet.abi.Size;
pub const Rectangle = ashet.abi.Rectangle;

pub const Theme = struct {
    text_color: Color,
    monospace_color: Color,
    emphasis_color: Color,
    link_color: Color,
    h1_color: Color,
    h2_color: Color,
    h3_color: Color,

    quote_mark_color: Color,

    padding: u15,
    line_spacing: u15,
    block_spacing: u15,
};

pub fn renderDocument(
    framebuffer: gui.Framebuffer,
    document: hdoc.Document,
    theme: Theme,
    scroll_offset: u15,
) void {
    var renderer = Renderer{
        .framebuffer = framebuffer.view((Rectangle{
            .x = 0,
            .y = 0,
            .width = framebuffer.width,
            .height = framebuffer.height,
        }).shrink(theme.padding)),
        .document = document,
        .theme = theme,
        .block_top = -@as(i16, scroll_offset),
    };
    renderer.run();
}

const Renderer = struct {
    framebuffer: gui.Framebuffer,
    document: hdoc.Document,
    theme: Theme,
    block_top: i16,

    const font_height = 8;

    fn run(ren: *Renderer) void {
        ren.renderBlocks(ren.document.contents, 0);
    }

    fn renderBlocks(ren: *Renderer, blocks: []const hdoc.Block, indent: u15) void {
        for (blocks, 0..) |block, i| {
            if (i > 0) {
                ren.block_top += ren.theme.block_spacing;
            }
            const height = ren.renderBlock(block, indent);
            ren.block_top += height;
        }
    }

    fn renderBlock(ren: *Renderer, block: hdoc.Block, indent: u15) u15 {
        const fb = ren.framebuffer.view(.{
            .x = indent,
            .y = ren.block_top,
            .width = ren.framebuffer.width -| indent,
            .height = @intCast(u15, std.math.max(0, ren.framebuffer.height -| ren.block_top)),
        });

        switch (block) {
            .table_of_contents => {
                // TODO: Implement TOC

                fb.drawString(0, 0, "Table of Contents", ren.theme.text_color, fb.width);

                return font_height;
            },

            .heading => |h| {
                const color = switch (h.level) {
                    .document => ren.theme.h1_color,
                    .chapter => ren.theme.h2_color,
                    .section => ren.theme.h3_color,
                };

                fb.drawString(0, 0, h.title, color, fb.width);

                switch (h.level) {
                    .document => {
                        fb.drawLine(
                            Point.new(0, font_height),
                            Point.new(fb.width - 1, font_height),
                            ren.theme.h1_color,
                        );
                        return font_height + 2;
                    },
                    .chapter => {
                        var i: u15 = 0;
                        while (i < fb.width) : (i += 2) {
                            fb.setPixel(i, font_height, ren.theme.h2_color);
                        }
                        return font_height + 1;
                    },
                    .section => return font_height,
                }
            },

            .paragraph => |p| return ren.renderSpans(fb, p.contents),

            .quote => |q| {
                const height = ren.renderSpans(fb.view(.{
                    .x = 3,
                    .y = 2,
                    .width = fb.width -| 3,
                    .height = fb.height -| 2,
                }), q.contents);

                fb.drawLine(
                    Point.new(0, 0),
                    Point.new(0, height + 3),
                    ren.theme.quote_mark_color,
                );

                return height + 4;
            },

            .preformatted => |pre| {
                return ren.renderSpans(fb, pre.contents);
            },

            .ordered_list => |ol| {
                _ = ol;
                return font_height;
            },

            .unordered_list => |ul| {
                const backup = ren.block_top;
                defer ren.block_top = backup;

                var offset_y: u15 = 0;

                for (ul, 0..) |inner_block, i| {
                    if (i > 0) {
                        offset_y += ren.theme.block_spacing;
                    }

                    fb.fillRectangle(.{
                        .x = 1,
                        .y = offset_y + 2,
                        .width = 3,
                        .height = 3,
                    }, ren.theme.text_color);

                    ren.block_top = backup + offset_y;
                    const height = ren.renderBlock(inner_block, indent + 6);

                    offset_y += height;
                }

                return offset_y;
            },

            .image => |img| {
                _ = img;
                return font_height;
            },
        }
    }

    fn measureString(ren: *Renderer, str: []const u8) u15 {
        _ = ren;
        return @intCast(u15, str.len * 6);
    }

    fn renderSpans(ren: *Renderer, fb: gui.Framebuffer, spans: []const hdoc.Span) u15 {
        var offset_y: u15 = 0;
        var offset_x: u15 = 0;
        for (spans) |span| {
            const string = switch (span) {
                .text => |str| str,
                .emphasis => |str| str,
                .monospace => |str| str,
                .link => |link| link.text,
            };
            const color = switch (span) {
                .text => ren.theme.text_color,
                .emphasis => ren.theme.emphasis_color,
                .monospace => ren.theme.text_color,
                .link => ren.theme.link_color,
            };

            var first_line = true;
            var lines = std.mem.split(u8, string, "\n");
            while (lines.next()) |line| {
                if (!first_line) {
                    // line break condition
                    offset_y += font_height + ren.theme.line_spacing;
                    offset_x = 0;
                }
                first_line = false;

                var words = std.mem.tokenize(u8, line, " \t\r");
                while (words.next()) |word| {
                    const width = ren.measureString(word);

                    if (offset_x > 0 and offset_x + width > fb.width) {
                        // line break condition
                        offset_y += font_height + ren.theme.line_spacing;
                        offset_x = 0;
                    }

                    fb.drawString(offset_x, offset_y, word, color, fb.width -| offset_x);

                    offset_x += width;
                    offset_x += 4; // space width
                }
            }
        }
        return offset_y + font_height;
    }
};
