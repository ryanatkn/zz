// Renderer wrapper - manages GPU rendering for all entities
const std = @import("std");
const entities = @import("entities.zig");
const types = @import("types.zig");
const simple_gpu_renderer = @import("simple_gpu_renderer.zig");
const camera = @import("camera.zig");
const borders = @import("borders.zig");
const constants = @import("constants.zig");
const effects = @import("effects.zig");

// SDL C imports
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

const Vec2 = types.Vec2;
const Color = types.Color;
const SimpleGPURenderer = simple_gpu_renderer.SimpleGPURenderer;

// Adapter to provide border drawing functionality to game state
pub const BorderRenderer = struct {
    renderer: *Renderer,
    cmd_buffer: *c.SDL_GPUCommandBuffer,
    render_pass: *c.SDL_GPURenderPass,

    pub fn drawBorderWithOffset(self: *const @This(), color: Color, width: f32, offset: f32) void {
        self.renderer.drawBorderWithOffset(self.cmd_buffer, self.render_pass, color, width, offset);
    }
};

pub const Renderer = struct {
    gpu: SimpleGPURenderer,
    camera: camera.Camera,

    pub fn init(allocator: std.mem.Allocator, window: *c.SDL_Window) !Renderer {
        return .{
            .gpu = try SimpleGPURenderer.init(allocator, window),
            .camera = camera.Camera.init(constants.SCREEN_WIDTH, constants.SCREEN_HEIGHT),
        };
    }

    pub fn deinit(self: *Renderer) void {
        self.gpu.deinit();
    }

    // Begin a new frame
    pub fn beginFrame(self: *Renderer, window: *c.SDL_Window) !*c.SDL_GPUCommandBuffer {
        return try self.gpu.beginFrame(window);
    }

    // Begin render pass
    pub fn beginRenderPass(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, window: *c.SDL_Window, bg_color: Color) !*c.SDL_GPURenderPass {
        return try self.gpu.beginRenderPass(cmd_buffer, window, bg_color);
    }

    // End render pass
    pub fn endRenderPass(self: *Renderer, render_pass: *c.SDL_GPURenderPass) void {
        self.gpu.endRenderPass(render_pass);
    }

    // End frame
    pub fn endFrame(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer) void {
        self.gpu.endFrame(cmd_buffer);
    }

    // Update camera based on current zone (call before game logic update)
    pub fn updateCamera(self: *Renderer, world: *const entities.World) void {
        // Ensure camera has current screen dimensions (in case window resized)
        if (self.camera.screen_width != self.gpu.screen_width or 
            self.camera.screen_height != self.gpu.screen_height) {
            self.camera.screen_width = self.gpu.screen_width;
            self.camera.screen_height = self.gpu.screen_height;
        }
        
        const zone = world.getCurrentZone();
        switch (zone.camera_mode) {
            .fixed => self.camera.setupFixed(zone.camera_scale),
            .follow => self.camera.setupFollow(world.player.pos, zone.camera_scale),
        }
    }

    // Render all entities in a zone
    pub fn renderZone(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, world: *const entities.World) void {
        const zone = world.getCurrentZone();

        // Draw all rectangles first (obstacles)
        self.renderObstacles(cmd_buffer, render_pass, zone);

        // Then draw all circles (player, enemies, bullets, etc)
        self.renderCircles(cmd_buffer, render_pass, world);
    }

    // Render all obstacles (rectangles)
    fn renderObstacles(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, zone: *const entities.Zone) void {
        for (0..zone.obstacle_count) |i| {
            const obstacle = &zone.obstacles[i];
            if (obstacle.active) {
                const screen_pos = self.camera.worldToScreen(obstacle.pos);
                const screen_size = Vec2{
                    .x = self.camera.worldSizeToScreen(obstacle.size.x),
                    .y = self.camera.worldSizeToScreen(obstacle.size.y),
                };
                self.gpu.drawRect(cmd_buffer, render_pass, screen_pos, screen_size, obstacle.color);
            }
        }
    }

    // Render all circular entities
    fn renderCircles(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, world: *const entities.World) void {
        const zone = world.getCurrentZone();

        // Draw player
        const player = &world.player;
        const player_screen_pos = self.camera.worldToScreen(player.pos);
        const player_screen_radius = self.camera.worldSizeToScreen(player.radius);
        self.gpu.drawCircle(cmd_buffer, render_pass, player_screen_pos, player_screen_radius, player.color);

        // Draw bullets
        for (0..entities.MAX_BULLETS) |i| {
            const bullet = &world.bullets[i];
            if (bullet.active) {
                const bullet_screen_pos = self.camera.worldToScreen(bullet.pos);
                const bullet_screen_radius = self.camera.worldSizeToScreen(bullet.radius);
                self.gpu.drawCircle(cmd_buffer, render_pass, bullet_screen_pos, bullet_screen_radius, bullet.color);
            }
        }

        // Draw lifestones
        for (0..zone.lifestone_count) |i| {
            const lifestone = &zone.lifestones[i];
            if (lifestone.active) {
                const lifestone_screen_pos = self.camera.worldToScreen(lifestone.pos);
                const lifestone_screen_radius = self.camera.worldSizeToScreen(lifestone.radius);
                self.gpu.drawCircle(cmd_buffer, render_pass, lifestone_screen_pos, lifestone_screen_radius, lifestone.color);
            }
        }

        // Draw portals
        for (0..zone.portal_count) |i| {
            const portal = &zone.portals[i];
            if (portal.active) {
                const portal_screen_pos = self.camera.worldToScreen(portal.pos);
                const portal_screen_radius = self.camera.worldSizeToScreen(portal.radius);
                self.gpu.drawCircle(cmd_buffer, render_pass, portal_screen_pos, portal_screen_radius, portal.color);
            }
        }

        // Draw units
        for (0..zone.unit_count) |i| {
            const unit = &zone.units[i];
            if (unit.active) {
                const unit_screen_pos = self.camera.worldToScreen(unit.pos);
                const unit_screen_radius = self.camera.worldSizeToScreen(unit.radius);
                self.gpu.drawCircle(cmd_buffer, render_pass, unit_screen_pos, unit_screen_radius, unit.color);
            }
        }
    }

    // Render visual effects
    pub fn renderEffects(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, effect_system: *const effects.EffectSystem) void {
        const active_effects = effect_system.getActiveEffects();

        // Get current time for shader animations
        const current_time = c.SDL_GetPerformanceCounter();
        const frequency = c.SDL_GetPerformanceFrequency();
        const time_sec = @as(f32, @floatFromInt(current_time)) / @as(f32, @floatFromInt(frequency));

        for (active_effects) |effect| {
            const screen_pos = self.camera.worldToScreen(effect.pos);
            const current_radius = effect.getCurrentRadius(); // Use dynamic radius for ping growth
            const screen_radius = self.camera.worldSizeToScreen(current_radius);
            const color = effect.getColor();
            const intensity = effect.getCurrentIntensity();

            self.gpu.drawEffect(cmd_buffer, render_pass, screen_pos, screen_radius, color, intensity, time_sec);
        }
    }

    // Draw border system with stacking support
    pub fn drawBorders(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, game_state: anytype) void {
        // Create adapter for border system to use our renderer
        const border_renderer = BorderRenderer{
            .renderer = self,
            .cmd_buffer = cmd_buffer,
            .render_pass = render_pass,
        };

        // Call the border drawing function with both renderer and game state
        drawBordersWithRenderer(border_renderer, game_state);
    }

    // Helper method for border system integration
    pub fn drawBorderWithOffset(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, color: Color, width: f32, offset: f32) void {
        const rects = borders.calculateBorderRects(width, offset);
        for (rects) |rect| {
            self.gpu.drawRect(cmd_buffer, render_pass, Vec2{ .x = rect.x, .y = rect.y }, Vec2{ .x = rect.w, .y = rect.h }, color);
        }
    }

    // Simple HUD rendering
    pub fn drawFPS(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, fps: u32) void {
        const WHITE = Color{ .r = 230, .g = 230, .b = 230, .a = 255 };
        const fps_x = 1840.0;
        const fps_y = 1060.0;

        // Simple 2-digit FPS display
        const tens = (fps / 10) % 10;
        const ones = fps % 10;

        // Draw tens digit
        if (tens > 0) {
            self.drawDigit(cmd_buffer, render_pass, @intCast(tens), fps_x, fps_y, WHITE);
        }

        // Draw ones digit
        self.drawDigit(cmd_buffer, render_pass, @intCast(ones), fps_x + 12.0, fps_y, WHITE);
    }

    fn drawDigit(self: *Renderer, cmd_buffer: *c.SDL_GPUCommandBuffer, render_pass: *c.SDL_GPURenderPass, digit: u8, x: f32, y: f32, color: Color) void {
        if (digit > 9) return;

        // Simple 3x5 digit patterns
        const patterns = [_][15]bool{
            .{ true, true, true, true, false, true, true, false, true, true, false, true, true, true, true }, // 0
            .{ false, true, false, false, true, false, false, true, false, false, true, false, false, true, false }, // 1
            .{ true, true, true, false, false, true, true, true, true, true, false, false, true, true, true }, // 2
            .{ true, true, true, false, false, true, true, true, true, false, false, true, true, true, true }, // 3
            .{ true, false, true, true, false, true, true, true, true, false, false, true, false, false, true }, // 4
            .{ true, true, true, true, false, false, true, true, true, false, false, true, true, true, true }, // 5
            .{ true, true, true, true, false, false, true, true, true, true, false, true, true, true, true }, // 6
            .{ true, true, true, false, false, true, false, false, true, false, false, true, false, false, true }, // 7
            .{ true, true, true, true, false, true, true, true, true, true, false, true, true, true, true }, // 8
            .{ true, true, true, true, false, true, true, true, true, false, false, true, true, true, true }, // 9
        };

        const pattern = patterns[digit];
        for (0..5) |row| {
            for (0..3) |col| {
                if (pattern[row * 3 + col]) {
                    const px = x + @as(f32, @floatFromInt(col)) * 2.0;
                    const py = y + @as(f32, @floatFromInt(row)) * 2.0;
                    self.gpu.drawRect(cmd_buffer, render_pass, Vec2{ .x = px, .y = py }, Vec2{ .x = 1.5, .y = 1.5 }, color);
                }
            }
        }
    }
};

