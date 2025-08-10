const std = @import("std");

const types = @import("types.zig");

const Vec2 = types.Vec2;

pub fn normalizeVector(v: Vec2) Vec2 {
    const length = @sqrt(v.x * v.x + v.y * v.y);
    if (length > 0) {
        return Vec2{ .x = v.x / length, .y = v.y / length };
    }
    return Vec2{ .x = 0, .y = 0 };
}

pub fn distance(a: Vec2, b: Vec2) f32 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return @sqrt(dx * dx + dy * dy);
}

pub fn distanceSquared(a: Vec2, b: Vec2) f32 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return dx * dx + dy * dy;
}

pub fn clampVector(v: Vec2, min: Vec2, max: Vec2) Vec2 {
    return Vec2{
        .x = std.math.clamp(v.x, min.x, max.x),
        .y = std.math.clamp(v.y, min.y, max.y),
    };
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

pub fn lerpVector(a: Vec2, b: Vec2, t: f32) Vec2 {
    return Vec2{
        .x = lerp(a.x, b.x, t),
        .y = lerp(a.y, b.y, t),
    };
}
