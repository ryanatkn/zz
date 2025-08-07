const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;
const types = @import("types.zig");
const physics = @import("physics.zig");
const input = @import("input.zig");

// Unit management and behavior systems
pub fn updatePlayer(gameState: *types.GameState, inputState: input.InputState, deltaTime: f32) void {
    var movement = raylib.Vector2{ .x = 0, .y = 0 };

    // Mouse movement - move toward left click position
    if (inputState.leftMouseDown) {
        const direction = raylib.Vector2{
            .x = inputState.mousePos.x - gameState.player.position.x,
            .y = inputState.mousePos.y - gameState.player.position.y,
        };

        const length = physics.vectorLength(direction);
        if (length > 10.0) { // Only move if mouse is far enough away
            movement = physics.normalizeVector(direction);
        }
    }

    // Keyboard movement (fallback/alternative)
    if (!inputState.leftMouseDown) {
        movement = inputState.keyboardMovement;
    }

    // Calculate target position
    const targetPos = raylib.Vector2{
        .x = gameState.player.position.x + movement.x * types.PLAYER_SPEED * deltaTime,
        .y = gameState.player.position.y + movement.y * types.PLAYER_SPEED * deltaTime,
    };

    // Use physics utility for safe movement
    gameState.player.position = physics.tryMoveUnit(gameState.player.position, targetPos, gameState.player.radius, gameState);

    // Keep player on screen
    gameState.player.position = physics.clampToScreen(gameState.player.position, gameState.player.radius);
}

pub fn fireBullet(gameState: *types.GameState, inputState: input.InputState) void {
    const direction = physics.normalizeVector(raylib.Vector2{
        .x = inputState.mousePos.x - gameState.player.position.x,
        .y = inputState.mousePos.y - gameState.player.position.y,
    });

    // Find inactive bullet
    for (0..types.MAX_BULLETS) |i| {
        if (!gameState.bullets[i].active) {
            gameState.bullets[i].position = gameState.player.position;
            gameState.bullets[i].velocity.x = direction.x * types.BULLET_SPEED;
            gameState.bullets[i].velocity.y = direction.y * types.BULLET_SPEED;
            gameState.bullets[i].active = true;
            break;
        }
    }
}

pub fn updateBullets(gameState: *types.GameState, deltaTime: f32) void {
    for (0..types.MAX_BULLETS) |i| {
        if (gameState.bullets[i].active) {
            gameState.bullets[i].position.x += gameState.bullets[i].velocity.x * deltaTime;
            gameState.bullets[i].position.y += gameState.bullets[i].velocity.y * deltaTime;

            // Deactivate if off screen
            if (!physics.isOnScreen(gameState.bullets[i].position)) {
                gameState.bullets[i].active = false;
            }
        }
    }
}

pub fn updateEnemies(gameState: *types.GameState, deltaTime: f32) void {
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            // Move towards player
            const direction = physics.normalizeVector(raylib.Vector2{
                .x = gameState.player.position.x - gameState.enemies[i].position.x,
                .y = gameState.player.position.y - gameState.enemies[i].position.y,
            });

            // Calculate target position
            const targetPos = raylib.Vector2{
                .x = gameState.enemies[i].position.x + direction.x * types.ENEMY_SPEED * deltaTime,
                .y = gameState.enemies[i].position.y + direction.y * types.ENEMY_SPEED * deltaTime,
            };

            // Use physics utility for safe movement
            gameState.enemies[i].position = physics.tryMoveUnit(gameState.enemies[i].position, targetPos, gameState.enemies[i].radius, gameState);
        }
    }
}
