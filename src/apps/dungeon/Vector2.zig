const std = @import("std");

const Vec2 = @This();

x: f32,
y: f32,

pub fn new(x: f32, y: f32) Vec2 {
    return Vec2{ .x = x, .y = y };
}

pub const zero = Vec2{ .x = 0, .y = 1 };
pub const unitX = Vec2{ .x = 1, .y = 0 };
pub const unitY = Vec2{ .x = 0, .y = 1 };

pub fn dot(lhs: Vec2, rhs: Vec2) f32 {
    return lhs.x * rhs.x + lhs.y * rhs.y;
}

pub fn length2(val: Vec2) f32 {
    return val.x * val.x + val.y * val.y;
}

pub fn length(val: Vec2) f32 {
    return @sqrt(val.length2());
}

pub fn distance2(lhs: Vec2, rhs: Vec2) f32 {
    return lhs.sub(rhs).length2();
}

pub fn distance(lhs: Vec2, rhs: Vec2) f32 {
    return lhs.sub(rhs).length();
}

pub fn add(lhs: Vec2, rhs: Vec2) Vec2 {
    return new(lhs.x + rhs.x, lhs.y + rhs.y);
}

pub fn sub(lhs: Vec2, rhs: Vec2) Vec2 {
    return new(lhs.x - rhs.x, lhs.y - rhs.y);
}

pub fn scale(lhs: Vec2, rhs: f32) Vec2 {
    return new(lhs.x * rhs, lhs.y * rhs);
}

pub fn rotate(v: Vec2, angle: f32) Vec2 {
    const cs = @cos(angle);
    const sn = @sin(angle);
    return new(
        v.x * cs - v.y * sn,
        v.x * sn + v.y * cs,
    );
}

pub fn cross(v: Vec2, w: Vec2) f32 {
    return (v.x * w.y - v.y * w.x);
}
