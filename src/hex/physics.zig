// Collision detection and physics
const std = @import("std");
const entities = @import("entities.zig");
const types = @import("types.zig");

const Vec2 = types.Vec2;

// Check circle-circle collision
pub fn checkCircleCollision(pos1: Vec2, radius1: f32, pos2: Vec2, radius2: f32) bool {
    const dx = pos1.x - pos2.x;
    const dy = pos1.y - pos2.y;
    const distance_sq = dx * dx + dy * dy;
    const radius_sum = radius1 + radius2;
    return distance_sq < radius_sum * radius_sum;
}

// Check circle-rectangle collision
pub fn checkCircleRectCollision(circle_pos: Vec2, circle_radius: f32, rect_pos: Vec2, rect_size: Vec2) bool {
    const closest_x = std.math.clamp(circle_pos.x, rect_pos.x, rect_pos.x + rect_size.x);
    const closest_y = std.math.clamp(circle_pos.y, rect_pos.y, rect_pos.y + rect_size.y);

    const dx = circle_pos.x - closest_x;
    const dy = circle_pos.y - closest_y;

    return dx * dx + dy * dy < circle_radius * circle_radius;
}

// Check player-unit collision
pub fn checkPlayerUnitCollision(player: *const entities.Player, unit: *const entities.Unit) bool {
    if (!player.alive or !unit.active or !unit.alive) return false;
    return checkCircleCollision(player.pos, player.radius, unit.pos, unit.radius);
}

// Check bullet-unit collision
pub fn checkBulletUnitCollision(bullet: *const entities.Bullet, unit: *const entities.Unit) bool {
    if (!bullet.active or !unit.active or !unit.alive) return false;
    return checkCircleCollision(bullet.pos, bullet.radius, unit.pos, unit.radius);
}

// Check player-obstacle collision
pub fn checkPlayerObstacleCollision(player: *const entities.Player, obstacle: *const entities.Obstacle) bool {
    if (!player.alive or !obstacle.active) return false;
    return checkCircleRectCollision(player.pos, player.radius, obstacle.pos, obstacle.size);
}

// Check unit-obstacle collision
pub fn checkUnitObstacleCollision(unit: *const entities.Unit, obstacle: *const entities.Obstacle) bool {
    if (!unit.active or !obstacle.active) return false;
    return checkCircleRectCollision(unit.pos, unit.radius, obstacle.pos, obstacle.size);
}

// Check player-portal collision
pub fn checkPlayerPortalCollision(player: *const entities.Player, portal: *const entities.Portal) bool {
    if (!player.alive or !portal.active) return false;
    return checkCircleCollision(player.pos, player.radius, portal.pos, portal.radius);
}

// Check player-lifestone collision
pub fn checkPlayerLifestoneCollision(player: *const entities.Player, lifestone: *const entities.Lifestone) bool {
    if (!player.alive or !lifestone.active) return false;
    return checkCircleCollision(player.pos, player.radius, lifestone.pos, lifestone.radius);
}

// Process all collisions for a zone
pub fn processCollisions(world: *entities.World) void {
    const zone = world.getCurrentZone();
    const player = &world.player;

    // Skip player collisions if dead
    if (!player.alive) return;

    // Player-Unit collisions
    for (0..zone.unit_count) |i| {
        if (checkPlayerUnitCollision(player, &zone.units[i])) {
            // Player dies on unit contact
            return; // Caller should handle player death
        }
    }

    // Player-Obstacle collisions (handled in movement to prevent penetration)
    // These are checked before movement is applied

    // Player-Portal collisions
    for (0..zone.portal_count) |i| {
        if (checkPlayerPortalCollision(player, &zone.portals[i])) {
            // Portal collision detected - caller handles zone travel
            return;
        }
    }

    // Player-Lifestone collisions
    for (0..zone.lifestone_count) |i| {
        if (checkPlayerLifestoneCollision(player, &zone.lifestones[i])) {
            if (!zone.lifestones[i].attuned) {
                // Lifestone collision detected - caller handles attunement
                return;
            }
        }
    }
}

