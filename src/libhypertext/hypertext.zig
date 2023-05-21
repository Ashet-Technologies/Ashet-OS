const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const hdoc = @import("hyperdoc");

pub const Color = ashet.abi.ColorIndex;
pub const Point = ashet.abi.Point;
pub const Size = ashet.abi.Size;
pub const Rectangle = ashet.abi.Rectangle;

pub const Style = struct {
    color: Color,
};

pub const Theme = struct {
    text: Style,
    monospace: Style,
    emphasis: Style,
    link: Style,
    h1: Style,
    h2: Style,
    h3: Style,

    quote_mark_color: Color,

    padding: u15,
    line_spacing: u15,
    block_spacing: u15,
};

const Block = hdoc.Block;
const Span = hdoc.Span;

pub fn renderDocument(
    framebuffer: gui.Framebuffer,
    document: hdoc.Document,
    theme: Theme,
    position: Point,
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
        .position = position,
    };
    renderer.run();
}

const Renderer = struct {
    context: *const anyopaque,
    linkCallback: *const fn (*const anyopaque, ashet.abi.Rectangle, hdoc.Link) void,

    framebuffer: gui.Framebuffer,
    document: hdoc.Document,
    theme: Theme,
    position: Point,

    enable_block_spacing: bool = true,

    const font_height = 8;

    fn run(ren: *Renderer) void {
        ren.processBlocks(ren.document.contents);
    }

    fn processBlocks(ren: *Renderer, blocks: []const Block) void {
        for (blocks, 0..) |block, i| {
            if (i > 0 and ren.enable_block_spacing) {
                ren.position.y += ren.theme.block_spacing;
            }
            ren.processBlock(block);
        }
    }

    fn processBlock(ren: *Renderer, block: Block) void {

        // rendering a block doesn't change any indentation,
        // but we might mutate it internally. Make sure we restore
        // it properly again
        const indent = ren.position.x;
        defer ren.position.x = indent;

        switch (block) {
            .paragraph => |p| ren.setRunningText(p.contents, null),
            .preformatted => |pre| ren.setPreformattedText(pre.contents, pre.language),

            .ordered_list => |ol| {
                if (ol.len == 0) return;
                const prev_block_spacing = ren.enable_block_spacing;
                defer ren.enable_block_spacing = prev_block_spacing;
                ren.enable_block_spacing = false;

                var string_width = std.math.log10_int(ol.len) + 2;

                ren.position.x += 6 * string_width;

                for (ol, 1..) |list_item, index| {
                    var str_buffer: [16]u8 = undefined;

                    const number = std.fmt.bufPrint(&str_buffer, "{d}.", .{index}) catch unreachable;

                    ren.framebuffer.drawString(
                        ren.position.x - @intCast(i16, 6 * number.len),
                        ren.position.y,
                        number,
                        ren.theme.text.color,
                        null,
                    );

                    ren.processBlocks(list_item.contents);
                }
            },

            .unordered_list => |ul| {
                if (ul.len == 0) return;

                const prev_block_spacing = ren.enable_block_spacing;
                defer ren.enable_block_spacing = prev_block_spacing;
                ren.enable_block_spacing = false;

                ren.position.x += 6;

                for (ul) |list_item| {
                    ren.framebuffer.drawRectangle(.{
                        .x = ren.position.x - 4,
                        .y = ren.position.y + 3,
                        .width = 2,
                        .height = 2,
                    }, ren.theme.text.color);

                    ren.processBlocks(list_item.contents);
                }
            },

            .quote => |q| {
                ren.position.x += 6;

                const top = ren.position.y;
                ren.setRunningText(q.contents, null);
                const bottom = ren.position.y;

                ren.framebuffer.drawLine(
                    Point.new(ren.position.x - 3, top),
                    Point.new(ren.position.x - 3, bottom),
                    ren.theme.quote_mark_color,
                );
            },

            .image => |img| {
                _ = img;
                ren.setRunningText(&.{
                    Span{ .monospace = "<Image Placeholder>" },
                }, null);
            },

            .heading => |h| {
                const heading_style = switch (h.level) {
                    .document => ren.theme.h1,
                    .chapter => ren.theme.h2,
                    .section => ren.theme.h3,
                };

                ren.setRunningText(&.{
                    Span{ .text = h.title },
                }, heading_style);

                if (h.level == .document) {
                    ren.framebuffer.horizontalLine(
                        ren.position.x,
                        ren.position.y + 1,
                        ren.framebuffer.width -| @intCast(u16, @max(0, ren.position.x)),
                        heading_style.color,
                    );
                    ren.position.y += 3;
                }
            },

            .table_of_contents => {
                ren.processBlock(.{
                    .heading = .{
                        .level = .document,
                        .title = "Table of Contents",
                        .anchor = "",
                    },
                });

                var levels = std.mem.zeroes([3]u32);

                for (ren.document.contents) |top_level_block| {
                    if (top_level_block != .heading)
                        continue;
                    const heading = top_level_block.heading;
                    const level = @enumToInt(heading.level);

                    levels[level] += 1;
                    for (levels[level + 1 ..]) |*item| {
                        item.* = 0;
                    }

                    var prefix_buffer: [32]u8 = undefined;
                    var stream = std.io.fixedBufferStream(&prefix_buffer);
                    const writer = stream.writer();

                    writer.print("{}", .{levels[0]}) catch unreachable;

                    for (levels[1 .. level + 1]) |item| {
                        writer.print(".{}", .{item}) catch unreachable;
                    }

                    writer.writeAll(" ") catch unreachable;

                    var href_buf: [128]u8 = undefined;

                    const href = std.fmt.bufPrint(&href_buf, "#{s}", .{heading.anchor}) catch "";

                    ren.setRunningText(&.{
                        Span{ .text = stream.getWritten() },
                        if (href.len > 1)
                            Span{ .link = .{ .text = heading.title, .href = href } }
                        else
                            Span{ .text = heading.title },
                    }, null);
                }
            },
        }
    }

    fn setRunningText(ren: *Renderer, spans: []const Span, style_override: ?Style) void {
        var setter = TextSetter.init(ren);

        var leftover_whitespace = false;

        for (spans) |span| {
            const string = spanToString(span);
            if (string.len == 0)
                continue;

            const span_style = style_override orelse switch (span) {
                .text => ren.theme.text,
                .emphasis => ren.theme.emphasis,
                .monospace => ren.theme.monospace,
                .link => ren.theme.link,
            };

            const starts_with_whitespace = isWhiteSpace(string[0..1]);
            const ends_with_whitespace = isWhiteSpace(string[string.len - 1 ..]);

            var insert_whitespace = (starts_with_whitespace or leftover_whitespace);
            var words = std.mem.tokenize(u8, string, whitespace);
            while (words.next()) |word| {
                if (insert_whitespace) {
                    setter.writeText(
                        " ",
                        .{
                            .word_wrap = true,
                            .style = span_style,
                            .trim_spaces = true,
                            .link = spanToLink(span),
                        },
                    );
                }
                insert_whitespace = true;

                setter.writeText(
                    word,
                    .{
                        .word_wrap = true,
                        .style = span_style,
                        .trim_spaces = true,
                        .link = spanToLink(span),
                    },
                );
            }

            leftover_whitespace = ends_with_whitespace;
        }

        setter.endCurrentLine();
    }

    fn setPreformattedText(ren: *Renderer, spans: []const Span, lang: ?[]const u8) void {
        var setter = TextSetter.init(ren);

        _ = lang;

        for (spans) |span| {
            const span_style = switch (span) {
                .text => ren.theme.text,
                .emphasis => ren.theme.emphasis,
                .monospace => ren.theme.monospace,
                .link => ren.theme.link,
            };

            setter.writeText(
                spanToString(span),
                .{
                    .word_wrap = false,
                    .style = span_style,
                    .trim_spaces = false,
                    .link = spanToLink(span),
                },
            );
        }

        setter.endCurrentLine();
    }

    fn spanToLink(span: Span) ?hdoc.Link {
        return switch (span) {
            .text => null,
            .emphasis => null,
            .monospace => null,
            .link => |l| l,
        };
    }

    fn spanToString(span: Span) []const u8 {
        return switch (span) {
            .text => |s| s,
            .emphasis => |s| s,
            .monospace => |s| s,
            .link => |l| l.text,
        };
    }

    fn emitLinkInfo(ren: Renderer, rect: Rectangle, link: hdoc.Link) void {
        ren.linkCallback(ren.context, rect, link);
    }

    const TextSetter = struct {
        renderer: *Renderer,
        position: *Point,
        line_start: i16,
        line_limit: i16,

        fn init(renderer: *Renderer) TextSetter {
            return TextSetter{
                .renderer = renderer,
                .position = &renderer.position,
                .line_start = renderer.position.x,
                .line_limit = renderer.framebuffer.width -| renderer.position.x,
            };
        }

        const WriteTextFlags = struct {
            style: Style,
            word_wrap: bool,
            trim_spaces: bool,
            link: ?hdoc.Link,
        };
        fn writeText(set: *TextSetter, string: []const u8, flags: WriteTextFlags) void {
            var pos: usize = 0;
            while (true) {
                const next_line_sep = std.mem.indexOfScalarPos(u8, string, pos, '\n');
                const end_of_line = next_line_sep orelse string.len;

                const raw_line = string[pos..end_of_line];

                const raw_width = @intCast(u15, 6 * raw_line.len);

                if (flags.word_wrap and set.position.x + raw_width > set.line_limit) {
                    set.newLine();
                }

                const line = if (flags.trim_spaces and set.isAtStartOfLine())
                    std.mem.trimLeft(u8, raw_line, whitespace)
                else
                    raw_line;

                const width = @intCast(u15, 6 * line.len);

                set.renderer.framebuffer.drawString(
                    set.position.x,
                    set.position.y,
                    line,
                    flags.style.color,
                    null,
                );

                if (flags.link) |link| {
                    set.renderer.emitLinkInfo(.{
                        .x = set.position.x,
                        .y = set.position.y,
                        .width = width,
                        .height = font_height,
                    }, link);
                }

                set.position.x += @intCast(u15, 6 * line.len); // TODO: Replace with actual font measurement

                pos = (next_line_sep orelse break) + 1;
                set.newLine();
            }
        }

        fn isAtStartOfLine(set: TextSetter) bool {
            return (set.position.x == set.line_start);
        }

        fn endCurrentLine(set: *TextSetter) void {
            if (!set.isAtStartOfLine()) {
                set.newLine();
            }
        }

        fn newLine(set: *TextSetter) void {
            set.position.x = set.line_start;
            set.position.y += font_height;
        }
    };

    fn isWhiteSpace(str: []const u8) bool {
        return for (str) |c| {
            if (std.mem.indexOfScalar(u8, whitespace, c) == null)
                break false;
        } else true;
    }

    const whitespace = " \t\r"; // line feed doesn't count as whitespace
};
