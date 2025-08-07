const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;

// Fixed 1080p resolution
const SCREEN_WIDTH: f32 = 1920;
const SCREEN_HEIGHT: f32 = 1080;
const PLAYER_SPEED = 200.0;
const BULLET_SPEED = 400.0;
const ENEMY_SPEED = 100.0;
const MAX_BULLETS = 20;
const MAX_ENEMIES = 10;
const MAX_OBSTACLES = 15;
const SAFE_SPAWN_DISTANCE = 150.0; // Minimum distance from player for safe spawning

// Vibrant color palette
const SOOTHING_BLUE = raylib.Color{ .r = 0, .g = 100, .b = 255, .a = 255 };
const SOOTHING_GREEN = raylib.Color{ .r = 0, .g = 180, .b = 0, .a = 255 };
const SOOTHING_PURPLE = raylib.Color{ .r = 150, .g = 50, .b = 200, .a = 255 };
const SOOTHING_RED = raylib.Color{ .r = 255, .g = 50, .b = 50, .a = 255 };
const SOOTHING_YELLOW = raylib.Color{ .r = 255, .g = 200, .b = 0, .a = 255 };
const SOOTHING_GRAY = raylib.Color{ .r = 128, .g = 128, .b = 128, .a = 255 };
const SOOTHING_WHITE = raylib.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const SOOTHING_DARK = raylib.Color{ .r = 25, .g = 25, .b = 35, .a = 255 };

const GameObject = struct {
    position: raylib.Vector2,
    velocity: raylib.Vector2,
    radius: f32,
    active: bool,
    color: raylib.Color,
};

const ObstacleType = enum {
    blocking, // Green - blocks movement
    deadly, // Purple - kills on contact
};

const Obstacle = struct {
    position: raylib.Vector2,
    size: raylib.Vector2,
    type: ObstacleType,
    active: bool,
};

