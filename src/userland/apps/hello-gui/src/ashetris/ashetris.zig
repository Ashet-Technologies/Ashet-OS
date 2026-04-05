// TODOs:
// Speedup "level" based on number of cleared lines
// Score display
// Refactoring into multiple files
// Refactoring to use struct-members for easier state management
// Key-repeat
// Restart on game over
// Start screen
// Graphical effects (line clear (brightness cycle wave), piece set (shake), piece create (warp in))

const std = @import("std");
const ashet = @import("ashet");
const consts = @import("consts.zig");
const types = @import("types.zig");
const drawing_mod = @import("drawing.zig");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

const Size = ashet.abi.Size;
const Piece = types.Piece;
const Drawing = drawing_mod.Drawing;

var field: types.Field = @splat(@splat(255));

var piece_mid_x: i8 = @intCast(consts.width / 2);
var piece_mid_y: i8 = 0;
var current_piece: Piece = consts.pieces[0];
var current_piece_index: u8 = 0;
var next_piece: Piece = consts.pieces[0];
var next_piece_index: u8 = 0;
var currentDropDurationMs: u16 = 1000;
var random: std.Random.Xoshiro256 = undefined;

var game_over: bool = false;
var score: u32 = 0;

fn is_free(x: u8, y: u8) bool {
    return field[y][x] == 255;
}

fn test_piece(piece: *const Piece, x: i8, y: i8) bool {
    for (0..piece.width) |px| {
        const px_i8 = @as(i8, @intCast(px));
        const fx = piece.left_coord(x) + px_i8;
        for (0..piece.height) |py| {
            const py_i8 = @as(i8, @intCast(py));
            const fy = piece.top_coord(y) + py_i8;
            if (piece.shape[py][px] and (fx < 0 or fx >= @as(i8, consts.width) or fy >= @as(i8, consts.height) or (fy >= 0 and !is_free(@intCast(fx), @intCast(fy))))) {
                return true;
            }
        }
    }
    return false;
}

fn draw_piece(piece: *const Piece, x: i8, y: i8, piece_index: u8) void {
    for (0..piece.width) |px| {
        const px_i8 = @as(i8, @intCast(px));
        const fx = piece.left_coord(x) + px_i8;
        for (0..piece.height) |py| {
            const py_i8 = @as(i8, @intCast(py));
            const fy = piece.top_coord(y) + py_i8;
            if (fx >= 0 and fx < @as(i8, consts.width) and fy >= 0 and fy < @as(i8, consts.height) and piece.shape[py][px]) {
                field[@intCast(fy)][@intCast(fx)] = piece_index;
            }
        }
    }
}

fn move_piece(dx: i8, dy: i8) bool {
    const newx = piece_mid_x + dx;
    const newy = piece_mid_y + dy;

    draw_piece(&current_piece, piece_mid_x, piece_mid_y, 255);
    defer draw_piece(&current_piece, piece_mid_x, piece_mid_y, current_piece_index);
    if (test_piece(&current_piece, newx, newy)) {
        return false;
    } else {
        piece_mid_x = newx;
        piece_mid_y = newy;
        return true;
    }
}

fn rotate_piece(piece: *const Piece) Piece {
    var rotated_piece: Piece = undefined;
    rotated_piece.width = piece.height;
    rotated_piece.height = piece.width;

    for (0..rotated_piece.width) |px| {
        for (0..rotated_piece.height) |py| {
            rotated_piece.shape[py][px] = piece.shape[px][rotated_piece.height - py - 1];
        }
    }

    return rotated_piece;
}

fn rotate_current_piece() bool {
    var rotated_piece: Piece = rotate_piece(&current_piece);

    draw_piece(&current_piece, piece_mid_x, piece_mid_y, 255);
    defer draw_piece(&current_piece, piece_mid_x, piece_mid_y, current_piece_index);
    if (test_piece(&rotated_piece, piece_mid_x, piece_mid_y)) {
        return false;
    } else {
        current_piece = rotated_piece;
        return true;
    }
}

