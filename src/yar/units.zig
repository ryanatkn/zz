const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;
const types = @import("types.zig");
const physics = @import("physics.zig");
const input = @import("input.zig");
const world = @import("world.zig");

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

    // Update position with collision checking
    const newX = gameState.player.position.x + movement.x * types.PLAYER_SPEED * deltaTime;
    const newY = gameState.player.position.y + movement.y * types.PLAYER_SPEED * deltaTime;

    // Check X movement
    const testPosX = raylib.Vector2{ .x = newX, .y = gameState.player.position.y };
    if (!world.isPositionBlocked(gameState, testPosX, gameState.player.radius)) {
        gameState.player.position.x = newX;
    }

    // Check Y movement
    const testPosY = raylib.Vector2{ .x = gameState.player.position.x, .y = newY };
    if (!world.isPositionBlocked(gameState, testPosY, gameState.player.radius)) {
        gameState.player.position.y = newY;
    }

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

            // Check for obstacle collision before moving
            const newX = gameState.enemies[i].position.x + direction.x * types.ENEMY_SPEED * deltaTime;
            const newY = gameState.enemies[i].position.y + direction.y * types.ENEMY_SPEED * deltaTime;

            // Check X movement
            const testPosX = raylib.Vector2{ .x = newX, .y = gameState.enemies[i].position.y };
            if (!world.isPositionBlocked(gameState, testPosX, gameState.enemies[i].radius)) {
                gameState.enemies[i].position.x = newX;
            }

            // Check Y movement
            const testPosY = raylib.Vector2{ .x = gameState.enemies[i].position.x, .y = newY };
            if (!world.isPositionBlocked(gameState, testPosY, gameState.enemies[i].radius)) {
                gameState.enemies[i].position.y = newY;
            }
        }
    }
}

pub fn checkCollisions(gameState: *types.GameState) void {
    // Bullet-Enemy collisions
    for (0..types.MAX_BULLETS) |i| {
        if (gameState.bullets[i].active) {
            for (0..types.MAX_ENEMIES) |j| {
                if (gameState.enemies[j].active) {
                    if (physics.checkCircleCircleCollision(gameState.bullets[i].position, gameState.bullets[i].radius, gameState.enemies[j].position, gameState.enemies[j].radius)) {
                        gameState.bullets[i].active = false;
                        gameState.enemies[j].active = false;
                    }
                }
            }
        }
    }

    // Player-Enemy collisions
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            if (physics.checkCircleCircleCollision(gameState.player.position, gameState.player.radius, gameState.enemies[i].position, gameState.enemies[i].radius)) {
                gameState.gameOver = true;
            }
        }
    }

    // Player-Deadly Obstacle collisions
    for (0..types.MAX_OBSTACLES) |i| {
        if (gameState.obstacles[i].active and gameState.obstacles[i].type == .deadly) {
            if (physics.checkCircleRectCollision(gameState.player.position, gameState.player.radius, gameState.obstacles[i].position, gameState.obstacles[i].size)) {
                gameState.gameOver = true;
            }
        }
    }

    // Enemy-Deadly Obstacle collisions
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            for (0..types.MAX_OBSTACLES) |j| {
                if (gameState.obstacles[j].active and gameState.obstacles[j].type == .deadly) {
                    if (physics.checkCircleRectCollision(gameState.enemies[i].position, gameState.enemies[i].radius, gameState.obstacles[j].position, gameState.obstacles[j].size)) {
                        gameState.enemies[i].active = false;
                    }
                }
            }
        }
    }

    // Check win condition - all enemies dead
    var allEnemiesDead = true;
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            allEnemiesDead = false;
            break;
        }
    }
    if (allEnemiesDead) {
        gameState.gameWon = true;
    }
}
