const std = @import("std");
const raylib = @import("raylib.zig");
const types = @import("types.zig");

pub fn draw(gameState: *const types.GameState) !void {
    raylib.beginDrawing();
    defer raylib.endDrawing();

    raylib.clearBackground(raylib.BLACK);

    if (!gameState.gameOver and !gameState.gameWon) {
        drawGameplay(gameState);
        try drawUI(gameState);
    } else if (gameState.gameWon) {
        drawWinScreen();
    } else {
        drawGameOverScreen();
    }
}

fn drawGameplay(gameState: *const types.GameState) void {
    // Draw player
    raylib.drawCircleV(gameState.player.position, gameState.player.radius, gameState.player.color);

    // Draw bullets
    for (0..types.MAX_BULLETS) |i| {
        if (gameState.bullets[i].active) {
            raylib.drawCircleV(gameState.bullets[i].position, gameState.bullets[i].radius, gameState.bullets[i].color);
        }
    }

    // Draw enemies
    for (0..types.MAX_ENEMIES) |i| {
        if (gameState.enemies[i].active) {
            raylib.drawCircleV(gameState.enemies[i].position, gameState.enemies[i].radius, gameState.enemies[i].color);
        }
    }

    // Draw obstacles
    for (0..types.MAX_OBSTACLES) |i| {
        if (gameState.obstacles[i].active) {
            const color = switch (gameState.obstacles[i].type) {
                .blocking => types.SOOTHING_GREEN,
                .deadly => types.SOOTHING_PURPLE,
            };
            raylib.drawRectangleV(gameState.obstacles[i].position, gameState.obstacles[i].size, color);
        }
    }
}

fn drawUI(gameState: *const types.GameState) !void {
    // Draw control instructions
    raylib.drawText("Left Click: Move | Right Click: Shoot", 10, @intFromFloat(types.SCREEN_HEIGHT - 60), 16, types.SOOTHING_GRAY);
    raylib.drawText("WASD/Arrows: Move (Alt) | ESC: Quit", 10, @intFromFloat(types.SCREEN_HEIGHT - 40), 16, types.SOOTHING_GRAY);

    // FPS Counter (top right corner)
    const fps = raylib.getFPS();
    const fpsText = try raylib.textFormat(gameState.allocator, "FPS: {d}", .{fps});
    defer gameState.allocator.free(fpsText);
    const fpsWidth = raylib.measureText(fpsText, 16);
    raylib.drawText(fpsText, @as(i32, @intFromFloat(types.SCREEN_WIDTH)) - fpsWidth - 10, 10, 16, types.SOOTHING_WHITE);
}

fn drawWinScreen() void {
    // Win screen
    raylib.drawText("YOU WIN!", @intFromFloat(types.SCREEN_WIDTH / 2 - 400), @intFromFloat(types.SCREEN_HEIGHT / 2 - 200), 160, types.SOOTHING_GREEN);
    raylib.drawText("All enemies eliminated!", @intFromFloat(types.SCREEN_WIDTH / 2 - 300), @intFromFloat(types.SCREEN_HEIGHT / 2 - 20), 48, types.SOOTHING_WHITE);
    raylib.drawText("Press R or Click to restart, ESC to quit", @intFromFloat(types.SCREEN_WIDTH / 2 - 480), @intFromFloat(types.SCREEN_HEIGHT / 2 + 80), 48, types.SOOTHING_GRAY);
}

fn drawGameOverScreen() void {
    // Game over screen
    raylib.drawText("GAME OVER", @intFromFloat(types.SCREEN_WIDTH / 2 - 480), @intFromFloat(types.SCREEN_HEIGHT / 2 - 200), 160, types.SOOTHING_RED);
    raylib.drawText("Press R or Click to restart, ESC to quit", @intFromFloat(types.SCREEN_WIDTH / 2 - 480), @intFromFloat(types.SCREEN_HEIGHT / 2 + 80), 48, types.SOOTHING_GRAY);
}
