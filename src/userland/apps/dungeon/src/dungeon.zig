const std = @import("std");
const ashet = @import("ashet");
const Vec2 = @import("Vector2.zig");

pub usingnamespace ashet.core;

const Color = ashet.abi.Color;

const screen_width = 200;
const screen_height = 150;

var raycaster: Raycaster = .{};

var sprites = [_]Sprite{
    .{ .texture_id = 8, .position = Vec2.new(1.5, 0.5) },
};

const walls = [_]Wall{
    Wall{
        .texture_id = 1,
        .points = .{ Vec2.new(2, -0.5), Vec2.new(-2, -0.5) },
        .u_offset = .{ 0, 4 },
    },

    Wall{
        .texture_id = 1,
        .points = .{ Vec2.new(2, -0.5), Vec2.new(2, 0.5) },
        .u_offset = .{ 0, 1 },
    },

    Wall{
        .texture_id = 5,
        .points = .{ Vec2.new(2, 0.5), Vec2.new(2, 1.5) },
        .u_offset = .{ 0, 1 },
    },

    Wall{
        .texture_id = 1,
        .points = .{ Vec2.new(2, 1.5), Vec2.new(2, 2.5) },
        .u_offset = .{ 0, 1 },
    },

    Wall{
        .texture_id = 1,
        .points = .{ Vec2.new(2, 2.5), Vec2.new(-2, 2.5) },
        .u_offset = .{ 0, 4 },
    },

    Wall{
        .texture_id = 1,
        .points = .{ Vec2.new(-2, -0.5), Vec2.new(-2, 2.5) },
        .u_offset = .{ 0, 3 },
    },
};

pub fn main() !void {
    var argv_buffer: [8]ashet.abi.SpawnProcessArg = undefined;
    const argv = ashet.process.get_arguments(null, &argv_buffer);

    std.debug.assert(argv.len == 2);
    std.debug.assert(argv[0].type == .string);
    std.debug.assert(argv[1].type == .resource);

    const desktop = try argv[1].value.resource.cast(.desktop);

    std.log.info("using desktop {}", .{desktop});

    try load_textures();

    const window = try ashet.gui.create_window(
        desktop,
        .{
            .title = "Dungeon Crawl",
            .min_size = .new(screen_width, screen_height),
            .max_size = .new(screen_width, screen_height),
            .initial_size = .new(screen_width, screen_height),
        },
    );
    defer window.destroy_now();

    const framebuffer = try ashet.graphics.create_window_framebuffer(window);
    defer framebuffer.release();

    var command_queue = try ashet.graphics.CommandQueue.init(ashet.process.mem.allocator());
    defer command_queue.deinit();

    try render(&command_queue, framebuffer);

    var rotate_enable = false;
    var move_enable = false;

    var last_mouse: ashet.abi.Point = undefined;

    const frame_time = ashet.clock.Duration.from_us(std.time.us_per_s / 20);

    var timer: ashet.clock.Timer = .{
        .inputs = .{
            .timeout = ashet.clock.monotonic(),
        },
    };

    var get_event: ashet.gui.GetWindowEvent = .{
        .inputs = .{ .window = window },
    };

    var moved = false;

    try ashet.overlapped.schedule(&get_event.arc);
    try ashet.overlapped.schedule(&timer.arc);

    while (true) {
        const completed = try ashet.overlapped.await_events(.{
            .timer = &timer,
            .get_event = &get_event,
        });

        if (completed.contains(.get_event)) {
            const event = get_event.outputs.event;
            switch (event.event_type) {
                .mouse_leave => {
                    move_enable = false;
                    rotate_enable = false;
                },

                .mouse_motion => {
                    const pos: ashet.abi.Point = .new(event.mouse.x, event.mouse.y);
                    defer last_mouse = pos;

                    const dx: f32 = @floatFromInt(pos.x - last_mouse.x);
                    const dy: f32 = @floatFromInt(pos.y - last_mouse.y);

                    if (((dx != 0) or (dy != 0)) and move_enable) {
                        const fwd = Vec2.unitX.rotate(raycaster.camera_rotation).scale(0.01);
                        const right = Vec2.unitY.rotate(raycaster.camera_rotation).scale(-0.01);

                        raycaster.camera_position = raycaster.camera_position.add(fwd.scale(dy));
                        raycaster.camera_position = raycaster.camera_position.sub(right.scale(dx));

                        moved = true;
                    }

                    if (dx != 0 and rotate_enable) {
                        raycaster.camera_rotation += 0.03 * dx;
                        moved = true;
                    }
                },

                .mouse_button_press => {
                    last_mouse = .new(event.mouse.x, event.mouse.y);
                    switch (event.mouse.button) {
                        .left => rotate_enable = true,
                        .right => move_enable = true,
                        else => {},
                    }
                },

                .mouse_button_release => switch (event.mouse.button) {
                    .left => rotate_enable = false,
                    .right => move_enable = false,
                    else => {},
                },

                .key_press => {
                    moved = true;

                    const fwd = Vec2.unitX.rotate(raycaster.camera_rotation).scale(0.1);
                    const right = Vec2.unitY.rotate(raycaster.camera_rotation).scale(0.1);

                    switch (event.keyboard.key) {
                        .escape => return,

                        .up => raycaster.camera_position = raycaster.camera_position.add(fwd),
                        .down => raycaster.camera_position = raycaster.camera_position.sub(fwd),

                        .left => raycaster.camera_position = raycaster.camera_position.sub(right),
                        .right => raycaster.camera_position = raycaster.camera_position.add(right),

                        .page_up => raycaster.camera_rotation -= 0.1,
                        .page_down => raycaster.camera_rotation += 0.1,

                        else => moved = false,
                    }
                },
                .window_close => return,
                else => {},
            }

            try ashet.overlapped.schedule(&get_event.arc);
        }

        if (completed.contains(.timer)) {
            if (moved) {
                try render(&command_queue, framebuffer);
            }
            moved = false;

            const now = ashet.clock.monotonic();
            const timeout = &timer.inputs.timeout;
            while (timeout.lt(now)) {
                timeout.* = timeout.increment_by(frame_time);
            }

            try ashet.overlapped.schedule(&timer.arc);
        }
    }
}

