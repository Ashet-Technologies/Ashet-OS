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

// Tiny move animation
const ANIM_FRAMES: u8 = 8; // set to 4 or 8
const ANIM_FRAME_DELAY_NS: u64 = 12_000_000; // ~12ms per frame

const Overlay = enum { none, win, game_over };
const Direction = enum { left, right, up, down };

fn u8ToUsize(v: u8) usize {
    return @as(usize, @intCast(v));
}

const MoveAnim = struct {
    value: u16,
    sx: u8,
    sy: u8,
    ex: u8,
    ey: u8,
};

const MovePlan = struct {
    dst: [GRID][GRID]u16 = .{ .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 }, .{ 0, 0, 0, 0 } },
    gain: u32 = 0,
    moves: [16]MoveAnim = undefined,
    moves_len: u8 = 0,
    changed: bool = false,
    reached_target: bool = false,
};

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
    won: bool = false,

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
        self.won = false;
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

    fn updateGameOver(self: *Game) void {
        if (!self.anyMovesPossible()) self.overlay = .game_over;
    }

    fn applyMovePlan(self: *Game, plan: *const MovePlan) void {
        self.board = plan.dst;
        self.score += plan.gain;

        _ = self.spawnTile();

        if (!self.won and plan.reached_target) {
            self.won = true;
            self.overlay = .win; // shown once; dismissed on next move
        }

        self.updateGameOver();
    }
};

