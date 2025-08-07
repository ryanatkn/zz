const std = @import("std");
const raylib = @import("raylib.zig");
const types = @import("types.zig");
const units = @import("units.zig");
const input = @import("input.zig");
const world = @import("world.zig");
const physics = @import("physics.zig");

pub fn init(allocator: std.mem.Allocator) types.GameState {
    var game = types.GameState{
        .player = types.GameObject{
            .position = raylib.Vector2{ .x = types.SCREEN_WIDTH / 2.0, .y = types.SCREEN_HEIGHT / 2.0 },
            .velocity = raylib.Vector2{ .x = 0, .y = 0 },
            .radius = 20.0,
            .active = true,
            .color = types.SOOTHING_BLUE,
        },
        .bullets = undefined,
        .enemies = undefined,
        .obstacles = undefined,
        .gameOver = false,
        .gameWon = false,
        .allocator = allocator,
    };

    // Initialize bullets
    for (0..types.MAX_BULLETS) |i| {
        game.bullets[i] = types.GameObject{
            .position = raylib.Vector2{ .x = 0, .y = 0 },
            .velocity = raylib.Vector2{ .x = 0, .y = 0 },
            .radius = 5.0,
            .active = false,
            .color = types.SOOTHING_YELLOW,
        };
    }

    // Initialize obstacles FIRST to avoid enemies spawning on them
    world.initializeObstacles(&game.obstacles, raylib.Vector2{ .x = types.SCREEN_WIDTH / 2.0, .y = types.SCREEN_HEIGHT / 2.0 });

    // Initialize enemies AFTER obstacles
    for (0..types.MAX_ENEMIES) |i| {
        const safePos = world.getSafeSpawnPosition(&game, raylib.Vector2{ .x = types.SCREEN_WIDTH / 2.0, .y = types.SCREEN_HEIGHT / 2.0 }, types.SAFE_SPAWN_DISTANCE, 15.0);
        game.enemies[i] = types.GameObject{
            .position = safePos,
            .velocity = raylib.Vector2{ .x = 0, .y = 0 },
            .radius = 15.0,
            .active = true,
            .color = types.SOOTHING_RED,
        };
    }

    return game;
}

pub fn restart(gameState: *types.GameState) void {
    // Reset player
    gameState.player.position = raylib.Vector2{ .x = types.SCREEN_WIDTH / 2.0, .y = types.SCREEN_HEIGHT / 2.0 };
    gameState.player.active = true;

    // Reset bullets
    for (0..types.MAX_BULLETS) |i| {
        gameState.bullets[i].active = false;
    }

    // Reinitialize obstacles FIRST
    world.initializeObstacles(&gameState.obstacles, raylib.Vector2{ .x = types.SCREEN_WIDTH / 2.0, .y = types.SCREEN_HEIGHT / 2.0 });

    // Reset enemies AFTER obstacles to ensure they don't spawn on obstacles
    for (0..types.MAX_ENEMIES) |i| {
        const safePos = world.getSafeSpawnPosition(gameState, raylib.Vector2{ .x = types.SCREEN_WIDTH / 2.0, .y = types.SCREEN_HEIGHT / 2.0 }, types.SAFE_SPAWN_DISTANCE, 15.0);
        gameState.enemies[i].position = safePos;
        gameState.enemies[i].active = true;
    }

    gameState.gameOver = false;
    gameState.gameWon = false;
}

pub fn update(gameState: *types.GameState, deltaTime: f32) void {
    const inputState = input.getInputState();

    if (!gameState.gameOver and !gameState.gameWon) {
        units.updatePlayer(gameState, inputState, deltaTime);

        if (inputState.rightMousePressed) {
            units.fireBullet(gameState, inputState);
        }

        units.updateBullets(gameState, deltaTime);
        units.updateEnemies(gameState, deltaTime);

        // Handle all collision detection and game state changes
        checkCollisionsAndGameState(gameState);
    } else {
        if (inputState.restartPressed) {
            restart(gameState);
        }
    }
}

// Centralized collision detection and game state management
fn checkCollisionsAndGameState(gameState: *types.GameState) void {
    // Bullet-Enemy collisions
    physics.checkBulletEnemyCollisions(gameState.bullets[0..], gameState.enemies[0..]);

    // Player-Enemy collisions
    if (physics.checkPlayerEnemyCollision(&gameState.player, gameState.enemies[0..])) {
        gameState.gameOver = true;
        return; // Exit early if game over
    }

    // Player-Deadly Obstacle collisions
    if (physics.checkPlayerObstacleCollision(&gameState.player, gameState.obstacles[0..])) {
        gameState.gameOver = true;
        return; // Exit early if game over
    }

    // Enemy-Deadly Obstacle collisions
    physics.checkEnemyObstacleCollisions(gameState.enemies[0..], gameState.obstacles[0..]);

    // Check win condition - all enemies dead
    if (checkWinCondition(gameState)) {
        gameState.gameWon = true;
    }
}

// Game state logic - moved from units.zig
fn checkWinCondition(gameState: *const types.GameState) bool {
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            return false;
        }
    }
    return true;
}

pub fn shouldQuit() bool {
    const inputState = input.getInputState();
    return inputState.quitPressed or raylib.windowShouldClose();
}
