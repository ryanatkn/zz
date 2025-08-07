const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;
const types = @import("types.zig");
const physics = @import("physics.zig");

// World/obstacle management functions

// Unit type for unified spawning
pub const UnitType = enum {
    circle, // For players, enemies, bullets
    rectangle, // For obstacles
};

pub const UnitSpec = struct {
    unitType: UnitType,
    radius: f32 = 0, // For circle units
    size: raylib.Vector2 = raylib.Vector2{ .x = 0, .y = 0 }, // For rectangle units
    minDistance: f32 = 0, // Minimum distance from avoid position
    avoidPos: raylib.Vector2 = raylib.Vector2{ .x = 0, .y = 0 }, // Position to avoid
    excludePlayer: bool = false, // Whether to exclude player from collision checks
};

// Unified function to find a safe spawn position for any unit type
pub fn findSafeSpawnPosition(gameState: *const types.GameState, spec: UnitSpec) raylib.Vector2 {
    var attempts: u32 = 0;
    const maxAttempts: u32 = 100;

    while (attempts < maxAttempts) {
        var testPos: raylib.Vector2 = undefined;

        switch (spec.unitType) {
            .circle => {
                const minX: i32 = @intFromFloat(spec.radius);
                const maxX: i32 = @intFromFloat(types.SCREEN_WIDTH - spec.radius);
                const minY: i32 = @intFromFloat(spec.radius);
                const maxY: i32 = @intFromFloat(types.SCREEN_HEIGHT - spec.radius);

                const x: f32 = @floatFromInt(raylib.getRandomValue(minX, maxX));
                const y: f32 = @floatFromInt(raylib.getRandomValue(minY, maxY));
                testPos = raylib.Vector2{ .x = x, .y = y };
            },
            .rectangle => {
                const minX: i32 = 0;
                const maxX: i32 = @intFromFloat(types.SCREEN_WIDTH - spec.size.x);
                const minY: i32 = 0;
                const maxY: i32 = @intFromFloat(types.SCREEN_HEIGHT - spec.size.y);

                const x: f32 = @floatFromInt(raylib.getRandomValue(minX, maxX));
                const y: f32 = @floatFromInt(raylib.getRandomValue(minY, maxY));
                testPos = raylib.Vector2{ .x = x, .y = y };
            },
        }

        // Check distance from avoid position
        const distanceFromAvoid = switch (spec.unitType) {
            .circle => physics.vectorLength(raylib.Vector2{ .x = testPos.x - spec.avoidPos.x, .y = testPos.y - spec.avoidPos.y }),
            .rectangle => {
                // Use center of rectangle for distance calculation
                const center = raylib.Vector2{ .x = testPos.x + spec.size.x / 2, .y = testPos.y + spec.size.y / 2 };
                physics.vectorLength(raylib.Vector2{ .x = center.x - spec.avoidPos.x, .y = center.y - spec.avoidPos.y });
            },
        };

        if (distanceFromAvoid >= spec.minDistance) {
            // Check if position is free from collisions
            const isColliding = switch (spec.unitType) {
                .circle => isPositionOccupied(gameState, testPos, spec.radius, spec.excludePlayer),
                .rectangle => isRectPositionOccupied(gameState, testPos, spec.size, spec.excludePlayer),
            };

            if (!isColliding) {
                return testPos;
            }
        }
        attempts += 1;
    }

    // Fallback position based on unit type and avoid position
    return getFallbackPosition(spec);
}

// Fallback position generator when safe spawn fails
fn getFallbackPosition(spec: UnitSpec) raylib.Vector2 {
    const rightSide = spec.avoidPos.x < types.SCREEN_WIDTH / 2;

    switch (spec.unitType) {
        .circle => {
            if (rightSide) {
                return raylib.Vector2{ .x = types.SCREEN_WIDTH - 50, .y = @floatFromInt(raylib.getRandomValue(50, @intFromFloat(types.SCREEN_HEIGHT - 50))) };
            } else {
                return raylib.Vector2{ .x = 50, .y = @floatFromInt(raylib.getRandomValue(50, @intFromFloat(types.SCREEN_HEIGHT - 50))) };
            }
        },
        .rectangle => {
            if (rightSide) {
                return raylib.Vector2{ .x = types.SCREEN_WIDTH - spec.size.x - 20, .y = @floatFromInt(raylib.getRandomValue(20, @intFromFloat(types.SCREEN_HEIGHT - spec.size.y - 20))) };
            } else {
                return raylib.Vector2{ .x = 20, .y = @floatFromInt(raylib.getRandomValue(20, @intFromFloat(types.SCREEN_HEIGHT - spec.size.y - 20))) };
            }
        },
    }
}

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

pub fn getSafeSpawnPosition(gameState: *const types.GameState, avoidPos: raylib.Vector2, minDistance: f32, unitRadius: f32) raylib.Vector2 {
    const spec = UnitSpec{
        .unitType = .circle,
        .radius = unitRadius,
        .minDistance = minDistance,
        .avoidPos = avoidPos,
        .excludePlayer = false,
    };
    return findSafeSpawnPosition(gameState, spec);
}

pub fn getSafeObstaclePosition(gameState: *const types.GameState, avoidPos: raylib.Vector2, minDistance: f32, obstacleSize: raylib.Vector2) raylib.Vector2 {
    const spec = UnitSpec{
        .unitType = .rectangle,
        .size = obstacleSize,
        .minDistance = minDistance,
        .avoidPos = avoidPos,
        .excludePlayer = false,
    };
    return findSafeSpawnPosition(gameState, spec);
}

pub fn initializeObstacles(obstacles: *[types.MAX_OBSTACLES]types.Obstacle, playerStartPos: raylib.Vector2) void {
    // Clear all obstacles first
    for (0..types.MAX_OBSTACLES) |i| {
        obstacles[i].active = false;
    }

    // Create obstacles one by one, checking against previously placed obstacles
    for (0..types.MAX_OBSTACLES) |i| {
        const obstacleType: types.ObstacleType = if (raylib.getRandomValue(0, 1) == 0) .blocking else .deadly;
        const obstacleSize = raylib.Vector2{
            .x = @floatFromInt(raylib.getRandomValue(20, 40)),
            .y = @floatFromInt(raylib.getRandomValue(20, 40)),
        };

        // Create a minimal GameState with only the player and previously placed obstacles
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

        const spec = UnitSpec{
            .unitType = .rectangle,
            .size = obstacleSize,
            .minDistance = types.SAFE_SPAWN_DISTANCE,
            .avoidPos = playerStartPos,
            .excludePlayer = false,
        };

        const safePos = findSafeSpawnPosition(&tempGameState, spec);
        obstacles[i] = types.Obstacle{
            .position = safePos,
            .size = obstacleSize,
            .type = obstacleType,
            .active = true,
        };
    }
}
