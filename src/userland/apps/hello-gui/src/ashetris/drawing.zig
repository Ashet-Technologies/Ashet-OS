const ashet = @import("ashet");
const consts = @import("consts.zig");
const types = @import("types.zig");

const Size = ashet.abi.Size;
const Piece = types.Piece;
const Field = types.Field;

const base_x = 10;
const base_y = 10;
const scale = 10;
const bgcolor = ashet.graphics.known_colors.brown;
const preview_margin = 8;
const preview_label_gap = 4;
const preview_box_blocks = 6;
const score_box_height = 16;

pub const Drawing = struct {
    command_queue: ashet.graphics.CommandQueue,
    framebuffer: ashet.graphics.Framebuffer,
    font: ashet.graphics.Font,
    window_size: Size,
    oldfield: Field = @splat(@splat(255)),

    pub fn init(allocator: std.mem.Allocator, framebuffer: ashet.graphics.Framebuffer, font: ashet.graphics.Font, window_size: Size) !Drawing {
        return .{
            .command_queue = try ashet.graphics.CommandQueue.init(allocator),
            .framebuffer = framebuffer,
            .font = font,
            .window_size = window_size,
        };
    }

    pub fn deinit(self: *Drawing) void {
        self.command_queue.deinit();
    }

    pub fn setWindowSize(self: *Drawing, window_size: Size) void {
        self.window_size = window_size;
    }

    pub fn submit(self: *Drawing) !void {
        try self.command_queue.submit(self.framebuffer, .{});
    }

    pub fn fullRedraw(self: *Drawing, field: *const Field, next_piece: *const Piece, next_piece_index: u8, score: u32) !void {
        try self.command_queue.clear(bgcolor);
        try self.command_queue.fill_rect(.{
            .x = @intCast(base_x),
            .y = @intCast(base_y),
            .width = consts.width * scale,
            .height = consts.height * scale,
        }, ashet.graphics.known_colors.black);
        try self.drawNextPiecePreview(next_piece, next_piece_index);
        try self.drawScore(score);
        self.oldfield = @splat(@splat(255));
        try self.updatePlayfield(field);
        try self.submit();
    }

    pub fn updatePlayfield(self: *Drawing, field: *const Field) !void {
        for (0..consts.height) |fy| {
            for (0..consts.width) |fx| {
                if (self.oldfield[fy][fx] != field[fy][fx]) {
                    const box_x: i16 = @intCast(base_x + scale * fx);
                    const box_y: i16 = @intCast(base_y + scale * fy);
                    try drawBlock(&self.command_queue, box_x, box_y, field[fy][fx]);
                }
            }
        }
        self.oldfield = field.*;
    }

    pub fn drawNextPiecePreview(self: *Drawing, next_piece: *const Piece, next_piece_index: u8) !void {
        const board_right = base_x + consts.width * scale;
        const preview_area_left = board_right + preview_margin;
        const preview_area_top = base_y;
        const preview_area_width = @as(i16, @intCast(self.window_size.width)) - preview_area_left - preview_margin;
        const label = "Next";
        const label_size = try ashet.graphics.measure_text_size(self.font, label);
        const preview_box_size = preview_box_blocks * scale;
        const preview_area_height = @as(i16, @intCast(label_size.height)) + preview_label_gap + preview_box_size;

        if (preview_area_width <= 0 or preview_area_height <= 0) return;

        try self.command_queue.fill_rect(.{
            .x = preview_area_left,
            .y = preview_area_top,
            .width = @intCast(preview_area_width),
            .height = @intCast(preview_area_height),
        }, bgcolor);

        const label_x = preview_area_left + @divTrunc(preview_area_width - @as(i16, @intCast(label_size.width)), 2);
        const label_y = preview_area_top;
        try self.command_queue.draw_text(.{
            .x = label_x,
            .y = label_y,
        }, self.font, ashet.graphics.known_colors.white, label);

        const box_top = label_y + @as(i16, @intCast(label_size.height)) + preview_label_gap;
        const box_left = preview_area_left + @divTrunc(preview_area_width - preview_box_size, 2);
        const box_width = preview_box_size;
        const box_height = preview_box_size;

        if (box_width <= 0 or box_height <= 0) return;

        try self.command_queue.fill_rect(.{
            .x = box_left,
            .y = box_top,
            .width = @intCast(box_width),
            .height = @intCast(box_height),
        }, ashet.graphics.known_colors.black);

        const piece_width_px: i16 = next_piece.width * scale;
        const piece_height_px: i16 = next_piece.height * scale;
        const preview_x = box_left + @divTrunc(box_width - piece_width_px, 2);
        const preview_y = box_top + @divTrunc(box_height - piece_height_px, 2);

        for (0..next_piece.width) |px| {
            for (0..next_piece.height) |py| {
                if (next_piece.shape[py][px]) {
                    try drawBlock(
                        &self.command_queue,
                        preview_x + @as(i16, @intCast(px * scale)),
                        preview_y + @as(i16, @intCast(py * scale)),
                        next_piece_index,
                    );
                }
            }
        }
    }

    pub fn drawScore(self: *Drawing, score: u32) !void {
        const board_right = base_x + consts.width * scale;
        const preview_area_left = board_right + preview_margin;
        const preview_area_width = @as(i16, @intCast(self.window_size.width)) - preview_area_left - preview_margin;
        const preview_box_size = preview_box_blocks * scale;
        const box_left = preview_area_left + @divTrunc(preview_area_width - preview_box_size, 2);
        const label = "Score";
        const label_size = try ashet.graphics.measure_text_size(self.font, label);
        const preview_box_top = base_y + @as(i16, @intCast(label_size.height)) + preview_label_gap;
        const score_label_y = preview_box_top + preview_box_size + preview_margin;
        const score_box_top = score_label_y + @as(i16, @intCast(label_size.height)) + preview_label_gap;

        if (preview_area_width <= 0) return;

        try self.command_queue.fill_rect(.{
            .x = preview_area_left,
            .y = score_label_y,
            .width = @intCast(preview_area_width),
            .height = @intCast(@as(i16, @intCast(label_size.height)) + preview_label_gap + score_box_height),
        }, bgcolor);

        const label_x = preview_area_left + @divTrunc(preview_area_width - @as(i16, @intCast(label_size.width)), 2);
        try self.command_queue.draw_text(.{
            .x = label_x,
            .y = score_label_y,
        }, self.font, ashet.graphics.known_colors.white, label);

        try self.command_queue.fill_rect(.{
            .x = box_left,
            .y = score_box_top,
            .width = @intCast(preview_box_size),
            .height = score_box_height,
        }, ashet.graphics.known_colors.black);

        var score_buf: [16]u8 = undefined;
        const score_text = try std.fmt.bufPrint(&score_buf, "{}", .{score});
        const score_size = try ashet.graphics.measure_text_size(self.font, score_text);
        try self.command_queue.draw_text(.{
            .x = box_left + @divTrunc(preview_box_size - @as(i16, @intCast(score_size.width)), 2),
            .y = score_box_top + @divTrunc(score_box_height - @as(i16, @intCast(score_size.height)), 2),
        }, self.font, ashet.graphics.known_colors.white, score_text);
    }

    pub fn drawGameOver(self: *Drawing) !void {
        const textbox_left: i16 = base_x + scale;
        const textbox_top: i16 = base_y + ((consts.height / 2 - 3) * scale);
        const textbox_width: i16 = consts.width * (scale - 2);
        const textbox_height: i16 = 6 * scale;

        try self.command_queue.fill_rect(.{
            .x = textbox_left,
            .y = textbox_top,
            .width = textbox_width,
            .height = textbox_height,
        }, ashet.graphics.known_colors.black);

        const text = "Game Over";
        const text_size = try ashet.graphics.measure_text_size(self.font, text);
        try self.command_queue.draw_text(.{
            .x = textbox_left + @divTrunc(textbox_width, 2) - @divTrunc(@as(i16, @intCast(text_size.width)), 2),
            .y = textbox_top + @divTrunc(textbox_height, 2) - @divTrunc(@as(i16, @intCast(text_size.height)), 2),
        }, self.font, ashet.graphics.known_colors.white, text);
        try self.submit();
    }
};

fn drawBlock(q: *ashet.graphics.CommandQueue, x: i16, y: i16, piece_index: u8) !void {
    const free = piece_index == 255;
    const block_color = if (free)
        ashet.graphics.known_colors.black
    else
        consts.colors[piece_index];

    try q.fill_rect(.{
        .x = x,
        .y = y,
        .width = scale,
        .height = scale,
    }, block_color);

    if (!free) {
        var lighter = block_color;
        lighter.value +|= 1;
        var darker = block_color;
        darker.value -|= 1;

        try q.draw_vertical_line(.{ .x = x, .y = y + 1 }, scale - 1, darker);
        try q.draw_vertical_line(.{ .x = x + scale - 1, .y = y }, scale - 1, lighter);
        try q.draw_horizontal_line(.{ .x = x + 1, .y = y }, scale - 2, lighter);
        try q.draw_horizontal_line(.{ .x = x + 1, .y = y + scale - 1 }, scale - 2, darker);
    }
}

const std = @import("std");
