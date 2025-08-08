const std = @import("std");
const math = std.math;

// SDL C imports
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

// Game constants - ported from YAR
const SCREEN_WIDTH: f32 = 1920;
const SCREEN_HEIGHT: f32 = 1080;
const DIAGONAL_FACTOR = @sqrt(0.5); // ~0.707
const TARGET_FPS = 144;

// Color cycling frequency for consistent rapid color changes
const COLOR_CYCLE_FREQ = 4.0;

// Border animation constants
const ASPECT_RATIO = 16.0 / 9.0;
const BORDER_PULSE_PAUSED = 1.5;
const BORDER_PULSE_DEAD = 1.2;

// Border color definitions for cycling
const BorderColorPair = struct {
    dark: struct { r: f32, g: f32, b: f32 },
    bright: struct { r: f32, g: f32, b: f32 },
};

const GOLD_YELLOW_COLORS = BorderColorPair{
    .dark = .{ .r = 200.0, .g = 150.0, .b = 10.0 },
    .bright = .{ .r = 255.0, .g = 240.0, .b = 0.0 },
};

const RED_COLORS = BorderColorPair{
    .dark = .{ .r = 180.0, .g = 40.0, .b = 40.0 },
    .bright = .{ .r = 255.0, .g = 30.0, .b = 30.0 },
};

const GREEN_COLORS = BorderColorPair{
    .dark = .{ .r = 20.0, .g = 160.0, .b = 20.0 },
    .bright = .{ .r = 50.0, .g = 220.0, .b = 80.0 },
};

// Player and movement constants
const PLAYER_SPEED = 600.0;
const BULLET_SPEED = 400.0;
const ENEMY_SPEED = 100.0;
const MAX_BULLETS = 20;
const MAX_ENEMIES = 12;
const MAX_OBSTACLES = 15;
const MAX_PORTALS = 6;
const MAX_LIFESTONES = 12;
const NUM_SCENES = 7;

// Colors (SDL RGBA format) - ported from YAR color palette
const Color = struct { r: u8, g: u8, b: u8, a: u8 };

const BLUE = Color{ .r = 0, .g = 70, .b = 200, .a = 255 };
const GREEN = Color{ .r = 0, .g = 140, .b = 0, .a = 255 };
const PURPLE = Color{ .r = 120, .g = 30, .b = 160, .a = 255 };
const RED = Color{ .r = 200, .g = 30, .b = 30, .a = 255 };
const YELLOW = Color{ .r = 220, .g = 160, .b = 0, .a = 255 };
const ORANGE = Color{ .r = 200, .g = 100, .b = 0, .a = 255 };
const GRAY = Color{ .r = 100, .g = 100, .b = 100, .a = 255 };
const WHITE = Color{ .r = 230, .g = 230, .b = 230, .a = 255 };
const DARK = Color{ .r = 20, .g = 20, .b = 30, .a = 255 };
const OCEAN_BLUE = Color{ .r = 40, .g = 60, .b = 80, .a = 255 };
const CYAN = Color{ .r = 0, .g = 200, .b = 200, .a = 255 };
const CYAN_FADED = Color{ .r = 0, .g = 100, .b = 100, .a = 255 };

// Bright outline variants
const BLUE_BRIGHT = Color{ .r = 100, .g = 150, .b = 255, .a = 255 };
const GREEN_BRIGHT = Color{ .r = 80, .g = 220, .b = 80, .a = 255 };
const PURPLE_BRIGHT = Color{ .r = 180, .g = 100, .b = 240, .a = 255 };
const RED_BRIGHT = Color{ .r = 255, .g = 100, .b = 100, .a = 255 };
const YELLOW_BRIGHT = Color{ .r = 255, .g = 220, .b = 80, .a = 255 };
const ORANGE_BRIGHT = Color{ .r = 255, .g = 180, .b = 80, .a = 255 };
const GRAY_BRIGHT = Color{ .r = 180, .g = 180, .b = 180, .a = 255 };
const WHITE_BRIGHT = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };

// Game structures - ported from YAR
const Vec2 = struct { x: f32, y: f32 };

const EnemyState = enum {
    alive,
    dead,
};

const GameObject = struct {
    position: Vec2,
    velocity: Vec2,
    radius: f32,
    active: bool,
    color: Color,
    enemyState: EnemyState,
};

const ObstacleType = enum {
    blocking,
    deadly,
};

const CameraMode = enum {
    fixed,
    follow,
};

const SceneShape = enum {
    circle,
    triangle,
    square,
};

const Portal = struct {
    position: Vec2,
    radius: f32,
    active: bool,
    destinationScene: u8,
    shape: SceneShape,
};

const Lifestone = struct {
    position: Vec2,
    radius: f32,
    active: bool,
    attuned: bool,
};

const LifestoneResult = struct {
    scene: u8,
    position: Vec2,
};

const Obstacle = struct {
    position: Vec2,
    size: Vec2,
    type: ObstacleType,
    active: bool,
};

const Scene = struct {
    enemies: [MAX_ENEMIES]GameObject,
    originalEnemies: [MAX_ENEMIES]GameObject,
    obstacles: [MAX_OBSTACLES]Obstacle,
    portals: [MAX_PORTALS]Portal,
    lifestones: [MAX_LIFESTONES]Lifestone,
    shape: SceneShape,
    name: []const u8,
    background_color: Color,
    unit_scale: f32,
    camera_mode: CameraMode,
};

// Data structures for loading from ZON (same as YAR)
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

const DataLifestone = struct {
    position: struct { x: f32, y: f32 },
    radius: f32,
};

