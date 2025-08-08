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
const MAX_ENEMIES = 12;
const MAX_OBSTACLES = 15;
const MAX_PORTALS = 6; // More portals needed for hexagon layout
const NUM_SCENES = 7; // Overworld + 6 dungeons

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

const EnemyState = enum {
    alive,
    dead,
};

const GameObject = struct {
    position: raylib.Vector2,
    velocity: raylib.Vector2,
    radius: f32,
    active: bool,
    color: raylib.Color,
    enemyState: EnemyState, // Only used for enemies
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
    originalEnemies: [MAX_ENEMIES]GameObject, // Store original enemy states for respawning
    obstacles: [MAX_OBSTACLES]Obstacle,
    portals: [MAX_PORTALS]Portal,
    shape: SceneShape,
    name: []const u8,
    background_color: raylib.Color,
    player_scale: f32,
    enemy_scale: f32,
};

// Data structures for loading from ZON
const DataPortal = struct {
    position: struct { x: f32, y: f32 },
    radius: f32,
    destination: u8,
    shape: []const u8,
};

const DataObstacle = struct {
    position: struct { x: f32, y: f32 },
    size: struct { x: f32, y: f32 },
    type: []const u8,
};

const DataEnemy = struct {
    position: struct { x: f32, y: f32 },
    radius: f32,
};

const DataScene = struct {
    name: []const u8,
    background_color: struct { r: u8, g: u8, b: u8 },
    player_scale: f32,
    enemy_scale: f32,
    obstacles: []const DataObstacle,
    enemies: []const DataEnemy,
    portals: []const DataPortal,
};

const GameData = struct {
    screen_width: f32,
    screen_height: f32,
    player_start: struct {
        scene: u8,
        position: struct { x: f32, y: f32 },
        radius: f32,
    },
    scenes: []const DataScene,
};

