const std = @import("std");
const math = std.math;

// Direct raylib module imports
const rl_types = @import("raylib_types.zig");
const rl_core = @import("raylib_core.zig");
const rl_shapes = @import("raylib_shapes.zig");
const rl_textures = @import("raylib_textures.zig");
const rl_text = @import("raylib_text.zig");

// Comptime constants for performance
const DIAGONAL_FACTOR = @sqrt(0.5); // ~0.707
const SCREEN_WIDTH: f32 = 1920;
const SCREEN_HEIGHT: f32 = 1080;

// Input constants
const KEY_SPACE = @intFromEnum(rl_types.KeyboardKey.KEY_SPACE);
const KEY_LEFT_BRACKET = @intFromEnum(rl_types.KeyboardKey.KEY_LEFT_BRACKET);
const KEY_RIGHT_BRACKET = @intFromEnum(rl_types.KeyboardKey.KEY_RIGHT_BRACKET);
const KEY_W = @intFromEnum(rl_types.KeyboardKey.KEY_W);
const KEY_S = @intFromEnum(rl_types.KeyboardKey.KEY_S);
const KEY_A = @intFromEnum(rl_types.KeyboardKey.KEY_A);
const KEY_D = @intFromEnum(rl_types.KeyboardKey.KEY_D);
const KEY_UP = @intFromEnum(rl_types.KeyboardKey.KEY_UP);
const KEY_DOWN = @intFromEnum(rl_types.KeyboardKey.KEY_DOWN);
const KEY_LEFT = @intFromEnum(rl_types.KeyboardKey.KEY_LEFT);
const KEY_RIGHT = @intFromEnum(rl_types.KeyboardKey.KEY_RIGHT);
const KEY_R = @intFromEnum(rl_types.KeyboardKey.KEY_R);
const KEY_T = @intFromEnum(rl_types.KeyboardKey.KEY_T);
const KEY_Y = @intFromEnum(rl_types.KeyboardKey.KEY_Y);
const KEY_ESCAPE = @intFromEnum(rl_types.KeyboardKey.KEY_ESCAPE);
const MOUSE_LEFT = @intFromEnum(rl_types.MouseButton.MOUSE_BUTTON_LEFT);
const MOUSE_RIGHT = @intFromEnum(rl_types.MouseButton.MOUSE_BUTTON_RIGHT);

// Game constants
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
const BLUE = rl_types.Color{ .r = 0, .g = 70, .b = 200, .a = 255 };
const GREEN = rl_types.Color{ .r = 0, .g = 140, .b = 0, .a = 255 };
const PURPLE = rl_types.Color{ .r = 120, .g = 30, .b = 160, .a = 255 };
const RED = rl_types.Color{ .r = 200, .g = 30, .b = 30, .a = 255 };
const YELLOW = rl_types.Color{ .r = 220, .g = 160, .b = 0, .a = 255 };
const ORANGE = rl_types.Color{ .r = 200, .g = 100, .b = 0, .a = 255 };
const GRAY = rl_types.Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
const WHITE = rl_types.Color{ .r = 230, .g = 230, .b = 230, .a = 255 };
const DARK = rl_types.Color{ .r = 20, .g = 20, .b = 30, .a = 255 };

// Bright outline variants
const BLUE_BRIGHT = rl_types.Color{ .r = 100, .g = 150, .b = 255, .a = 255 };
const GREEN_BRIGHT = rl_types.Color{ .r = 80, .g = 220, .b = 80, .a = 255 };
const PURPLE_BRIGHT = rl_types.Color{ .r = 180, .g = 100, .b = 240, .a = 255 };
const RED_BRIGHT = rl_types.Color{ .r = 255, .g = 100, .b = 100, .a = 255 };
const YELLOW_BRIGHT = rl_types.Color{ .r = 255, .g = 220, .b = 80, .a = 255 };
const ORANGE_BRIGHT = rl_types.Color{ .r = 255, .g = 180, .b = 80, .a = 255 };
const GRAY_BRIGHT = rl_types.Color{ .r = 180, .g = 180, .b = 180, .a = 255 };
const WHITE_BRIGHT = rl_types.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

