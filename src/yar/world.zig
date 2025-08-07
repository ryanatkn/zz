const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;
const types = @import("types.zig");
const physics = @import("physics.zig");

// World/obstacle management functions
// Check if a position would collide with any existing units or obstacles
pub fn isPositionOccupied(gameState: *const types.GameState, pos: raylib.Vector2, radius: f32, excludePlayer: bool) bool {
    // Check against player (unless excluded)
    if (!excludePlayer and gameState.player.active) {
        if (physics.checkCircleCircleCollision(pos, radius, gameState.player.position, gameState.player.radius)) {
            return true;
        }
    }

    // Check against all enemies
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            if (physics.checkCircleCircleCollision(pos, radius, gameState.enemies[i].position, gameState.enemies[i].radius)) {
                return true;
            }
        }
    }

    // Check against all obstacles (both blocking and deadly)
    for (0..types.MAX_OBSTACLES) |i| {
        if (gameState.obstacles[i].active) {
            if (physics.checkCircleRectCollision(pos, radius, gameState.obstacles[i].position, gameState.obstacles[i].size)) {
                return true;
            }
        }
    }

    return false;
}

// Check if a rectangle position would collide with existing obstacles
pub fn isRectPositionOccupied(gameState: *const types.GameState, pos: raylib.Vector2, size: raylib.Vector2, excludePlayer: bool) bool {
    // Check against player (unless excluded)
    if (!excludePlayer and gameState.player.active) {
        if (physics.checkCircleRectCollision(gameState.player.position, gameState.player.radius, pos, size)) {
            return true;
        }
    }

    // Check against all enemies
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            if (physics.checkCircleRectCollision(gameState.enemies[i].position, gameState.enemies[i].radius, pos, size)) {
                return true;
            }
        }
    }

    // Check against all obstacles with proper rectangle-rectangle collision
    for (0..types.MAX_OBSTACLES) |i| {
        if (gameState.obstacles[i].active) {
            // Rectangle-rectangle collision check with margin
            const margin: f32 = 10.0;
            if (!(pos.x > gameState.obstacles[i].position.x + gameState.obstacles[i].size.x + margin or
                pos.x + size.x < gameState.obstacles[i].position.x - margin or
                pos.y > gameState.obstacles[i].position.y + gameState.obstacles[i].size.y + margin or
                pos.y + size.y < gameState.obstacles[i].position.y - margin))
            {
                return true;
            }
        }
    }

    return false;
}

// Check if position is blocked by blocking obstacles (for movement)
pub fn isPositionBlocked(gameState: *const types.GameState, pos: raylib.Vector2, radius: f32) bool {
    for (0..types.MAX_OBSTACLES) |i| {
        if (gameState.obstacles[i].active and gameState.obstacles[i].type == .blocking) {
            if (physics.checkCircleRectCollision(pos, radius, gameState.obstacles[i].position, gameState.obstacles[i].size)) {
                return true;
            }
        }
    }
    return false;
}

pub fn getSafeSpawnPosition(gameState: *const types.GameState, avoidPos: raylib.Vector2, minDistance: f32, entityRadius: f32) raylib.Vector2 {
    var attempts: u32 = 0;
    const maxAttempts: u32 = 100; // Increased attempts for better placement

    while (attempts < maxAttempts) {
        const minX: i32 = @intFromFloat(entityRadius);
        const maxX: i32 = @intFromFloat(types.SCREEN_WIDTH - entityRadius);
        const minY: i32 = @intFromFloat(entityRadius);
        const maxY: i32 = @intFromFloat(types.SCREEN_HEIGHT - entityRadius);

        const x: f32 = @floatFromInt(raylib.getRandomValue(minX, maxX));
        const y: f32 = @floatFromInt(raylib.getRandomValue(minY, maxY));
        const testPos = raylib.Vector2{ .x = x, .y = y };

        // Check distance from avoid position
        if (physics.vectorLength(raylib.Vector2{ .x = testPos.x - avoidPos.x, .y = testPos.y - avoidPos.y }) >= minDistance) {
            // Check if position is free from collisions
            if (!isPositionOccupied(gameState, testPos, entityRadius, false)) {
                return testPos;
            }
        }
        attempts += 1;
    }

    // Fallback: spawn at edge of screen away from player
    if (avoidPos.x < types.SCREEN_WIDTH / 2) {
        return raylib.Vector2{ .x = types.SCREEN_WIDTH - 50, .y = @floatFromInt(raylib.getRandomValue(50, @intFromFloat(types.SCREEN_HEIGHT - 50))) };
    } else {
        return raylib.Vector2{ .x = 50, .y = @floatFromInt(raylib.getRandomValue(50, @intFromFloat(types.SCREEN_HEIGHT - 50))) };
    }
}

