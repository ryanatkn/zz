const std = @import("std");
const types = @import("types.zig");
const entities = @import("entities.zig");
const behaviors = @import("behaviors.zig");
const maths = @import("maths.zig");
const physics = @import("physics.zig");
const player_controller = @import("player.zig");
const input = @import("input.zig");
const constants = @import("constants.zig");
const effects = @import("effects.zig");

const Vec2 = types.Vec2;
const World = entities.World;
const Portal = entities.Portal;
const Player = entities.Player;

pub fn handlePortalTravel(game_state: anytype, portal: *const Portal) void {
    const world = &game_state.world;
    const effect_system = &game_state.effect_system;
    game_state.input_state.clearMouseHold();

    const movement_direction = player_controller.getPlayerMovementDirection(&world.player);

    const origin_zone = world.current_zone;
    const destination_zone = portal.destination_zone;
    game_state.travelToZone(destination_zone);

    std.debug.print("Portal travel! Entering zone {} from zone {}\n", .{ destination_zone, origin_zone });

    const new_zone = &world.zones[destination_zone];
    for (0..new_zone.portal_count) |i| {
        const return_portal = &new_zone.portals[i];
        if (return_portal.active and return_portal.destination_zone == origin_zone) {
            const offset_distance = return_portal.radius + world.player.radius + constants.PORTAL_SPAWN_OFFSET;

            if (movement_direction.x != 0 or movement_direction.y != 0) {
                world.player.pos = Vec2{
                    .x = return_portal.pos.x + movement_direction.x * offset_distance,
                    .y = return_portal.pos.y + movement_direction.y * offset_distance,
                };
            } else {
                world.player.pos = Vec2{
                    .x = return_portal.pos.x,
                    .y = return_portal.pos.y + offset_distance,
                };
            }

            world.player.pos.x = std.math.clamp(world.player.pos.x, world.player.radius, constants.SCREEN_WIDTH - world.player.radius);
            world.player.pos.y = std.math.clamp(world.player.pos.y, world.player.radius, constants.SCREEN_HEIGHT - world.player.radius);

            // Add portal travel effect on the player
            effect_system.addPortalTravelEffect(world.player.pos, world.player.radius);
            
            // Add portal ripple effect on the portal itself in the new zone
            effect_system.addPortalRippleEffect(return_portal.pos, return_portal.radius);
            return;
        }
    }

    world.player.pos = Vec2{ .x = constants.SCREEN_CENTER_X, .y = constants.SCREEN_CENTER_Y };

    // Add portal travel effect for fallback spawn
    effect_system.addPortalTravelEffect(world.player.pos, world.player.radius);
}

pub fn checkPortalCollisions(game_state: anytype) bool {
    const world = &game_state.world;
    const zone = world.getCurrentZone();
    const player = &world.player;

    if (!player.alive) return false;

    for (0..zone.portal_count) |i| {
        if (physics.checkPlayerPortalCollision(player, &zone.portals[i])) {
            handlePortalTravel(game_state, &zone.portals[i]);
            return true;
        }
    }

    return false;
}
