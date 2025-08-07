const std = @import("std");
const raylib = @import("raylib.zig");
const types = @import("types.zig");
const units = @import("units.zig");
const input = @import("input.zig");
const world = @import("world.zig");

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

    // Initialize enemies
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

    // Initialize obstacles
    world.initializeObstacles(&game.obstacles, raylib.Vector2{ .x = types.SCREEN_WIDTH / 2.0, .y = types.SCREEN_HEIGHT / 2.0 });

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

    // Reset enemies
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
        units.checkCollisions(gameState);
    } else {
        if (inputState.restartPressed) {
            restart(gameState);
        }
    }
}

pub fn shouldQuit() bool {
    const inputState = input.getInputState();
    return inputState.quitPressed or raylib.windowShouldClose();
}
