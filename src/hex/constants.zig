const types = @import("types.zig");

// Screen/Window dimensions
pub const SCREEN_WIDTH = 1920.0;
pub const SCREEN_HEIGHT = 1080.0;
pub const SCREEN_CENTER_X = SCREEN_WIDTH / 2.0;
pub const SCREEN_CENTER_Y = SCREEN_HEIGHT / 2.0;

// Movement and gameplay constants
pub const PLAYER_SPEED = 600.0;
pub const PLAYER_RADIUS = 20.0;
pub const UNIT_SPEED = 80.0;
pub const UNIT_AGGRO_RANGE = 300.0;
pub const UNIT_WALK_SPEED = UNIT_SPEED * 0.333; // 1/3 speed when returning home
pub const UNIT_HOME_TOLERANCE = 2.0; // Distance tolerance for "at home" check
pub const BULLET_SPEED = 400.0;
pub const BULLET_RADIUS = 5.0;
pub const PORTAL_SPAWN_OFFSET = 10.0; // Extra distance when spawning near portals

// Color constants
pub const COLOR_PLAYER_ALIVE = types.Color{ .r = 0, .g = 70, .b = 200, .a = 255 }; // BLUE
pub const COLOR_UNIT_DEFAULT = types.Color{ .r = 100, .g = 100, .b = 100, .a = 255 }; // GRAY (default unit color)
pub const COLOR_UNIT_AGGRO = types.Color{ .r = 200, .g = 30, .b = 30, .a = 255 }; // RED (aggro)
pub const COLOR_UNIT_NON_AGGRO = types.Color{ .r = 120, .g = 60, .b = 60, .a = 255 }; // DIMMED RED (non-aggro)
pub const COLOR_OBSTACLE_DEADLY = types.Color{ .r = 200, .g = 100, .b = 0, .a = 255 }; // ORANGE (deadly)
pub const COLOR_OBSTACLE_BLOCKING = types.Color{ .r = 0, .g = 140, .b = 0, .a = 255 }; // GREEN (blocking)
pub const COLOR_BULLET = types.Color{ .r = 220, .g = 160, .b = 0, .a = 255 }; // YELLOW
pub const COLOR_PORTAL = types.Color{ .r = 120, .g = 30, .b = 160, .a = 255 }; // PURPLE
pub const COLOR_LIFESTONE_ATTUNED = types.Color{ .r = 0, .g = 200, .b = 200, .a = 255 }; // CYAN (attuned)
pub const COLOR_LIFESTONE_UNATTUNED = types.Color{ .r = 0, .g = 100, .b = 100, .a = 255 }; // CYAN_FADED (unattuned)
pub const COLOR_DEAD = types.Color{ .r = 100, .g = 100, .b = 100, .a = 255 }; // GRAY