const EnemyState = enum {
    alive,
    dead,
};

const GameObject = struct {
    position: rl_types.Vector2,
    velocity: rl_types.Vector2,
    radius: f32,
    active: bool,
    color: rl_types.Color,
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
    position: rl_types.Vector2,
    radius: f32,
    active: bool,
    destinationScene: u8,
    shape: SceneShape, // Shape of the destination scene
};

const Obstacle = struct {
    position: rl_types.Vector2,
    size: rl_types.Vector2,
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
    background_color: rl_types.Color,
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
    winTime: f32, // Track time since winning for animation
    // Aggro system - enemies target this position when not null
    aggroTarget: ?rl_types.Vector2,
    // Friendly target - for healing/support abilities (future use)
    friendlyTarget: ?rl_types.Vector2,
    // Pre-allocated text buffers to avoid per-frame allocation
    sceneTextBuffer: [128]u8,
    fpsTextBuffer: [32]u8,
    // 2D camera for tracking player movement in non-overworld scenes
    camera: rl_types.Camera2D,

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
                .position = rl_types.Vector2{ .x = gameData.player_start.position.x, .y = gameData.player_start.position.y },
                .velocity = rl_types.Vector2{ .x = 0, .y = 0 },
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
            .winTime = 0.0,
            .aggroTarget = null, // Start with no aggro target (enemies go home)
            .friendlyTarget = null, // No friendly target initially
            .sceneTextBuffer = undefined,
            .fpsTextBuffer = undefined,
            .camera = rl_types.Camera2D{
                .offset = rl_types.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }, // Center the camera
                .target = rl_types.Vector2{ .x = gameData.player_start.position.x, .y = gameData.player_start.position.y }, // Start tracking player
                .rotation = 0.0,
                .zoom = 1.0,
            },
        };

        // Initialize bullets
        for (0..MAX_BULLETS) |i| {
            game.bullets[i] = GameObject{
                .position = rl_types.Vector2{ .x = 0, .y = 0 },
                .velocity = rl_types.Vector2{ .x = 0, .y = 0 },
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
                .background_color = rl_types.Color{
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
                .position = rl_types.Vector2{ .x = enemy.position.x, .y = enemy.position.y },
                .velocity = rl_types.Vector2{ .x = 0, .y = 0 },
                .radius = enemy.radius * enemyScale,
                .active = true,
                .color = RED,
                .enemyState = .alive,
            };
        } else {
            return GameObject{
                .position = rl_types.Vector2{ .x = 0, .y = 0 },
                .velocity = rl_types.Vector2{ .x = 0, .y = 0 },
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
                    .position = rl_types.Vector2{ .x = dataObstacle.position.x, .y = dataObstacle.position.y },
                    .size = rl_types.Vector2{ .x = dataObstacle.size.x, .y = dataObstacle.size.y },
                    .type = obstacleType,
                    .active = true,
                };
            } else {
                self.scenes[sceneIndex].obstacles[i] = Obstacle{
                    .position = rl_types.Vector2{ .x = 0, .y = 0 },
                    .size = rl_types.Vector2{ .x = 0, .y = 0 },
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
                    .position = rl_types.Vector2{ .x = dataPortal.position.x, .y = dataPortal.position.y },
                    .radius = dataPortal.radius,
                    .active = true,
                    .destinationScene = dataPortal.destination,
                    .shape = destinationShape,
                };
            } else {
                self.scenes[sceneIndex].portals[i] = Portal{
                    .position = rl_types.Vector2{ .x = 0, .y = 0 },
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
        self.player.position = rl_types.Vector2{ .x = self.gameData.player_start.position.x, .y = self.gameData.player_start.position.y };
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
        self.winTime = 0.0;
        self.aggroTarget = null; // Reset aggro target
        self.friendlyTarget = null; // Reset friendly target
    }

    pub fn resurrect(self: *Self) void {
        // Resurrect player at original spawn location without resetting world state
        self.player.position = rl_types.Vector2{ .x = self.gameData.player_start.position.x, .y = self.gameData.player_start.position.y };
        self.player.active = true;
        self.gameOver = false;
        self.gameWon = false;
        self.isPaused = false;
        self.winTime = 0.0;
        // Don't reset aggroTarget/friendlyTarget - let enemies continue their current behavior

        // Clear any active bullets
        for (0..MAX_BULLETS) |i| {
            self.bullets[i].active = false;
        }
    }

    pub fn resetScene(self: *Self) void {
        // Reset only the current scene enemies to their spawn positions
        self.restoreEnemiesInScene(self.currentScene);

        // Reset player to original spawn location
        self.player.position = rl_types.Vector2{ .x = self.gameData.player_start.position.x, .y = self.gameData.player_start.position.y };
        self.player.active = true;

        // Clear bullets
        for (0..MAX_BULLETS) |i| {
            self.bullets[i].active = false;
        }

        // Reset game state flags
        self.gameOver = false;
        self.gameWon = false;
        self.isPaused = false;
        self.winTime = 0.0;
        self.aggroTarget = null; // Reset aggro target
        self.friendlyTarget = null; // Reset friendly target
    }

    fn checkCircleRectCollision(self: *Self, circlePos: rl_types.Vector2, radius: f32, rectPos: rl_types.Vector2, rectSize: rl_types.Vector2) bool {
        _ = self;
        const closestX = math.clamp(circlePos.x, rectPos.x, rectPos.x + rectSize.x);
        const closestY = math.clamp(circlePos.y, rectPos.y, rectPos.y + rectSize.y);

        const dx = circlePos.x - closestX;
        const dy = circlePos.y - closestY;

        return (dx * dx + dy * dy) <= (radius * radius);
    }

    fn isPositionBlocked(self: *Self, pos: rl_types.Vector2, radius: f32) bool {
        for (0..MAX_OBSTACLES) |i| {
            if (self.scenes[self.currentScene].obstacles[i].active and self.scenes[self.currentScene].obstacles[i].type == .blocking) {
                if (self.checkCircleRectCollision(pos, radius, self.scenes[self.currentScene].obstacles[i].position, self.scenes[self.currentScene].obstacles[i].size)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn updateCamera(self: *Self) void {
        // Only use camera tracking in non-overworld scenes (currentScene != 0)
        if (self.currentScene != 0) {
            // Smoothly follow the player
            self.camera.target = self.player.position;
        } else {
            // In overworld (scene 0), reset camera to center the screen
            self.camera.target = rl_types.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
            self.camera.offset = rl_types.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
        }
    }

    pub fn handleInput(self: *Self) void {
        // Handle pause toggle
        if (rl_core.IsKeyPressed(KEY_SPACE)) {
            self.isPaused = !self.isPaused;
        }

        // Handle speed control with chunky increments
        if (rl_core.IsKeyPressed(KEY_LEFT_BRACKET)) {
            self.gameSpeed = @max(0.25, self.gameSpeed - 0.25); // Min 0.25x speed
        }
        if (rl_core.IsKeyPressed(KEY_RIGHT_BRACKET)) {
            self.gameSpeed = @min(4.0, self.gameSpeed + 0.25); // Max 4x speed
        }
    }

    pub fn updatePlayer(self: *Self, deltaTime: f32) void {
        if (self.isPaused) return;

        // Set aggro target to player position (enemies will chase this)
        self.aggroTarget = self.player.position;
        var movement = rl_types.Vector2{ .x = 0, .y = 0 };

        // Mouse movement - move toward left click position
        if (rl_core.IsMouseButtonDown(MOUSE_LEFT)) {
            const mouseScreenPos = rl_core.GetMousePosition();
            const mousePos = rl_core.GetScreenToWorld2D(mouseScreenPos, self.camera);
            var direction = rl_types.Vector2{
                .x = mousePos.x - self.player.position.x,
                .y = mousePos.y - self.player.position.y,
            };

            const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
            // Get player radius for current scene
            const currentScene = &self.scenes[self.currentScene];
            const playerRadius = self.gameData.player_start.radius * currentScene.player_scale;
            if (length > playerRadius) { // Only move if mouse is outside player's radius
                direction.x /= length;
                direction.y /= length;
                movement = direction;
            }
        }

        // Keyboard movement (fallback/alternative)
        if (rl_core.IsKeyDown(KEY_W) or rl_core.IsKeyDown(KEY_UP)) movement.y -= 1;
        if (rl_core.IsKeyDown(KEY_S) or rl_core.IsKeyDown(KEY_DOWN)) movement.y += 1;
        if (rl_core.IsKeyDown(KEY_A) or rl_core.IsKeyDown(KEY_LEFT)) movement.x -= 1;
        if (rl_core.IsKeyDown(KEY_D) or rl_core.IsKeyDown(KEY_RIGHT)) movement.x += 1;

        // Normalize diagonal movement for keyboard
        if (movement.x != 0 and movement.y != 0 and !rl_core.IsMouseButtonDown(MOUSE_LEFT)) {
            movement.x *= DIAGONAL_FACTOR;
            movement.y *= DIAGONAL_FACTOR;
        }

        // Update position with collision checking (apply game speed)
        const effectiveDeltaTime = deltaTime * self.gameSpeed;
        const newX = self.player.position.x + movement.x * PLAYER_SPEED * effectiveDeltaTime;
        const newY = self.player.position.y + movement.y * PLAYER_SPEED * effectiveDeltaTime;

        // Get player radius for current scene
        const currentScene = &self.scenes[self.currentScene];
        const playerRadius = self.gameData.player_start.radius * currentScene.player_scale;

        // Check X movement
        const testPosX = rl_types.Vector2{ .x = newX, .y = self.player.position.y };
        if (!self.isPositionBlocked(testPosX, playerRadius)) {
            self.player.position.x = newX;
        }

        // Check Y movement
        const testPosY = rl_types.Vector2{ .x = self.player.position.x, .y = newY };
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
        const mouseScreenPos = rl_core.GetMousePosition();
        const mousePos = rl_core.GetScreenToWorld2D(mouseScreenPos, self.camera);
        var direction = rl_types.Vector2{
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
                // Choose target: aggro target if set, otherwise go to spawn location
                const target = if (self.aggroTarget) |aggroPos|
                    aggroPos
                else
                    self.scenes[self.currentScene].originalEnemies[i].position;

                // Move towards target
                var direction = rl_types.Vector2{
                    .x = target.x - self.scenes[self.currentScene].enemies[i].position.x,
                    .y = target.y - self.scenes[self.currentScene].enemies[i].position.y,
                };

                const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
                if (length > 0) {
                    direction.x /= length;
                    direction.y /= length;
                }

                // Use different speeds for overworld vs dungeons, and slower when not aggro
                var enemySpeed: f32 = if (self.currentScene == 0) ENEMY_SPEED * 0.15 else ENEMY_SPEED; // Slower in overworld
                if (self.aggroTarget == null) {
                    enemySpeed *= 0.333; // 1/3 speed when not aggro (returning to spawn)
                }
                const effectiveDeltaTime = deltaTime * self.gameSpeed;

                // Check for obstacle collision before moving
                const newX = self.scenes[self.currentScene].enemies[i].position.x + direction.x * enemySpeed * effectiveDeltaTime;
                const newY = self.scenes[self.currentScene].enemies[i].position.y + direction.y * enemySpeed * effectiveDeltaTime;

                // Check X movement
                const testPosX = rl_types.Vector2{ .x = newX, .y = self.scenes[self.currentScene].enemies[i].position.y };
                if (!self.isPositionBlocked(testPosX, self.scenes[self.currentScene].enemies[i].radius)) {
                    self.scenes[self.currentScene].enemies[i].position.x = newX;
                }

                // Check Y movement
                const testPosY = rl_types.Vector2{ .x = self.scenes[self.currentScene].enemies[i].position.x, .y = newY };
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
                    self.aggroTarget = null; // Clear aggro - enemies will return home
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
                    self.player.position = rl_types.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
                    // Update camera for new scene
                    self.updateCamera();
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
                    self.aggroTarget = null; // Clear aggro - enemies will return home
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
        if (allEnemiesDead and !self.gameWon) {
            self.gameWon = true;
            self.winTime = 0.0; // Start win animation timer
        }
    }

    pub fn updateWinState(self: *Self, deltaTime: f32) void {
        if (self.gameWon and !self.isPaused) {
            self.winTime += deltaTime;
        }
    }

    pub fn draw(self: *Self) !void {
        rl_core.BeginDrawing();
        defer rl_core.EndDrawing();

        // Use scene-specific background color
        const currentSceneBg = if (self.currentScene < NUM_SCENES)
            self.scenes[self.currentScene].background_color
        else
            rl_types.BLACK;
        rl_core.ClearBackground(currentSceneBg);

        // Begin camera mode for all game objects (player, enemies, bullets, obstacles, portals)
        rl_core.BeginMode2D(self.camera);

        if (!self.gameOver) {
            // Draw player with scene-based scaling
            const currentScene = &self.scenes[self.currentScene];
            const playerRadius = self.gameData.player_start.radius * currentScene.player_scale;
            rl_shapes.DrawCircleV(self.player.position, playerRadius, self.player.color);
            rl_shapes.DrawCircleLinesV(self.player.position, playerRadius, BLUE_BRIGHT);

            // Draw bullets
            for (0..MAX_BULLETS) |i| {
                if (self.bullets[i].active) {
                    rl_shapes.DrawCircleV(self.bullets[i].position, self.bullets[i].radius, self.bullets[i].color);
                    rl_shapes.DrawCircleLinesV(self.bullets[i].position, self.bullets[i].radius, YELLOW_BRIGHT);
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
                            rl_shapes.DrawCircleV(sceneData.enemies[i].position, sceneData.enemies[i].radius, sceneData.enemies[i].color);
                            rl_shapes.DrawCircleLinesV(sceneData.enemies[i].position, sceneData.enemies[i].radius, RED_BRIGHT);
                        },
                        .dead => {
                            // Draw dead enemies as gray circles with outline (same size)
                            rl_shapes.DrawCircleV(sceneData.enemies[i].position, sceneData.enemies[i].radius, GRAY);
                            rl_shapes.DrawCircleLinesV(sceneData.enemies[i].position, sceneData.enemies[i].radius, GRAY_BRIGHT);
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
                    rl_shapes.DrawRectangleV(sceneData.obstacles[i].position, sceneData.obstacles[i].size, color);
                    const obstacleRect = rl_types.Rectangle{ .x = sceneData.obstacles[i].position.x, .y = sceneData.obstacles[i].position.y, .width = sceneData.obstacles[i].size.x, .height = sceneData.obstacles[i].size.y };
                    rl_shapes.DrawRectangleLinesEx(obstacleRect, 2.0, outlineColor);
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
                            rl_shapes.DrawCircleV(pos, radius, ORANGE);
                            rl_shapes.DrawCircleLinesV(pos, radius, ORANGE_BRIGHT);
                        },
                        .triangle => {
                            // Draw triangle pointing up
                            rl_shapes.DrawTriangle(rl_types.Vector2{ .x = pos.x, .y = pos.y - radius }, rl_types.Vector2{ .x = pos.x - radius * 0.866, .y = pos.y + radius * 0.5 }, rl_types.Vector2{ .x = pos.x + radius * 0.866, .y = pos.y + radius * 0.5 }, ORANGE);
                            rl_shapes.DrawTriangleLines(rl_types.Vector2{ .x = pos.x, .y = pos.y - radius }, rl_types.Vector2{ .x = pos.x - radius * 0.866, .y = pos.y + radius * 0.5 }, rl_types.Vector2{ .x = pos.x + radius * 0.866, .y = pos.y + radius * 0.5 }, ORANGE_BRIGHT);
                        },
                        .square => {
                            const size = radius * 1.4; // Make square similar area to circle
                            const rectPos = rl_types.Vector2{ .x = pos.x - size / 2, .y = pos.y - size / 2 };
                            const rectSize = rl_types.Vector2{ .x = size, .y = size };
                            rl_shapes.DrawRectangleV(rectPos, rectSize, ORANGE);
                            const portalRect = rl_types.Rectangle{ .x = rectPos.x, .y = rectPos.y, .width = rectSize.x, .height = rectSize.y };
                            rl_shapes.DrawRectangleLinesEx(portalRect, 2.0, ORANGE_BRIGHT);
                        },
                    }
                }
            }

            // End camera mode before drawing UI elements
            rl_core.EndMode2D();

            // Draw UI with scene info (always in screen space)
            rl_text.DrawText("Left Click: Move | Right Click: Shoot | Orange = Portal", 10, @intFromFloat(SCREEN_HEIGHT - 80), 16, GRAY);
            rl_text.DrawText("WASD/Arrows: Move (Alt) | R: Resurrect | T: Reset Scene | Y: Reset Game | ESC: Quit", 10, @intFromFloat(SCREEN_HEIGHT - 60), 16, GRAY);

            // Scene indicator (using pre-allocated buffer)
            const sceneName = if (self.currentScene < NUM_SCENES)
                self.scenes[self.currentScene].name
            else
                "Unknown";
            const sceneText = std.fmt.bufPrintZ(&self.sceneTextBuffer, "Scene {d}/{d}: {s}", .{ self.currentScene, NUM_SCENES - 1, sceneName }) catch "Scene";
            rl_text.DrawText(sceneText, 10, @intFromFloat(SCREEN_HEIGHT - 40), 16, WHITE);

            // FPS Counter (top right corner, using pre-allocated buffer)
            const fps = rl_core.GetFPS();
            const fpsText = std.fmt.bufPrintZ(&self.fpsTextBuffer, "FPS: {d}", .{fps}) catch "FPS: --";
            const fpsWidth = rl_text.MeasureText(fpsText, 16);
            rl_text.DrawText(fpsText, @as(i32, @intFromFloat(SCREEN_WIDTH)) - fpsWidth - 10, 10, 16, WHITE);

            // Pause effect - yellow cycling border (takes priority over other states)
            if (self.isPaused) {
                const time = rl_core.GetTime();
                const pulse = (math.sin(time * 1.5) + 1.0) * 0.5; // 0.0 to 1.0, slower pulse
                const borderWidth = @as(i32, @intFromFloat(2 + pulse * 4)); // 2 to 6 pixels

                // Smooth cycle from orange (30°) to yellow (60°)
                const hue = 30.0 + (math.sin(time * 0.8) + 1.0) * 0.5 * 30.0; // 30° to 60° smoothly
                const borderColor = rl_textures.ColorFromHSV(@floatCast(hue), 0.8, 1.0); // Slightly less saturated

                // Draw thick border around entire screen
                rl_shapes.DrawRectangle(0, 0, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Top
                rl_shapes.DrawRectangle(0, @as(i32, @intFromFloat(SCREEN_HEIGHT)) - borderWidth, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Bottom
                rl_shapes.DrawRectangle(0, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Left
                rl_shapes.DrawRectangle(@as(i32, @intFromFloat(SCREEN_WIDTH)) - borderWidth, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Right
            }
            // Win state effect - different colored pulsing border
            else if (self.gameWon) {
                const pulse = (math.sin(self.winTime * 2.0) + 1.0) * 0.5; // 0.0 to 1.0, faster pulse for win
                const borderWidth = @as(i32, @intFromFloat(3 + pulse * 6)); // 3 to 9 pixels, thicker for win

                // Cycle between green and teal colors for win state (wider range)
                const hue: f32 = 120.0 + (math.sin(self.winTime * 1.0) + 1.0) * 0.5 * 60.0; // 120° to 180° smoothly (green to teal)
                const borderColor = rl_textures.ColorFromHSV(@floatCast(hue), 0.9, 1.0);

                // Draw thick border around entire screen
                rl_shapes.DrawRectangle(0, 0, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Top
                rl_shapes.DrawRectangle(0, @as(i32, @intFromFloat(SCREEN_HEIGHT)) - borderWidth, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Bottom
                rl_shapes.DrawRectangle(0, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Left
                rl_shapes.DrawRectangle(@as(i32, @intFromFloat(SCREEN_WIDTH)) - borderWidth, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Right
            }
        } else {
            // Game over - still draw the game world first
            const currentScene = &self.scenes[self.currentScene];
            const playerRadius = self.gameData.player_start.radius * currentScene.player_scale;
            // Draw player as gray circle when dead, same size as alive
            rl_shapes.DrawCircleV(self.player.position, playerRadius, GRAY);
            rl_shapes.DrawCircleLinesV(self.player.position, playerRadius, GRAY_BRIGHT);

            // Draw bullets
            for (0..MAX_BULLETS) |i| {
                if (self.bullets[i].active) {
                    rl_shapes.DrawCircleV(self.bullets[i].position, self.bullets[i].radius, self.bullets[i].color);
                    rl_shapes.DrawCircleLinesV(self.bullets[i].position, self.bullets[i].radius, YELLOW_BRIGHT);
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
                            rl_shapes.DrawCircleV(sceneData.enemies[i].position, sceneData.enemies[i].radius, sceneData.enemies[i].color);
                            rl_shapes.DrawCircleLinesV(sceneData.enemies[i].position, sceneData.enemies[i].radius, RED_BRIGHT);
                        },
                        .dead => {
                            // Draw dead enemies as gray circles with outline (same size)
                            rl_shapes.DrawCircleV(sceneData.enemies[i].position, sceneData.enemies[i].radius, GRAY);
                            rl_shapes.DrawCircleLinesV(sceneData.enemies[i].position, sceneData.enemies[i].radius, GRAY_BRIGHT);
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
                    rl_shapes.DrawRectangleV(sceneData.obstacles[i].position, sceneData.obstacles[i].size, color);
                    const obstacleRect = rl_types.Rectangle{ .x = sceneData.obstacles[i].position.x, .y = sceneData.obstacles[i].position.y, .width = sceneData.obstacles[i].size.x, .height = sceneData.obstacles[i].size.y };
                    rl_shapes.DrawRectangleLinesEx(obstacleRect, 2.0, outlineColor);
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
                            rl_shapes.DrawCircleV(pos, radius, ORANGE);
                            rl_shapes.DrawCircleLinesV(pos, radius, ORANGE_BRIGHT);
                        },
                        .triangle => {
                            // Draw triangle pointing up
                            rl_shapes.DrawTriangle(rl_types.Vector2{ .x = pos.x, .y = pos.y - radius }, rl_types.Vector2{ .x = pos.x - radius * 0.866, .y = pos.y + radius * 0.5 }, rl_types.Vector2{ .x = pos.x + radius * 0.866, .y = pos.y + radius * 0.5 }, ORANGE);
                            rl_shapes.DrawTriangleLines(rl_types.Vector2{ .x = pos.x, .y = pos.y - radius }, rl_types.Vector2{ .x = pos.x - radius * 0.866, .y = pos.y + radius * 0.5 }, rl_types.Vector2{ .x = pos.x + radius * 0.866, .y = pos.y + radius * 0.5 }, ORANGE_BRIGHT);
                        },
                        .square => {
                            const size = radius * 1.4; // Make square similar area to circle
                            const rectPos = rl_types.Vector2{ .x = pos.x - size / 2, .y = pos.y - size / 2 };
                            const rectSize = rl_types.Vector2{ .x = size, .y = size };
                            rl_shapes.DrawRectangleV(rectPos, rectSize, ORANGE);
                            const portalRect = rl_types.Rectangle{ .x = rectPos.x, .y = rectPos.y, .width = rectSize.x, .height = rectSize.y };
                            rl_shapes.DrawRectangleLinesEx(portalRect, 2.0, ORANGE_BRIGHT);
                        },
                    }
                }
            }

            // End camera mode before drawing UI in game over state
            rl_core.EndMode2D();

            // Draw UI with scene info (same as normal gameplay)
            rl_text.DrawText("Left Click: Move | Right Click: Shoot | Orange = Portal", 10, @intFromFloat(SCREEN_HEIGHT - 80), 16, GRAY);
            rl_text.DrawText("WASD/Arrows: Move (Alt) | R: Resurrect | T: Reset Scene | Y: Reset Game | ESC: Quit", 10, @intFromFloat(SCREEN_HEIGHT - 60), 16, GRAY);

            // Scene indicator (using pre-allocated buffer)
            const sceneName = if (self.currentScene < NUM_SCENES)
                self.scenes[self.currentScene].name
            else
                "Unknown";
            const sceneText = std.fmt.bufPrintZ(&self.sceneTextBuffer, "Scene {d}/{d}: {s}", .{ self.currentScene, NUM_SCENES - 1, sceneName }) catch "Scene";
            rl_text.DrawText(sceneText, 10, @intFromFloat(SCREEN_HEIGHT - 40), 16, WHITE);

            // FPS Counter (top right corner, using pre-allocated buffer)
            const fps = rl_core.GetFPS();
            const fpsText = std.fmt.bufPrintZ(&self.fpsTextBuffer, "FPS: {d}", .{fps}) catch "FPS: --";
            const fpsWidth = rl_text.MeasureText(fpsText, 16);
            rl_text.DrawText(fpsText, @as(i32, @intFromFloat(SCREEN_WIDTH)) - fpsWidth - 10, 10, 16, WHITE);

            // Game over effect - subtle red pulsing border
            const time = rl_core.GetTime();
            const pulse = (math.sin(time * 1.2) + 1.0) * 0.5; // 0.0 to 1.0, slower pulse for game over
            const borderWidth = @as(i32, @intFromFloat(3 + pulse * 5)); // 3 to 8 pixels

            // Dark red pulsing border
            const intensity = 0.6 + pulse * 0.4; // 0.6 to 1.0
            const borderColor = rl_types.Color{ .r = @intFromFloat(200 * intensity), .g = @intFromFloat(30 * intensity), .b = @intFromFloat(30 * intensity), .a = 255 };

            // Draw thick border around entire screen
            rl_shapes.DrawRectangle(0, 0, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Top
            rl_shapes.DrawRectangle(0, @as(i32, @intFromFloat(SCREEN_HEIGHT)) - borderWidth, @as(i32, @intFromFloat(SCREEN_WIDTH)), borderWidth, borderColor); // Bottom
            rl_shapes.DrawRectangle(0, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Left
            rl_shapes.DrawRectangle(@as(i32, @intFromFloat(SCREEN_WIDTH)) - borderWidth, 0, borderWidth, @as(i32, @intFromFloat(SCREEN_HEIGHT)), borderColor); // Right
        }
    }
};

// Main entry point for CLI integration
pub fn run(allocator: std.mem.Allocator) !void {
    std.debug.print("Starting YAR - Yet Another RPG...\n", .{});

    rl_core.InitWindow(@intFromFloat(SCREEN_WIDTH), @intFromFloat(SCREEN_HEIGHT), "YAR - Yet Another RPG");
    defer rl_core.CloseWindow();

    rl_core.SetTargetFPS(144);

    var game = GameState.init(allocator) catch |err| {
        std.debug.print("Failed to initialize game: {}\n", .{err});
        return err;
    };

    while (!rl_core.WindowShouldClose()) {
        const deltaTime = rl_core.GetFrameTime();

        // Handle input regardless of game state
        game.handleInput();

        if (!game.gameOver) {
            game.updatePlayer(deltaTime);
            game.updateCamera(); // Update camera after player movement
            game.updateWinState(deltaTime);

            if (rl_core.IsMouseButtonPressed(MOUSE_RIGHT) and !game.isPaused) {
                game.fireBullet();
            }

            game.updateBullets(deltaTime);
            if (!game.isPaused) {
                game.checkCollisions();
            }
        } else {
            // Update camera even when game is over
            game.updateCamera();
            // Allow mouse click resurrect on game over screens
            if (rl_core.IsMouseButtonPressed(MOUSE_LEFT)) {
                game.resurrect();
            }
        }

        // Always update enemies (they target spawn when game over)
        game.updateEnemies(deltaTime);

        // R key: always resurrect (revive player at spawn without resetting world)
        if (rl_core.IsKeyPressed(KEY_R)) {
            game.resurrect();
        }

        // T key: reset current scene (restore enemies in current scene only)
        if (rl_core.IsKeyPressed(KEY_T)) {
            game.resetScene();
        }

        // Y key: full restart (reset entire game state)
        if (rl_core.IsKeyPressed(KEY_Y)) {
            game.restart();
        }

        if (rl_core.IsKeyPressed(KEY_ESCAPE)) break;

        try game.draw();
    }
}
