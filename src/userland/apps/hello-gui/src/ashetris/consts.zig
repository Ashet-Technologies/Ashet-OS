const ashet = @import("ashet");
const std = @import("std");
const types = @import("types.zig");

pub const Piece = types.Piece;

pub const width = 10;
pub const height = 20;
pub const pieces: [7]Piece = .{
    parsePiece(
        \\####
    ),
    parsePiece(
        \\##
        \\##
    ),
    parsePiece(
        \\..#
        \\###
    ),
    parsePiece(
        \\#..
        \\###
    ),
    parsePiece(
        \\###
        \\.#.
    ),
    parsePiece(
        \\.##
        \\##.
    ),
    parsePiece(
        \\##.
        \\.##
    ),
};

pub const colors: [7]ashet.graphics.Color = .{
    ashet.graphics.known_colors.blue,
    ashet.graphics.known_colors.gold,
    ashet.graphics.known_colors.gray,
    ashet.graphics.known_colors.gray,
    ashet.graphics.known_colors.white,
    ashet.graphics.known_colors.red,
    ashet.graphics.known_colors.red,
};

fn parsePiece(comptime text: []const u8) Piece {
    var shape: [4][4]bool = @splat(@splat(false));

    var lines = std.mem.splitScalar(u8, text, '\n');

    var y: usize = 0;
    var line_length: u8 = 0;

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (y == 0) {
            if (line.len > 4) {
                @compileError("Rows must have at most 4 chars");
            }
            line_length = line.len;
        } else if (y > 3) {
            @compileError("Pieces must have at most 4 rows");
        }

        if (line.len != line_length) {
            @compileError("All rows must have the same number of chars");
        }

        for (line, 0..) |c, x| {
            shape[y][x] = switch (c) {
                '#' => true,
                '.' => false,
                else => @compileError("use only '#' and '.' in piece definitions"),
            };
        }

        y += 1;
    }

    return .{ .width = line_length, .height = y, .shape = shape };
}
