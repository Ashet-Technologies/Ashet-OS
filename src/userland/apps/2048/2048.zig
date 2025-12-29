//!
//! 2048 implemented by ChatGPT.
//!
const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const Size = ashet.abi.Size;
const Point = ashet.abi.Point;
const Rectangle = ashet.abi.Rectangle;

const Color = ashet.graphics.Color;
const Font = ashet.graphics.Font;
const Framebuffer = ashet.graphics.Framebuffer;

const GRID: usize = 4;
const TARGET: u16 = 2048;

const Overlay = enum { none, win, game_over };
const Direction = enum { left, right, up, down };

const Layout = struct {
    top_bar_h: u16,
    margin: u16,
    gap: u16,
    board_rect: Rectangle,
    cell: u16,

    fn cellRect(self: Layout, x: usize, y: usize) Rectangle {
        const ix: i16 = @as(i16, @intCast(@as(i32, self.board_rect.x) + @as(i32, @intCast(x)) * (@as(i32, self.cell) + @as(i32, self.gap))));
        const iy: i16 = @as(i16, @intCast(@as(i32, self.board_rect.y) + @as(i32, @intCast(y)) * (@as(i32, self.cell) + @as(i32, self.gap))));
        return .{ .x = ix, .y = iy, .width = self.cell, .height = self.cell };
    }
};

const Game = struct {
    board: [GRID][GRID]u16 = .{ .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } },
    score: u32 = 0,
    overlay: Overlay = .none,

    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Game {
        var g: Game = .{
            .prng = std.Random.DefaultPrng.init(seed),
        };
        g.reset();
        return g;
    }

    pub fn reset(self: *Game) void {
        self.board = .{ .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } };
        self.score = 0;
        self.overlay = .none;
        _ = self.spawnTile();
        _ = self.spawnTile();
    }

    fn rng(self: *Game) std.Random {
        return self.prng.random();
    }

    fn spawnTile(self: *Game) bool {
        var empties: [GRID * GRID]u8 = undefined;
        var n: usize = 0;

        for (0..GRID) |y| {
            for (0..GRID) |x| {
                if (self.board[y][x] == 0) {
                    empties[n] = @as(u8, @intCast(y * GRID + x));
                    n += 1;
                }
            }
        }

        if (n == 0) return false;

        const choice = empties[self.rng().uintLessThan(usize, n)];
        const cy: usize = @intCast(choice / GRID);
        const cx: usize = @intCast(choice % GRID);

        const v: u16 = if (self.rng().float(f32) < 0.10) 4 else 2;
        self.board[cy][cx] = v;
        return true;
    }

    fn hasWon(self: *const Game) bool {
        for (0..GRID) |y| for (0..GRID) |x| {
            if (self.board[y][x] >= TARGET) return true;
        };
        return false;
    }

    fn anyMovesPossible(self: *const Game) bool {
        // any empty
        for (0..GRID) |y| for (0..GRID) |x| {
            if (self.board[y][x] == 0) return true;
        };

        // any merge horizontally/vertically
        for (0..GRID) |y| {
            for (0..GRID) |x| {
                const v = self.board[y][x];
                if (x + 1 < GRID and self.board[y][x + 1] == v) return true;
                if (y + 1 < GRID and self.board[y + 1][x] == v) return true;
            }
        }

        return false;
    }

    fn reverse4(line: [GRID]u16) [GRID]u16 {
        return .{ line[3], line[2], line[1], line[0] };
    }

    fn processLineLeft(line_in: [GRID]u16, gained: *u32) [GRID]u16 {
        var temp: [GRID]u16 = .{ 0, 0, 0, 0 };
        var cnt: usize = 0;

        for (line_in) |v| {
            if (v != 0) {
                temp[cnt] = v;
                cnt += 1;
            }
        }

        var out: [GRID]u16 = .{ 0, 0, 0, 0 };
        var oi: usize = 0;
        var i: usize = 0;

        while (i < cnt) : (i += 1) {
            if (i + 1 < cnt and temp[i] == temp[i + 1]) {
                const merged: u16 = temp[i] * 2;
                out[oi] = merged;
                gained.* += merged;
                oi += 1;
                i += 1; // skip next
            } else {
                out[oi] = temp[i];
                oi += 1;
            }
        }

        return out;
    }

    pub fn move(self: *Game, dir: Direction) bool {
        if (self.overlay != .none) return false;

        var changed = false;
        var gained: u32 = 0;

        switch (dir) {
            .left, .right => {
                for (0..GRID) |y| {
                    const in0: [GRID]u16 = self.board[y];

                    const in_line = if (dir == .left) in0 else reverse4(in0);
                    const out_line = processLineLeft(in_line, &gained);
                    const out0 = if (dir == .left) out_line else reverse4(out_line);

                    if (!std.mem.eql(u16, &in0, &out0)) changed = true;
                    self.board[y] = out0;
                }
            },
            .up, .down => {
                for (0..GRID) |x| {
                    var in0: [GRID]u16 = .{ 0, 0, 0, 0 };
                    for (0..GRID) |y| in0[y] = self.board[y][x];

                    const in_line = if (dir == .up) in0 else reverse4(in0);
                    const out_line = processLineLeft(in_line, &gained);
                    const out0 = if (dir == .up) out_line else reverse4(out_line);

                    if (!std.mem.eql(u16, &in0, &out0)) changed = true;
                    for (0..GRID) |y| self.board[y][x] = out0[y];
                }
            },
        }

        if (changed) {
            self.score += gained;
            _ = self.spawnTile();

            if (self.hasWon()) {
                self.overlay = .win;
            } else if (!self.anyMovesPossible()) {
                self.overlay = .game_over;
            }
        } else {
            // even if the attempted move didn’t change the board, we can be stuck
            if (!self.anyMovesPossible()) self.overlay = .game_over;
        }

        return changed;
    }
};

