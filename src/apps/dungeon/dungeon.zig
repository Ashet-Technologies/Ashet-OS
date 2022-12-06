const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const Vec2 = @import("Vector2.zig");

pub usingnamespace ashet.core;

const ColorIndex = ashet.abi.ColorIndex;

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
    if (!ashet.video.acquire()) {
        ashet.process.exit(1);
    }

    ashet.video.setResolution(400, 300);
    ashet.video.setBorder(ColorIndex.get(2));

    render();

    while (true) {
        var moved = false;
        const event = try ashet.input.getEvent();
        switch (event) {
            .mouse => |data| std.log.info("mouse => {}", .{data}),
            .keyboard => |data| {
                if (data.pressed and data.key == .escape)
                    return;
                // std.log.info("keyboard: pressed={}, alt={}, shift={}, ctrl={}, altgr={}, scancode={d: >3}, key={s: <10}, text='{?s}'", .{
                //     @boolToInt(data.pressed),
                //     @boolToInt(data.modifiers.alt),
                //     @boolToInt(data.modifiers.shift),
                //     @boolToInt(data.modifiers.ctrl),
                //     @boolToInt(data.modifiers.alt_graph),
                //     data.scancode,
                //     @tagName(data.key),
                //     data.text,
                // });
                if (data.pressed) {
                    moved = true;

                    const fwd = Vec2.unitX.rotate(raycaster.camera_rotation).scale(0.1);
                    const right = Vec2.unitY.rotate(raycaster.camera_rotation).scale(0.1);

                    switch (data.key) {
                        .up => raycaster.camera_position = raycaster.camera_position.add(fwd),
                        .down => raycaster.camera_position = raycaster.camera_position.sub(fwd),

                        .left => raycaster.camera_position = raycaster.camera_position.sub(right),
                        .right => raycaster.camera_position = raycaster.camera_position.add(right),

                        .page_up => raycaster.camera_rotation -= 0.1,
                        .page_down => raycaster.camera_rotation += 0.1,

                        else => moved = false,
                    }
                }
            },
        }
        if (moved) {
            render();
        }
    }
}

const screen_width = 400;
const screen_height = 300;

var clonebuffer: [screen_width * screen_height]ColorIndex = undefined;

fn render() void {
    std.mem.set(ColorIndex, &clonebuffer, ColorIndex.get(0));

    const fb = gui.Framebuffer{
        .width = screen_width,
        .height = screen_height,
        .stride = screen_width,
        .pixels = &clonebuffer,
    };

    raycaster.drawWalls(fb);

    raycaster.sortSprites(&sprites);
    raycaster.drawSprites(fb, &sprites);

    // double buffering:
    std.mem.copy(ashet.abi.Color, ashet.video.getPaletteMemory(), &palette);
    std.mem.copy(ColorIndex, ashet.video.getVideoMemory()[0..clonebuffer.len], &clonebuffer);
}

const Texture = gui.Bitmap.EmbeddedBitmap;

fn loadTexture(comptime path: []const u8) Texture {
    return gui.Bitmap.embed(@embedFile(path));
}

inline fn branchClamp(x: i32, limit: u16) u32 {
    return if (limit & (limit - 1) == 0)
        @bitCast(u32, x) & (limit - 1)
    else
        @bitCast(u32, x) % limit;
}

pub inline fn sampleTexture(tex: *const Texture, x: i32, y: i32) ColorIndex {
    @setRuntimeSafety(false);
    const u = branchClamp(x, tex.bitmap.width);
    const v = branchClamp(y, tex.bitmap.height);
    return tex.bitmap.pixels[v * tex.bitmap.stride + u];
}

const textures = [_]Texture{
    loadTexture("data/floor.abm"), // 0
    loadTexture("data/wall-plain.abm"), // 1
    loadTexture("data/wall-cobweb.abm"), // 2
    loadTexture("data/wall-paper.abm"), // 3
    loadTexture("data/wall-vines.abm"), // 4
    loadTexture("data/wall-door.abm"), // 5
    loadTexture("data/wall-post-l.abm"), // 6
    loadTexture("data/wall-post-r.abm"), // 7
    loadTexture("data/enforcer.abm"), // 8
};

