const std = @import("std");
const raylib = @import("raylib.zig");
const math = std.math;

// Fixed 1080p resolution
const SCREEN_WIDTH: f32 = 1920;
const SCREEN_HEIGHT: f32 = 1080;
const PLAYER_SPEED = 600.0;
const BULLET_SPEED = 400.0;
const ENEMY_SPEED = 100.0;
const MAX_BULLETS = 20;
const MAX_ENEMIES = 10;
const MAX_OBSTACLES = 15;
const MAX_PORTALS = 2;
const NUM_SCENES = 3;
const SAFE_SPAWN_DISTANCE = 200.0; // Minimum distance from player for safe spawning

// Vibrant color palette
// Darker main colors
const BLUE = raylib.Color{ .r = 0, .g = 70, .b = 200, .a = 255 };
const GREEN = raylib.Color{ .r = 0, .g = 140, .b = 0, .a = 255 };
const PURPLE = raylib.Color{ .r = 120, .g = 30, .b = 160, .a = 255 };
const RED = raylib.Color{ .r = 200, .g = 30, .b = 30, .a = 255 };
const YELLOW = raylib.Color{ .r = 220, .g = 160, .b = 0, .a = 255 };
const ORANGE = raylib.Color{ .r = 200, .g = 100, .b = 0, .a = 255 };
const GRAY = raylib.Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
const WHITE = raylib.Color{ .r = 230, .g = 230, .b = 230, .a = 255 };
const DARK = raylib.Color{ .r = 20, .g = 20, .b = 30, .a = 255 };

// Bright outline variants
const BLUE_BRIGHT = raylib.Color{ .r = 100, .g = 150, .b = 255, .a = 255 };
const GREEN_BRIGHT = raylib.Color{ .r = 80, .g = 220, .b = 80, .a = 255 };
const PURPLE_BRIGHT = raylib.Color{ .r = 180, .g = 100, .b = 240, .a = 255 };
const RED_BRIGHT = raylib.Color{ .r = 255, .g = 100, .b = 100, .a = 255 };
const YELLOW_BRIGHT = raylib.Color{ .r = 255, .g = 220, .b = 80, .a = 255 };
const ORANGE_BRIGHT = raylib.Color{ .r = 255, .g = 180, .b = 80, .a = 255 };
const GRAY_BRIGHT = raylib.Color{ .r = 180, .g = 180, .b = 180, .a = 255 };
const WHITE_BRIGHT = raylib.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

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

const SceneShape = enum {
    circle, // Scene 0
    triangle, // Scene 1
    square, // Scene 2
};

const Portal = struct {
    position: raylib.Vector2,
    radius: f32,
    active: bool,
    destinationScene: u8,
    shape: SceneShape, // Shape of the destination scene
};

const Obstacle = struct {
    position: raylib.Vector2,
    size: raylib.Vector2,
    type: ObstacleType,
    active: bool,
};

const Scene = struct {
    enemies: [MAX_ENEMIES]GameObject,
    obstacles: [MAX_OBSTACLES]Obstacle,
    portals: [MAX_PORTALS]Portal,
    shape: SceneShape,
};