fn computeLayout(size: Size) Layout {
    const margin: u16 = 10;
    const gap: u16 = 6;
    const top_bar_h: u16 = 8 + 8 + 12; // two text lines + padding

    const avail_w: u16 = size.width -| (margin * 2);
    const avail_h: u16 = size.height -| (margin * 2 + top_bar_h);

    const board_size: u16 = if (avail_w < avail_h) avail_w else avail_h;

    const gaps_total: u16 = gap * @as(u16, @intCast(GRID - 1));
    var cell: u16 = 1;
    if (board_size > gaps_total) {
        cell = (board_size - gaps_total) / @as(u16, @intCast(GRID));
        if (cell == 0) cell = 1;
    }

    const board_w: u16 = cell * @as(u16, @intCast(GRID)) + gaps_total;
    const left: u16 = (size.width -| board_w) / 2;
    const top: u16 = top_bar_h + margin;

    return .{
        .top_bar_h = top_bar_h,
        .margin = margin,
        .gap = gap,
        .board_rect = .{
            .x = @as(i16, @intCast(left)),
            .y = @as(i16, @intCast(top)),
            .width = board_w,
            .height = board_w,
        },
        .cell = cell,
    };
}

fn textWidthMono8(text: []const u8) u16 {
    // mono-8 is 5px wide per char
    return @as(u16, @intCast(text.len)) * 5;
}

fn drawCenteredText(q: *ashet.graphics.CommandQueue, rect: Rectangle, font: Font, color: Color, text: []const u8) !void {
    const tw: i32 = @intCast(textWidthMono8(text));
    const th: i32 = 8;

    const rx: i32 = rect.x;
    const ry: i32 = rect.y;
    const rw: i32 = @intCast(rect.width);
    const rh: i32 = @intCast(rect.height);

    const px: i32 = rx + @divTrunc((rw - tw), 2);
    const py: i32 = ry + @divTrunc((rh - th), 2);

    try q.draw_text(.{
        .x = @as(i16, @intCast(px)),
        .y = @as(i16, @intCast(py)),
    }, font, color, text);
}

fn tileBg(v: u16) Color {
    // good-enough palette-ish mapping using HTML -> Ashet Color conversion
    return switch (v) {
        0 => Color.from_html("#2f3143"),
        2 => Color.from_html("#eee4da"),
        4 => Color.from_html("#ede0c8"),
        8 => Color.from_html("#f2b179"),
        16 => Color.from_html("#f59563"),
        32 => Color.from_html("#f67c5f"),
        64 => Color.from_html("#f65e3b"),
        128 => Color.from_html("#edcf72"),
        256 => Color.from_html("#edcc61"),
        512 => Color.from_html("#edc850"),
        1024 => Color.from_html("#edc53f"),
        2048 => Color.from_html("#edc22e"),
        else => Color.from_html("#b44cef"),
    };
}

fn tileTextColor(v: u16) Color {
    return if (v <= 4) ashet.graphics.known_colors.black else ashet.graphics.known_colors.white;
}

