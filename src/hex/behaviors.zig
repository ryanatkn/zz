// Behavior functions - direct, named functions for entity updates
const std = @import("std");
const entities = @import("entities.zig");
const types = @import("types.zig");
const constants = @import("constants.zig");

const Vec2 = types.Vec2;
const Player = entities.Player;
const Unit = entities.Unit;
const Bullet = entities.Bullet;
const World = entities.World;

// Update player based on input with camera-aware bounds
pub fn updatePlayer(player: *Player, vel: Vec2, dt: f32, use_screen_bounds: bool) void {
    if (!player.alive) return;

    player.vel = vel;
    player.pos.x += vel.x * dt;
    player.pos.y += vel.y * dt;

    // Apply bounds based on camera mode
    if (use_screen_bounds) {
        // Fixed camera (overworld) - keep player in visible area
        player.pos.x = std.math.clamp(player.pos.x, player.radius, constants.SCREEN_WIDTH - player.radius);
        player.pos.y = std.math.clamp(player.pos.y, player.radius, constants.SCREEN_HEIGHT - player.radius);
    }
    // Follow camera (dungeons) - no bounds, terrain collision handles this
}

// Update unit - chase player or return home
pub fn updateUnit(unit: *Unit, player_pos: Vec2, player_alive: bool, dt: f32) void {
    var velocity = Vec2{ .x = 0, .y = 0 };

    if (player_alive) {
        const dx_player = player_pos.x - unit.pos.x;
        const dy_player = player_pos.y - unit.pos.y;
        const dist_sq_to_player = dx_player * dx_player + dy_player * dy_player;
        const aggro_range_sq = constants.UNIT_AGGRO_RANGE * constants.UNIT_AGGRO_RANGE;
        const min_dist_sq = (unit.radius + constants.PLAYER_RADIUS) * (unit.radius + constants.PLAYER_RADIUS);

        if (dist_sq_to_player < aggro_range_sq and dist_sq_to_player > min_dist_sq) {
            // Chase player (aggro state)
            const distance_to_player = @sqrt(dist_sq_to_player);
            velocity.x = (dx_player / distance_to_player) * constants.UNIT_SPEED;
            velocity.y = (dy_player / distance_to_player) * constants.UNIT_SPEED;
            // Set aggro color - bright red
            unit.color = constants.COLOR_UNIT_AGGRO;
        } else {
            // Return home (non-aggro state)
            velocity = calculateReturnHomeVelocity(unit);
            // Set non-aggro color - dimmed reddish (similar to lifestone dimmed color)
            unit.color = constants.COLOR_UNIT_NON_AGGRO;
        }
    } else {
        // Player dead - return home (non-aggro state)
        velocity = calculateReturnHomeVelocity(unit);
        // Set non-aggro color - dimmed reddish (similar to lifestone dimmed color)
        unit.color = constants.COLOR_UNIT_NON_AGGRO;
    }

    // Apply velocity
    unit.vel = velocity;
    unit.pos.x += velocity.x * dt;
    unit.pos.y += velocity.y * dt;
}

// Calculate velocity for unit returning home
fn calculateReturnHomeVelocity(unit: *const Unit) Vec2 {
    const dx = unit.home_pos.x - unit.pos.x;
    const dy = unit.home_pos.y - unit.pos.y;
    const dist_sq = dx * dx + dy * dy;

    // Use squared distance to avoid sqrt when possible
    const tolerance_sq = constants.UNIT_HOME_TOLERANCE * constants.UNIT_HOME_TOLERANCE;
    if (dist_sq <= tolerance_sq) {
        return Vec2{ .x = 0, .y = 0 };
    }

    const distance = @sqrt(dist_sq);
    return Vec2{
        .x = (dx / distance) * constants.UNIT_WALK_SPEED,
        .y = (dy / distance) * constants.UNIT_WALK_SPEED,
    };
}

// Update bullet position
pub fn updateBullet(bullet: *Bullet, dt: f32) void {
    if (!bullet.active) return;

    bullet.pos.x += bullet.vel.x * dt;
    bullet.pos.y += bullet.vel.y * dt;

    // Deactivate if off screen
    if (bullet.pos.x < 0 or bullet.pos.x > constants.SCREEN_WIDTH or
        bullet.pos.y < 0 or bullet.pos.y > constants.SCREEN_HEIGHT)
    {
        bullet.active = false;
    }
}

// Fire a bullet from source position toward target
pub fn fireBullet(bullet: *Bullet, source_pos: Vec2, target_pos: Vec2) void {
    const direction = Vec2{
        .x = target_pos.x - source_pos.x,
        .y = target_pos.y - source_pos.y,
    };

    const length = @sqrt(direction.x * direction.x + direction.y * direction.y);
    if (length > 0) {
        bullet.pos = source_pos;
        bullet.vel.x = (direction.x / length) * constants.BULLET_SPEED;
        bullet.vel.y = (direction.y / length) * constants.BULLET_SPEED;
        bullet.active = true;
    }
}

// Kill player
pub fn killPlayer(player: *Player) void {
    player.alive = false;
    player.color = constants.COLOR_DEAD;
}

// Respawn player at position
pub fn respawnPlayer(player: *Player, pos: Vec2) void {
    player.pos = pos;
    player.alive = true;
    player.color = constants.COLOR_PLAYER_ALIVE;
}

// Kill unit
pub fn killUnit(unit: *Unit) void {
    unit.alive = false;
    unit.color = constants.COLOR_DEAD;
}

// Attune lifestone
pub fn attuneLifestone(lifestone: *entities.Lifestone) void {
    if (!lifestone.attuned) {
        lifestone.attuned = true;
        lifestone.color = constants.COLOR_LIFESTONE_ATTUNED;
    }
}
