const std = @import("std");

const types = @import("types.zig");
const constants = @import("constants.zig");

const Vec2 = types.Vec2;
const Color = types.Color;

// Game constants
pub const MAX_UNITS = 12;
pub const MAX_OBSTACLES = 50;
pub const MAX_BULLETS = 20;
pub const MAX_PORTALS = 6;
pub const MAX_LIFESTONES = 13;

// Player entity - special, only one
pub const Player = struct {
    pos: Vec2,
    vel: Vec2,
    radius: f32,
    color: Color,
    alive: bool,

    pub fn init() Player {
        return .{
            .pos = Vec2{ .x = constants.SCREEN_CENTER_X, .y = constants.SCREEN_CENTER_Y },
            .vel = Vec2{ .x = 0, .y = 0 },
            .radius = constants.PLAYER_RADIUS,
            .color = constants.COLOR_PLAYER_ALIVE,
            .alive = true,
        };
    }
};

// Unit entity (enemies, neutrals, allies)
pub const Unit = struct {
    pos: Vec2,
    vel: Vec2,
    home_pos: Vec2, // Original spawn position for return behavior
    radius: f32,
    color: Color,
    alive: bool,
    active: bool,

    pub fn init(x: f32, y: f32, radius: f32) Unit {
        return .{
            .pos = Vec2{ .x = x, .y = y },
            .vel = Vec2{ .x = 0, .y = 0 },
            .home_pos = Vec2{ .x = x, .y = y },
            .radius = radius,
            .color = constants.COLOR_UNIT_DEFAULT,
            .alive = true,
            .active = true,
        };
    }
};

// Obstacle entity (rectangles)
pub const Obstacle = struct {
    pos: Vec2,
    size: Vec2,
    color: Color,
    is_deadly: bool,
    active: bool,

    pub fn init(x: f32, y: f32, width: f32, height: f32, is_deadly: bool) Obstacle {
        return .{
            .pos = Vec2{ .x = x, .y = y },
            .size = Vec2{ .x = width, .y = height },
            .color = if (is_deadly)
                constants.COLOR_OBSTACLE_DEADLY
            else
                constants.COLOR_OBSTACLE_BLOCKING,
            .is_deadly = is_deadly,
            .active = true,
        };
    }
};

// Bullet entity
pub const Bullet = struct {
    pos: Vec2,
    vel: Vec2,
    radius: f32,
    color: Color,
    active: bool,

    pub fn init() Bullet {
        return .{
            .pos = Vec2{ .x = 0, .y = 0 },
            .vel = Vec2{ .x = 0, .y = 0 },
            .radius = constants.BULLET_RADIUS,
            .color = constants.COLOR_BULLET,
            .active = false,
        };
    }
};

// Portal entity - gateway to travel between zones
pub const Portal = struct {
    pos: Vec2,
    radius: f32,
    color: Color,
    destination_zone: u8,
    active: bool,

    pub fn init(x: f32, y: f32, radius: f32, destination: u8) Portal {
        return .{
            .pos = Vec2{ .x = x, .y = y },
            .radius = radius,
            .color = constants.COLOR_PORTAL,
            .destination_zone = destination,
            .active = true,
        };
    }
};

// Lifestone entity
pub const Lifestone = struct {
    pos: Vec2,
    radius: f32,
    color: Color,
    attuned: bool,
    active: bool,

    pub fn init(x: f32, y: f32, radius: f32, pre_attuned: bool) Lifestone {
        return .{
            .pos = Vec2{ .x = x, .y = y },
            .radius = radius,
            .color = if (pre_attuned)
                constants.COLOR_LIFESTONE_ATTUNED
            else
                constants.COLOR_LIFESTONE_UNATTUNED,
            .attuned = pre_attuned,
            .active = true,
        };
    }
};

// Camera modes
pub const CameraMode = enum {
    fixed,
    follow,
};