fn paint(q: *ashet.graphics.CommandQueue, size: Size, fb: Framebuffer, font: Font, game: *const Game) !void {
    q.reset();

    const layout = computeLayout(size);

    // background
    try q.clear(ashet.graphics.known_colors.dim_gray);

    // header
    {
        var buf: [64]u8 = undefined;
        const title = "2048";
        const score_line = try std.fmt.bufPrint(&buf, "Score: {}", .{game.score});
        try q.draw_text(.{ .x = @as(i16, @intCast(layout.margin)), .y = 6 }, font, ashet.graphics.known_colors.white, title);
        try q.draw_text(.{ .x = @as(i16, @intCast(layout.margin)), .y = 6 + 10 }, font, ashet.graphics.known_colors.bright_gray, score_line);
        try q.draw_text(
            .{ .x = @as(i16, @intCast(layout.margin)), .y = 6 + 20 },
            font,
            ashet.graphics.known_colors.gray,
            "Arrows/WASD/Numpad to move, R restart",
        );
    }

    // board background
    try q.fill_rect(layout.board_rect, Color.from_html("#3c3a32"));
    try q.draw_rect(layout.board_rect, ashet.graphics.known_colors.black);

    // cells
    for (0..GRID) |y| {
        for (0..GRID) |x| {
            const v = game.board[y][x];
            const r = layout.cellRect(x, y);

            try q.fill_rect(r, tileBg(v));
            try q.draw_rect(r, Color.from_html("#1b1b1b"));

            if (v != 0) {
                var nbuf: [16]u8 = undefined;
                const s = try std.fmt.bufPrint(&nbuf, "{}", .{v});
                try drawCenteredText(q, r, font, tileTextColor(v), s);
            }
        }
    }

    // overlay
    if (game.overlay != .none) {
        const full: Rectangle = .{ .x = 0, .y = 0, .width = size.width, .height = size.height };
        try q.fill_rect(full, Color.from_html("#2f3143"));

        const line1 = switch (game.overlay) {
            .win => "YOU WIN!",
            .game_over => "GAME OVER",
            .none => "",
        };
        const line2 = "Press R to restart";

        const center_box: Rectangle = .{
            .x = @as(i16, @intCast((size.width -| 220) / 2)),
            .y = @as(i16, @intCast((size.height -| 80) / 2)),
            .width = 220,
            .height = 80,
        };

        try q.fill_rect(center_box, Color.from_html("#505d6d"));
        try q.draw_rect(center_box, ashet.graphics.known_colors.white);

        const l1: Rectangle = .{ .x = center_box.x, .y = center_box.y + 14, .width = center_box.width, .height = 16 };
        const l2: Rectangle = .{ .x = center_box.x, .y = center_box.y + 40, .width = center_box.width, .height = 16 };

        try drawCenteredText(q, l1, font, ashet.graphics.known_colors.white, line1);
        try drawCenteredText(q, l2, font, ashet.graphics.known_colors.bright_gray, line2);
    }

    try q.submit(fb, .{});
}

fn usageToAction(usage: ashet.abi.KeyUsageCode) ?union(enum) { move: Direction, restart: void } {
    return switch (usage) {
        .left_arrow, .a, .kp_4 => .{ .move = .left },
        .right_arrow, .d, .kp_6 => .{ .move = .right },
        .up_arrow, .w, .kp_8 => .{ .move = .up },
        .down_arrow, .s, .kp_2 => .{ .move = .down },
        .r => .{ .restart = {} },
        else => null,
    };
}

pub fn main() !void {
    std.log.info("2048 starting...", .{});
    defer std.log.info("2048 exiting...", .{});

    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = try ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "2048",
            .min_size = Size.new(220, 260),
            .max_size = Size.new(900, 900),
            .initial_size = Size.new(256, 256),
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    const font = try ashet.graphics.get_system_font("mono-8");
    defer font.release();

    // seed PRNG from monotonic clock
    const mono = ashet.abi.clock.monotonic();
    const seed: u64 = @as(u64, @intCast(@intFromEnum(mono))) ^ 0x9e3779b97f4a7c15;

    var game = Game.init(seed);

    try paint(
        &command_queue,
        ashet.gui.get_window_size(window) catch unreachable,
        framebuffer,
        font,
        &game,
    );

    main_loop: while (true) {
        const event_res = try ashet.overlapped.performOne(ashet.abi.gui.GetWindowEvent, .{
            .window = window,
        });

        const event = &event_res.event;
        switch (event.event_type) {
            .window_close => break :main_loop,

            .window_resizing,
            .window_resized,
            => {
                try paint(
                    &command_queue,
                    ashet.gui.get_window_size(window) catch unreachable,
                    framebuffer,
                    font,
                    &game,
                );
            },

            .key_press => {
                if (!event.keyboard.pressed) continue;

                var repaint = false;

                if (usageToAction(event.keyboard.usage)) |act| {
                    switch (act) {
                        .restart => {
                            game.reset();
                            repaint = true;
                        },
                        .move => |dir| {
                            // if overlay is up, ignore moves (restart still works)
                            _ = game.move(dir);
                            repaint = true;
                        },
                    }
                }

                if (repaint) {
                    try paint(
                        &command_queue,
                        ashet.gui.get_window_size(window) catch unreachable,
                        framebuffer,
                        font,
                        &game,
                    );
                }
            },

            // ignore key releases and other events
            else => {},
        }
    }
}
