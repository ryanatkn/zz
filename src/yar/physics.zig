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

// Collision detection systems - moved from units.zig for better separation of concerns
pub fn checkBulletEnemyCollisions(bullets: []types.GameObject, enemies: []types.GameObject) void {
    for (0..bullets.len) |i| {
        if (bullets[i].active) {
            for (0..enemies.len) |j| {
                if (enemies[j].active) {
                    if (checkCircleCircleCollision(bullets[i].position, bullets[i].radius, enemies[j].position, enemies[j].radius)) {
                        bullets[i].active = false;
                        enemies[j].active = false;
                    }
                }
            }
        }
    }
}

pub fn checkPlayerEnemyCollision(player: *const types.GameObject, enemies: []const types.GameObject) bool {
    for (0..enemies.len) |i| {
        if (enemies[i].active) {
            if (checkCircleCircleCollision(player.position, player.radius, enemies[i].position, enemies[i].radius)) {
                return true;
            }
        }
    }
    return false;
}

pub fn checkPlayerObstacleCollision(player: *const types.GameObject, obstacles: []const types.Obstacle) bool {
    for (0..obstacles.len) |i| {
        if (obstacles[i].active and obstacles[i].type == .deadly) {
            if (checkCircleRectCollision(player.position, player.radius, obstacles[i].position, obstacles[i].size)) {
                return true;
            }
        }
    }
    return false;
}

pub fn checkEnemyObstacleCollisions(enemies: []types.GameObject, obstacles: []const types.Obstacle) void {
    for (0..enemies.len) |i| {
        if (enemies[i].active) {
            for (0..obstacles.len) |j| {
                if (obstacles[j].active and obstacles[j].type == .deadly) {
                    if (checkCircleRectCollision(enemies[i].position, enemies[i].radius, obstacles[j].position, obstacles[j].size)) {
                        enemies[i].active = false;
                    }
                }
            }
        }
    }
}

// Utility function for safe movement with collision checking
pub fn tryMoveUnit(currentPos: raylib.Vector2, targetPos: raylib.Vector2, radius: f32, gameState: *const types.GameState) raylib.Vector2 {
    var newPos = currentPos;

    // Try X movement first
    const testPosX = raylib.Vector2{ .x = targetPos.x, .y = currentPos.y };
    if (!@import("world.zig").isPositionBlocked(gameState, testPosX, radius)) {
        newPos.x = targetPos.x;
    }

    // Try Y movement
    const testPosY = raylib.Vector2{ .x = newPos.x, .y = targetPos.y };
    if (!@import("world.zig").isPositionBlocked(gameState, testPosY, radius)) {
        newPos.y = targetPos.y;
    }

    return newPos;
}