const DataScene = struct {
    name: []const u8,
    background_color: struct { r: u8, g: u8, b: u8 },
    unit_scale: f32,
    camera_mode: []const u8,
    obstacles: []const DataObstacle,
    enemies: []const DataEnemy,
    portals: []const DataPortal,
    lifestones: []const DataLifestone,
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

// Camera structure for SDL3 (simplified)
const Camera2D = struct {
    offset: Vec2,
    target: Vec2,
    rotation: f32,
    zoom: f32,
};

// Viewport management for maintaining aspect ratio
const Viewport = struct {
    rect: c.SDL_Rect,
    window_width: c_int,
    window_height: c_int,

    fn update(self: *Viewport, window: *c.SDL_Window) void {
        _ = c.SDL_GetWindowSize(window, &self.window_width, &self.window_height);

        const window_aspect_ratio = @as(f32, @floatFromInt(self.window_width)) / @as(f32, @floatFromInt(self.window_height));

        if (window_aspect_ratio > ASPECT_RATIO) {
            // Pillarboxing
            const viewport_width = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(self.window_height)) * ASPECT_RATIO));
            const offset_x = @divTrunc(self.window_width - viewport_width, 2);

            self.rect = c.SDL_Rect{
                .x = offset_x,
                .y = 0,
                .w = viewport_width,
                .h = self.window_height,
            };
        } else {
            // Letterboxing
            const viewport_height = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(self.window_width)) / ASPECT_RATIO));
            const offset_y = @divTrunc(self.window_height - viewport_height, 2);

            self.rect = c.SDL_Rect{
                .x = 0,
                .y = offset_y,
                .w = self.window_width,
                .h = viewport_height,
            };
        }
    }

    fn windowToGameCoords(self: *const Viewport, window_x: f32, window_y: f32) Vec2 {
        const viewport_x = window_x - @as(f32, @floatFromInt(self.rect.x));
        const viewport_y = window_y - @as(f32, @floatFromInt(self.rect.y));

        const scale_x = SCREEN_WIDTH / @as(f32, @floatFromInt(self.rect.w));
        const scale_y = SCREEN_HEIGHT / @as(f32, @floatFromInt(self.rect.h));

        return Vec2{
            .x = viewport_x * scale_x,
            .y = viewport_y * scale_y,
        };
    }
};

// Color interpolation utility
fn interpolateColor(color_pair: BorderColorPair, t: f32, intensity: f32) Color {
    return Color{
        .r = @intFromFloat((color_pair.dark.r + (color_pair.bright.r - color_pair.dark.r) * t) * intensity),
        .g = @intFromFloat((color_pair.dark.g + (color_pair.bright.g - color_pair.dark.g) * t) * intensity),
        .b = @intFromFloat((color_pair.dark.b + (color_pair.bright.b - color_pair.dark.b) * t) * intensity),
        .a = 255,
    };
}