fn computeLayout(size: Size) Layout {
    const margin: u16 = 10;
    const gap: u16 = 6;

    // score line (mono-8) + tutorial line (mono-6) + padding
    const top_bar_h: u16 = 30;

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

fn drawCenteredTextMono8(q: *ashet.graphics.CommandQueue, rect: Rectangle, font: Font, color: Color, text: []const u8) !void {
    const tw: i32 = @intCast(textWidthMono8(text));
    const th: i32 = 8;

    const rx: i32 = rect.x;
    const ry: i32 = rect.y;
    const rw: i32 = @intCast(rect.width);
    const rh: i32 = @intCast(rect.height);

    const px: i32 = rx + @divFloor((rw - tw), 2);
    const py: i32 = ry + @divFloor((rh - th), 2);

    try q.draw_text(.{
        .x = @as(i16, @intCast(px)),
        .y = @as(i16, @intCast(py)),
    }, font, color, text);
}

fn tileBg(v: u16) Color {
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

const AnimRender = struct {
    moves: []const MoveAnim,
    frame: u8, // 1..total
    total: u8,
};

fn paint(
    q: *ashet.graphics.CommandQueue,
    size: Size,
    fb: Framebuffer,
    font_main: Font,
    font_tutorial: Font,
    game: *const Game,
    anim: ?AnimRender,
) !void {
    q.reset();

    const layout = computeLayout(size);

    // background
    try q.clear(ashet.graphics.known_colors.dim_gray);

    // header (no "2048" title - window decorations already show it)
    {
        var buf: [64]u8 = undefined;
        const score_line = try std.fmt.bufPrint(&buf, "Score: {}", .{game.score});

        try q.draw_text(
            .{ .x = @as(i16, @intCast(layout.margin)), .y = 6 },
            font_main,
            ashet.graphics.known_colors.bright_gray,
            score_line,
        );

        // tutorial line uses mono-6
        try q.draw_text(
            .{ .x = @as(i16, @intCast(layout.margin)), .y = 6 + 12 },
            font_tutorial,
            ashet.graphics.known_colors.gray,
            "Arrows/WASD/Numpad to move, R restart",
        );
    }

    // board background
    try q.fill_rect(layout.board_rect, Color.from_html("#3c3a32"));
    try q.draw_rect(layout.board_rect, ashet.graphics.known_colors.black);

    // During animation, we draw stationary tiles from the *current* board, except tiles that move out.
    var moving_from: [GRID][GRID]bool = .{
        .{ false, false, false, false },
        .{ false, false, false, false },
        .{ false, false, false, false },
        .{ false, false, false, false },
    };

    if (anim) |a| {
        for (a.moves) |m| {
            moving_from[u8ToUsize(m.sy)][u8ToUsize(m.sx)] = true;
        }
    }

    // cells + stationary tiles
    for (0..GRID) |y| {
        for (0..GRID) |x| {
            const base_v = game.board[y][x];
            const r = layout.cellRect(x, y);

            const draw_v: u16 = if (base_v != 0 and !moving_from[y][x]) base_v else 0;

            try q.fill_rect(r, tileBg(draw_v));
            try q.draw_rect(r, Color.from_html("#1b1b1b"));

            if (draw_v != 0) {
                var nbuf: [16]u8 = undefined;
                const s = try std.fmt.bufPrint(&nbuf, "{}", .{draw_v});
                try drawCenteredTextMono8(q, r, font_main, tileTextColor(draw_v), s);
            }
        }
    }

    // moving tiles on top
    if (anim) |a| {
        const f: i32 = @intCast(a.frame);
        const t: i32 = @intCast(a.total);

        for (a.moves) |m| {
            const sr = layout.cellRect(u8ToUsize(m.sx), u8ToUsize(m.sy));
            const er = layout.cellRect(u8ToUsize(m.ex), u8ToUsize(m.ey));

            const sx: i32 = sr.x;
            const sy: i32 = sr.y;
            const ex: i32 = er.x;
            const ey: i32 = er.y;

            const ix: i16 = @as(i16, @intCast(sx + @divFloor((ex - sx) * f, t)));
            const iy: i16 = @as(i16, @intCast(sy + @divFloor((ey - sy) * f, t)));

            const r: Rectangle = .{ .x = ix, .y = iy, .width = layout.cell, .height = layout.cell };

            try q.fill_rect(r, tileBg(m.value));
            try q.draw_rect(r, Color.from_html("#1b1b1b"));

            var nbuf: [16]u8 = undefined;
            const s = try std.fmt.bufPrint(&nbuf, "{}", .{m.value});
            try drawCenteredTextMono8(q, r, font_main, tileTextColor(m.value), s);
        }
    }

    // overlay (win is non-blocking; game-over blocks moves until R)
    if (game.overlay != .none) {
        const full: Rectangle = .{ .x = 0, .y = 0, .width = size.width, .height = size.height };
        try q.fill_rect(full, Color.from_html("#2f3143"));

        const line1 = switch (game.overlay) {
            .win => "YOU WIN!",
            .game_over => "GAME OVER",
            .none => "",
        };

        const line2 = switch (game.overlay) {
            .win => "Continue playing, R restart",
            .game_over => "Press R to restart",
            .none => "",
        };

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

        try drawCenteredTextMono8(q, l1, font_main, ashet.graphics.known_colors.white, line1);
        try drawCenteredTextMono8(q, l2, font_main, ashet.graphics.known_colors.bright_gray, line2);
    }

    try q.submit(fb, .{});
}

fn coordFor(dir: Direction, line: usize, p: usize) struct { x: u8, y: u8 } {
    // p is in "forward" order (towards the move direction)
    return switch (dir) {
        .left => .{ .x = @as(u8, @intCast(p)), .y = @as(u8, @intCast(line)) },
        .right => .{ .x = @as(u8, @intCast(3 - p)), .y = @as(u8, @intCast(line)) },
        .up => .{ .x = @as(u8, @intCast(line)), .y = @as(u8, @intCast(p)) },
        .down => .{ .x = @as(u8, @intCast(line)), .y = @as(u8, @intCast(3 - p)) },
    };
}

fn addMove(plan: *MovePlan, dir: Direction, line: usize, src_p: usize, dst_p: usize, value: u16) void {
    const s = coordFor(dir, line, src_p);
    const d = coordFor(dir, line, dst_p);
    if (s.x == d.x and s.y == d.y) return; // not moving
    const idx: usize = @intCast(plan.moves_len);
    if (idx >= plan.moves.len) return; // should never happen
    plan.moves[idx] = .{ .value = value, .sx = s.x, .sy = s.y, .ex = d.x, .ey = d.y };
    plan.moves_len += 1;
}

fn setDst(plan: *MovePlan, dir: Direction, line: usize, dst_p: usize, value: u16) void {
    const c = coordFor(dir, line, dst_p);
    plan.dst[@as(usize, @intCast(c.y))][@as(usize, @intCast(c.x))] = value;
    if (value >= TARGET) plan.reached_target = true;
}

fn makeMovePlan(board: *const [GRID][GRID]u16, dir: Direction) MovePlan {
    var plan: MovePlan = .{};
    // dst already zeroed by default init

    for (0..GRID) |line| {
        var pos: [GRID]u8 = undefined;
        var val: [GRID]u16 = undefined;
        var n: usize = 0;

        // collect tiles in forward order
        for (0..GRID) |p| {
            const c = coordFor(dir, line, p);
            const v = board[@as(usize, @intCast(c.y))][@as(usize, @intCast(c.x))];
            if (v != 0) {
                pos[n] = @as(u8, @intCast(p));
                val[n] = v;
                n += 1;
            }
        }

        var out_p: usize = 0;
        var i: usize = 0;
        while (i < n) {
            const v = val[i];
            if (i + 1 < n and val[i + 1] == v) {
                // merge
                const merged: u16 = v * 2;
                plan.gain += merged;
                plan.changed = true;

                addMove(&plan, dir, line, pos[i], out_p, v);
                addMove(&plan, dir, line, pos[i + 1], out_p, v);
                setDst(&plan, dir, line, out_p, merged);

                out_p += 1;
                i += 2;
            } else {
                if (pos[i] != out_p) plan.changed = true;
                addMove(&plan, dir, line, pos[i], out_p, v);
                setDst(&plan, dir, line, out_p, v);
                out_p += 1;
                i += 1;
            }
        }
    }

    return plan;
}

fn sleepNs(delta_ns: u64) !void {
    const now = ashet.abi.clock.monotonic();
    const now_ns: u64 = @intFromEnum(now);
    const timeout: ashet.abi.Absolute = @enumFromInt(now_ns + delta_ns);
    _ = try ashet.overlapped.performOne(ashet.abi.clock.Timer, .{ .timeout = timeout });
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
            .min_size = Size.new(220, 220),
            .max_size = Size.new(900, 900),
            .initial_size = Size.new(256, 256),
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    const font_main = try ashet.graphics.get_system_font("mono-8");
    defer font_main.release();

    const font_tutorial = try ashet.graphics.get_system_font("mono-6");
    defer font_tutorial.release();

    // seed PRNG from monotonic clock
    const mono = ashet.abi.clock.monotonic();
    const seed: u64 = @as(u64, @intCast(@intFromEnum(mono))) ^ 0x9e3779b97f4a7c15;

    var game = Game.init(seed);

    try paint(
        &command_queue,
        ashet.gui.get_window_size(window) catch unreachable,
        framebuffer,
        font_main,
        font_tutorial,
        &game,
        null,
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
                    font_main,
                    font_tutorial,
                    &game,
                    null,
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
                            if (game.overlay == .game_over) {
                                // only restart allowed
                                repaint = false;
                            } else {
                                // win overlay is non-blocking; dismiss it on next move
                                if (game.overlay == .win) game.overlay = .none;

                                const plan = makeMovePlan(&game.board, dir);

                                if (!plan.changed) {
                                    game.updateGameOver();
                                    repaint = true;
                                } else {
                                    const size = ashet.gui.get_window_size(window) catch unreachable;
                                    const mv_len: usize = @intCast(plan.moves_len);
                                    const mv_slice = plan.moves[0..mv_len];

                                    var f: u8 = 1;
                                    while (f <= ANIM_FRAMES) : (f += 1) {
                                        try paint(
                                            &command_queue,
                                            size,
                                            framebuffer,
                                            font_main,
                                            font_tutorial,
                                            &game,
                                            .{ .moves = mv_slice, .frame = f, .total = ANIM_FRAMES },
                                        );
                                        try sleepNs(ANIM_FRAME_DELAY_NS);
                                    }

                                    game.applyMovePlan(&plan);
                                    repaint = true;
                                }
                            }
                        },
                    }
                }

                if (repaint) {
                    try paint(
                        &command_queue,
                        ashet.gui.get_window_size(window) catch unreachable,
                        framebuffer,
                        font_main,
                        font_tutorial,
                        &game,
                        null,
                    );
                }
            },

            else => {},
        }
    }
}