const GameState = struct {
    player: GameObject,
    bullets: [MAX_BULLETS]GameObject,
    scenes: [NUM_SCENES]Scene,
    currentScene: u8,
    gameOver: bool,
    gameWon: bool,
    allocator: std.mem.Allocator,
    gameData: GameData,
    isPaused: bool,
    gameSpeed: f32,
    // Pre-allocated text buffers to avoid per-frame allocation
    sceneTextBuffer: [128]u8,
    fpsTextBuffer: [32]u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        // Load game data from ZON file
        const gameDataFile = @embedFile("game_data.zon");

        // Convert to null-terminated string for ZON parser
        const gameDataNullTerm = try allocator.dupeZ(u8, gameDataFile);
        defer allocator.free(gameDataNullTerm);

        const gameData = std.zon.parse.fromSlice(GameData, allocator, gameDataNullTerm, null, .{}) catch |err| {
            std.debug.print("Failed to load game data: {}\n", .{err});
            return err;
        };

        var game = Self{
            .player = GameObject{
                .position = raylib.Vector2{ .x = gameData.player_start.position.x, .y = gameData.player_start.position.y },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = gameData.player_start.radius,
                .active = true,
                .color = BLUE,
                .enemyState = .alive, // Not used for player, but required
            },
            .bullets = undefined,
            .scenes = undefined,
            .currentScene = gameData.player_start.scene,
            .gameOver = false,
            .gameWon = false,
            .allocator = allocator,
            .gameData = gameData,
            .isPaused = false,
            .gameSpeed = 1.0,
            .sceneTextBuffer = undefined,
            .fpsTextBuffer = undefined,
        };

        // Initialize bullets
        for (0..MAX_BULLETS) |i| {
            game.bullets[i] = GameObject{
                .position = raylib.Vector2{ .x = 0, .y = 0 },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 5.0,
                .active = false,
                .color = YELLOW,
                .enemyState = .alive, // Not used for bullets, but required
            };
        }

        // Initialize all scenes from data
        for (0..NUM_SCENES) |sceneIndex| {
            if (sceneIndex >= game.gameData.scenes.len) continue;

            const dataScene = game.gameData.scenes[sceneIndex];
            const shape: SceneShape = if (std.mem.eql(u8, dataScene.name, "Overworld"))
                .circle
            else switch (sceneIndex % 3) {
                1, 4 => .circle,
                2, 5 => .triangle,
                0, 3, 6 => .square,
                else => .circle,
            };

            game.scenes[sceneIndex] = Scene{
                .enemies = undefined,
                .originalEnemies = undefined,
                .obstacles = undefined,
                .portals = undefined,
                .shape = shape,
                .name = dataScene.name,
                .background_color = raylib.Color{
                    .r = dataScene.background_color.r,
                    .g = dataScene.background_color.g,
                    .b = dataScene.background_color.b,
                    .a = 255,
                },
                .player_scale = dataScene.player_scale,
                .enemy_scale = dataScene.enemy_scale,
            };

            game.loadSceneFromData(@intCast(sceneIndex));
        }

        return game;
    }

    fn createEnemyFromData(dataEnemy: ?DataEnemy, enemyScale: f32) GameObject {
        if (dataEnemy) |enemy| {
            return GameObject{
                .position = raylib.Vector2{ .x = enemy.position.x, .y = enemy.position.y },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = enemy.radius * enemyScale,
                .active = true,
                .color = RED,
                .enemyState = .alive,
            };
        } else {
            return GameObject{
                .position = raylib.Vector2{ .x = 0, .y = 0 },
                .velocity = raylib.Vector2{ .x = 0, .y = 0 },
                .radius = 15.0,
                .active = false,
                .color = RED,
                .enemyState = .alive,
            };
        }
    }

    fn loadSceneFromData(self: *Self, sceneIndex: u8) void {
        const dataScene = self.gameData.scenes[sceneIndex];

        // Load enemies from data (create once, store in both arrays)
        for (0..MAX_ENEMIES) |i| {
            const dataEnemy = if (i < dataScene.enemies.len) dataScene.enemies[i] else null;
            const enemy = createEnemyFromData(dataEnemy, dataScene.enemy_scale);
            self.scenes[sceneIndex].enemies[i] = enemy;
            self.scenes[sceneIndex].originalEnemies[i] = enemy;
        }

        // Load obstacles from data
        for (0..MAX_OBSTACLES) |i| {
            if (i < dataScene.obstacles.len) {
                const dataObstacle = dataScene.obstacles[i];
                const obstacleType: ObstacleType = if (std.mem.eql(u8, dataObstacle.type, "blocking"))
                    .blocking
                else
                    .deadly;

                self.scenes[sceneIndex].obstacles[i] = Obstacle{
                    .position = raylib.Vector2{ .x = dataObstacle.position.x, .y = dataObstacle.position.y },
                    .size = raylib.Vector2{ .x = dataObstacle.size.x, .y = dataObstacle.size.y },
                    .type = obstacleType,
                    .active = true,
                };
            } else {
                self.scenes[sceneIndex].obstacles[i] = Obstacle{
                    .position = raylib.Vector2{ .x = 0, .y = 0 },
                    .size = raylib.Vector2{ .x = 0, .y = 0 },
                    .type = .blocking,
                    .active = false,
                };
            }
        }

        // Load portals from data
        for (0..MAX_PORTALS) |i| {
            if (i < dataScene.portals.len) {
                const dataPortal = dataScene.portals[i];
                const destinationShape: SceneShape = if (std.mem.eql(u8, dataPortal.shape, "circle"))
                    .circle
                else if (std.mem.eql(u8, dataPortal.shape, "triangle"))
                    .triangle
                else
                    .square;

                self.scenes[sceneIndex].portals[i] = Portal{
                    .position = raylib.Vector2{ .x = dataPortal.position.x, .y = dataPortal.position.y },
                    .radius = dataPortal.radius,
                    .active = true,
                    .destinationScene = dataPortal.destination,
                    .shape = destinationShape,
                };
            } else {
                self.scenes[sceneIndex].portals[i] = Portal{
                    .position = raylib.Vector2{ .x = 0, .y = 0 },
                    .radius = 25.0,
                    .active = false,
                    .destinationScene = 0,
                    .shape = .circle,
                };
            }
        }
    }

    fn restoreEnemiesInScene(self: *Self, sceneIndex: u8) void {
        // Restore all enemies in the specified scene to their original state (bulk copy)
        self.scenes[sceneIndex].enemies = self.scenes[sceneIndex].originalEnemies;
    }

    pub fn restart(self: *Self) void {
        // Reset player to starting position
        self.player.position = raylib.Vector2{ .x = self.gameData.player_start.position.x, .y = self.gameData.player_start.position.y };
        self.player.active = true;
        self.currentScene = self.gameData.player_start.scene;

        // Reset bullets
        for (0..MAX_BULLETS) |i| {
            self.bullets[i].active = false;
        }

        // Reload all scenes from data (restore original state)
        for (0..NUM_SCENES) |sceneIndex| {
            if (sceneIndex < self.gameData.scenes.len) {
                self.loadSceneFromData(@intCast(sceneIndex));
            }
        }

        self.gameOver = false;
        self.gameWon = false;
        self.isPaused = false;
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

    pub fn handleInput(self: *Self) void {
        // Handle pause toggle
        if (raylib.isKeyPressed(raylib.KEY_SPACE)) {
            self.isPaused = !self.isPaused;
        }

        // Handle speed control with chunky increments
        if (raylib.isKeyPressed(raylib.KEY_LEFT_BRACKET)) {
            self.gameSpeed = @max(0.25, self.gameSpeed - 0.25); // Min 0.25x speed
        }
        if (raylib.isKeyPressed(raylib.KEY_RIGHT_BRACKET)) {
            self.gameSpeed = @min(4.0, self.gameSpeed + 0.25); // Max 4x speed
        }
    }

    pub fn updatePlayer(self: *Self, deltaTime: f32) void {
        if (self.isPaused) return;
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

        // Update position with collision checking (apply game speed)
        const effectiveDeltaTime = deltaTime * self.gameSpeed;
        const newX = self.player.position.x + movement.x * PLAYER_SPEED * effectiveDeltaTime;
        const newY = self.player.position.y + movement.y * PLAYER_SPEED * effectiveDeltaTime;

        // Get player radius for current scene
        const currentScene = &self.scenes[self.currentScene];
        const playerRadius = self.gameData.player_start.radius * currentScene.player_scale;

        // Check X movement
        const testPosX = raylib.Vector2{ .x = newX, .y = self.player.position.y };
        if (!self.isPositionBlocked(testPosX, playerRadius)) {
            self.player.position.x = newX;
        }

        // Check Y movement
        const testPosY = raylib.Vector2{ .x = self.player.position.x, .y = newY };
        if (!self.isPositionBlocked(testPosY, playerRadius)) {
            self.player.position.y = newY;
        }

        // Keep player on screen
        if (self.player.position.x < playerRadius)
            self.player.position.x = playerRadius;
        if (self.player.position.x > SCREEN_WIDTH - playerRadius)
            self.player.position.x = SCREEN_WIDTH - playerRadius;
        if (self.player.position.y < playerRadius)
            self.player.position.y = playerRadius;
        if (self.player.position.y > SCREEN_HEIGHT - playerRadius)
            self.player.position.y = SCREEN_HEIGHT - playerRadius;
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
        if (self.isPaused) return;
        const effectiveDeltaTime = deltaTime * self.gameSpeed;
        for (0..MAX_BULLETS) |i| {
            if (self.bullets[i].active) {
                self.bullets[i].position.x += self.bullets[i].velocity.x * effectiveDeltaTime;
                self.bullets[i].position.y += self.bullets[i].velocity.y * effectiveDeltaTime;

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
        if (self.isPaused) return;
        for (0..MAX_ENEMIES) |i| {
            if (self.scenes[self.currentScene].enemies[i].active and self.scenes[self.currentScene].enemies[i].enemyState == .alive) {
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

                // Use different speeds for overworld vs dungeons
                const enemySpeed: f32 = if (self.currentScene == 0) 50.0 else ENEMY_SPEED; // Slower in overworld
                const effectiveDeltaTime = deltaTime * self.gameSpeed;

                // Check for obstacle collision before moving
                const newX = self.scenes[self.currentScene].enemies[i].position.x + direction.x * enemySpeed * effectiveDeltaTime;
                const newY = self.scenes[self.currentScene].enemies[i].position.y + direction.y * enemySpeed * effectiveDeltaTime;

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
        const playerRadius = self.gameData.player_start.radius * currentScene.player_scale;

        // Bullet-Enemy collisions (current scene only)
        for (0..MAX_BULLETS) |i| {
            if (self.bullets[i].active) {
                for (0..MAX_ENEMIES) |j| {
                    if (currentScene.enemies[j].active and currentScene.enemies[j].enemyState == .alive) {
                        const dx = self.bullets[i].position.x - currentScene.enemies[j].position.x;
                        const dy = self.bullets[i].position.y - currentScene.enemies[j].position.y;
                        const distance = math.sqrt(dx * dx + dy * dy);

                        if (distance < self.bullets[i].radius + currentScene.enemies[j].radius) {
                            self.bullets[i].active = false;
                            currentScene.enemies[j].enemyState = .dead;
                        }
                    }
                }
            }
        }

        // Player-Enemy collisions (current scene only)
        for (0..MAX_ENEMIES) |i| {
            if (currentScene.enemies[i].active and currentScene.enemies[i].enemyState == .alive) {
                const dx = self.player.position.x - currentScene.enemies[i].position.x;
                const dy = self.player.position.y - currentScene.enemies[i].position.y;
                const distance = math.sqrt(dx * dx + dy * dy);

                if (distance < playerRadius + currentScene.enemies[i].radius) {
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

                if (distance < playerRadius + currentScene.portals[i].radius) {
                    const destinationScene = currentScene.portals[i].destinationScene;
                    self.currentScene = destinationScene;
                    // Always place player at screen center
                    self.player.position = raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
                    // Restore enemies in the destination scene to their original positions
                    self.restoreEnemiesInScene(destinationScene);
                    return; // Exit early to avoid processing more collisions
                }
            }
        }

        // Player-Deadly Obstacle collisions (current scene only)
        for (0..MAX_OBSTACLES) |i| {
            if (currentScene.obstacles[i].active and currentScene.obstacles[i].type == .deadly) {
                if (self.checkCircleRectCollision(self.player.position, playerRadius, currentScene.obstacles[i].position, currentScene.obstacles[i].size)) {
                    self.gameOver = true;
                }
            }
        }

        // Enemy-Deadly Obstacle collisions (current scene only)
        for (0..MAX_ENEMIES) |i| {
            if (currentScene.enemies[i].active and currentScene.enemies[i].enemyState == .alive) {
                for (0..MAX_OBSTACLES) |j| {
                    if (currentScene.obstacles[j].active and currentScene.obstacles[j].type == .deadly) {
                        if (self.checkCircleRectCollision(currentScene.enemies[i].position, currentScene.enemies[i].radius, currentScene.obstacles[j].position, currentScene.obstacles[j].size)) {
                            currentScene.enemies[i].enemyState = .dead;
                        }
                    }
                }
            }
        }

        // Check win condition - all enemies dead in current scene
        var allEnemiesDead = true;
        for (0..MAX_ENEMIES) |i| {
            if (currentScene.enemies[i].active and currentScene.enemies[i].enemyState == .alive) {
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

        // Use scene-specific background color
        const currentSceneBg = if (self.currentScene < NUM_SCENES)
            self.scenes[self.currentScene].background_color
        else
            raylib.BLACK;
        raylib.clearBackground(currentSceneBg);
        if (!self.gameOver and !self.gameWon) {
            // Draw player with scene-based scaling
            const currentScene = &self.scenes[self.currentScene];
            const playerRadius = self.gameData.player_start.radius * currentScene.player_scale;
            raylib.drawCircleV(self.player.position, playerRadius, self.player.color);
            raylib.drawCircleLinesV(self.player.position, playerRadius, BLUE_BRIGHT);

            // Draw bullets
            for (0..MAX_BULLETS) |i| {
                if (self.bullets[i].active) {
                    raylib.drawCircleV(self.bullets[i].position, self.bullets[i].radius, self.bullets[i].color);
                    raylib.drawCircleLinesV(self.bullets[i].position, self.bullets[i].radius, YELLOW_BRIGHT);
                }
            }

            // Draw current scene entities
            const sceneData = &self.scenes[self.currentScene];

            // Draw enemies from current scene
            for (0..MAX_ENEMIES) |i| {
                if (sceneData.enemies[i].active) {
                    switch (sceneData.enemies[i].enemyState) {
                        .alive => {
                            // Draw alive enemies normally
                            raylib.drawCircleV(sceneData.enemies[i].position, sceneData.enemies[i].radius, sceneData.enemies[i].color);
                            raylib.drawCircleLinesV(sceneData.enemies[i].position, sceneData.enemies[i].radius, RED_BRIGHT);
                        },
                        .dead => {
                            // Draw dead enemies as smaller gray circles with outline
                            const deadRadius = sceneData.enemies[i].radius * 0.7; // Smaller when dead
                            raylib.drawCircleV(sceneData.enemies[i].position, deadRadius, GRAY);
                            raylib.drawCircleLinesV(sceneData.enemies[i].position, deadRadius, GRAY_BRIGHT);
                        },
                    }
                }
            }

            // Draw obstacles from current scene
            for (0..MAX_OBSTACLES) |i| {
                if (sceneData.obstacles[i].active) {
                    const color = switch (sceneData.obstacles[i].type) {
                        .blocking => GREEN,
                        .deadly => PURPLE,
                    };
                    const outlineColor = switch (sceneData.obstacles[i].type) {
                        .blocking => GREEN_BRIGHT,
                        .deadly => PURPLE_BRIGHT,
                    };
                    raylib.drawRectangleV(sceneData.obstacles[i].position, sceneData.obstacles[i].size, color);
                    raylib.drawRectangleLinesV(sceneData.obstacles[i].position, sceneData.obstacles[i].size, outlineColor);
                }
            }

            // Draw portals with destination-specific shapes
            for (0..MAX_PORTALS) |i| {
                if (sceneData.portals[i].active) {
                    const pos = sceneData.portals[i].position;
                    const radius = sceneData.portals[i].radius;

                    // Draw portal with the shape of its destination scene
                    switch (sceneData.portals[i].shape) {
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

            // Scene indicator (using pre-allocated buffer)
            const sceneName = if (self.currentScene < NUM_SCENES)
                self.scenes[self.currentScene].name
            else
                "Unknown";
            const sceneText = std.fmt.bufPrintZ(&self.sceneTextBuffer, "Scene {d}/{d}: {s}", .{ self.currentScene, NUM_SCENES - 1, sceneName }) catch "Scene";
            raylib.drawText(sceneText, 10, @intFromFloat(SCREEN_HEIGHT - 40), 16, WHITE);

            // FPS Counter (top right corner, using pre-allocated buffer)
            const fps = raylib.getFPS();
            const fpsText = std.fmt.bufPrintZ(&self.fpsTextBuffer, "FPS: {d}", .{fps}) catch "FPS: --";
            const fpsWidth = raylib.measureText(fpsText, 16);
            raylib.drawText(fpsText, @as(i32, @intFromFloat(SCREEN_WIDTH)) - fpsWidth - 10, 10, 16, WHITE);

            // Pause effect - subtle colorful pulsing border
            if (self.isPaused) {
                const time = raylib.getTime();
                const pulse = (math.sin(time * 1.5) + 1.0) * 0.5; // 0.0 to 1.0, slower pulse
                const borderWidth = @as(i32, @intFromFloat(2 + pulse * 4)); // 2 to 6 pixels
                
                // Pulsing rainbow border effect
                const hue = @mod(time * 60.0, 360.0); // Cycle through colors
                const borderColor = raylib.colorFromHSV(@floatCast(hue), 1.0, 1.0);
                
                // Draw thick border around entire screen
                raylib.drawRectangle(0, 0, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Top
                raylib.drawRectangle(0, @as(i32, @intFromFloat(SCREEN_HEIGHT)) - borderWidth, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Bottom  
                raylib.drawRectangle(0, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Left
                raylib.drawRectangle(@as(i32, @intFromFloat(SCREEN_WIDTH)) - borderWidth, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Right
            }
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

    var game = GameState.init(allocator) catch |err| {
        std.debug.print("Failed to initialize game: {}\n", .{err});
        return err;
    };

    while (!raylib.windowShouldClose()) {
        const deltaTime = raylib.getFrameTime();

        // Handle input regardless of game state
        game.handleInput();

        if (!game.gameOver and !game.gameWon) {
            game.updatePlayer(deltaTime);

            if (raylib.isMouseButtonPressed(raylib.MOUSE_BUTTON_RIGHT) and !game.isPaused) {
                game.fireBullet();
            }

            game.updateBullets(deltaTime);
            game.updateEnemies(deltaTime);
            if (!game.isPaused) {
                game.checkCollisions();
            }
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
