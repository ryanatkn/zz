const std = @import("std");

const types = @import("types.zig");
const constants = @import("constants.zig");

const Vec2 = types.Vec2;

pub const Camera = struct {
    // Screen dimensions (pixels)
    screen_width: f32,
    screen_height: f32,

    // World view bounds
    view_x: f32, // Left edge of view in world space
    view_y: f32, // Top edge of view in world space
    view_width: f32, // Width of view in world units
    view_height: f32, // Height of view in world units

    // Visual scale (zoom level)
    scale: f32,

    const Self = @This();

    pub fn init(screen_w: f32, screen_h: f32) Self {
        return .{
            .screen_width = screen_w,
            .screen_height = screen_h,
            .view_x = 0.0,
            .view_y = 0.0,
            .view_width = screen_w,
            .view_height = screen_h,
            .scale = 1.0,
        };
    }

    // Fixed camera - shows entire world with adjustable zoom
    pub fn setupFixed(self: *Self, scale: f32) void {
        self.scale = scale;
        // View always encompasses entire world
        self.view_x = 0.0;
        self.view_y = 0.0;
        self.view_width = constants.SCREEN_WIDTH;
        self.view_height = constants.SCREEN_HEIGHT;
    }

    // Follow camera - tracks player position with adjustable zoom
    pub fn setupFollow(self: *Self, player_pos: Vec2, scale: f32) void {
        self.scale = scale;
        // Zoom affects view size (inverse relationship)
        self.view_width = self.screen_width / self.scale;
        self.view_height = self.screen_height / self.scale;
        // Center view on player
        self.view_x = player_pos.x - self.view_width / 2.0;
        self.view_y = player_pos.y - self.view_height / 2.0;
    }

    // Convert world position to screen position
    pub fn worldToScreen(self: *const Self, world_pos: Vec2) Vec2 {
        // Normalize to view space [0,1]
        const norm_x = (world_pos.x - self.view_x) / self.view_width;
        const norm_y = (world_pos.y - self.view_y) / self.view_height;
        // Map to screen pixels
        return Vec2{
            .x = norm_x * self.screen_width,
            .y = norm_y * self.screen_height,
        };
    }

    // Convert world size to screen size (for radii, dimensions)
    pub fn worldSizeToScreen(self: *const Self, world_size: f32) f32 {
        return (world_size / self.view_width) * self.screen_width;
    }

    // Convert screen position to world position (for mouse input)
    pub fn screenToWorld(self: *const Self, screen_pos: Vec2) Vec2 {
        // Normalize from screen space [0,1]
        const norm_x = screen_pos.x / self.screen_width;
        const norm_y = screen_pos.y / self.screen_height;
        // Map to world coordinates
        return Vec2{
            .x = norm_x * self.view_width + self.view_x,
            .y = norm_y * self.view_height + self.view_y,
        };
    }
};