const GameState = struct {
    player: GameObject,
    bullets: [MAX_BULLETS]GameObject,
    scenes: [NUM_SCENES]Scene,
    currentScene: u8,
    gameOver: bool,
    gameWon: bool,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        // Set random seed for proper randomization
        raylib.setRandomSeed(@intCast(std.time.timestamp()));

        var game = Self{
            .player = GameObject{
                .position = raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 20.0,
                .active = true,
                .color = BLUE,
            },
            .bullets = undefined,
            .scenes = undefined,
            .currentScene = 0,
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
                .color = YELLOW,
            };
        }

        // Initialize all scenes
        for (0..NUM_SCENES) |sceneIndex| {
            const shape: SceneShape = switch (sceneIndex) {
                0 => .circle,
                1 => .triangle,
                2 => .square,
                else => .circle,
            };

            game.scenes[sceneIndex] = Scene{
                .enemies = undefined,
                .obstacles = undefined,
                .portals = undefined,
                .shape = shape,
            };

            game.initializeScene(@intCast(sceneIndex));
        }

        return game;
    }

    fn initializeScene(self: *Self, sceneIndex: u8) void {
        // Initialize enemies for this scene
        for (0..MAX_ENEMIES) |i| {
            const safePos = self.getSafeSpawnPosition(raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }, SAFE_SPAWN_DISTANCE, 15.0, sceneIndex);
            self.scenes[sceneIndex].enemies[i] = GameObject{
                .position = safePos,
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 15.0,
                .active = true,
                .color = RED,
            };
        }

        // Initialize obstacles for this scene
        for (0..MAX_OBSTACLES) |i| {
            const obstacleType: ObstacleType = if (raylib.getRandomValue(0, 1) == 0) .blocking else .deadly;
            const baseSize = raylib.Vector2{
                .x = @floatFromInt(raylib.getRandomValue(20, 40)),
                .y = @floatFromInt(raylib.getRandomValue(20, 40)),
            };

            const obstacleSize = switch (obstacleType) {
                .blocking => raylib.Vector2{ .x = baseSize.x * 4.0, .y = baseSize.y * 4.0 },
                .deadly => baseSize,
            };

            const safePos = self.getSafeSpawnPosition(raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }, SAFE_SPAWN_DISTANCE, 0.0, sceneIndex);
            self.scenes[sceneIndex].obstacles[i] = Obstacle{
                .position = safePos,
                .size = obstacleSize,
                .type = obstacleType,
                .active = true,
            };
        }

        // Initialize portals (2 per scene, each going to one of the other scenes)
        for (0..MAX_PORTALS) |i| {
            // Get the two other scenes (not current scene)
            const otherScenes = switch (sceneIndex) {
                0 => [_]u8{ 1, 2 }, // Scene 0: go to scenes 1 and 2
                1 => [_]u8{ 0, 2 }, // Scene 1: go to scenes 0 and 2
                2 => [_]u8{ 0, 1 }, // Scene 2: go to scenes 0 and 1
                else => [_]u8{ 0, 1 },
            };

            const destinationScene = otherScenes[i];
            const destinationShape: SceneShape = switch (destinationScene) {
                0 => .circle,
                1 => .triangle,
                2 => .square,
                else => .circle,
            };

            const safePos = self.getSafeSpawnPosition(raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }, SAFE_SPAWN_DISTANCE, 25.0, sceneIndex);
            self.scenes[sceneIndex].portals[i] = Portal{
                .position = safePos,
                .radius = 25.0,
                .active = true,
                .destinationScene = destinationScene,
                .shape = destinationShape,
            };
        }
    }

    pub fn restart(self: *Self) void {
        // Set new random seed for different layouts
        raylib.setRandomSeed(@intCast(std.time.timestamp()));

        // Reset player
        self.player.position = raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
        self.player.active = true;

        // Reset bullets
        for (0..MAX_BULLETS) |i| {
            self.bullets[i].active = false;
        }

        // Only regenerate the current scene
        self.initializeScene(self.currentScene);

        self.gameOver = false;
        self.gameWon = false;
    }

    fn getSafeSpawnPosition(self: *Self, avoidPos: raylib.Vector2, minDistance: f32, unitRadius: f32, sceneIndex: u8) raylib.Vector2 {
        var attempts: u32 = 0;
        const maxAttempts: u32 = 100; // More attempts for better placement
        const isObstacle = unitRadius == 0;
        const effectiveRadius = if (isObstacle) 40.0 else unitRadius; // Use 40 as obstacle test size

        while (attempts < maxAttempts) {
            const margin = effectiveRadius + 10.0; // Safety margin
            const x: f32 = @floatFromInt(raylib.getRandomValue(@intFromFloat(margin), @intFromFloat(SCREEN_WIDTH - margin)));
            const y: f32 = @floatFromInt(raylib.getRandomValue(@intFromFloat(margin), @intFromFloat(SCREEN_HEIGHT - margin)));
            const testPos = raylib.Vector2{ .x = x, .y = y };

            // Check distance from avoid position (usually player)
            const dx = testPos.x - avoidPos.x;
            const dy = testPos.y - avoidPos.y;
            const distance = math.sqrt(dx * dx + dy * dy);
            if (distance < minDistance) {
                attempts += 1;
                continue;
            }

            // Check collisions with all existing objects in this scene
            var hasCollision = false;

            // Check obstacle collisions
            if (!hasCollision) {
                for (0..MAX_OBSTACLES) |i| {
                    if (self.scenes[sceneIndex].obstacles[i].active) {
                        const collisionMargin: f32 = 30.0; // Good spacing
                        if (isObstacle) {
                            // Obstacle-obstacle: check rectangle overlap with margin
                            if (!(testPos.x > self.scenes[sceneIndex].obstacles[i].position.x + self.scenes[sceneIndex].obstacles[i].size.x + collisionMargin or
                                testPos.x + 40 < self.scenes[sceneIndex].obstacles[i].position.x - collisionMargin or
                                testPos.y > self.scenes[sceneIndex].obstacles[i].position.y + self.scenes[sceneIndex].obstacles[i].size.y + collisionMargin or
                                testPos.y + 40 < self.scenes[sceneIndex].obstacles[i].position.y - collisionMargin))
                            {
                                hasCollision = true;
                                break;
                            }
                        } else {
                            // Circle-obstacle: use circle-rect collision with margin
                            if (self.checkCircleRectCollision(testPos, effectiveRadius + collisionMargin, self.scenes[sceneIndex].obstacles[i].position, self.scenes[sceneIndex].obstacles[i].size)) {
                                hasCollision = true;
                                break;
                            }
                        }
                    }
                }
            }

            // Check enemy collisions (circle-circle)
            if (!hasCollision) {
                for (0..MAX_ENEMIES) |i| {
                    if (self.scenes[sceneIndex].enemies[i].active) {
                        const dx2 = testPos.x - self.scenes[sceneIndex].enemies[i].position.x;
                        const dy2 = testPos.y - self.scenes[sceneIndex].enemies[i].position.y;
                        const dist = math.sqrt(dx2 * dx2 + dy2 * dy2);
                        if (dist < effectiveRadius + self.scenes[sceneIndex].enemies[i].radius + 20.0) {
                            hasCollision = true;
                            break;
                        }
                    }
                }
            }

            // Check portal collisions (circle-circle)
            if (!hasCollision) {
                for (0..MAX_PORTALS) |i| {
                    if (self.scenes[sceneIndex].portals[i].active) {
                        const dx2 = testPos.x - self.scenes[sceneIndex].portals[i].position.x;
                        const dy2 = testPos.y - self.scenes[sceneIndex].portals[i].position.y;
                        const dist = math.sqrt(dx2 * dx2 + dy2 * dy2);
                        if (dist < effectiveRadius + self.scenes[sceneIndex].portals[i].radius + 20.0) {
                            hasCollision = true;
                            break;
                        }
                    }
                }
            }

            if (!hasCollision) {
                return testPos;
            }

            attempts += 1;
        }

        // Fallback: spawn at edge of screen away from everything
        const fallbackX = if (avoidPos.x < SCREEN_WIDTH / 2) SCREEN_WIDTH - 100 else 100;
        const fallbackY: f32 = @floatFromInt(raylib.getRandomValue(100, @intFromFloat(SCREEN_HEIGHT - 100)));
        return raylib.Vector2{ .x = fallbackX, .y = fallbackY };
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
            if (self.scenes[self.currentScene].obstacles[i].active and self.scenes[self.currentScene].obstacles[i].type == .blocking) {
                if (self.checkCircleRectCollision(pos, radius, self.scenes[self.currentScene].obstacles[i].position, self.scenes[self.currentScene].obstacles[i].size)) {
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
            if (self.scenes[self.currentScene].enemies[i].active) {
                // Move towards player
                var direction = raylib.Vector2{
                    .x = self.player.position.x - self.scenes[self.currentScene].enemies[i].position.x,
                    .y = self.player.position.y - self.scenes[self.currentScene].enemies[i].position.y,
                };

                const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
                if (length > 0) {
                    direction.x /= length;
                    direction.y /= length;
                }

                // Check for obstacle collision before moving
                const newX = self.scenes[self.currentScene].enemies[i].position.x + direction.x * ENEMY_SPEED * deltaTime;
                const newY = self.scenes[self.currentScene].enemies[i].position.y + direction.y * ENEMY_SPEED * deltaTime;

                // Check X movement
                const testPosX = raylib.Vector2{ .x = newX, .y = self.scenes[self.currentScene].enemies[i].position.y };
                if (!self.isPositionBlocked(testPosX, self.scenes[self.currentScene].enemies[i].radius)) {
                    self.scenes[self.currentScene].enemies[i].position.x = newX;
                }

                // Check Y movement
                const testPosY = raylib.Vector2{ .x = self.scenes[self.currentScene].enemies[i].position.x, .y = newY };
                if (!self.isPositionBlocked(testPosY, self.scenes[self.currentScene].enemies[i].radius)) {
                    self.scenes[self.currentScene].enemies[i].position.y = newY;
                }
            }
        }
    }

    pub fn checkCollisions(self: *Self) void {
        const currentScene = &self.scenes[self.currentScene];

        // Bullet-Enemy collisions (current scene only)
        for (0..MAX_BULLETS) |i| {
            if (self.bullets[i].active) {
                for (0..MAX_ENEMIES) |j| {
                    if (currentScene.enemies[j].active) {
                        const dx = self.bullets[i].position.x - currentScene.enemies[j].position.x;
                        const dy = self.bullets[i].position.y - currentScene.enemies[j].position.y;
                        const distance = math.sqrt(dx * dx + dy * dy);

                        if (distance < self.bullets[i].radius + currentScene.enemies[j].radius) {
                            self.bullets[i].active = false;
                            currentScene.enemies[j].active = false;
                        }
                    }
                }
            }
        }

        // Player-Enemy collisions (current scene only)
        for (0..MAX_ENEMIES) |i| {
            if (currentScene.enemies[i].active) {
                const dx = self.player.position.x - currentScene.enemies[i].position.x;
                const dy = self.player.position.y - currentScene.enemies[i].position.y;
                const distance = math.sqrt(dx * dx + dy * dy);

                if (distance < self.player.radius + currentScene.enemies[i].radius) {
                    self.gameOver = true;
                }
            }
        }

        // Player-Portal collisions (scene switching)
        for (0..MAX_PORTALS) |i| {
            if (currentScene.portals[i].active) {
                const dx = self.player.position.x - currentScene.portals[i].position.x;
                const dy = self.player.position.y - currentScene.portals[i].position.y;
                const distance = math.sqrt(dx * dx + dy * dy);

                if (distance < self.player.radius + currentScene.portals[i].radius) {
                    self.currentScene = currentScene.portals[i].destinationScene;
                    // Player position stays the same - world changes around them
                    return; // Exit early to avoid processing more collisions
                }
            }
        }

        // Player-Deadly Obstacle collisions (current scene only)
        for (0..MAX_OBSTACLES) |i| {
            if (currentScene.obstacles[i].active and currentScene.obstacles[i].type == .deadly) {
                if (self.checkCircleRectCollision(self.player.position, self.player.radius, currentScene.obstacles[i].position, currentScene.obstacles[i].size)) {
                    self.gameOver = true;
                }
            }
        }

        // Enemy-Deadly Obstacle collisions (current scene only)
        for (0..MAX_ENEMIES) |i| {
            if (currentScene.enemies[i].active) {
                for (0..MAX_OBSTACLES) |j| {
                    if (currentScene.obstacles[j].active and currentScene.obstacles[j].type == .deadly) {
                        if (self.checkCircleRectCollision(currentScene.enemies[i].position, currentScene.enemies[i].radius, currentScene.obstacles[j].position, currentScene.obstacles[j].size)) {
                            currentScene.enemies[i].active = false;
                        }
                    }
                }
            }
        }

        // Check win condition - all enemies dead in current scene
        var allEnemiesDead = true;
        for (0..MAX_ENEMIES) |i| {
            if (currentScene.enemies[i].active) {
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
            raylib.drawCircleLinesV(self.player.position, self.player.radius, BLUE_BRIGHT);

            // Draw bullets
            for (0..MAX_BULLETS) |i| {
                if (self.bullets[i].active) {
                    raylib.drawCircleV(self.bullets[i].position, self.bullets[i].radius, self.bullets[i].color);
                    raylib.drawCircleLinesV(self.bullets[i].position, self.bullets[i].radius, YELLOW_BRIGHT);
                }
            }

            // Draw current scene entities
            const currentScene = &self.scenes[self.currentScene];

            // Draw enemies from current scene
            for (0..MAX_ENEMIES) |i| {
                if (currentScene.enemies[i].active) {
                    raylib.drawCircleV(currentScene.enemies[i].position, currentScene.enemies[i].radius, currentScene.enemies[i].color);
                    raylib.drawCircleLinesV(currentScene.enemies[i].position, currentScene.enemies[i].radius, RED_BRIGHT);
                }
            }

            // Draw obstacles from current scene
            for (0..MAX_OBSTACLES) |i| {
                if (currentScene.obstacles[i].active) {
                    const color = switch (currentScene.obstacles[i].type) {
                        .blocking => GREEN,
                        .deadly => PURPLE,
                    };
                    const outlineColor = switch (currentScene.obstacles[i].type) {
                        .blocking => GREEN_BRIGHT,
                        .deadly => PURPLE_BRIGHT,
                    };
                    raylib.drawRectangleV(currentScene.obstacles[i].position, currentScene.obstacles[i].size, color);
                    raylib.drawRectangleLinesV(currentScene.obstacles[i].position, currentScene.obstacles[i].size, outlineColor);
                }
            }

            // Draw portals with destination-specific shapes
            for (0..MAX_PORTALS) |i| {
                if (currentScene.portals[i].active) {
                    const pos = currentScene.portals[i].position;
                    const radius = currentScene.portals[i].radius;

                    // Draw portal with the shape of its destination scene
                    switch (currentScene.portals[i].shape) {
                        .circle => {
                            raylib.drawCircleV(pos, radius, ORANGE);
                            raylib.drawCircleLinesV(pos, radius, ORANGE_BRIGHT);
                        },
                        .triangle => {
                            // Draw triangle pointing up
                            raylib.drawTriangle(raylib.Vector2{ .x = pos.x, .y = pos.y - radius }, raylib.Vector2{ .x = pos.x - radius * 0.866, .y = pos.y + radius * 0.5 }, raylib.Vector2{ .x = pos.x + radius * 0.866, .y = pos.y + radius * 0.5 }, ORANGE);
                            raylib.drawTriangleLines(raylib.Vector2{ .x = pos.x, .y = pos.y - radius }, raylib.Vector2{ .x = pos.x - radius * 0.866, .y = pos.y + radius * 0.5 }, raylib.Vector2{ .x = pos.x + radius * 0.866, .y = pos.y + radius * 0.5 }, ORANGE_BRIGHT);
                        },
                        .square => {
                            const size = radius * 1.4; // Make square similar area to circle
                            const rectPos = raylib.Vector2{ .x = pos.x - size / 2, .y = pos.y - size / 2 };
                            const rectSize = raylib.Vector2{ .x = size, .y = size };
                            raylib.drawRectangleV(rectPos, rectSize, ORANGE);
                            raylib.drawRectangleLinesV(rectPos, rectSize, ORANGE_BRIGHT);
                        },
                    }
                }
            }

            // Draw UI with scene info
            raylib.drawText("Left Click: Move | Right Click: Shoot | Orange = Portal", 10, @intFromFloat(SCREEN_HEIGHT - 80), 16, GRAY);
            raylib.drawText("WASD/Arrows: Move (Alt) | R: Restart Scene | ESC: Quit", 10, @intFromFloat(SCREEN_HEIGHT - 60), 16, GRAY);

            // Scene indicator
            const shapeName = switch (self.scenes[self.currentScene].shape) {
                .circle => "circle",
                .triangle => "triangle",
                .square => "square",
            };
            const sceneText = try raylib.textFormat(self.allocator, "Scene {d}/3 ({s})", .{ self.currentScene + 1, shapeName });
            defer self.allocator.free(sceneText);
            raylib.drawText(sceneText, 10, @intFromFloat(SCREEN_HEIGHT - 40), 16, WHITE);

            // FPS Counter (top right corner)
            const fps = raylib.getFPS();
            const fpsText = try raylib.textFormat(self.allocator, "FPS: {d}", .{fps});
            defer self.allocator.free(fpsText);
            const fpsWidth = raylib.measureText(fpsText, 16);
            raylib.drawText(fpsText, @as(i32, @intFromFloat(SCREEN_WIDTH)) - fpsWidth - 10, 10, 16, WHITE);
        } else if (self.gameWon) {
            // Win screen
            raylib.drawText("YOU WIN!", @intFromFloat(SCREEN_WIDTH / 2 - 400), @intFromFloat(SCREEN_HEIGHT / 2 - 200), 160, GREEN);

            raylib.drawText("All enemies eliminated!", @intFromFloat(SCREEN_WIDTH / 2 - 300), @intFromFloat(SCREEN_HEIGHT / 2 - 20), 48, WHITE);
            raylib.drawText("Press R or Click to restart, ESC to quit", @intFromFloat(SCREEN_WIDTH / 2 - 480), @intFromFloat(SCREEN_HEIGHT / 2 + 80), 48, GRAY);
        } else {
            // Game over screen
            raylib.drawText("GAME OVER", @intFromFloat(SCREEN_WIDTH / 2 - 480), @intFromFloat(SCREEN_HEIGHT / 2 - 200), 160, RED);

            raylib.drawText("Press R or Click to restart, ESC to quit", @intFromFloat(SCREEN_WIDTH / 2 - 480), @intFromFloat(SCREEN_HEIGHT / 2 + 80), 48, GRAY);
        }
    }
};

// Main entry point for CLI integration
pub fn run(allocator: std.mem.Allocator) !void {
    std.debug.print("Starting YAR - Yet Another RPG...\n", .{});

    raylib.initWindow(@intFromFloat(SCREEN_WIDTH), @intFromFloat(SCREEN_HEIGHT), "YAR - Yet Another RPG");
    defer raylib.closeWindow();

    raylib.setTargetFPS(144);

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