var clonebuffer: [screen_width * screen_height]Color align(4) = undefined;

inline fn set_pixel(x: u16, y: u16, c: Color) void {
    clonebuffer[@as(usize, y) * screen_width + x] = c;
}

fn render(q: *ashet.graphics.CommandQueue, fb: ashet.graphics.Framebuffer) !void {
    const bmp = ashet.graphics.Bitmap{
        .width = screen_width,
        .height = screen_height,
        .stride = screen_width,
        .pixels = &clonebuffer,
        .has_transparency = false,
        .transparency_key = .black,
    };
    @memset(&clonebuffer, Color.black);

    raycaster.drawWalls();

    raycaster.sortSprites(&sprites);
    raycaster.drawSprites(&sprites);

    try q.blit_bitmap(.zero, &bmp);

    try q.submit(fb, .{});
}

const Texture = ashet.graphics.Bitmap;

inline fn branchClamp(x: i32, limit: u16) u32 {
    return if (limit & (limit - 1) == 0)
        @as(u32, @bitCast(x)) & (limit - 1)
    else
        @as(u32, @bitCast(x)) % limit;
}

pub inline fn sampleTexture(tex: *const Texture, x: i32, y: i32) Color {
    @setRuntimeSafety(false);
    const u = branchClamp(x, tex.width);
    const v = branchClamp(y, tex.height);
    return tex.pixels[v * tex.stride + u];
}

var textures: [9]Texture = undefined;

fn load_textures() !void {
    var assets_dir = try ashet.fs.Directory.openDrive(.system, "apps/dungeon/data");
    defer assets_dir.close();

    textures[0] = try load_texture(assets_dir, "floor.abm");
    textures[1] = try load_texture(assets_dir, "wall-plain.abm");
    textures[2] = try load_texture(assets_dir, "wall-cobweb.abm");
    textures[3] = try load_texture(assets_dir, "wall-paper.abm");
    textures[4] = try load_texture(assets_dir, "wall-vines.abm");
    textures[5] = try load_texture(assets_dir, "wall-door.abm");
    textures[6] = try load_texture(assets_dir, "wall-post-l.abm");
    textures[7] = try load_texture(assets_dir, "wall-post-r.abm");
    textures[8] = try load_texture(assets_dir, "enforcer.abm");
}

