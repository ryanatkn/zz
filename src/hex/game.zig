const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const behaviors = @import("behaviors.zig");
const physics = @import("physics.zig");
const input = @import("input.zig");
const player_controller = @import("player.zig");
const combat = @import("combat.zig");
const portals = @import("portals.zig");
const camera = @import("camera.zig");
const effects = @import("effects.zig");

const sdl = @import("sdl.zig").c;

const Vec2 = types.Vec2;
const World = entities.World;
const InputState = input.InputState;

pub const GameState = struct {
    world: World,
    input_state: InputState,
    game_paused: bool,
    quit_requested: bool,

    // Visual effects system
    effect_system: effects.EffectSystem,

    // Iris wipe effect for resurrection
    iris_wipe_active: bool,
    iris_wipe_start_time: u64,

    const Self = @This();

    pub fn init() Self {
        return .{
            .world = World.init(),
            .input_state = InputState.init(),
            .game_paused = false,
            .quit_requested = false,
            .effect_system = effects.EffectSystem.init(),
            .iris_wipe_active = false,
            .iris_wipe_start_time = 0,
        };
    }

    pub fn travelToZone(self: *Self, destination_zone: usize) void {
        if (destination_zone < self.world.zones.len) {
            self.world.current_zone = destination_zone;
            self.world.zones[destination_zone].resetUnits();
            // Clear bullets on zone travel
            for (0..entities.MAX_BULLETS) |i| {
                self.world.bullets[i].active = false;
            }
            // Clear ALL effects on zone travel to prevent persistence
            self.effect_system.clear();
            // Rebuild ambient effects for new zone
            self.effect_system.refreshAmbientEffects(&self.world);
        }
    }

    pub fn togglePause(self: *Self) void {
        self.game_paused = !self.game_paused;
        if (self.game_paused) {
            std.debug.print("Game paused\n", .{});
        } else {
            std.debug.print("Game resumed\n", .{});
        }
    }

    pub fn requestQuit(self: *Self) void {
        self.quit_requested = true;
    }

    pub fn shouldQuit(self: *const Self) bool {
        return self.quit_requested;
    }

    pub fn isPaused(self: *const Self) bool {
        return self.game_paused;
    }

    pub fn resetZone(self: *Self) void {
        // Reset units in current zone to their original spawn state
        self.world.resetCurrentZone();
        std.debug.print("Zone units reset to original state\n", .{});
    }

    pub fn resetGame(self: *Self) void {
        // Reset player to starting position and state
        self.world.player.pos = self.world.player_start_pos;
        self.world.player.vel = types.Vec2{ .x = 0, .y = 0 };
        self.world.player.alive = true;
        self.world.player.color = @import("constants.zig").COLOR_PLAYER_ALIVE;
        
        // Reset to starting zone
        if (self.world.current_zone != 0) {
            self.travelToZone(0);
        }
        
        // Reset all zones
        self.world.resetAllZones();
        
        // Clear effects for clean slate
        self.effect_system.clear();
        self.effect_system.refreshAmbientEffects(&self.world);
        
        std.debug.print("Full game reset\n", .{});
    }
};

pub fn updateGame(game_state: *GameState, cam: *const camera.Camera, deltaTime: f32) void {
    if (game_state.game_paused) return;

    const world = &game_state.world;
    const input_state = &game_state.input_state;

    if (world.player.alive) {
        player_controller.updatePlayer(&world.player, input_state, world.getCurrentZone(), cam, deltaTime);
    }

    for (0..entities.MAX_BULLETS) |i| {
        behaviors.updateBullet(&world.bullets[i], deltaTime);
    }

    const zone = world.getCurrentZoneMut();
    for (0..zone.unit_count) |i| {
        const unit = &zone.units[i];

        if (!unit.active or !unit.alive) continue;

        const old_pos = unit.pos;
        behaviors.updateUnit(unit, world.player.pos, world.player.alive, deltaTime);

        for (0..zone.obstacle_count) |j| {
            const obstacle = &zone.obstacles[j];
            if (!obstacle.active) continue;

            if (physics.checkCircleRectCollision(unit.pos, unit.radius, obstacle.pos, obstacle.size)) {
                if (obstacle.is_deadly) {
                    combat.handleUnitDeathOnHazard(unit);
                } else {
                    unit.pos = old_pos;
                }
                break;
            }
        }
    }

    checkCollisions(game_state);

    // Update visual effects
    game_state.effect_system.update();
}

pub fn checkCollisions(game_state: *GameState) void {
    const world = &game_state.world;
    const zone = world.getCurrentZoneMut();
    const player = &world.player;

    physics.processBulletCollisions(world);

    if (!player.alive) return;

    if (portals.checkPortalCollisions(game_state)) {
        return;
    }

    for (0..zone.unit_count) |i| {
        if (physics.checkPlayerUnitCollision(player, &zone.units[i])) {
            combat.handlePlayerDeath(player);
            return;
        }
    }

    for (0..zone.lifestone_count) |i| {
        if (!zone.lifestones[i].attuned and physics.checkPlayerLifestoneCollision(player, &zone.lifestones[i])) {
            behaviors.attuneLifestone(&zone.lifestones[i]);
            std.debug.print("Lifestone attuned!\n", .{});
            // Add inner effect for newly attuned lifestone
            // TODO more declaratively?
            game_state.effect_system.addLifestoneInnerEffectOnly(zone.lifestones[i].pos, zone.lifestones[i].radius);
        }
    }

    if (physics.collidesWithDeadlyObstacle(player.pos, player.radius, zone)) {
        combat.handlePlayerDeathOnHazard(player);
    }
}

pub fn handleFireBullet(game_state: *GameState, cam: *const camera.Camera) void {
    if (game_state.world.player.alive and !game_state.game_paused) {
        const world_mouse_pos = game_state.input_state.getWorldMousePos(cam);
        combat.fireBulletAtMouse(&game_state.world, world_mouse_pos);
    }
}

pub fn handleRespawn(game_state: *GameState) void {
    // Start iris wipe effect
    game_state.iris_wipe_active = true;
    game_state.iris_wipe_start_time = sdl.SDL_GetPerformanceCounter();

    combat.respawnPlayer(game_state);
}
