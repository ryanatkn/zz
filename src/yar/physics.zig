const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;
const types = @import("types.zig");

// Physics utilities for collision detection and spatial queries
pub fn checkCircleRectCollision(circlePos: raylib.Vector2, radius: f32, rectPos: raylib.Vector2, rectSize: raylib.Vector2) bool {
    const closestX = math.clamp(circlePos.x, rectPos.x, rectPos.x + rectSize.x);
    const closestY = math.clamp(circlePos.y, rectPos.y, rectPos.y + rectSize.y);

    const dx = circlePos.x - closestX;
    const dy = circlePos.y - closestY;

    return (dx * dx + dy * dy) <= (radius * radius);
}

pub fn checkCircleCircleCollision(pos1: raylib.Vector2, radius1: f32, pos2: raylib.Vector2, radius2: f32) bool {
    const dx = pos1.x - pos2.x;
    const dy = pos1.y - pos2.y;
    const distance = math.sqrt(dx * dx + dy * dy);
    return distance < radius1 + radius2;
}

pub fn normalizeVector(vec: raylib.Vector2) raylib.Vector2 {
    const length = math.sqrt(vec.x * vec.x + vec.y * vec.y);
    if (length > 0) {
        return raylib.Vector2{ .x = vec.x / length, .y = vec.y / length };
    }
    return raylib.Vector2{ .x = 0, .y = 0 };
}

pub fn vectorLength(vec: raylib.Vector2) f32 {
    return math.sqrt(vec.x * vec.x + vec.y * vec.y);
}

pub fn clampToScreen(pos: raylib.Vector2, radius: f32) raylib.Vector2 {
    var result = pos;
    if (result.x < radius) result.x = radius;
    if (result.x > types.SCREEN_WIDTH - radius) result.x = types.SCREEN_WIDTH - radius;
    if (result.y < radius) result.y = radius;
    if (result.y > types.SCREEN_HEIGHT - radius) result.y = types.SCREEN_HEIGHT - radius;
    return result;
}

pub fn isOnScreen(pos: raylib.Vector2) bool {
    return pos.x >= 0 and pos.x <= types.SCREEN_WIDTH and
        pos.y >= 0 and pos.y <= types.SCREEN_HEIGHT;
}
