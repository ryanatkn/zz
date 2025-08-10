// Loader - loads ZON data into entity pools
const std = @import("std");
const entities = @import("entities.zig");
const types = @import("types.zig");

const Vec2 = types.Vec2;
const Color = types.Color;

// Global arena for ZON data that persists for game lifetime
var game_data_arena: ?std.heap.ArenaAllocator = null;

// Clean up game data memory
pub fn deinit() void {
    if (game_data_arena) |*arena| {
        arena.deinit();
        game_data_arena = null;
    }
}

// Load game data from ZON file
pub fn loadGameData(allocator: std.mem.Allocator, world: *entities.World) !void {
    // Load game data from ZON file
    const gameDataFile = @embedFile("game_data.zon");

    // Initialize arena if not already done
    if (game_data_arena == null) {
        game_data_arena = std.heap.ArenaAllocator.init(allocator);
    }
    const arena_allocator = game_data_arena.?.allocator();

    // Convert to null-terminated string for ZON parser
    const gameDataNullTerm = try arena_allocator.dupeZ(u8, gameDataFile);

    const game_data = std.zon.parse.fromSlice(GameData, arena_allocator, gameDataNullTerm, null, .{}) catch |err| {
        std.debug.print("Failed to parse ZON file: {}\n", .{err});
        std.debug.print("This is likely due to a mismatch between the ZON file structure and the expected GameData struct\n", .{});
        return err;
    };

    // Set player start position
    world.player.pos = Vec2{
        .x = game_data.player_start.position.x,
        .y = game_data.player_start.position.y,
    };
    world.player.radius = game_data.player_start.radius;
    // Store original spawn position for full reset
    world.player_start_pos = world.player.pos;

    // Load each zone
    for (game_data.zones, 0..) |zone_data, i| {
        // Initialize zone with basic data (scale will be set in loadZone)
        world.zones[i] = entities.Zone.init("", types.Color{ .r = 0, .g = 0, .b = 0, .a = 255 }, entities.CameraMode.follow, 1.0);
        // Then load detailed data
        loadZone(&world.zones[i], zone_data);
    }
}

// Load a single zone from ZON data
fn loadZone(zone: *entities.Zone, data: ZoneData) void {
    // Set zone properties - use static strings to avoid allocation
    if (std.mem.eql(u8, data.name, "Overworld")) {
        zone.name = "Overworld";
    } else if (std.mem.indexOf(u8, data.name, "Southeast") != null) {
        zone.name = "Southeast Dungeon";
    } else if (std.mem.indexOf(u8, data.name, "Southwest") != null) {
        zone.name = "Southwest Dungeon";
    } else if (std.mem.indexOf(u8, data.name, "West") != null) {
        zone.name = "West Dungeon";
    } else if (std.mem.indexOf(u8, data.name, "Northwest") != null) {
        zone.name = "Northwest Dungeon";
    } else if (std.mem.indexOf(u8, data.name, "Northeast") != null) {
        zone.name = "Northeast Dungeon";
    } else if (std.mem.indexOf(u8, data.name, "East") != null) {
        zone.name = "East Dungeon";
    } else {
        zone.name = "Unknown";
    }

    zone.background_color = Color{
        .r = data.background_color.r,
        .g = data.background_color.g,
        .b = data.background_color.b,
        .a = 255,
    };

    // Set camera mode for this zone
    if (std.mem.eql(u8, data.camera_mode, "fixed")) {
        zone.camera_mode = entities.CameraMode.fixed;
    } else {
        zone.camera_mode = entities.CameraMode.follow;
    }

    // Set camera scale (default to 1.0 if not specified)
    zone.camera_scale = data.camera_scale orelse 1.0;

    // Load obstacles
    if (data.obstacles) |obstacles| {
        for (obstacles) |obstacle_data| {
            const is_deadly = std.mem.eql(u8, obstacle_data.type, "deadly");
            const obstacle = entities.Obstacle.init(
                obstacle_data.position.x,
                obstacle_data.position.y,
                obstacle_data.size.x,
                obstacle_data.size.y,
                is_deadly,
            );
            zone.addObstacle(obstacle);
        }
    }

    // Load units
    if (data.units) |units| {
        for (units) |unit_data| {
            const unit = entities.Unit.init(
                unit_data.position.x,
                unit_data.position.y,
                unit_data.radius,
            );
            zone.addUnit(unit);
            // Also store in original units for reset functionality
            if (zone.original_unit_count < entities.MAX_UNITS) {
                zone.original_units[zone.original_unit_count] = unit;
                zone.original_unit_count += 1;
            }
        }
    }

    // Load portals
    if (data.portals) |portals| {
        for (portals) |portal_data| {
            const portal = entities.Portal.init(
                portal_data.position.x,
                portal_data.position.y,
                portal_data.radius,
                portal_data.destination,
            );
            zone.addPortal(portal);
        }
    }

    // Load lifestones
    if (data.lifestones) |lifestones| {
        for (lifestones) |lifestone_data| {
            // First lifestone in overworld (zone 0) is pre-attuned
            const pre_attuned = (zone.lifestone_count == 0 and std.mem.eql(u8, data.name, "Overworld"));
            const lifestone = entities.Lifestone.init(
                lifestone_data.position.x,
                lifestone_data.position.y,
                lifestone_data.radius,
                pre_attuned,
            );
            zone.addLifestone(lifestone);
        }
    }
}

// ZON data structures
const GameData = struct {
    screen_width: f32,
    screen_height: f32,
    player_start: struct {
        zone: u8,
        position: struct { x: f32, y: f32 },
        radius: f32,
    },
    zones: []const ZoneData,
};

const ZoneData = struct {
    name: []const u8,
    background_color: struct { r: u8, g: u8, b: u8 },
    camera_mode: []const u8,
    camera_scale: ?f32 = null,  // Optional camera scale with default value
    obstacles: ?[]const struct {
        position: struct { x: f32, y: f32 },
        size: struct { x: f32, y: f32 },
        type: []const u8,
    },
    units: ?[]const struct {
        position: struct { x: f32, y: f32 },
        radius: f32,
    },
    portals: ?[]const struct {
        position: struct { x: f32, y: f32 },
        radius: f32,
        destination: u8,
        shape: []const u8,
    },
    lifestones: ?[]const struct {
        position: struct { x: f32, y: f32 },
        radius: f32,
    },
};