fn load_texture(dir: ashet.fs.Directory, path: []const u8) !Texture {
    var file = try dir.openFile(path, .read_only, .open_existing);
    defer file.close();

    return try ashet.graphics.load_bitmap_file(ashet.process.mem.allocator(), file);
}

const palette = blk: {
    var pal: [256]ashet.abi.Color = undefined;
    for (textures, 0..) |tex, i| {
        std.mem.copyForwards(
            ashet.abi.Color,
            pal[16 * i ..],
            tex.palette,
        );
    }
    pal[255] = ashet.abi.Color.fromRgb888(0x80, 0xCC, 0xFF);
    break :blk pal;
};

const Sprite = struct {
    texture_id: u16,
    position: Vec2,
};

const Wall = struct {
    texture_id: u16,
    points: [2]Vec2,
    u_offset: [2]f32,
};

const Raycaster = struct {
    const BackgroundPattern = union(enum) {
        background_texture: usize,
        perspective_texture: usize,
        flat_color: Color,
    };

    const width = screen_width;
    const height = screen_height;
    const aspect = @as(f32, @floatFromInt(screen_width)) / @as(f32, @floatFromInt(screen_height));

    const floor_texture: BackgroundPattern = .{ .perspective_texture = 0 };
    const ceiling_texture: BackgroundPattern = .{ .flat_color = Color.from_rgb(255, 255, 255) };

    camera_rotation: f32 = 0,
    camera_position: Vec2 = Vec2.zero,
    zbuffer: [width]f32 = undefined,

    /// returns the direction a ray has when going through a specifc column
    fn getRayDirection(rc: Raycaster, column: usize) Vec2 {
        return Vec2.new(1.0, protorays[column]).rotate(rc.camera_rotation);
    }

    const protorays = blk: {
        @setEvalBranchQuota(10_000);

        var rays: [width]f32 = undefined;
        for (&rays, 0..) |*dir, x| {
            const fx = aspect * (2.0 * (@as(f32, @floatFromInt(x)) / (width - 1)) - 1.0);

            const deltaAngle = std.math.atan(0.5 * fx);

            const raw_dir = Vec2.unitX.rotate(deltaAngle);

            // set length of x to 1 for early correct perspective correction
            dir.* = raw_dir.scale(1.0 / raw_dir.x).y; // .x  is always 1.0 after this scaling. Thus, we don't need to store it.
        }

        break :blk rays;
    };

    const RaycastResult = struct {
        wall: *const Wall,
        distance: f32,
        u: f32,
    };

    const perspective_factor: [height]f32 = blk: {
        var val: [height]f32 = undefined;
        for (&val, 0..) |*v, y| {
            if (y < height / 2) {
                const scale = 2.0 / @as(f32, @floatFromInt(height - 1));
                const fy = 1.0 - scale * @as(f32, @floatFromInt(y));

                if (fy == 0)
                    continue;

                v.* = 1.0 / fy;
            } else {
                const fy = (1.0 / @as(f32, @floatFromInt(height / 2))) * @as(f32, @floatFromInt(y - (height / 2) + 1));

                if (fy == 0)
                    continue;

                v.* = 1.0 / fy;
            }
        }

        break :blk val;
    };

    fn drawWalls(rc: *Raycaster) void {

        // render the walls
        var x: u15 = 0;
        while (x < width) : (x += 1) {
            // std.log.info("cast {}...", .{x});
            // rotate our precalculated ray
            const dir = rc.getRayDirection(x);

            // Raycast here
            var maybe_hit = castRay(rc.camera_position, dir);

            var wallHeight: u32 = 0;
            rc.zbuffer[x] = if (maybe_hit) |result| blk: {
                // std.log.info("hit {}", .{result});
                if (result.distance < 0.01) {
                    // znear discard
                    maybe_hit = null;
                    break :blk std.math.inf(f32);
                }

                // project the wall height onto the screen and
                // adjust the zbuffer
                wallHeight = @as(u32, @intFromFloat(height / @abs(result.distance) + 0.5));
                // std.log.info("x={} => d={d} => {}", .{ x, result.distance, wallHeight });
                break :blk result.distance;
            } else std.math.inf(f32); // no hit means infinite distance

            // calculate screen boundaries of the wall
            const wallTop = @as(i32, @intCast(height / 2)) - @as(i32, @intCast(wallHeight / 2));
            const wallBottom = @as(i32, @intCast(height / 2)) + @as(i32, @intCast(wallHeight / 2));

            // Draw ceiling
            switch (ceiling_texture) {
                .background_texture => unreachable,
                .flat_color => |color| {
                    var y: u15 = 0;
                    while (y < wallTop) : (y += 1) {
                        set_pixel(x, y, color);
                    }
                },
                .perspective_texture => |texture_id| {
                    const index_shift = 16 * texture_id;
                    const texture = &textures[texture_id];

                    const u_scale = @as(f32, @floatFromInt(texture.bitmap.width - 1));
                    const v_scale = @as(f32, @floatFromInt(texture.bitmap.height - 1));

                    var y: u15 = 0;
                    while (y < wallTop) : (y += 1) {
                        const d = perspective_factor[y];

                        const pos = rc.camera_position.add(dir.scale(d));

                        const u = @as(i32, @intFromFloat(u_scale * fract(pos.x)));
                        const v = @as(i32, @intFromFloat(v_scale * fract(pos.y)));

                        set_pixel(x, y, sampleTexture(texture, u, v).shift(index_shift));
                    }
                },
            }

            // Draw the wall
            if (maybe_hit) |result| {
                const tex_id = result.wall.texture_id;
                const texture = &textures[tex_id];

                const u = @as(i32, @intFromFloat(@as(f32, @floatFromInt(texture.width - 1)) * fract(result.u)));

                const maxy = @min(height, wallBottom);

                var y: u15 = @as(u15, @intCast(std.math.clamp(wallTop, 0, height)));
                while (y < maxy) : (y += 1) {
                    const v = @as(i32, @intCast(@divTrunc(texture.height * (y - wallTop), @as(i32, @intCast(wallHeight)))));
                    set_pixel(x, y, sampleTexture(texture, u, v));
                }
            }

            // Draw floor
            switch (floor_texture) {
                .background_texture => unreachable,
                .flat_color => |color| {
                    var y: u15 = @as(u15, @intCast(@min(height, wallBottom)));
                    while (y < height) : (y += 1) {
                        set_pixel(x, y, color);
                    }
                },
                .perspective_texture => |texture_id| {
                    const texture = &textures[texture_id];

                    const u_scale = @as(f32, @floatFromInt(texture.width - 1));
                    const v_scale = @as(f32, @floatFromInt(texture.height - 1));

                    var y: u15 = @as(u15, @intCast(@min(height, wallBottom)));
                    while (y < height) : (y += 1) {
                        const d = perspective_factor[y];

                        const pos = rc.camera_position.add(dir.scale(d));

                        const u = @as(i32, @intFromFloat(u_scale * fract(pos.x)));
                        const v = @as(i32, @intFromFloat(v_scale * fract(pos.y)));

                        set_pixel(x, y, sampleTexture(texture, u, v));
                    }
                },
            }
        }
    }

    fn sortSprites(rc: *const Raycaster, spriteset: []Sprite) void {
        std.sort.block(Sprite, spriteset, rc, struct {
            fn lt(this: *const Raycaster, lhs: Sprite, rhs: Sprite) bool {
                // "a < b"
                return Vec2.distance2(lhs.position, this.camera_position) < Vec2.distance2(rhs.position, this.camera_position);
            }
        }.lt);
    }

    fn drawSprites(rc: Raycaster, spriteset: []const Sprite) void {
        for (spriteset) |sprite| {
            rc.drawSprite(sprite);
        }
    }

    fn ang(a: f32) f32 {
        return @mod((a + std.math.pi), std.math.tau) - std.math.pi;
    }

    fn angdiff(lhs: f32, rhs: f32) f32 {
        return ang(lhs - rhs);
    }

    fn drawSprite(rc: Raycaster, sprite: Sprite) void {
        const delta = sprite.position.sub(rc.camera_position);
        const angle = angdiff(std.math.atan2(delta.y, delta.x), rc.camera_rotation);

        if (@abs(angle) > std.math.pi / 2.0)
            return;

        const distance2 = delta.length2();
        if (distance2 < 0.0025) // 0.05²
            return; // discard early

        const distance = @sqrt(distance2);

        // if(distance > 100)
        //  return; // discard far objects

        const fx = 2.0 * @tan(angle) / aspect;

        const cx = @as(i32, @intFromFloat((width - 1) * (0.5 + 0.5 * fx)));

        const texture = &textures[sprite.texture_id];

        // calculate perspective correction
        const correction = @sqrt(0.5 * fx * fx + 1);

        // calculate on-screen size
        const spriteHeight = @as(u31, @intFromFloat(correction * height / distance));
        const spriteWidth = (texture.width * spriteHeight) / texture.height;

        // discard the sprite when out of screen
        if ((cx + spriteWidth) < 0)
            return;
        if ((cx - spriteWidth) >= width)
            return;

        // calculate screen positions and boundaries
        const wallTop = (height / 2) - @as(i32, spriteHeight / 2);
        const wallBottom = wallTop + spriteHeight;

        const left = cx - spriteWidth / 2;

        const minx = @max(0, left);
        const maxx = @min(width - 1, cx + spriteWidth / 2);

        const miny = @max(0, wallTop);
        const maxy = @min(height, wallBottom);

        // render the sprite also column major
        var x: u15 = @as(u15, @intCast(std.math.clamp(minx, 0, width)));
        while (x < maxx) : (x += 1) {
            // Test if we are occluded by a sprite
            if (rc.zbuffer[x] < distance)
                continue;

            const u = @divTrunc((texture.width - 1) * (x - left), spriteWidth - 1);

            var y: u15 = @as(u15, @intCast(std.math.clamp(miny, 0, height)));
            while (y < maxy) : (y += 1) {
                const v = @as(i32, @intFromFloat(@as(f32, @floatFromInt((texture.height - 1) * (y - wallTop))) / @as(f32, @floatFromInt(spriteHeight - 1))));

                const c = sampleTexture(texture, u, v);

                // alpha testing
                if (texture.has_transparency and c == texture.transparency_key)
                    continue;

                set_pixel(x, y, c);
            }
        }
    }

    inline fn fract(v: f32) f32 {
        return v - @floor(v);
    }

    fn intersect(ray_pos: Vec2, ray_dir: Vec2, line_start: Vec2, line_offset: Vec2, t: *f32, u: *f32) bool {
        const d = Vec2.cross(ray_dir, line_offset);
        const v = line_start.sub(ray_pos);

        if (d == 0) // parallel or colinear
            return false;

        t.* = Vec2.cross(v, line_offset) / d;
        u.* = Vec2.cross(v, ray_dir) / d;

        return (t.* >= 0.0) and (u.* >= 0.0 and u.* <= 1.0);
    }

    fn castRay(pos: Vec2, dir: Vec2) ?RaycastResult {
        var nearest: ?RaycastResult = null;

        for (&walls) |*wall| {
            var t: f32 = undefined;
            var u: f32 = undefined;
            if (!intersect(pos, dir, wall.points[0], wall.points[1].sub(wall.points[0]), &t, &u))
                continue;

            // std.log.info("wall hit with {} distance", .{t});

            if ((nearest == null) or (nearest.?.distance > t)) {
                nearest = RaycastResult{
                    .distance = t,
                    .wall = wall,
                    .u = wall.u_offset[0] + u * (wall.u_offset[1] - wall.u_offset[0]),
                };
            }
        }

        return nearest;
    }
};