// Zone - a distinct area of the game world with its own entities and environment
pub const Zone = struct {
    // Environmental properties
    name: []const u8,
    background_color: Color,
    camera_mode: CameraMode,
    camera_scale: f32, // Zoom level for this zone (1.0 = default, <1.0 = zoomed out, >1.0 = zoomed in)

    // Entity pools with counts
    units: [MAX_UNITS]Unit,
    unit_count: usize,

    obstacles: [MAX_OBSTACLES]Obstacle,
    obstacle_count: usize,

    portals: [MAX_PORTALS]Portal,
    portal_count: usize,

    lifestones: [MAX_LIFESTONES]Lifestone,
    lifestone_count: usize,

    // Original state for reset functionality
    original_units: [MAX_UNITS]Unit,
    original_unit_count: usize,

    pub fn init(name: []const u8, bg_color: Color, cam_mode: CameraMode, scale: f32) Zone {
        return .{
            .name = name,
            .background_color = bg_color,
            .camera_mode = cam_mode,
            .camera_scale = scale,
            .units = std.mem.zeroes([MAX_UNITS]Unit),
            .unit_count = 0,
            .obstacles = std.mem.zeroes([MAX_OBSTACLES]Obstacle),
            .obstacle_count = 0,
            .portals = std.mem.zeroes([MAX_PORTALS]Portal),
            .portal_count = 0,
            .lifestones = std.mem.zeroes([MAX_LIFESTONES]Lifestone),
            .lifestone_count = 0,
            .original_units = std.mem.zeroes([MAX_UNITS]Unit),
            .original_unit_count = 0,
        };
    }

    pub fn addUnit(self: *Zone, unit: Unit) void {
        if (self.unit_count < MAX_UNITS) {
            self.units[self.unit_count] = unit;
            self.unit_count += 1;
        }
    }

    pub fn addObstacle(self: *Zone, obstacle: Obstacle) void {
        if (self.obstacle_count < MAX_OBSTACLES) {
            self.obstacles[self.obstacle_count] = obstacle;
            self.obstacle_count += 1;
        }
    }

    pub fn addPortal(self: *Zone, portal: Portal) void {
        if (self.portal_count < MAX_PORTALS) {
            self.portals[self.portal_count] = portal;
            self.portal_count += 1;
        }
    }

    pub fn addLifestone(self: *Zone, lifestone: Lifestone) void {
        if (self.lifestone_count < MAX_LIFESTONES) {
            self.lifestones[self.lifestone_count] = lifestone;
            self.lifestone_count += 1;
        }
    }

    pub fn resetUnits(self: *Zone) void {
        for (0..self.unit_count) |i| {
            // Reset velocity to stop aggro movement - units will walk home naturally
            self.units[i].vel = Vec2{ .x = 0, .y = 0 };
            // Don't reset position or alive status - preserve death state and let them walk home
        }
    }

    pub fn resetUnitsToOriginal(self: *Zone) void {
        // Restore units from original state (bulk copy)
        self.units = self.original_units;
        self.unit_count = self.original_unit_count;
    }
};

// World state - contains all game zones and entities
pub const World = struct {
    // Player is special
    player: Player,
    player_start_pos: Vec2, // Original spawn position for full reset

    // Global bullet pool (persists across zone travel)
    bullets: [MAX_BULLETS]Bullet,

    // Zones the player can travel between
    zones: [7]Zone, // Overworld + 6 dungeons
    current_zone: usize,

    pub fn init() World {
        var world = World{
            .player = Player.init(),
            .player_start_pos = Vec2{ .x = constants.SCREEN_CENTER_X, .y = constants.SCREEN_CENTER_Y },
            .bullets = undefined,
            .zones = undefined,
            .current_zone = 0,
        };

        // Initialize bullets
        for (0..MAX_BULLETS) |i| {
            world.bullets[i] = Bullet.init();
        }

        // Zones will be loaded from ZON data
        return world;
    }

    pub fn getCurrentZone(self: *const World) *const Zone {
        return &self.zones[self.current_zone];
    }

    pub fn getCurrentZoneMut(self: *World) *Zone {
        return &self.zones[self.current_zone];
    }

    pub fn findInactiveBullet(self: *World) ?*Bullet {
        for (0..MAX_BULLETS) |i| {
            if (!self.bullets[i].active) {
                return &self.bullets[i];
            }
        }
        return null;
    }

    pub fn resetCurrentZone(self: *World) void {
        // Reset units in current zone to their original spawn state
        self.zones[self.current_zone].resetUnitsToOriginal();
    }

    pub fn resetAllZones(self: *World) void {
        // Reset all zones to their original state
        for (0..self.zones.len) |i| {
            self.zones[i].resetUnitsToOriginal();
        }
        // Clear all bullets
        for (0..MAX_BULLETS) |i| {
            self.bullets[i].active = false;
        }
    }
};