pub fn getSafeObstaclePosition(gameState: *const types.GameState, avoidPos: raylib.Vector2, minDistance: f32, obstacleSize: raylib.Vector2) raylib.Vector2 {
    var attempts: u32 = 0;
    const maxAttempts: u32 = 100;

    while (attempts < maxAttempts) {
        const minX: i32 = 0;
        const maxX: i32 = @intFromFloat(types.SCREEN_WIDTH - obstacleSize.x);
        const minY: i32 = 0;
        const maxY: i32 = @intFromFloat(types.SCREEN_HEIGHT - obstacleSize.y);

        const x: f32 = @floatFromInt(raylib.getRandomValue(minX, maxX));
        const y: f32 = @floatFromInt(raylib.getRandomValue(minY, maxY));
        const testPos = raylib.Vector2{ .x = x, .y = y };

        // Check distance from avoid position (using obstacle center)
        const obstacleCenter = raylib.Vector2{ .x = testPos.x + obstacleSize.x / 2, .y = testPos.y + obstacleSize.y / 2 };
        if (physics.vectorLength(raylib.Vector2{ .x = obstacleCenter.x - avoidPos.x, .y = obstacleCenter.y - avoidPos.y }) >= minDistance) {
            // Check if position is free from collisions
            if (!isRectPositionOccupied(gameState, testPos, obstacleSize, false)) {
                return testPos;
            }
        }
        attempts += 1;
    }

    // Fallback: place at screen edge
    if (avoidPos.x < types.SCREEN_WIDTH / 2) {
        return raylib.Vector2{ .x = types.SCREEN_WIDTH - obstacleSize.x - 20, .y = @floatFromInt(raylib.getRandomValue(20, @intFromFloat(types.SCREEN_HEIGHT - obstacleSize.y - 20))) };
    } else {
        return raylib.Vector2{ .x = 20, .y = @floatFromInt(raylib.getRandomValue(20, @intFromFloat(types.SCREEN_HEIGHT - obstacleSize.y - 20))) };
    }
}

pub fn initializeObstacles(obstacles: *[types.MAX_OBSTACLES]types.Obstacle, playerStartPos: raylib.Vector2) void {
    // Clear all obstacles first
    for (0..types.MAX_OBSTACLES) |i| {
        obstacles[i].active = false;
    }

    for (0..types.MAX_OBSTACLES) |i| {
        const obstacleType: types.ObstacleType = if (raylib.getRandomValue(0, 1) == 0) .blocking else .deadly;
        const obstacleSize = raylib.Vector2{
            .x = @floatFromInt(raylib.getRandomValue(20, 40)),
            .y = @floatFromInt(raylib.getRandomValue(20, 40)),
        };

        // Create a temporary GameState with current obstacles for collision checking
        var tempGameState = types.GameState{
            .player = types.GameObject{
                .position = playerStartPos,
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 20.0,
                .active = true,
                .color = types.SOOTHING_BLUE,
            },
            .bullets = undefined,
            .enemies = undefined,
            .obstacles = obstacles.*,
            .gameOver = false,
            .gameWon = false,
            .allocator = undefined,
        };

        const safePos = getSafeObstaclePosition(&tempGameState, playerStartPos, types.SAFE_SPAWN_DISTANCE, obstacleSize);
        obstacles[i] = types.Obstacle{
            .position = safePos,
            .size = obstacleSize,
            .type = obstacleType,
            .active = true,
        };
    }
}