const GameState = struct {
    player: GameObject,
    bullets: [MAX_BULLETS]GameObject,
    scenes: [NUM_SCENES]Scene,
    currentScene: u8,
    playerDead: bool,
    allocator: std.mem.Allocator,
    gameData: GameData,
    isPaused: bool,
    gameSpeed: f32,
    aggroTarget: ?Vec2,
    friendlyTarget: ?Vec2,
    sceneTextBuffer: [128]u8,
    fpsTextBuffer: [32]u8,
    camera: Camera2D,

    // FPS tracking with SDL high-resolution timers
    fps_counter: u32,
    fps_frames: u32,
    fps_last_time: u64,

    // SDL-specific state
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    mouse_x: f32,
    mouse_y: f32,
    keys_down: std.StaticBitSet(512), // SDL_SCANCODE_COUNT
    left_mouse_held: bool,

    // Viewport for maintaining 16:9 aspect ratio with letterboxing/pillarboxing
    viewport: Viewport,

    // Pre-allocated drawing buffers for performance
    circle_points: [200]c.SDL_FPoint, // Max points for largest circle
    rect_points: [4]c.SDL_FPoint, // Rectangle corners

    const Self = @This();

    pub fn deinit(self: *Self) void {
        std.zon.parse.free(self.allocator, self.gameData);
    }

    pub fn init(allocator: std.mem.Allocator, window: *c.SDL_Window, renderer: *c.SDL_Renderer) !Self {
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
                .position = Vec2{ .x = gameData.player_start.position.x, .y = gameData.player_start.position.y },
                .velocity = Vec2{ .x = 0, .y = 0 },
                .radius = gameData.player_start.radius,
                .active = true,
                .color = BLUE,
                .enemyState = .alive,
            },
            .bullets = undefined,
            .scenes = undefined,
            .currentScene = gameData.player_start.scene,
            .playerDead = false,
            .allocator = allocator,
            .gameData = gameData,
            .isPaused = false,
            .gameSpeed = 1.0,
            .aggroTarget = null,
            .friendlyTarget = null,
            .sceneTextBuffer = undefined,
            .fpsTextBuffer = undefined,
            .fps_counter = 60, // Start with reasonable default
            .fps_frames = 0,
            .fps_last_time = c.SDL_GetPerformanceCounter(),
            .camera = Camera2D{
                .offset = Vec2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 },
                .target = Vec2{ .x = gameData.player_start.position.x, .y = gameData.player_start.position.y },
                .rotation = 0.0,
                .zoom = 1.0,
            },
            .window = window,
            .renderer = renderer,
            .mouse_x = 0,
            .mouse_y = 0,
            .keys_down = std.StaticBitSet(512).initEmpty(),
            .left_mouse_held = false,
            .viewport = Viewport{
                .rect = undefined,
                .window_width = 0,
                .window_height = 0,
            },
            .circle_points = undefined,
            .rect_points = undefined,
        };

        // Initialize bullets
        for (0..MAX_BULLETS) |i| {
            game.bullets[i] = GameObject{
                .position = Vec2{ .x = 0, .y = 0 },
                .velocity = Vec2{ .x = 0, .y = 0 },
                .radius = 5.0,
                .active = false,
                .color = YELLOW,
                .enemyState = .alive,
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

            const camera_mode: CameraMode = if (std.mem.eql(u8, dataScene.camera_mode, "follow"))
                .follow
            else
                .fixed;

            game.scenes[sceneIndex] = Scene{
                .enemies = undefined,
                .originalEnemies = undefined,
                .obstacles = undefined,
                .portals = undefined,
                .lifestones = undefined,
                .shape = shape,
                .name = dataScene.name,
                .background_color = Color{
                    .r = dataScene.background_color.r,
                    .g = dataScene.background_color.g,
                    .b = dataScene.background_color.b,
                    .a = 255,
                },
                .unit_scale = dataScene.unit_scale,
                .camera_mode = camera_mode,
            };

            game.loadSceneFromData(@intCast(sceneIndex));
        }

        // Initialize viewport
        game.viewport.update(window);

        return game;
    }

    fn createEnemyFromData(dataEnemy: ?DataEnemy, unitScale: f32) GameObject {
        if (dataEnemy) |enemy| {
            return GameObject{
                .position = Vec2{ .x = enemy.position.x, .y = enemy.position.y },
                .velocity = Vec2{ .x = 0, .y = 0 },
                .radius = enemy.radius * unitScale,
                .active = true,
                .color = RED,
                .enemyState = .alive,
            };
        } else {
            return GameObject{
                .position = Vec2{ .x = 0, .y = 0 },
                .velocity = Vec2{ .x = 0, .y = 0 },
                .radius = 15.0,
                .active = false,
                .color = RED,
                .enemyState = .alive,
            };
        }
    }

    fn loadSceneFromData(self: *Self, sceneIndex: u8) void {
        const dataScene = self.gameData.scenes[sceneIndex];

        // Load enemies from data
        for (0..MAX_ENEMIES) |i| {
            const dataEnemy = if (i < dataScene.enemies.len) dataScene.enemies[i] else null;
            const enemy = createEnemyFromData(dataEnemy, dataScene.unit_scale);
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
                    .position = Vec2{ .x = dataObstacle.position.x, .y = dataObstacle.position.y },
                    .size = Vec2{ .x = dataObstacle.size.x, .y = dataObstacle.size.y },
                    .type = obstacleType,
                    .active = true,
                };
            } else {
                self.scenes[sceneIndex].obstacles[i] = Obstacle{
                    .position = Vec2{ .x = 0, .y = 0 },
                    .size = Vec2{ .x = 0, .y = 0 },
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
                    .position = Vec2{ .x = dataPortal.position.x, .y = dataPortal.position.y },
                    .radius = dataPortal.radius * dataScene.unit_scale,
                    .active = true,
                    .destinationScene = dataPortal.destination,
                    .shape = destinationShape,
                };
            } else {
                self.scenes[sceneIndex].portals[i] = Portal{
                    .position = Vec2{ .x = 0, .y = 0 },
                    .radius = 25.0 * dataScene.unit_scale,
                    .active = false,
                    .destinationScene = 0,
                    .shape = .circle,
                };
            }
        }

        // Load lifestones from data
        for (0..MAX_LIFESTONES) |i| {
            if (i < dataScene.lifestones.len) {
                const dataLifestone = dataScene.lifestones[i];
                self.scenes[sceneIndex].lifestones[i] = Lifestone{
                    .position = Vec2{ .x = dataLifestone.position.x, .y = dataLifestone.position.y },
                    .radius = dataLifestone.radius * dataScene.unit_scale,
                    .active = true,
                    .attuned = false,
                };
            } else {
                self.scenes[sceneIndex].lifestones[i] = Lifestone{
                    .position = Vec2{ .x = 0, .y = 0 },
                    .radius = 8.0 * dataScene.unit_scale,
                    .active = false,
                    .attuned = false,
                };
            }
        }
    }

    // Optimized color handling - cache last color to avoid redundant SDL calls
    var last_color: ?Color = null;

    inline fn colorToSDL(color: Color) struct { r: u8, g: u8, b: u8, a: u8 } {
        return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
    }

    fn setRenderColor(self: *Self, color: Color) void {
        // Only change SDL color state if different from last color
        if (last_color == null or !std.meta.eql(last_color.?, color)) {
            const sdl_color = colorToSDL(color);
            _ = c.SDL_SetRenderDrawColor(self.renderer, sdl_color.r, sdl_color.g, sdl_color.b, sdl_color.a);
            last_color = color;
        }
    }

    fn checkCircleRectCollision(self: *Self, circlePos: Vec2, radius: f32, rectPos: Vec2, rectSize: Vec2) bool {
        _ = self;
        const closestX = math.clamp(circlePos.x, rectPos.x, rectPos.x + rectSize.x);
        const closestY = math.clamp(circlePos.y, rectPos.y, rectPos.y + rectSize.y);

        const dx = circlePos.x - closestX;
        const dy = circlePos.y - closestY;

        return (dx * dx + dy * dy) <= (radius * radius);
    }

    fn isPositionBlocked(self: *Self, pos: Vec2, radius: f32) bool {
        for (0..MAX_OBSTACLES) |i| {
            if (self.scenes[self.currentScene].obstacles[i].active and self.scenes[self.currentScene].obstacles[i].type == .blocking) {
                if (self.checkCircleRectCollision(pos, radius, self.scenes[self.currentScene].obstacles[i].position, self.scenes[self.currentScene].obstacles[i].size)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn restoreEnemiesInScene(self: *Self, sceneIndex: u8) void {
        // Restore all enemies in the specified scene to their original state (bulk copy)
        self.scenes[sceneIndex].enemies = self.scenes[sceneIndex].originalEnemies;
    }

    fn findNearestAttunedLifestone(self: *Self) ?LifestoneResult {
        // 1. Check current scene first - prefer any lifestone in current scene
        var nearestDistance: f32 = std.math.floatMax(f32);
        var nearestLifestone: ?LifestoneResult = null;

        for (0..MAX_LIFESTONES) |i| {
            if (self.scenes[self.currentScene].lifestones[i].active and self.scenes[self.currentScene].lifestones[i].attuned) {
                const dx = self.player.position.x - self.scenes[self.currentScene].lifestones[i].position.x;
                const dy = self.player.position.y - self.scenes[self.currentScene].lifestones[i].position.y;
                const distance = dx * dx + dy * dy; // Use squared distance to avoid sqrt

                if (distance < nearestDistance) {
                    nearestDistance = distance;
                    nearestLifestone = LifestoneResult{
                        .scene = self.currentScene,
                        .position = self.scenes[self.currentScene].lifestones[i].position,
                    };
                }
            }
        }

        // If found in current scene, return it immediately
        if (nearestLifestone != null) {
            return nearestLifestone;
        }

        // 2-3. Breadth-first search through portal network
        // We'll use simple arrays for BFS queue since scene count is small
        var visited: [NUM_SCENES]bool = [_]bool{false} ** NUM_SCENES;
        var queue: [NUM_SCENES]struct { scene: u8, entry_portal_pos: Vec2, depth: u32 } = undefined;
        var queue_start: usize = 0;
        var queue_end: usize = 0;

        visited[self.currentScene] = true;

        // 2. Start BFS: Add all portals from current scene to queue
        for (0..MAX_PORTALS) |i| {
            if (self.scenes[self.currentScene].portals[i].active) {
                const portal = self.scenes[self.currentScene].portals[i];
                const dest_scene = portal.destinationScene;

                if (!visited[dest_scene]) {
                    visited[dest_scene] = true;

                    // Find the return portal in the destination scene that leads back to current scene
                    var entry_portal_pos = Vec2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }; // Default center
                    for (0..MAX_PORTALS) |j| {
                        if (self.scenes[dest_scene].portals[j].active and
                            self.scenes[dest_scene].portals[j].destinationScene == self.currentScene)
                        {
                            entry_portal_pos = self.scenes[dest_scene].portals[j].position;
                            break;
                        }
                    }

                    queue[queue_end] = .{
                        .scene = dest_scene,
                        .entry_portal_pos = entry_portal_pos, // Position of portal in destination scene
                        .depth = 1,
                    };
                    queue_end += 1;
                }
            }
        }

        // BFS through scenes
        while (queue_start < queue_end) {
            const current = queue[queue_start];
            queue_start += 1;

            // Search for lifestones in this scene
            for (0..MAX_LIFESTONES) |i| {
                if (self.scenes[current.scene].lifestones[i].active and self.scenes[current.scene].lifestones[i].attuned) {
                    // Calculate distance from portal entry point in this scene to the lifestone
                    const lifestone_dx = current.entry_portal_pos.x - self.scenes[current.scene].lifestones[i].position.x;
                    const lifestone_dy = current.entry_portal_pos.y - self.scenes[current.scene].lifestones[i].position.y;
                    const lifestone_distance = lifestone_dx * lifestone_dx + lifestone_dy * lifestone_dy;

                    // Add penalty based on depth (number of portal hops)
                    const depth_penalty = @as(f32, @floatFromInt(current.depth)) * 100000.0;
                    const total_distance = lifestone_distance + depth_penalty;

                    if (total_distance < nearestDistance) {
                        nearestDistance = total_distance;
                        nearestLifestone = LifestoneResult{
                            .scene = current.scene,
                            .position = self.scenes[current.scene].lifestones[i].position,
                        };
                    }
                }
            }

            // Add connected scenes to queue for next depth level
            for (0..MAX_PORTALS) |i| {
                if (self.scenes[current.scene].portals[i].active) {
                    const portal = self.scenes[current.scene].portals[i];
                    const dest_scene = portal.destinationScene;

                    if (!visited[dest_scene] and queue_end < NUM_SCENES) {
                        visited[dest_scene] = true;

                        // Find the entry portal in the new destination scene
                        var entry_portal_pos = Vec2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 }; // Default center
                        for (0..MAX_PORTALS) |j| {
                            if (self.scenes[dest_scene].portals[j].active and
                                self.scenes[dest_scene].portals[j].destinationScene == current.scene)
                            {
                                entry_portal_pos = self.scenes[dest_scene].portals[j].position;
                                break;
                            }
                        }

                        queue[queue_end] = .{
                            .scene = dest_scene,
                            .entry_portal_pos = entry_portal_pos,
                            .depth = current.depth + 1,
                        };
                        queue_end += 1;
                    }
                }
            }
        }

        return nearestLifestone;
    }

    fn updateCamera(self: *Self) void {
        const currentScene = &self.scenes[self.currentScene];

        if (currentScene.camera_mode == .follow) {
            // Camera follows the player
            self.camera.target = self.player.position;
            // Set camera offset to center of screen for proper following
            self.camera.offset = Vec2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
        } else {
            // Fixed camera - center the screen
            self.camera.target = Vec2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
            self.camera.offset = Vec2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
        }
    }

    // Transform world coordinates to screen coordinates using camera
    fn worldToScreen(self: *Self, worldPos: Vec2) Vec2 {
        const currentScene = &self.scenes[self.currentScene];

        if (currentScene.camera_mode == .fixed) {
            // No camera transformation for fixed camera
            return worldPos;
        } else {
            // Apply camera transformation for following camera
            return Vec2{
                .x = worldPos.x - self.camera.target.x + self.camera.offset.x,
                .y = worldPos.y - self.camera.target.y + self.camera.offset.y,
            };
        }
    }

    // Transform screen coordinates to world coordinates using camera
    fn screenToWorld(self: *Self, screenPos: Vec2) Vec2 {
        const currentScene = &self.scenes[self.currentScene];

        if (currentScene.camera_mode == .fixed) {
            // No camera transformation for fixed camera
            return screenPos;
        } else {
            // Reverse camera transformation for following camera
            return Vec2{
                .x = screenPos.x + self.camera.target.x - self.camera.offset.x,
                .y = screenPos.y + self.camera.target.y - self.camera.offset.y,
            };
        }
    }

    pub fn restart(self: *Self) void {
        // Reset player to starting position
        self.player.position = Vec2{ .x = self.gameData.player_start.position.x, .y = self.gameData.player_start.position.y };
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

        self.playerDead = false;
        self.isPaused = false;
        self.aggroTarget = null; // Reset aggro target
        self.friendlyTarget = null; // Reset friendly target
    }

    pub fn resurrect(self: *Self) void {
        // Find nearest attuned lifestone
        if (self.findNearestAttunedLifestone()) |nearestLifestone| {
            // Teleport to nearest attuned lifestone
            if (nearestLifestone.scene != self.currentScene) {
                // Switch to the lifestone's scene
                self.currentScene = nearestLifestone.scene;
                // Update camera for new scene
                self.updateCamera();
                // Restore enemies in the destination scene
                self.restoreEnemiesInScene(nearestLifestone.scene);
            }
            self.player.position = nearestLifestone.position;
        } else {
            // Fallback to original spawn location if no lifestones are attuned
            self.player.position = Vec2{ .x = self.gameData.player_start.position.x, .y = self.gameData.player_start.position.y };
            self.currentScene = self.gameData.player_start.scene;
        }

        self.player.active = true;
        self.playerDead = false;
        self.isPaused = false;
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
        self.player.position = Vec2{ .x = self.gameData.player_start.position.x, .y = self.gameData.player_start.position.y };
        self.player.active = true;

        // Clear bullets
        for (0..MAX_BULLETS) |i| {
            self.bullets[i].active = false;
        }

        // Reset game state flags
        self.playerDead = false;
        self.isPaused = false;
        self.aggroTarget = null; // Reset aggro target
        self.friendlyTarget = null; // Reset friendly target
    }

    pub fn handleInput(self: *Self) void {
        // TODO: Convert SDL input to YAR-style input handling
        // Handle keyboard state
        _ = self;
    }

    pub fn updatePlayer(self: *Self, deltaTime: f32) void {
        if (self.isPaused) return;

        // Set aggro target to player position (enemies will chase this)
        self.aggroTarget = self.player.position;
        var movement = Vec2{ .x = 0, .y = 0 };

        // Mouse movement - ONLY when left mouse button is held down
        if (self.left_mouse_held) {
            const direction = Vec2{
                .x = self.mouse_x - self.player.position.x,
                .y = self.mouse_y - self.player.position.y,
            };

            const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
            const playerRadius = self.gameData.player_start.radius * self.scenes[self.currentScene].unit_scale;
            if (length > playerRadius) { // Only move if mouse is outside player's radius
                movement.x = direction.x / length;
                movement.y = direction.y / length;
            }
        }

        // Keyboard movement (fallback/alternative)
        if (self.keys_down.isSet(c.SDL_SCANCODE_W) or self.keys_down.isSet(c.SDL_SCANCODE_UP)) movement.y -= 1;
        if (self.keys_down.isSet(c.SDL_SCANCODE_S) or self.keys_down.isSet(c.SDL_SCANCODE_DOWN)) movement.y += 1;
        if (self.keys_down.isSet(c.SDL_SCANCODE_A) or self.keys_down.isSet(c.SDL_SCANCODE_LEFT)) movement.x -= 1;
        if (self.keys_down.isSet(c.SDL_SCANCODE_D) or self.keys_down.isSet(c.SDL_SCANCODE_RIGHT)) movement.x += 1;

        // Normalize diagonal movement for keyboard
        if (movement.x != 0 and movement.y != 0 and !self.left_mouse_held) {
            movement.x *= DIAGONAL_FACTOR;
            movement.y *= DIAGONAL_FACTOR;
        }

        // Update position with collision checking (apply game speed)
        const effectiveDeltaTime = deltaTime * self.gameSpeed;
        const newX = self.player.position.x + movement.x * PLAYER_SPEED * effectiveDeltaTime;
        const newY = self.player.position.y + movement.y * PLAYER_SPEED * effectiveDeltaTime;

        // Get player radius with scene scaling
        const playerRadius = self.gameData.player_start.radius * self.scenes[self.currentScene].unit_scale;

        // Check X movement
        const testPosX = Vec2{ .x = newX, .y = self.player.position.y };
        if (!self.isPositionBlocked(testPosX, playerRadius)) {
            self.player.position.x = newX;
        }

        // Check Y movement
        const testPosY = Vec2{ .x = self.player.position.x, .y = newY };
        if (!self.isPositionBlocked(testPosY, playerRadius)) {
            self.player.position.y = newY;
        }

        // Keep player bounded based on camera mode
        const currentScene = &self.scenes[self.currentScene];
        if (currentScene.camera_mode == .fixed) {
            // Fixed camera: keep player on screen
            if (self.player.position.x < playerRadius)
                self.player.position.x = playerRadius;
            if (self.player.position.x > SCREEN_WIDTH - playerRadius)
                self.player.position.x = SCREEN_WIDTH - playerRadius;
            if (self.player.position.y < playerRadius)
                self.player.position.y = playerRadius;
            if (self.player.position.y > SCREEN_HEIGHT - playerRadius)
                self.player.position.y = SCREEN_HEIGHT - playerRadius;
        }
        // Follow camera: no screen bounds, movement only limited by terrain (obstacles)
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
                var direction = Vec2{
                    .x = target.x - self.scenes[self.currentScene].enemies[i].position.x,
                    .y = target.y - self.scenes[self.currentScene].enemies[i].position.y,
                };

                const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
                if (length > 0) {
                    direction.x /= length;
                    direction.y /= length;
                }

                // Use different speeds for overworld vs dungeons, and slower when not aggro
                var enemySpeed: f32 = if (self.currentScene == 0) ENEMY_SPEED * 0.15 else ENEMY_SPEED;
                if (self.aggroTarget == null) {
                    enemySpeed *= 0.333; // 1/3 speed when not aggro (returning to spawn)
                }
                const effectiveDeltaTime = deltaTime * self.gameSpeed;

                // Check for obstacle collision before moving
                const newX = self.scenes[self.currentScene].enemies[i].position.x + direction.x * enemySpeed * effectiveDeltaTime;
                const newY = self.scenes[self.currentScene].enemies[i].position.y + direction.y * enemySpeed * effectiveDeltaTime;

                // Check X movement
                const testPosX = Vec2{ .x = newX, .y = self.scenes[self.currentScene].enemies[i].position.y };
                if (!self.isPositionBlocked(testPosX, self.scenes[self.currentScene].enemies[i].radius)) {
                    self.scenes[self.currentScene].enemies[i].position.x = newX;
                }

                // Check Y movement
                const testPosY = Vec2{ .x = self.scenes[self.currentScene].enemies[i].position.x, .y = newY };
                if (!self.isPositionBlocked(testPosY, self.scenes[self.currentScene].enemies[i].radius)) {
                    self.scenes[self.currentScene].enemies[i].position.y = newY;
                }
            }
        }
    }

    pub fn checkCollisions(self: *Self) void {
        const currentScene = &self.scenes[self.currentScene];
        const playerRadius = self.gameData.player_start.radius * currentScene.unit_scale;
        const playerPos = self.player.position;

        // Cache arrays for better performance
        const bullets = &self.bullets;
        const enemies = &currentScene.enemies;
        const obstacles = &currentScene.obstacles;
        const portals = &currentScene.portals;
        const lifestones = &currentScene.lifestones;

        // Player-Lifestone collisions (attunement) - avoid sqrt
        for (0..MAX_LIFESTONES) |i| {
            if (lifestones[i].active and !lifestones[i].attuned) {
                const dx = playerPos.x - lifestones[i].position.x;
                const dy = playerPos.y - lifestones[i].position.y;
                const distanceSq = dx * dx + dy * dy;
                const radiusSum = playerRadius + lifestones[i].radius;

                if (distanceSq < radiusSum * radiusSum) {
                    // Attune to this lifestone
                    lifestones[i].attuned = true;
                }
            }
        }

        // Bullet-Enemy collisions (current scene only) - avoid sqrt when possible
        for (0..MAX_BULLETS) |i| {
            if (bullets[i].active) {
                const bulletPos = bullets[i].position;
                const bulletRadius = bullets[i].radius;

                for (0..MAX_ENEMIES) |j| {
                    if (enemies[j].active and enemies[j].enemyState == .alive) {
                        const dx = bulletPos.x - enemies[j].position.x;
                        const dy = bulletPos.y - enemies[j].position.y;
                        const distanceSq = dx * dx + dy * dy;
                        const radiusSum = bulletRadius + enemies[j].radius;

                        if (distanceSq < radiusSum * radiusSum) {
                            bullets[i].active = false;
                            enemies[j].enemyState = .dead;
                        }
                    }
                }
            }
        }

        // Player-Enemy collisions (current scene only) - avoid sqrt
        for (0..MAX_ENEMIES) |i| {
            if (enemies[i].active and enemies[i].enemyState == .alive) {
                const dx = playerPos.x - enemies[i].position.x;
                const dy = playerPos.y - enemies[i].position.y;
                const distanceSq = dx * dx + dy * dy;
                const radiusSum = playerRadius + enemies[i].radius;

                if (distanceSq < radiusSum * radiusSum) {
                    self.playerDead = true;
                    self.aggroTarget = null; // Clear aggro - enemies will return home
                }
            }
        }

        // Player-Portal collisions (scene switching) - avoid sqrt
        for (0..MAX_PORTALS) |i| {
            if (portals[i].active) {
                const dx = playerPos.x - portals[i].position.x;
                const dy = playerPos.y - portals[i].position.y;
                const distanceSq = dx * dx + dy * dy;
                const radiusSum = playerRadius + portals[i].radius;

                if (distanceSq < radiusSum * radiusSum) {
                    const destinationScene = portals[i].destinationScene;
                    self.currentScene = destinationScene;
                    // Always place player at screen center
                    self.player.position = Vec2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
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
            if (obstacles[i].active and obstacles[i].type == .deadly) {
                if (self.checkCircleRectCollision(playerPos, playerRadius, obstacles[i].position, obstacles[i].size)) {
                    self.playerDead = true;
                    self.aggroTarget = null; // Clear aggro - enemies will return home
                }
            }
        }

        // Enemy-Deadly Obstacle collisions (current scene only)
        for (0..MAX_ENEMIES) |i| {
            if (enemies[i].active and enemies[i].enemyState == .alive) {
                for (0..MAX_OBSTACLES) |j| {
                    if (obstacles[j].active and obstacles[j].type == .deadly) {
                        if (self.checkCircleRectCollision(enemies[i].position, enemies[i].radius, obstacles[j].position, obstacles[j].size)) {
                            enemies[i].enemyState = .dead;
                        }
                    }
                }
            }
        }
    }

    pub fn fireBullet(self: *Self) void {
        // TODO: Port bullet firing logic from YAR
        // For now, simple bullet firing toward mouse
        const direction = Vec2{
            .x = self.mouse_x - self.player.position.x,
            .y = self.mouse_y - self.player.position.y,
        };

        const length = math.sqrt(direction.x * direction.x + direction.y * direction.y);
        if (length > 0) {
            const normalizedX = direction.x / length;
            const normalizedY = direction.y / length;

            // Find inactive bullet
            for (0..MAX_BULLETS) |i| {
                if (!self.bullets[i].active) {
                    self.bullets[i].position = self.player.position;
                    self.bullets[i].velocity.x = normalizedX * BULLET_SPEED;
                    self.bullets[i].velocity.y = normalizedY * BULLET_SPEED;
                    self.bullets[i].active = true;
                    break;
                }
            }
        }
    }

    // SDL3-specific drawing methods - optimized circle drawing with batched lines
    fn drawCircle(self: *Self, pos: Vec2, radius: f32, color: Color) void {
        self.setRenderColor(color);

        const center_x = pos.x;
        const center_y = pos.y;
        const r = radius;
        const r_sq = r * r;

        // Pre-compute and batch horizontal lines for better performance
        const r_int: i32 = @intFromFloat(r);
        var y: i32 = -r_int;
        while (y <= r_int) : (y += 1) {
            const y_f: f32 = @floatFromInt(y);
            const y_sq = y_f * y_f;
            if (y_sq <= r_sq) {
                const half_width = @sqrt(r_sq - y_sq);
                _ = c.SDL_RenderLine(self.renderer, center_x - half_width, center_y + y_f, center_x + half_width, center_y + y_f);
            }
        }
    }

    fn drawRect(self: *Self, pos: Vec2, size: Vec2, color: Color) void {
        self.setRenderColor(color);

        const rect = c.SDL_FRect{
            .x = pos.x,
            .y = pos.y,
            .w = size.x,
            .h = size.y,
        };
        _ = c.SDL_RenderFillRect(self.renderer, &rect);
    }

    pub fn draw(self: *Self) !void {
        // First clear the entire window with black (for letterbox/pillarbox bars)
        self.setRenderColor(Color{ .r = 0, .g = 0, .b = 0, .a = 255 });
        _ = c.SDL_RenderClear(self.renderer);

        // Set the viewport for 16:9 game content
        _ = c.SDL_SetRenderViewport(self.renderer, &self.viewport.rect);

        // Cache frequently used values
        const currentScene = &self.scenes[self.currentScene];

        // Clear game area with scene-specific background color
        const background_color = if (self.currentScene == 0) OCEAN_BLUE else currentScene.background_color;
        self.setRenderColor(background_color);
        _ = c.SDL_RenderClear(self.renderer);
        const playerRadius = self.gameData.player_start.radius * currentScene.unit_scale;
        const playerColor = if (self.playerDead) GRAY else self.player.color;

        // Draw player with scene-based scaling and camera transform
        const playerScreenPos = self.worldToScreen(self.player.position);
        self.drawCircle(playerScreenPos, playerRadius, playerColor);

        // Draw bullets (always visible) with scene-based scaling and camera transform
        for (0..MAX_BULLETS) |i| {
            if (self.bullets[i].active) {
                const bulletRadius = self.bullets[i].radius;
                const bulletScreenPos = self.worldToScreen(self.bullets[i].position);
                self.drawCircle(bulletScreenPos, bulletRadius, self.bullets[i].color);
            }
        }

        // Draw all scene entities (unified for alive/dead states)
        self.drawSceneEntities(currentScene);

        // Draw FPS counter in bottom right
        self.drawFPS();

        // Draw state-based screen border
        self.drawScreenBorder();

        // Reset viewport to full window before presenting
        _ = c.SDL_SetRenderViewport(self.renderer, null);

        _ = c.SDL_RenderPresent(self.renderer);
    }

    fn drawSceneEntities(self: *Self, sceneData: *const Scene) void {
        // Cache arrays to avoid repeated pointer dereferencing
        const enemies = &sceneData.enemies;
        const obstacles = &sceneData.obstacles;
        const portals = &sceneData.portals;
        const lifestones = &sceneData.lifestones;

        // Batch enemies by color to reduce state changes
        // Draw alive enemies first (red)
        for (0..MAX_ENEMIES) |i| {
            if (enemies[i].active and enemies[i].enemyState == .alive) {
                const enemyScreenPos = self.worldToScreen(enemies[i].position);
                self.drawCircle(enemyScreenPos, enemies[i].radius, enemies[i].color);
            }
        }

        // Draw dead enemies (gray) - batched together
        for (0..MAX_ENEMIES) |i| {
            if (enemies[i].active and enemies[i].enemyState == .dead) {
                const enemyScreenPos = self.worldToScreen(enemies[i].position);
                self.drawCircle(enemyScreenPos, enemies[i].radius, GRAY);
            }
        }

        // Batch obstacles by type to reduce state changes
        // Draw blocking obstacles first (green)
        for (0..MAX_OBSTACLES) |i| {
            if (obstacles[i].active and obstacles[i].type == .blocking) {
                const obstacleScreenPos = self.worldToScreen(obstacles[i].position);
                self.drawRect(obstacleScreenPos, obstacles[i].size, GREEN);
            }
        }

        // Draw deadly obstacles (purple)
        for (0..MAX_OBSTACLES) |i| {
            if (obstacles[i].active and obstacles[i].type == .deadly) {
                const obstacleScreenPos = self.worldToScreen(obstacles[i].position);
                self.drawRect(obstacleScreenPos, obstacles[i].size, PURPLE);
            }
        }

        // Draw all portals together (orange) - already batched by color
        for (0..MAX_PORTALS) |i| {
            if (portals[i].active) {
                const portalScreenPos = self.worldToScreen(portals[i].position);
                self.drawCircle(portalScreenPos, portals[i].radius, ORANGE);
            }
        }

        // Draw lifestones - batch by attunement state
        // Draw unattunmed lifestones first (faded cyan)
        for (0..MAX_LIFESTONES) |i| {
            if (lifestones[i].active and !lifestones[i].attuned) {
                const lifestoneScreenPos = self.worldToScreen(lifestones[i].position);
                self.drawCircle(lifestoneScreenPos, lifestones[i].radius, CYAN_FADED);
            }
        }

        // Draw attuned lifestones (bright cyan)
        for (0..MAX_LIFESTONES) |i| {
            if (lifestones[i].active and lifestones[i].attuned) {
                const lifestoneScreenPos = self.worldToScreen(lifestones[i].position);
                self.drawCircle(lifestoneScreenPos, lifestones[i].radius, CYAN);
            }
        }
    }

    // Simple bitmap digits for FPS display (5x7 pixels each)
    const DIGIT_WIDTH = 6; // 5 + 1 spacing
    const DIGIT_HEIGHT = 7;

    const DIGITS = [_][7]u8{
        // 0
        [_]u8{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
        // 1
        [_]u8{ 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
        // 2
        [_]u8{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111 },
        // 3
        [_]u8{ 0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110 },
        // 4
        [_]u8{ 0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010 },
        // 5
        [_]u8{ 0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110 },
        // 6
        [_]u8{ 0b01110, 0b10001, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 },
        // 7
        [_]u8{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000 },
        // 8
        [_]u8{ 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110 },
        // 9
        [_]u8{ 0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b10001, 0b01110 },
    };

    fn drawDigit(self: *Self, digit: u8, x: f32, y: f32) void {
        if (digit > 9) return;

        const pattern = DIGITS[digit];
        for (0..DIGIT_HEIGHT) |row| {
            const line = pattern[row];
            for (0..5) |col| { // 5 bits wide
                if ((line >> @intCast(4 - col)) & 1 != 0) {
                    const px = x + @as(f32, @floatFromInt(col));
                    const py = y + @as(f32, @floatFromInt(row));
                    _ = c.SDL_RenderPoint(self.renderer, px, py);
                }
            }
        }
    }

    fn updateFPS(self: *Self) void {
        self.fps_frames += 1;
        const current_time = c.SDL_GetPerformanceCounter();
        const elapsed_ticks = current_time - self.fps_last_time;
        const frequency = c.SDL_GetPerformanceFrequency();

        // Update FPS counter every second
        if (elapsed_ticks >= frequency) { // 1 second has passed
            self.fps_counter = self.fps_frames;
            self.fps_frames = 0;
            self.fps_last_time = current_time;
        }
    }

    fn drawFPS(self: *Self) void {

        // Set color for FPS text
        self.setRenderColor(WHITE);

        // Draw "FPS: " label and numbers in bottom right
        const fps_text_x = SCREEN_WIDTH - 80.0; // 80 pixels from right edge
        const fps_text_y = SCREEN_HEIGHT - 20.0; // 20 pixels from bottom

        // For now, just draw the FPS counter as a simple number
        // Extract digits from fps_counter
        if (self.fps_counter >= 100) {
            const hundreds = self.fps_counter / 100;
            const tens = (self.fps_counter % 100) / 10;
            const ones = self.fps_counter % 10;
            self.drawDigit(@intCast(hundreds), fps_text_x, fps_text_y);
            self.drawDigit(@intCast(tens), fps_text_x + DIGIT_WIDTH, fps_text_y);
            self.drawDigit(@intCast(ones), fps_text_x + DIGIT_WIDTH * 2, fps_text_y);
        } else if (self.fps_counter >= 10) {
            const tens = self.fps_counter / 10;
            const ones = self.fps_counter % 10;
            self.drawDigit(@intCast(tens), fps_text_x + DIGIT_WIDTH, fps_text_y);
            self.drawDigit(@intCast(ones), fps_text_x + DIGIT_WIDTH * 2, fps_text_y);
        } else {
            self.drawDigit(@intCast(self.fps_counter), fps_text_x + DIGIT_WIDTH * 2, fps_text_y);
        }
    }

    fn drawScreenBorder(self: *Self) void {
        // Determine border color and width based on game state
        // Priority: Paused (yellow) > Dead (red) > All enemies dead (green) > None

        const current_time_ms = @as(f32, @floatFromInt(c.SDL_GetTicks()));
        const current_time_sec = current_time_ms / 1000.0;

        var border_color: ?Color = null;
        var border_width: f32 = 0;

        // Paused state takes highest priority (yellow)
        if (self.isPaused) {
            const pulse = (math.sin(current_time_sec * BORDER_PULSE_PAUSED) + 1.0) * 0.5;
            border_width = 6.0 + pulse * 4.0;

            const hue_cycle = (math.sin(current_time_sec * COLOR_CYCLE_FREQ) + 1.0) * 0.5;
            const intensity = 0.8 + pulse * 0.2;
            border_color = interpolateColor(GOLD_YELLOW_COLORS, hue_cycle, intensity);
        }
        // Player dead state (red)
        else if (self.playerDead) {
            const pulse = (math.sin(current_time_sec * BORDER_PULSE_DEAD) + 1.0) * 0.5;
            border_width = 9.0 + pulse * 5.0;

            const hue_cycle = (math.sin(current_time_sec * COLOR_CYCLE_FREQ) + 1.0) * 0.5;
            const intensity = 0.6 + pulse * 0.4;
            border_color = interpolateColor(RED_COLORS, hue_cycle, intensity);
        }

        // Draw border if a state is active
        if (border_color) |color| {
            self.setRenderColor(color);

            // Draw 4 rectangles efficiently (top, bottom, left, right)
            const top_rect = c.SDL_FRect{ .x = 0, .y = 0, .w = SCREEN_WIDTH, .h = border_width };
            const bottom_rect = c.SDL_FRect{ .x = 0, .y = SCREEN_HEIGHT - border_width, .w = SCREEN_WIDTH, .h = border_width };
            const left_rect = c.SDL_FRect{ .x = 0, .y = 0, .w = border_width, .h = SCREEN_HEIGHT };
            const right_rect = c.SDL_FRect{ .x = SCREEN_WIDTH - border_width, .y = 0, .w = border_width, .h = SCREEN_HEIGHT };

            _ = c.SDL_RenderFillRect(self.renderer, &top_rect);
            _ = c.SDL_RenderFillRect(self.renderer, &bottom_rect);
            _ = c.SDL_RenderFillRect(self.renderer, &left_rect);
            _ = c.SDL_RenderFillRect(self.renderer, &right_rect);
        }
    }

    // All core methods from YAR have been ported
};

// Main game loop entry point
pub fn run(allocator: std.mem.Allocator, window: *c.SDL_Window, renderer: *c.SDL_Renderer) !void {
    var game = try GameState.init(allocator, window, renderer);
    defer game.deinit();

    // Use SDL high-resolution timer for better precision
    var last_time = c.SDL_GetPerformanceCounter();
    const frequency = c.SDL_GetPerformanceFrequency();

    // Main game loop
    while (true) {
        const current_time = c.SDL_GetPerformanceCounter();
        const delta_ticks = current_time - last_time;
        const deltaTimeSec: f32 = @as(f32, @floatFromInt(delta_ticks)) / @as(f32, @floatFromInt(frequency));
        last_time = current_time;

        // Handle events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => return,
                c.SDL_EVENT_WINDOW_RESIZED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
                    game.viewport.update(game.window);
                },
                c.SDL_EVENT_KEY_DOWN => {
                    game.keys_down.set(event.key.scancode);
                    switch (event.key.scancode) {
                        c.SDL_SCANCODE_ESCAPE => return,
                        c.SDL_SCANCODE_SPACE => game.isPaused = !game.isPaused,
                        c.SDL_SCANCODE_R => {
                            game.resurrect();
                        },
                        c.SDL_SCANCODE_T => {
                            game.resetScene();
                        },
                        c.SDL_SCANCODE_Y => {
                            game.restart();
                        },
                        else => {},
                    }
                },
                c.SDL_EVENT_KEY_UP => {
                    game.keys_down.unset(event.key.scancode);
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    const screen_coords = game.viewport.windowToGameCoords(event.motion.x, event.motion.y);
                    const world_coords = game.screenToWorld(screen_coords);
                    game.mouse_x = world_coords.x;
                    game.mouse_y = world_coords.y;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    switch (event.button.button) {
                        c.SDL_BUTTON_LEFT => {
                            if (game.playerDead) {
                                game.resurrect();
                            }
                            // Always start holding left mouse button and update coordinates
                            // (works for both resurrect case and normal movement)
                            game.left_mouse_held = true;
                            const screen_coords = game.viewport.windowToGameCoords(event.button.x, event.button.y);
                            const world_coords = game.screenToWorld(screen_coords);
                            game.mouse_x = world_coords.x;
                            game.mouse_y = world_coords.y;
                        },
                        c.SDL_BUTTON_RIGHT => {
                            if (!game.isPaused and !game.playerDead) {
                                game.fireBullet();
                            }
                        },
                        else => {},
                    }
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    switch (event.button.button) {
                        c.SDL_BUTTON_LEFT => {
                            // Stop holding left mouse button
                            game.left_mouse_held = false;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Update FPS counter
        game.updateFPS();

        // Update game state
        game.handleInput();

        // Always update camera, bullets, and enemies
        game.updateCamera();
        game.updateBullets(deltaTimeSec);
        game.updateEnemies(deltaTimeSec);

        // Only update player when alive
        if (!game.playerDead) {
            game.updatePlayer(deltaTimeSec);
        }

        // Only check collisions when alive and not paused
        if (!game.playerDead and !game.isPaused) {
            game.checkCollisions();
        }

        // Render
        try game.draw();

        // Optional frame limiting to target FPS
        const target_frame_time = frequency / TARGET_FPS;
        const frame_time = c.SDL_GetPerformanceCounter() - current_time;
        if (frame_time < target_frame_time) {
            const delay_ticks = target_frame_time - frame_time;
            const delay_ns = (delay_ticks * c.SDL_NS_PER_SECOND) / frequency;
            c.SDL_DelayPrecise(delay_ns);
        }
    }
}
