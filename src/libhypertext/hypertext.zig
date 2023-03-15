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
    context: anytype,
    comptime linkCallback: fn (@TypeOf(context), ashet.abi.Rectangle, hdoc.Link) void,
) void {
    const T = struct {
        const Ctx = @TypeOf(context);
        const alignment = if (@alignOf(Ctx) == 0) 1 else @alignOf(Ctx);

        fn erasedLinkCallback(ctx: *const anyopaque, rect: ashet.abi.Rectangle, link: hdoc.Link) void {
            linkCallback(
                @ptrCast(*const Ctx, @alignCast(alignment, ctx)).*,
                rect,
                link,
            );
        }
    };

    var renderer = Renderer{
        .context = @ptrCast(*const anyopaque, &context),
        .linkCallback = T.erasedLinkCallback,
        .framebuffer = framebuffer,
        .document = document,
        .theme = theme,
        .block_top = -@as(i16, scroll_offset),
    };
    renderer.run();
}

const Renderer = struct {
    context: *const anyopaque,
    linkCallback: *const fn (*const anyopaque, ashet.abi.Rectangle, hdoc.Link) void,

    framebuffer: gui.Framebuffer,
    document: hdoc.Document,
    theme: Theme,
    block_top: i16,

    const font_height = 8;

    fn run(ren: *Renderer) void {
        const target_rect = Rectangle{
            .x = 0,
            .y = ren.block_top,
            .width = ren.framebuffer.width,
            .height = ren.framebuffer.height,
        };

        ren.renderBlocks(ren.framebuffer.view(target_rect.shrink(ren.theme.padding)), ren.document.contents);
    }

    fn renderBlocks(ren: *Renderer, fb: gui.Framebuffer, blocks: []const hdoc.Block) void {
        var mut_fb = fb;
        for (blocks, 0..) |block, i| {
            if (i > 0) {
                mut_fb = mut_fb.view(Rectangle{
                    .x = 0,
                    .y = ren.theme.block_spacing,
                    .width = fb.width,
                    .height = fb.height -| ren.theme.block_spacing,
                });
            }
            const height = ren.renderBlock(block, mut_fb);
            mut_fb = mut_fb.view(Rectangle{
                .x = 0,
                .y = height,
                .width = fb.width,
                .height = fb.height -| height,
            });
        }
    }

    fn indentFramebuffer(ren: *Renderer, fb: gui.Framebuffer, indent: u15, scroll: u15) gui.Framebuffer {
        return fb.view(.{
            .x = indent,
            .y = scroll,
            .width = ren.framebuffer.width -| indent,
            .height = ren.framebuffer.height -| scroll,
        });
    }

    fn renderBlock(ren: *Renderer, block: hdoc.Block, fb: gui.Framebuffer) u15 {
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
                            Point.new(fb.width -| 1, font_height),
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
                return ren.renderPreformattedSpans(fb, pre.contents);
            },

            .ordered_list => |ol| {
                const backup = ren.block_top;
                defer ren.block_top = backup;

                const digits = std.math.log10(if (ol.len == 0) 1 else ol.len) + 1;
                const padding = @intCast(u15, 6 * (digits + 2));

                var mut_fb = fb;
                var offset_y: u15 = 0;
                for (ol, 0..) |inner_block, i| {
                    if (i > 0) {
                        offset_y += ren.theme.block_spacing;
                    }

                    var numbuf: [16]u8 = undefined;

                    const numstr = std.fmt.bufPrint(&numbuf, "{[number]d: >[digits]}. ", .{
                        .number = i + 1,
                        .digits = digits,
                    }) catch unreachable;

                    mut_fb.drawString(0, offset_y, numstr, ren.theme.text_color, padding);

                    const height = ren.renderBlock(inner_block, ren.indentFramebuffer(mut_fb, padding, offset_y));

                    offset_y += height;
                }

                return offset_y;
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

                    const height = ren.renderBlock(inner_block, ren.indentFramebuffer(fb, 12, offset_y));

                    offset_y += height;
                }

                return offset_y;
            },

            .image => |img| {
                fb.drawString(0, 0, "<IMAGE PLACEHOLDER>", ren.theme.text_color, null);
                _ = img;
                return font_height;
            },
        }
    }

    fn measureString(ren: *Renderer, str: []const u8) u15 {
        _ = ren;
        return @intCast(u15, str.len * 6);
    }

    fn emitSpanRectangle(ren: *Renderer, fb: gui.Framebuffer, rect: Rectangle, span: hdoc.Span) void {
        if (span != .link) return;
        if (rect.width == 0) return;

        const global_offset = @ptrToInt(fb.pixels) -| @ptrToInt(ren.framebuffer.pixels);

        // reconstruct the original position
        const dx = @intCast(u15, global_offset % ren.framebuffer.stride);
        const dy = @intCast(u15, global_offset / ren.framebuffer.stride);

        ren.linkCallback(
            ren.context,
            .{
                .x = dx + rect.x,
                .y = dy + rect.y,
                .width = rect.width,
                .height = rect.height,
            },
            span.link,
        );
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
                .monospace => ren.theme.monospace_color,
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

                var span_rectangle = Rectangle{
                    .x = offset_x,
                    .y = offset_y,
                    .width = 0,
                    .height = font_height,
                };

                var fist_word = true;
                var words = std.mem.tokenize(u8, line, " \t\r");
                while (words.next()) |word| {
                    const width = ren.measureString(word);

                    if (offset_x > 0 and offset_x + width + 4 > fb.width) {
                        // line break condition
                        offset_y += font_height + ren.theme.line_spacing;
                        offset_x = 0;

                        ren.emitSpanRectangle(fb, span_rectangle, span);
                        span_rectangle = Rectangle{
                            .x = offset_x,
                            .y = offset_y,
                            .width = 0,
                            .height = font_height,
                        };
                    } else if (!fist_word) {
                        offset_x += 4; // space width
                        span_rectangle.width += 4;
                    }
                    fist_word = false;

                    fb.drawString(offset_x, offset_y, word, color, fb.width -| offset_x);

                    offset_x += width;
                    span_rectangle.width += width;
                }

                ren.emitSpanRectangle(fb, span_rectangle, span);
            }
        }
        return offset_y + font_height;
    }

    fn renderPreformattedSpans(ren: *Renderer, fb: gui.Framebuffer, spans: []const hdoc.Span) u15 {

        // TODO: Fix preformatted rendering with multiple spans on the same line

        var offset_y: u15 = 0;
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
                .monospace => ren.theme.monospace_color,
                .link => ren.theme.link_color,
            };

            var first_line = true;
            var lines = std.mem.split(u8, string, "\n");
            while (lines.next()) |line| {
                if (!first_line) {
                    // line break condition
                    offset_y += font_height + ren.theme.line_spacing;
                }
                first_line = false;

                fb.drawString(0, offset_y, line, color, fb.width);
            }
        }
        return offset_y + font_height;
    }
};
