const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const PLAYER_SPEED = 200.0;
const BULLET_SPEED = 400.0;
const ENEMY_SPEED = 100.0;
const MAX_BULLETS = 20;
const MAX_ENEMIES = 10;

const GameObject = struct {
    position: raylib.Vector2,
    velocity: raylib.Vector2,
    radius: f32,
    active: bool,
    color: raylib.Color,
};

const GameState = struct {
    player: GameObject,
    bullets: [MAX_BULLETS]GameObject,
    enemies: [MAX_ENEMIES]GameObject,
    score: i32,
    gameOver: bool,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        var game = Self{
            .player = GameObject{
                .position = raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 20.0,
                .active = true,
                .color = raylib.BLUE,
            },
            .bullets = undefined,
            .enemies = undefined,
            .score = 0,
            .gameOver = false,
            .allocator = allocator,
        };

        // Initialize bullets
        for (0..MAX_BULLETS) |i| {
            game.bullets[i] = GameObject{
                .position = raylib.Vector2{ .x = 0, .y = 0 },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 5.0,
                .active = false,
                .color = raylib.YELLOW,
            };
        }

        // Initialize enemies
        for (0..MAX_ENEMIES) |i| {
            game.enemies[i] = GameObject{
                .position = raylib.Vector2{
                    .x = @floatFromInt(raylib.getRandomValue(0, SCREEN_WIDTH)),
                    .y = @floatFromInt(raylib.getRandomValue(0, SCREEN_HEIGHT)),
                },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 15.0,
                .active = true,
                .color = raylib.RED,
            };
        }

        return game;
    }

    pub fn restart(self: *Self) void {
        // Reset player
        self.player.position = raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
        self.player.active = true;

        // Reset bullets
        for (0..MAX_BULLETS) |i| {
            self.bullets[i].active = false;
        }

        // Reset enemies
        for (0..MAX_ENEMIES) |i| {
            self.enemies[i].position = raylib.Vector2{
                .x = @floatFromInt(raylib.getRandomValue(0, SCREEN_WIDTH)),
                .y = @floatFromInt(raylib.getRandomValue(0, SCREEN_HEIGHT)),
            };
            self.enemies[i].active = true;
        }

        self.score = 0;
        self.gameOver = false;
    }

    pub fn updatePlayer(self: *Self, deltaTime: f32) void {
        var movement = raylib.Vector2{ .x = 0, .y = 0 };

        if (raylib.isKeyDown(raylib.KEY_W) or raylib.isKeyDown(raylib.KEY_UP)) movement.y -= 1;
        if (raylib.isKeyDown(raylib.KEY_S) or raylib.isKeyDown(raylib.KEY_DOWN)) movement.y += 1;
        if (raylib.isKeyDown(raylib.KEY_A) or raylib.isKeyDown(raylib.KEY_LEFT)) movement.x -= 1;
        if (raylib.isKeyDown(raylib.KEY_D) or raylib.isKeyDown(raylib.KEY_RIGHT)) movement.x += 1;

        // Normalize diagonal movement
        if (movement.x != 0 and movement.y != 0) {
            movement.x *= 0.707;
            movement.y *= 0.707;
        }

        // Update position
        self.player.position.x += movement.x * PLAYER_SPEED * deltaTime;
        self.player.position.y += movement.y * PLAYER_SPEED * deltaTime;

        // Keep player on screen
        if (self.player.position.x < self.player.radius)
            self.player.position.x = self.player.radius;
        if (self.player.position.x > SCREEN_WIDTH - self.player.radius)
            self.player.position.x = SCREEN_WIDTH - self.player.radius;
        if (self.player.position.y < self.player.radius)
            self.player.position.y = self.player.radius;
        if (self.player.position.y > SCREEN_HEIGHT - self.player.radius)
            self.player.position.y = SCREEN_HEIGHT - self.player.radius;
    }

    pub fn fireBullet(self: *Self) void {
        const mousePos = raylib.getMousePosition();
        var direction = raylib.Vector2{
            .x = mousePos.x - self.player.position.x,
            .y = mousePos.y - self.player.position.y,
        };

        const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
        if (length > 0) {
            direction.x /= length;
            direction.y /= length;
        }

        // Find inactive bullet
        for (0..MAX_BULLETS) |i| {
            if (!self.bullets[i].active) {
                self.bullets[i].position = self.player.position;
                self.bullets[i].velocity.x = direction.x * BULLET_SPEED;
                self.bullets[i].velocity.y = direction.y * BULLET_SPEED;
                self.bullets[i].active = true;
                break;
            }
        }
    }

    pub fn updateBullets(self: *Self, deltaTime: f32) void {
        for (0..MAX_BULLETS) |i| {
            if (self.bullets[i].active) {
                self.bullets[i].position.x += self.bullets[i].velocity.x * deltaTime;
                self.bullets[i].position.y += self.bullets[i].velocity.y * deltaTime;

                // Deactivate if off screen
                if (self.bullets[i].position.x < 0 or self.bullets[i].position.x > SCREEN_WIDTH or
                    self.bullets[i].position.y < 0 or self.bullets[i].position.y > SCREEN_HEIGHT)
                {
                    self.bullets[i].active = false;
                }
            }
        }
    }

    pub fn updateEnemies(self: *Self, deltaTime: f32) void {
        for (0..MAX_ENEMIES) |i| {
            if (self.enemies[i].active) {
                // Move towards player
                var direction = raylib.Vector2{
                    .x = self.player.position.x - self.enemies[i].position.x,
                    .y = self.player.position.y - self.enemies[i].position.y,
                };

                const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
                if (length > 0) {
                    direction.x /= length;
                    direction.y /= length;
                }

                self.enemies[i].position.x += direction.x * ENEMY_SPEED * deltaTime;
                self.enemies[i].position.y += direction.y * ENEMY_SPEED * deltaTime;
            }
        }
    }

    pub fn checkCollisions(self: *Self) void {
        // Bullet-Enemy collisions
        for (0..MAX_BULLETS) |i| {
            if (self.bullets[i].active) {
                for (0..MAX_ENEMIES) |j| {
                    if (self.enemies[j].active) {
                        const dx = self.bullets[i].position.x - self.enemies[j].position.x;
                        const dy = self.bullets[i].position.y - self.enemies[j].position.y;
                        const distance = math.sqrt(dx * dx + dy * dy);

                        if (distance < self.bullets[i].radius + self.enemies[j].radius) {
                            self.bullets[i].active = false;
                            self.enemies[j].active = false;
                            self.score += 10;

                            // Respawn enemy at random edge
                            const edge = raylib.getRandomValue(0, 3);
                            switch (edge) {
                                0 => { // Top
                                    self.enemies[j].position = raylib.Vector2{
                                        .x = @floatFromInt(raylib.getRandomValue(0, SCREEN_WIDTH)),
                                        .y = -50,
                                    };
                                },
                                1 => { // Right
                                    self.enemies[j].position = raylib.Vector2{
                                        .x = SCREEN_WIDTH + 50,
                                        .y = @floatFromInt(raylib.getRandomValue(0, SCREEN_HEIGHT)),
                                    };
                                },
                                2 => { // Bottom
                                    self.enemies[j].position = raylib.Vector2{
                                        .x = @floatFromInt(raylib.getRandomValue(0, SCREEN_WIDTH)),
                                        .y = SCREEN_HEIGHT + 50,
                                    };
                                },
                                3 => { // Left
                                    self.enemies[j].position = raylib.Vector2{
                                        .x = -50,
                                        .y = @floatFromInt(raylib.getRandomValue(0, SCREEN_HEIGHT)),
                                    };
                                },
                                else => {},
                            }
                            self.enemies[j].active = true;
                        }
                    }
                }
            }
        }

        // Player-Enemy collisions
        for (0..MAX_ENEMIES) |i| {
            if (self.enemies[i].active) {
                const dx = self.player.position.x - self.enemies[i].position.x;
                const dy = self.player.position.y - self.enemies[i].position.y;
                const distance = math.sqrt(dx * dx + dy * dy);

                if (distance < self.player.radius + self.enemies[i].radius) {
                    self.gameOver = true;
                }
            }
        }
    }

    pub fn draw(self: *Self) !void {
        raylib.beginDrawing();
        defer raylib.endDrawing();

        raylib.clearBackground(raylib.BLACK);

        if (!self.gameOver) {
            // Draw player
            raylib.drawCircleV(self.player.position, self.player.radius, self.player.color);

            // Draw bullets
            for (0..MAX_BULLETS) |i| {
                if (self.bullets[i].active) {
                    raylib.drawCircleV(self.bullets[i].position, self.bullets[i].radius, self.bullets[i].color);
                }
            }

            // Draw enemies
            for (0..MAX_ENEMIES) |i| {
                if (self.enemies[i].active) {
                    raylib.drawCircleV(self.enemies[i].position, self.enemies[i].radius, self.enemies[i].color);
                }
            }

            // Draw UI
            const scoreText = try raylib.textFormat(self.allocator, "Score: {d}", .{self.score});
            defer self.allocator.free(scoreText);
            raylib.drawText(scoreText, 10, 10, 20, raylib.WHITE);

            raylib.drawText("WASD/Arrows: Move", 10, SCREEN_HEIGHT - 60, 16, raylib.GRAY);
            raylib.drawText("Mouse: Aim & Click to Shoot", 10, SCREEN_HEIGHT - 40, 16, raylib.GRAY);
            raylib.drawText("ESC: Quit", 10, SCREEN_HEIGHT - 20, 16, raylib.GRAY);
        } else {
            // Game over screen
            raylib.drawText("GAME OVER", SCREEN_WIDTH / 2 - 100, SCREEN_HEIGHT / 2 - 50, 40, raylib.RED);

            const finalScoreText = try raylib.textFormat(self.allocator, "Final Score: {d}", .{self.score});
            defer self.allocator.free(finalScoreText);
            raylib.drawText(finalScoreText, SCREEN_WIDTH / 2 - 80, SCREEN_HEIGHT / 2, 20, raylib.WHITE);

            raylib.drawText("Press R to restart or ESC to quit", SCREEN_WIDTH / 2 - 140, SCREEN_HEIGHT / 2 + 40, 16, raylib.GRAY);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    raylib.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "YAR - Yet Another RPG");
    defer raylib.closeWindow();

    raylib.setTargetFPS(60);

    var game = GameState.init(allocator);

    while (!raylib.windowShouldClose()) {
        const deltaTime = raylib.getFrameTime();

        if (!game.gameOver) {
            game.updatePlayer(deltaTime);

            if (raylib.isMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                game.fireBullet();
            }

            game.updateBullets(deltaTime);
            game.updateEnemies(deltaTime);
            game.checkCollisions();
        } else {
            if (raylib.isKeyPressed(raylib.KEY_R)) {
                game.restart();
            }
        }

        if (raylib.isKeyPressed(raylib.KEY_ESCAPE)) break;

        try game.draw();
    }
}
