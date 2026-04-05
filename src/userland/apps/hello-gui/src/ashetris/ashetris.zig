// TODOs:
// Speedup "level" based on number of cleared lines
// Score display
// Refactoring into multiple files
// Refactoring to use struct-members for easier state management
// Key-repeat
// Restart on game over
// Start screen
// Sound / Music
// Slam down key
// Graphical effects (line clear (brightness cycle wave), piece set (shake), piece create (warp in))
// Next piece preview
// Properly initialize first piece

const std = @import("std");
const ashet = @import("ashet");
const consts = @import("consts.zig");

pub const std_options = ashet.core.std_options;
pub const panic = ashet.core.panic;
comptime {
    _ = ashet.core;
}

const UUID = ashet.abi.UUID;
const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Piece = consts.Piece;

var field: [consts.height][consts.width]u8 = @splat(@splat(255));
var oldfield: [consts.height][consts.width]u8 = @splat(@splat(255));

var piece_mid_x: i8 = @intCast(consts.width / 2);
var piece_mid_y: i8 = 0;
var current_piece: Piece = consts.pieces[0];
var current_piece_index: u8 = 0;
var next_piece: Piece = consts.pieces[1];
var next_piece_index: u8 = 1;
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

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    try initial_draw(
        &command_queue,
        ashet.gui.get_window_size(window) catch unreachable,
        framebuffer,
    );

    var timer_iop = ashet.clock.Timer.new(.{ .timeout = nextDropTime() });
    try ashet.overlapped.schedule(&timer_iop.arc);

    var get_event_iop = ashet.gui.GetWindowEvent.new(.{ .window = window });
    try ashet.overlapped.schedule(&get_event_iop.arc);

    main_loop: while (true) {
        var arc_buffer: [2]*ashet.overlapped.ARC = undefined;
        const font = ashet.graphics.get_system_font("mono-8") catch @panic("mono-8 font not found!");

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
                game_over = try lowerPiece(
                    &command_queue,
                    ashet.gui.get_window_size(window) catch unreachable,
                    framebuffer,
                    font,
                );

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
                                    game_over = try lowerPiece(
                                        &command_queue,
                                        ashet.gui.get_window_size(window) catch unreachable,
                                        framebuffer,
                                        font,
                                    );
                                }
                            },

                            else => {},
                        }
                        try update_playfield(
                            &command_queue,
                            ashet.gui.get_window_size(window) catch unreachable,
                            framebuffer,
                        );
                    },

                    .window_resizing,
                    .window_resized,
                    => {
                        // we changed size, so we have to resize our window content:
                        try update_playfield(
                            &command_queue,
                            ashet.gui.get_window_size(window) catch unreachable,
                            framebuffer,
                        );
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

const base_x = 10;
const base_y = 10;
const scale = 10;
const bgcolor = ashet.graphics.known_colors.brown;

fn initial_draw(q: *ashet.graphics.CommandQueue, size: ashet.abi.Size, fb: ashet.graphics.Framebuffer) !void {
    _ = size;
    try q.clear(ashet.graphics.known_colors.brown);
    try q.fill_rect(.{
        .x = @intCast(base_x),
        .y = @intCast(base_y),
        .width = consts.width * scale,
        .height = consts.height * scale,
    }, ashet.graphics.known_colors.black);
    try q.submit(fb, .{});
}

fn draw_game_over(q: *ashet.graphics.CommandQueue, size: ashet.abi.Size, fb: ashet.graphics.Framebuffer, font: ashet.graphics.Font) !void {
    _ = size;

    const textbox_left: i16 = base_x + scale;
    const textbox_top: i16 = base_y + ((consts.height / 2 - 3) * scale);
    const textbox_width: i16 = consts.width * (scale - 2);
    const textbox_height: i16 = 6 * scale;

    try q.fill_rect(.{
        .x = textbox_left,
        .y = textbox_top,
        .width = textbox_width,
        .height = textbox_height,
    }, ashet.graphics.known_colors.black);

    const text = "Game Over";
    const text_size = try ashet.graphics.measure_text_size(font, text);
    try q.draw_text(.{
        .x = textbox_left + @divTrunc(textbox_width, 2) - @divTrunc(@as(i16, @intCast(text_size.width)), 2),
        .y = textbox_top + @divTrunc(textbox_height, 2) - @divTrunc(@as(i16, @intCast(text_size.height)), 2),
    }, font, ashet.graphics.known_colors.white, "Game Over");
    try q.submit(fb, .{});
}

fn update_playfield(q: *ashet.graphics.CommandQueue, size: ashet.abi.Size, fb: ashet.graphics.Framebuffer) !void {
    _ = size;

    for (0..consts.height) |fy| {
        for (0..consts.width) |fx| {
            if (oldfield[fy][fx] != field[fy][fx]) {
                const box_x: i16 = @intCast(base_x + scale * fx);
                const box_y: i16 = @intCast(base_y + scale * fy);
                const free = is_free(@intCast(fx), @intCast(fy));
                const block_color = if (free)
                    ashet.graphics.known_colors.black
                else
                    consts.colors[field[fy][fx]];

                try q.fill_rect(.{
                    .x = @intCast(box_x),
                    .y = @intCast(box_y),
                    .width = scale,
                    .height = scale,
                }, block_color);
                if (!free) {
                    var lighter = block_color;
                    lighter.value +|= 1;
                    var darker = block_color;
                    darker.value -|= 1;

                    try q.draw_vertical_line(.{ .x = box_x, .y = box_y + 1 }, scale - 1, darker);
                    try q.draw_vertical_line(.{ .x = box_x + scale - 1, .y = box_y }, scale - 1, lighter);
                    try q.draw_horizontal_line(.{ .x = box_x + 1, .y = box_y }, scale - 2, lighter);
                    try q.draw_horizontal_line(.{ .x = box_x + 1, .y = box_y + scale - 1 }, scale - 2, darker);
                }
            }
        }
    }

    oldfield = field;

    try q.submit(fb, .{});
}

fn nextDropTime() ashet.clock.Absolute {
    return ashet.clock.monotonic().increment_by(ashet.clock.Duration.from_ms(currentDropDurationMs));
}

fn lowerPiece(command_queue: *ashet.graphics.CommandQueue, window_size: Size, framebuffer: ashet.graphics.Framebuffer, font: ashet.graphics.Font) !bool {
    var game_over_result: bool = false;

    if (!move_piece(0, 1)) {
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

        if (test_piece(&current_piece, piece_mid_x, piece_mid_y)) {
            game_over_result = true;
        }

        draw_piece(&current_piece, piece_mid_x, piece_mid_y, current_piece_index);
    }

    if (!game_over_result) {
        try update_playfield(
            command_queue,
            window_size,
            framebuffer,
        );
    } else {
        try draw_game_over(
            command_queue,
            window_size,
            framebuffer,
            font,
        );
    }

    return game_over_result;
}

fn init_new_piece() void {
    current_piece = next_piece;
    current_piece_index = next_piece_index;

    const pieceIndex = random.random().intRangeAtMost(usize, 0, consts.pieces.len - 1);
    next_piece = consts.pieces[pieceIndex];
    next_piece_index = @intCast(pieceIndex);
    for (0..random.random().intRangeAtMost(usize, 0, 3)) |_| {
        next_piece = rotate_piece(&next_piece);
    }

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
