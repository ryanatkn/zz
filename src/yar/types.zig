const std = @import("std");
const raylib = @import("raylib.zig");

// Fixed 1080p resolution
pub const SCREEN_WIDTH: f32 = 1920;
pub const SCREEN_HEIGHT: f32 = 1080;
pub const PLAYER_SPEED = 200.0;
pub const BULLET_SPEED = 400.0;
pub const ENEMY_SPEED = 100.0;
pub const MAX_BULLETS = 20;
pub const MAX_ENEMIES = 10;
pub const MAX_OBSTACLES = 15;
pub const SAFE_SPAWN_DISTANCE = 150.0; // Minimum distance from player for safe spawning

// Vibrant color palette
pub const SOOTHING_BLUE = raylib.Color{ .r = 0, .g = 100, .b = 255, .a = 255 };
pub const SOOTHING_GREEN = raylib.Color{ .r = 0, .g = 180, .b = 0, .a = 255 };
pub const SOOTHING_PURPLE = raylib.Color{ .r = 150, .g = 50, .b = 200, .a = 255 };
pub const SOOTHING_RED = raylib.Color{ .r = 255, .g = 50, .b = 50, .a = 255 };
pub const SOOTHING_YELLOW = raylib.Color{ .r = 255, .g = 200, .b = 0, .a = 255 };
pub const SOOTHING_GRAY = raylib.Color{ .r = 128, .g = 128, .b = 128, .a = 255 };
pub const SOOTHING_WHITE = raylib.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
pub const SOOTHING_DARK = raylib.Color{ .r = 25, .g = 25, .b = 35, .a = 255 };

// Core data structures - designed for SOA/ECS patterns
pub const GameObject = struct {
    position: raylib.Vector2,
    velocity: raylib.Vector2,
    radius: f32,
    active: bool,
    color: raylib.Color,
};

pub const ObstacleType = enum {
    blocking, // Green - blocks movement
    deadly, // Purple - kills on contact
};

pub const Obstacle = struct {
    position: raylib.Vector2,
    size: raylib.Vector2,
    type: ObstacleType,
    active: bool,
};

// Main game state - could be further decomposed into SOA components
pub const GameState = struct {
    player: GameObject,
    bullets: [MAX_BULLETS]GameObject,
    enemies: [MAX_ENEMIES]GameObject,
    obstacles: [MAX_OBSTACLES]Obstacle,
    gameOver: bool,
    gameWon: bool,
    allocator: std.mem.Allocator,
};