const palette = blk: {
    var pal: [256]ashet.abi.Color = undefined;
    for (textures) |tex, i| {
        std.mem.copy(
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
        flat_color: ColorIndex,
    };

    const width = screen_width;
    const height = screen_height;
    const aspect = @intToFloat(f32, screen_width) / @intToFloat(f32, screen_height);

    const floor_texture: BackgroundPattern = .{ .perspective_texture = 0 };
    const ceiling_texture: BackgroundPattern = .{ .flat_color = ColorIndex.get(255) };

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
        for (rays) |*dir, x| {
            const fx = aspect * (2.0 * (@intToFloat(f32, x) / (width - 1)) - 1.0);

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
        for (val) |*v, y| {
            if (y < height / 2) {
                const scale = 2.0 / @intToFloat(f32, height - 1);
                const fy = 1.0 - scale * @intToFloat(f32, y);

                if (fy == 0)
                    continue;

                v.* = 1.0 / fy;
            } else {
                const fy = (1.0 / @intToFloat(f32, height / 2)) * @intToFloat(f32, y - (height / 2) + 1);

                if (fy == 0)
                    continue;

                v.* = 1.0 / fy;
            }
        }

        break :blk val;
    };

    fn drawWalls(rc: *Raycaster, fb: gui.Framebuffer) void {
        std.debug.assert(fb.width == width);
        std.debug.assert(fb.height == height);

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
                wallHeight = @floatToInt(u32, height / @fabs(result.distance) + 0.5);
                // std.log.info("x={} => d={d} => {}", .{ x, result.distance, wallHeight });
                break :blk result.distance;
            } else std.math.inf(f32); // no hit means infinite distance

            // calculate screen boundaries of the wall
            const wallTop = @intCast(i32, height / 2) - @intCast(i32, wallHeight / 2);
            const wallBottom = @intCast(i32, height / 2) + @intCast(i32, wallHeight / 2);

            // Draw ceiling
            switch (ceiling_texture) {
                .background_texture => unreachable,
                .flat_color => |color| {
                    var y: u15 = 0;
                    while (y < wallTop) : (y += 1) {
                        fb.setPixel(x, y, color);
                    }
                },
                .perspective_texture => |texture_id| {
                    const index_shift = 16 * texture_id;
                    const texture = &textures[texture_id];

                    const u_scale = @intToFloat(f32, texture.bitmap.width - 1);
                    const v_scale = @intToFloat(f32, texture.bitmap.height - 1);

                    var y: u15 = 0;
                    while (y < wallTop) : (y += 1) {
                        const d = perspective_factor[y];

                        const pos = rc.camera_position.add(dir.scale(d));

                        const u = @floatToInt(i32, u_scale * fract(pos.x));
                        const v = @floatToInt(i32, v_scale * fract(pos.y));

                        fb.setPixel(x, y, sampleTexture(texture, u, v).shift(index_shift));
                    }
                },
            }

            // Draw the wall
            if (maybe_hit) |result| {
                const tex_id = result.wall.texture_id;
                const texture = &textures[tex_id];

                const index_shift = @intCast(u8, 16 * tex_id);

                const u = @floatToInt(i32, @intToFloat(f32, texture.bitmap.width - 1) * fract(result.u));

                const maxy = std.math.min(height, wallBottom);

                var y: u15 = @intCast(u15, std.math.clamp(wallTop, 0, height));
                while (y < maxy) : (y += 1) {
                    const v = @intCast(i32, @divTrunc(texture.bitmap.height * (y - wallTop), @intCast(i32, wallHeight)));
                    fb.setPixel(x, y, sampleTexture(texture, u, v).shift(index_shift));
                }
            }

            // Draw floor
            switch (floor_texture) {
                .background_texture => unreachable,
                .flat_color => |color| {
                    var y: u15 = @intCast(u15, std.math.min(height, wallBottom));
                    while (y < height) : (y += 1) {
                        fb.setPixel(x, y, color);
                    }
                },
                .perspective_texture => |texture_id| {
                    const index_shift = 16 * texture_id;
                    const texture = &textures[texture_id];

                    const u_scale = @intToFloat(f32, texture.bitmap.width - 1);
                    const v_scale = @intToFloat(f32, texture.bitmap.height - 1);

                    var y: u15 = @intCast(u15, std.math.min(height, wallBottom));
                    while (y < height) : (y += 1) {
                        const d = perspective_factor[y];

                        const pos = rc.camera_position.add(dir.scale(d));

                        const u = @floatToInt(i32, u_scale * fract(pos.x));
                        const v = @floatToInt(i32, v_scale * fract(pos.y));

                        fb.setPixel(x, y, sampleTexture(texture, u, v).shift(index_shift));
                    }
                },
            }
        }
    }

    fn sortSprites(rc: *const Raycaster, spriteset: []Sprite) void {
        std.sort.sort(Sprite, spriteset, rc, struct {
            fn lt(this: *const Raycaster, lhs: Sprite, rhs: Sprite) bool {
                // "a < b"
                return Vec2.distance2(lhs.position, this.camera_position) < Vec2.distance2(rhs.position, this.camera_position);
            }
        }.lt);
    }

    fn drawSprites(rc: Raycaster, fb: gui.Framebuffer, spriteset: []const Sprite) void {
        for (spriteset) |sprite| {
            rc.drawSprite(fb, sprite);
        }
    }

    fn ang(a: f32) f32 {
        return @mod((a + std.math.pi), std.math.tau) - std.math.pi;
    }

    fn angdiff(lhs: f32, rhs: f32) f32 {
        return ang(lhs - rhs);
    }

    fn drawSprite(rc: Raycaster, fb: gui.Framebuffer, sprite: Sprite) void {
        const delta = sprite.position.sub(rc.camera_position);
        const angle = angdiff(std.math.atan2(f32, delta.y, delta.x), rc.camera_rotation);

        if (@fabs(angle) > std.math.pi / 2.0)
            return;

        const distance2 = delta.length2();
        if (distance2 < 0.0025) // 0.05²
            return; // discard early

        const distance = @sqrt(distance2);

        // if(distance > 100)
        //  return; // discard far objects

        const fx = 2.0 * @tan(angle) / aspect;

        const cx = @floatToInt(i32, (width - 1) * (0.5 + 0.5 * fx));

        const texture = &textures[sprite.texture_id];

        // calculate perspective correction
        const correction = @sqrt(0.5 * fx * fx + 1);

        // calculate on-screen size
        const spriteHeight = @floatToInt(u31, correction * height / distance);
        const spriteWidth = (texture.bitmap.width * spriteHeight) / texture.bitmap.height;

        // discard the sprite when out of screen
        if ((cx + spriteWidth) < 0)
            return;
        if ((cx - spriteWidth) >= width)
            return;

        // calculate screen positions and boundaries
        const wallTop = (height / 2) - @as(i32, spriteHeight / 2);
        const wallBottom = wallTop + spriteHeight;

        const left = cx - spriteWidth / 2;

        const minx = std.math.max(0, left);
        const maxx = std.math.min(width - 1, cx + spriteWidth / 2);

        const miny = std.math.max(0, wallTop);
        const maxy = std.math.min(height, wallBottom);

        const texture_shift = @intCast(u8, 16 * sprite.texture_id);

        // render the sprite also column major
        var x: u15 = @intCast(u15, std.math.clamp(minx, 0, width));
        while (x < maxx) : (x += 1) {
            // Test if we are occluded by a sprite
            if (rc.zbuffer[x] < distance)
                continue;

            const u = @divTrunc((texture.bitmap.width - 1) * (x - left), spriteWidth - 1);

            var y: u15 = @intCast(u15, std.math.clamp(miny, 0, height));
            while (y < maxy) : (y += 1) {
                const v = @floatToInt(i32, @intToFloat(f32, (texture.bitmap.height - 1) * (y - wallTop)) / @intToFloat(f32, spriteHeight - 1));

                const c = sampleTexture(texture, u, v);

                // alpha testing
                if (texture.bitmap.transparent != null and c == texture.bitmap.transparent.?)
                    continue;

                fb.setPixel(x, y, c.shift(texture_shift));
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

        for (walls) |*wall| {
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