// Process bullet collisions
pub fn processBulletCollisions(world: *entities.World) void {
    const zone = world.getCurrentZoneMut();

    for (0..entities.MAX_BULLETS) |i| {
        if (!world.bullets[i].active) continue;

        const bullet = &world.bullets[i];

        // Check collision with obstacles first (bullets destroyed on contact)
        for (0..zone.obstacle_count) |j| {
            const obstacle = &zone.obstacles[j];
            if (!obstacle.active) continue;

            if (checkCircleRectCollision(bullet.pos, bullet.radius, obstacle.pos, obstacle.size)) {
                bullet.active = false;
                break; // Bullet destroyed, no need to check other collisions
            }
        }

        // If bullet still active, check collision with units
        if (!bullet.active) continue;

        for (0..zone.unit_count) |j| {
            const unit = &zone.units[j];
            // Skip dead/inactive units before expensive collision check
            if (!unit.active or !unit.alive) continue;

            if (checkCircleCollision(bullet.pos, bullet.radius, unit.pos, unit.radius)) {
                bullet.active = false;
                unit.alive = false;
                unit.color = .{ .r = 100, .g = 100, .b = 100, .a = 255 }; // GRAY
                break; // Bullet can only hit one unit
            }
        }
    }
}

// Check if position would collide with any blocking obstacle
pub fn wouldCollideWithObstacle(pos: Vec2, radius: f32, zone: *const entities.Zone) bool {
    for (0..zone.obstacle_count) |i| {
        const obstacle = &zone.obstacles[i];
        if (!obstacle.active or obstacle.is_deadly) continue; // Only check blocking obstacles

        if (checkCircleRectCollision(pos, radius, obstacle.pos, obstacle.size)) {
            return true;
        }
    }
    return false;
}

// Check if position collides with deadly obstacle
pub fn collidesWithDeadlyObstacle(pos: Vec2, radius: f32, zone: *const entities.Zone) bool {
    for (0..zone.obstacle_count) |i| {
        const obstacle = &zone.obstacles[i];
        if (!obstacle.active or !obstacle.is_deadly) continue; // Only check deadly obstacles

        if (checkCircleRectCollision(pos, radius, obstacle.pos, obstacle.size)) {
            return true;
        }
    }
    return false;
}

// Find nearest attuned lifestone across all zones
pub const LifestoneResult = struct {
    zone_index: usize,
    pos: Vec2,
};

pub fn findNearestAttunedLifestone(world: *const entities.World, current_pos: Vec2) ?LifestoneResult {
    // First check current zone
    const current_zone = world.getCurrentZone();
    var nearest_distance: f32 = std.math.floatMax(f32);
    var nearest_lifestone: ?LifestoneResult = null;

    for (0..current_zone.lifestone_count) |i| {
        const lifestone = &current_zone.lifestones[i];
        if (!lifestone.active or !lifestone.attuned) continue;

        const dx = current_pos.x - lifestone.pos.x;
        const dy = current_pos.y - lifestone.pos.y;
        const distance = dx * dx + dy * dy;

        if (distance < nearest_distance) {
            nearest_distance = distance;
            nearest_lifestone = LifestoneResult{
                .zone_index = world.current_zone,
                .pos = lifestone.pos,
            };
        }
    }

    // If found in current zone, return it
    if (nearest_lifestone != null) {
        return nearest_lifestone;
    }

    // Otherwise, search other zones with distance penalty
    for (0..world.zones.len) |zone_idx| {
        if (zone_idx == world.current_zone) continue;

        const zone = &world.zones[zone_idx];
        for (0..zone.lifestone_count) |i| {
            const lifestone = &zone.lifestones[i];
            if (!lifestone.active or !lifestone.attuned) continue;

            // Add penalty for being in different zone
            const dx = current_pos.x - lifestone.pos.x;
            const dy = current_pos.y - lifestone.pos.y;
            const distance = (dx * dx + dy * dy) + 1000000.0; // Large penalty

            if (distance < nearest_distance) {
                nearest_distance = distance;
                nearest_lifestone = LifestoneResult{
                    .zone_index = zone_idx,
                    .pos = lifestone.pos,
                };
            }
        }
    }

    return nearest_lifestone;
}
