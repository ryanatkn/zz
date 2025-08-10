const std = @import("std");

const types = @import("types.zig");
const entities = @import("entities.zig");
const behaviors = @import("behaviors.zig");
const physics = @import("physics.zig");
const effects = @import("effects.zig");
const constants = @import("constants.zig");

const Vec2 = types.Vec2;
const World = entities.World;
const Player = entities.Player;

pub fn fireBullet(world: *World, target_pos: Vec2) void {
    if (!world.player.alive) return;

    if (world.findInactiveBullet()) |bullet| {
        behaviors.fireBullet(bullet, world.player.pos, target_pos);
    }
}

pub fn fireBulletAtMouse(world: *World, mouse_pos: Vec2) void {
    fireBullet(world, mouse_pos);
}

pub fn respawnPlayer(game_state: anytype) void {
    const world = &game_state.world;
    const effect_system = &game_state.effect_system;
    const nearest = physics.findNearestAttunedLifestone(world, world.player.pos);

    var respawn_pos: Vec2 = undefined;

    if (nearest) |result| {
        if (result.zone_index != world.current_zone) {
            game_state.travelToZone(result.zone_index);
            std.debug.print("Traveling to zone {} for nearest lifestone\n", .{result.zone_index});
        }
        respawn_pos = result.pos;
    } else {
        if (world.current_zone != 0) {
            game_state.travelToZone(0);
            std.debug.print("No lifestones found, returning to overworld spawn\n", .{});
        }
        respawn_pos = Vec2{ .x = constants.SCREEN_CENTER_X, .y = constants.SCREEN_CENTER_Y };
    }

    // Common respawn logic
    behaviors.respawnPlayer(&world.player, respawn_pos);
    effect_system.addPlayerSpawnEffect(respawn_pos, world.player.radius);
    std.debug.print("Player respawned!\n", .{});
}

pub fn handlePlayerDeath(player: *Player) void {
    behaviors.killPlayer(player);
    std.debug.print("Player died! Press R or click to respawn\n", .{});
}

pub fn handlePlayerDeathOnHazard(player: *Player) void {
    behaviors.killPlayer(player);
    std.debug.print("Player died on hazard! Press R or click to respawn\n", .{});
}

pub fn handleUnitDeath(unit: *entities.Unit) void {
    behaviors.killUnit(unit);
    std.debug.print("Unit defeated!\n", .{});
}

pub fn handleUnitDeathOnHazard(unit: *entities.Unit) void {
    behaviors.killUnit(unit);
    std.debug.print("Unit died on hazard!\n", .{});
}