pub fn main() !void {
    random = std.Random.DefaultPrng.init(ashet.clock.monotonic().ns_since_start());
    seed_next_piece();
    init_new_piece();
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = try ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);
    defer desktop.release();
    std.log.info("using desktop {f}", .{desktop});

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Ashetris",
            .initial_size = Size.new(200, 300),
        },
    );
    defer window.destroy_now();
    std.log.info("created window: {f}", .{window});

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    std.log.info("created framebuffer: {f}", .{framebuffer});

    const font = ashet.graphics.get_system_font("mono-8") catch @panic("mono-8 font not found!");
    var drawing = try Drawing.init(
        ashet.process.mem.allocator(),
        framebuffer,
        font,
        ashet.gui.get_window_size(window) catch unreachable,
    );
    defer drawing.deinit();

    try drawing.fullRedraw(&field, &next_piece, next_piece_index);

    var timer_iop = ashet.clock.Timer.new(.{ .timeout = nextDropTime() });
    try ashet.overlapped.schedule(&timer_iop.arc);

    var get_event_iop = ashet.gui.GetWindowEvent.new(.{ .window = window });
    try ashet.overlapped.schedule(&get_event_iop.arc);

    main_loop: while (true) {
        var arc_buffer: [2]*ashet.overlapped.ARC = undefined;

        const completed = try ashet.overlapped.await_completion(&arc_buffer, .{
            .wait = .wait_one,
            .thread_affinity = .this_thread,
        });

        for (completed) |overlapped_event| {
            if (overlapped_event == &timer_iop.arc) {
                if (game_over) {
                    continue;
                }

                try timer_iop.check_error();
                game_over = (try lowerPiece(
                    &drawing,
                )).game_over;

                if (!game_over) {
                    timer_iop.inputs.timeout = nextDropTime();
                    try ashet.overlapped.schedule(&timer_iop.arc);
                }
            } else if (overlapped_event == &get_event_iop.arc) {
                const event = try get_event_iop.get_output();

                switch (event.event_type) {
                    .window_close => break :main_loop,

                    // .key_release => |kbdevt| {
                    //     // Let's use this for auto-repeat
                    // },

                    .key_press => {
                        const kbdevt = event.keyboard;
                        switch (kbdevt.usage) {
                            .left_arrow => {
                                if (!game_over) {
                                    _ = move_piece(-1, 0);
                                }
                            },

                            .right_arrow => {
                                if (!game_over) {
                                    _ = move_piece(1, 0);
                                }
                            },

                            .up_arrow => {
                                if (!game_over) {
                                    _ = rotate_current_piece();
                                }
                            },

                            .down_arrow => {
                                if (!game_over) {
                                    game_over = (try lowerPiece(
                                        &drawing,
                                    )).game_over;
                                }
                            },

                            .space => {
                                if (!game_over) {
                                    while (true) {
                                        const lower_piece_result = try lowerPiece(
                                            &drawing,
                                        );
                                        if (lower_piece_result.piece_settled or lower_piece_result.game_over) {
                                            game_over = lower_piece_result.game_over;
                                            break;
                                        }
                                    }
                                }
                            },

                            else => {},
                        }
                        try drawing.updatePlayfield(&field);
                        try drawing.submit();
                    },

                    .window_resizing,
                    .window_resized,
                    => {
                        // we changed size, so we have to resize our window content:
                        const window_size = ashet.gui.get_window_size(window) catch unreachable;
                        drawing.setWindowSize(window_size);
                        try drawing.fullRedraw(&field, &next_piece, next_piece_index);
                    },

                    else => {},
                }

                // reschedule the IOP to receive more events:
                try ashet.overlapped.schedule(&get_event_iop.arc);
            } else {
                unreachable;
            }
        }
    }
}

fn nextDropTime() ashet.clock.Absolute {
    return ashet.clock.monotonic().increment_by(ashet.clock.Duration.from_ms(currentDropDurationMs));
}

fn seed_next_piece() void {
    const piece_index = random.random().intRangeAtMost(usize, 0, consts.pieces.len - 1);
    next_piece = consts.pieces[piece_index];
    next_piece_index = @intCast(piece_index);
    for (0..random.random().intRangeAtMost(usize, 0, 3)) |_| {
        next_piece = rotate_piece(&next_piece);
    }
}

const LowerPieceResult = struct {
    game_over: bool,
    piece_settled: bool,
};

fn lowerPiece(drawing: *Drawing) !LowerPieceResult {
    var result: LowerPieceResult = .{
        .game_over = false,
        .piece_settled = false,
    };
    var next_piece_changed = false;

    if (!move_piece(0, 1)) {
        result.piece_settled = true;

        // Piece comes to rest, check clearing rows
        const top: i8 = current_piece.top_coord(piece_mid_y);
        const clipped_top: usize = @intCast(@max(0, top));
        const bot: i8 = top + @as(i8, @intCast(current_piece.height));
        const clipped_bot: usize = @intCast(@max(0, bot));

        var cleared_rows: u8 = 0;
        for (clipped_top..clipped_bot) |fy| {
            if (is_row_full(fy)) {
                collapse_row(fy);
                cleared_rows += 1;
            }
        }
        score += cleared_rows * cleared_rows;

        init_new_piece();
        next_piece_changed = true;

        if (test_piece(&current_piece, piece_mid_x, piece_mid_y)) {
            result.game_over = true;
        }

        draw_piece(&current_piece, piece_mid_x, piece_mid_y, current_piece_index);
    }

    if (!result.game_over) {
        try drawing.updatePlayfield(&field);
        if (next_piece_changed) {
            try drawing.drawNextPiecePreview(&next_piece, next_piece_index);
        }
        try drawing.submit();
    } else {
        try drawing.drawGameOver();
    }

    return result;
}

fn init_new_piece() void {
    current_piece = next_piece;
    current_piece_index = next_piece_index;
    seed_next_piece();

    piece_mid_x = @as(i8, consts.width / 2);
    piece_mid_y = 0;
}

fn is_row_full(fy: usize) bool {
    for (0..consts.width) |fx| {
        if (is_free(@intCast(fx), @intCast(fy))) {
            return false;
        }
    }
    return true;
}

fn collapse_row(y: usize) void {
    var i: usize = y;
    while (i > 0) {
        field[i] = field[i - 1];
        i -= 1;
    }

    field[0] = @splat(255);
}