const GameState = struct {
    player: GameObject,
    bullets: [MAX_BULLETS]GameObject,
    enemies: [MAX_ENEMIES]GameObject,
    obstacles: [MAX_OBSTACLES]Obstacle,
    gameOver: bool,
    gameWon: bool,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        var game = Self{
            .player = GameObject{
                .position = raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 20.0,
                .active = true,
                .color = SOOTHING_BLUE,
            },
            .bullets = undefined,
            .enemies = undefined,
            .obstacles = undefined,
            .gameOver = false,
            .gameWon = false,
            .allocator = allocator,
        };

        // Initialize bullets
        for (0..MAX_BULLETS) |i| {
            game.bullets[i] = GameObject{
                .position = raylib.Vector2{ .x = 0, .y = 0 },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 5.0,
                .active = false,
                .color = SOOTHING_YELLOW,
            };
        }

        // Initialize enemies
        for (0..MAX_ENEMIES) |i| {
            const safePos = game.getSafeSpawnPosition(raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }, // Player start position
                SAFE_SPAWN_DISTANCE, 15.0 // Enemy radius
            );
            game.enemies[i] = GameObject{
                .position = safePos,
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 15.0,
                .active = true,
                .color = SOOTHING_RED,
            };
        }

        // Initialize obstacles
        for (0..MAX_OBSTACLES) |i| {
            const obstacleType: ObstacleType = if (raylib.getRandomValue(0, 1) == 0) .blocking else .deadly;
            const safePos = game.getSafeSpawnPosition(raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }, // Player start position
                SAFE_SPAWN_DISTANCE, 0.0 // Use 0 to indicate this is an obstacle
            );
            game.obstacles[i] = Obstacle{
                .position = safePos,
                .size = raylib.Vector2{
                    .x = @floatFromInt(raylib.getRandomValue(20, 40)),
                    .y = @floatFromInt(raylib.getRandomValue(20, 40)),
                },
                .type = obstacleType,
                .active = true,
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
            const safePos = self.getSafeSpawnPosition(raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }, // Player start position
                SAFE_SPAWN_DISTANCE, 15.0 // Enemy radius
            );
            self.enemies[i].position = safePos;
            self.enemies[i].active = true;
        }

        self.gameOver = false;
        self.gameWon = false;
    }

    fn getSafeSpawnPosition(self: *Self, avoidPos: raylib.Vector2, minDistance: f32, unitRadius: f32) raylib.Vector2 {
        var attempts: u32 = 0;
        const maxAttempts: u32 = 50; // Prevent infinite loops

        while (attempts < maxAttempts) {
            const minX: i32 = @intFromFloat(unitRadius);
            const maxX: i32 = @intFromFloat(SCREEN_WIDTH - unitRadius);
            const minY: i32 = @intFromFloat(unitRadius);
            const maxY: i32 = @intFromFloat(SCREEN_HEIGHT - unitRadius);

            const x: f32 = @floatFromInt(raylib.getRandomValue(minX, maxX));
            const y: f32 = @floatFromInt(raylib.getRandomValue(minY, maxY));
            const testPos = raylib.Vector2{ .x = x, .y = y };

            // Check distance from avoid position
            const dx = testPos.x - avoidPos.x;
            const dy = testPos.y - avoidPos.y;
            const distance = math.sqrt(dx * dx + dy * dy);

            if (distance >= minDistance) {
                // For obstacles, also check they don't overlap with existing obstacles
                if (unitRadius == 0) { // This is an obstacle (using radius 0 as indicator)
                    var overlaps = false;
                    for (0..MAX_OBSTACLES) |i| {
                        if (self.obstacles[i].active) {
                            const obstacleRight = self.obstacles[i].position.x + self.obstacles[i].size.x;
                            const obstacleBottom = self.obstacles[i].position.y + self.obstacles[i].size.y;

                            // Assume test obstacle size of 40x40 for overlap check (updated for smaller obstacles)
                            if (!(testPos.x > obstacleRight + 10 or
                                testPos.x + 40 < self.obstacles[i].position.x - 10 or
                                testPos.y > obstacleBottom + 10 or
                                testPos.y + 40 < self.obstacles[i].position.y - 10))
                            {
                                overlaps = true;
                                break;
                            }
                        }
                    }
                    if (!overlaps) return testPos;
                } else {
                    return testPos;
                }
            }
            attempts += 1;
        }

        // Fallback: spawn at edge of screen away from player
        if (avoidPos.x < SCREEN_WIDTH / 2) {
            return raylib.Vector2{ .x = SCREEN_WIDTH - 50, .y = @floatFromInt(raylib.getRandomValue(50, @intFromFloat(SCREEN_HEIGHT - 50))) };
        } else {
            return raylib.Vector2{ .x = 50, .y = @floatFromInt(raylib.getRandomValue(50, @intFromFloat(SCREEN_HEIGHT - 50))) };
        }
    }

    fn checkCircleRectCollision(self: *Self, circlePos: raylib.Vector2, radius: f32, rectPos: raylib.Vector2, rectSize: raylib.Vector2) bool {
        _ = self;
        const closestX = math.clamp(circlePos.x, rectPos.x, rectPos.x + rectSize.x);
        const closestY = math.clamp(circlePos.y, rectPos.y, rectPos.y + rectSize.y);

        const dx = circlePos.x - closestX;
        const dy = circlePos.y - closestY;

        return (dx * dx + dy * dy) <= (radius * radius);
    }

    fn isPositionBlocked(self: *Self, pos: raylib.Vector2, radius: f32) bool {
        for (0..MAX_OBSTACLES) |i| {
            if (self.obstacles[i].active and self.obstacles[i].type == .blocking) {
                if (self.checkCircleRectCollision(pos, radius, self.obstacles[i].position, self.obstacles[i].size)) {
                    return true;
                }
            }
        }
        return false;
    }
    pub fn updatePlayer(self: *Self, deltaTime: f32) void {
        var movement = raylib.Vector2{ .x = 0, .y = 0 };

        // Mouse movement - move toward left click position
        if (raylib.isMouseButtonDown(raylib.MOUSE_BUTTON_LEFT)) {
            const mousePos = raylib.getMousePosition();
            var direction = raylib.Vector2{
                .x = mousePos.x - self.player.position.x,
                .y = mousePos.y - self.player.position.y,
            };

            const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
            if (length > 10.0) { // Only move if mouse is far enough away
                direction.x /= length;
                direction.y /= length;
                movement = direction;
            }
        }

        // Keyboard movement (fallback/alternative)
        if (raylib.isKeyDown(raylib.KEY_W) or raylib.isKeyDown(raylib.KEY_UP)) movement.y -= 1;
        if (raylib.isKeyDown(raylib.KEY_S) or raylib.isKeyDown(raylib.KEY_DOWN)) movement.y += 1;
        if (raylib.isKeyDown(raylib.KEY_A) or raylib.isKeyDown(raylib.KEY_LEFT)) movement.x -= 1;
        if (raylib.isKeyDown(raylib.KEY_D) or raylib.isKeyDown(raylib.KEY_RIGHT)) movement.x += 1;

        // Normalize diagonal movement for keyboard
        if (movement.x != 0 and movement.y != 0 and !raylib.isMouseButtonDown(raylib.MOUSE_BUTTON_LEFT)) {
            movement.x *= 0.707;
            movement.y *= 0.707;
        }

        // Update position with collision checking
        const newX = self.player.position.x + movement.x * PLAYER_SPEED * deltaTime;
        const newY = self.player.position.y + movement.y * PLAYER_SPEED * deltaTime;

        // Check X movement
        const testPosX = raylib.Vector2{ .x = newX, .y = self.player.position.y };
        if (!self.isPositionBlocked(testPosX, self.player.radius)) {
            self.player.position.x = newX;
        }

        // Check Y movement
        const testPosY = raylib.Vector2{ .x = self.player.position.x, .y = newY };
        if (!self.isPositionBlocked(testPosY, self.player.radius)) {
            self.player.position.y = newY;
        }

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

                // Check for obstacle collision before moving
                const newX = self.enemies[i].position.x + direction.x * ENEMY_SPEED * deltaTime;
                const newY = self.enemies[i].position.y + direction.y * ENEMY_SPEED * deltaTime;

                // Check X movement
                const testPosX = raylib.Vector2{ .x = newX, .y = self.enemies[i].position.y };
                if (!self.isPositionBlocked(testPosX, self.enemies[i].radius)) {
                    self.enemies[i].position.x = newX;
                }

                // Check Y movement
                const testPosY = raylib.Vector2{ .x = self.enemies[i].position.x, .y = newY };
                if (!self.isPositionBlocked(testPosY, self.enemies[i].radius)) {
                    self.enemies[i].position.y = newY;
                }
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

                            // Don't respawn enemy - let player win when all are dead
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

        // Player-Deadly Obstacle collisions
        for (0..MAX_OBSTACLES) |i| {
            if (self.obstacles[i].active and self.obstacles[i].type == .deadly) {
                if (self.checkCircleRectCollision(self.player.position, self.player.radius, self.obstacles[i].position, self.obstacles[i].size)) {
                    self.gameOver = true;
                }
            }
        }

        // Enemy-Deadly Obstacle collisions
        for (0..MAX_ENEMIES) |i| {
            if (self.enemies[i].active) {
                for (0..MAX_OBSTACLES) |j| {
                    if (self.obstacles[j].active and self.obstacles[j].type == .deadly) {
                        if (self.checkCircleRectCollision(self.enemies[i].position, self.enemies[i].radius, self.obstacles[j].position, self.obstacles[j].size)) {
                            self.enemies[i].active = false;
                        }
                    }
                }
            }
        }

        // Check win condition - all enemies dead
        var allEnemiesDead = true;
        for (0..MAX_ENEMIES) |i| {
            if (self.enemies[i].active) {
                allEnemiesDead = false;
                break;
            }
        }
        if (allEnemiesDead) {
            self.gameWon = true;
        }
    }

    pub fn draw(self: *Self) !void {
        raylib.beginDrawing();
        defer raylib.endDrawing();

        raylib.clearBackground(raylib.BLACK);
        if (!self.gameOver and !self.gameWon) {
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

            // Draw obstacles
            for (0..MAX_OBSTACLES) |i| {
                if (self.obstacles[i].active) {
                    const color = switch (self.obstacles[i].type) {
                        .blocking => SOOTHING_GREEN,
                        .deadly => SOOTHING_PURPLE,
                    };
                    raylib.drawRectangleV(self.obstacles[i].position, self.obstacles[i].size, color);
                }
            }

            // Draw UI
            raylib.drawText("Left Click: Move | Right Click: Shoot", 10, @intFromFloat(SCREEN_HEIGHT - 60), 16, SOOTHING_GRAY);
            raylib.drawText("WASD/Arrows: Move (Alt) | ESC: Quit", 10, @intFromFloat(SCREEN_HEIGHT - 40), 16, SOOTHING_GRAY);

            // FPS Counter (top right corner)
            const fps = raylib.getFPS();
            const fpsText = try raylib.textFormat(self.allocator, "FPS: {d}", .{fps});
            defer self.allocator.free(fpsText);
            const fpsWidth = raylib.measureText(fpsText, 16);
            raylib.drawText(fpsText, @as(i32, @intFromFloat(SCREEN_WIDTH)) - fpsWidth - 10, 10, 16, SOOTHING_WHITE);
        } else if (self.gameWon) {
            // Win screen
            raylib.drawText("YOU WIN!", @intFromFloat(SCREEN_WIDTH / 2 - 400), @intFromFloat(SCREEN_HEIGHT / 2 - 200), 160, SOOTHING_GREEN);

            raylib.drawText("All enemies eliminated!", @intFromFloat(SCREEN_WIDTH / 2 - 300), @intFromFloat(SCREEN_HEIGHT / 2 - 20), 48, SOOTHING_WHITE);
            raylib.drawText("Press R or Click to restart, ESC to quit", @intFromFloat(SCREEN_WIDTH / 2 - 480), @intFromFloat(SCREEN_HEIGHT / 2 + 80), 48, SOOTHING_GRAY);
        } else {
            // Game over screen
            raylib.drawText("GAME OVER", @intFromFloat(SCREEN_WIDTH / 2 - 480), @intFromFloat(SCREEN_HEIGHT / 2 - 200), 160, SOOTHING_RED);

            raylib.drawText("Press R or Click to restart, ESC to quit", @intFromFloat(SCREEN_WIDTH / 2 - 480), @intFromFloat(SCREEN_HEIGHT / 2 + 80), 48, SOOTHING_GRAY);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    raylib.initWindow(@intFromFloat(SCREEN_WIDTH), @intFromFloat(SCREEN_HEIGHT), "YAR - Yet Another RPG");
    defer raylib.closeWindow();

    raylib.setTargetFPS(144);

    // Initialize game
    var game = GameState.init(allocator);

    while (!raylib.windowShouldClose()) {
        const deltaTime = raylib.getFrameTime();

        if (!game.gameOver and !game.gameWon) {
            game.updatePlayer(deltaTime);

            if (raylib.isMouseButtonPressed(raylib.MOUSE_BUTTON_RIGHT)) {
                game.fireBullet();
            }

            game.updateBullets(deltaTime);
            game.updateEnemies(deltaTime);
            game.checkCollisions();
        } else {
            // Allow mouse click restart only on game over/win screens
            if (raylib.isMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT)) {
                game.restart();
            }
        }

        // R key resets at any time
        if (raylib.isKeyPressed(raylib.KEY_R)) {
            game.restart();
        }

        if (raylib.isKeyPressed(raylib.KEY_ESCAPE)) break;

        try game.draw();
    }
}