// Helper function to bridge border system with renderer
fn drawBordersWithRenderer(border_renderer: BorderRenderer, game_state: anytype) void {
    var border_stack = borders.BorderStack.init();

    // Iris wipe effect (highest priority - renders over everything)
    if (game_state.iris_wipe_active) {
        const current_time = c.SDL_GetPerformanceCounter();
        const frequency = c.SDL_GetPerformanceFrequency();
        const elapsed_sec = @as(f32, @floatFromInt(current_time - game_state.iris_wipe_start_time)) / @as(f32, @floatFromInt(frequency));
        const wipe_duration = 1.5;

        if (elapsed_sec < wipe_duration) {
            const progress = elapsed_sec / wipe_duration; // 0.0 to 1.0
            // Strong ease-out curve: fast at start, very slow at end
            const eased_progress = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress) * (1.0 - progress); // Quartic ease-out
            const shrink_factor = 1.0 - eased_progress; // 1.0 to 0.0 (shrinking with strong ease-out)

            // Create iris wipe bands using existing game colors
            const wipe_colors = [_]Color{
                Color{ .r = 100, .g = 150, .b = 255, .a = 255 }, // BLUE_BRIGHT
                Color{ .r = 80, .g = 220, .b = 80, .a = 255 }, // GREEN_BRIGHT
                Color{ .r = 255, .g = 220, .b = 80, .a = 255 }, // YELLOW_BRIGHT
                Color{ .r = 255, .g = 180, .b = 80, .a = 255 }, // ORANGE_BRIGHT
                Color{ .r = 180, .g = 100, .b = 240, .a = 255 }, // PURPLE_BRIGHT
                Color{ .r = 0, .g = 200, .b = 200, .a = 255 }, // CYAN
            };

            for (wipe_colors) |wipe_color| {
                const max_width = 12.0;
                const current_width = max_width * shrink_factor;

                if (current_width > 0.5) { // Only render if visible
                    border_stack.pushStatic(current_width, wipe_color);
                }
            }
        } else {
            // End iris wipe
            @constCast(game_state).iris_wipe_active = false;
        }
    }

    // Game state borders (lower priority)
    if (game_state.isPaused()) {
        // Animated paused border: base 6px + 4px pulse amplitude
        border_stack.pushAnimated(6.0, borders.GOLD_YELLOW_COLORS, 1.5, 4.0);
    }

    if (!game_state.world.player.alive) {
        // Animated dead border: base 9px + 5px pulse amplitude
        border_stack.pushAnimated(9.0, borders.RED_COLORS, 1.2, 5.0);
    }

    // Render all borders with automatic offset calculation based on current animated widths
    var current_offset: f32 = 0;

    for (0..border_stack.count) |i| {
        const spec = &border_stack.specs[i];
        const current_width = spec.getCurrentWidth();
        const current_color = spec.getCurrentColor();

        border_renderer.drawBorderWithOffset(current_color, current_width, current_offset);
        current_offset += current_width;
    }
}
