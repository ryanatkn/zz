const std = @import("std");
const math = std.math;

// SDL C imports
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
});

// Import shared types
const types = @import("types.zig");
const Vec2 = types.Vec2;
const Color = types.Color;

// Color utility functions for visual effects
pub fn createRainbowColor(hue: f32, saturation: f32, value: f32) Color {
    const h = hue * 6.0;
    const chroma = value * saturation;
    const x = chroma * (1.0 - @abs(@mod(h, 2.0) - 1.0));
    const m = value - chroma;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h < 1.0) {
        r = chroma;
        g = x;
        b = 0;
    } else if (h < 2.0) {
        r = x;
        g = chroma;
        b = 0;
    } else if (h < 3.0) {
        r = 0;
        g = chroma;
        b = x;
    } else if (h < 4.0) {
        r = 0;
        g = x;
        b = chroma;
    } else if (h < 5.0) {
        r = x;
        g = 0;
        b = chroma;
    } else {
        r = chroma;
        g = 0;
        b = x;
    }

    return Color{
        .r = @intFromFloat((r + m) * 255.0),
        .g = @intFromFloat((g + m) * 255.0),
        .b = @intFromFloat((b + m) * 255.0),
        .a = 255,
    };
}

pub fn calculateAnimationPulse(frequency: f32) f32 {
    const current_time_ms = @as(f32, @floatFromInt(c.SDL_GetTicks()));
    const current_time_sec = current_time_ms / 1000.0;
    return (math.sin(current_time_sec * frequency) + 1.0) * 0.5;
}

pub fn calculateColorCycle() f32 {
    const COLOR_CYCLE_FREQ = 4.0;
    const current_time_ms = @as(f32, @floatFromInt(c.SDL_GetTicks()));
    const current_time_sec = current_time_ms / 1000.0;
    return (math.sin(current_time_sec * COLOR_CYCLE_FREQ) + 1.0) * 0.5;
}

// Visual effect constants
const MAX_VISUAL_EFFECTS = 32;

// Visual effect types for different game entities
pub const VisualEffectType = enum {
    player_spawn,        // Temporary bright effect when player spawns/resurrects (full intensity)
    player_transition,   // Subtle effect for scene transitions and game start
    portal_ambient,      // Permanent subtle pulsing around portals
    lifestone_dormant,   // Permanent gentle glow for unattached lifestones
    lifestone_attuned,   // Permanent vibrant glow for attuned lifestones
};

const VisualEffect = struct {
    position: Vec2,
    radius: f32,
    effect_type: VisualEffectType,
    active: bool,
    start_time: u64,
    duration: f32, // Duration in seconds (0.0 = permanent)
    
    fn isActive(self: *const VisualEffect) bool {
        if (!self.active) return false;
        if (self.duration == 0.0) return true; // Permanent effect
        
        const current_time = c.SDL_GetPerformanceCounter();
        const frequency = c.SDL_GetPerformanceFrequency();
        const elapsed_sec = @as(f32, @floatFromInt(current_time - self.start_time)) / @as(f32, @floatFromInt(frequency));
        return elapsed_sec < self.duration;
    }
    
    fn getEffectColor(self: *const VisualEffect, intensity: f32) Color {
        switch (self.effect_type) {
            .player_spawn => {
                // Bright blue/white for player spawn - temporary and noticeable
                // Linear alpha fade all the way to 0
                return Color{
                    .r = @min(255, @as(u8, @intFromFloat(100.0 + intensity * 155.0))),
                    .g = @min(255, @as(u8, @intFromFloat(150.0 + intensity * 105.0))),
                    .b = 255,
                    .a = @as(u8, @intFromFloat(120.0 * intensity)),
                };
            },
            .player_transition => {
                // Same color as player_spawn but with reduced alpha for transitions
                return Color{
                    .r = @min(255, @as(u8, @intFromFloat(100.0 + intensity * 155.0))),
                    .g = @min(255, @as(u8, @intFromFloat(150.0 + intensity * 105.0))),
                    .b = 255,
                    .a = @as(u8, @intFromFloat(60.0 * intensity)), // Half the alpha of player_spawn
                };
            },
            .portal_ambient => {
                // More prominent warm orange for portal ambient glow
                return Color{
                    .r = @as(u8, @intFromFloat(255.0 * intensity)),
                    .g = @as(u8, @intFromFloat(180.0 * intensity)),
                    .b = @as(u8, @intFromFloat(80.0 * intensity)),
                    .a = @as(u8, @intFromFloat(85.0 * intensity)), // Increased from 40 to 85
                };
            },
            .lifestone_dormant => {
                // Gentle faded cyan for dormant lifestones
                return Color{
                    .r = @as(u8, @intFromFloat(0.0 * intensity)),
                    .g = @as(u8, @intFromFloat(150.0 * intensity)),
                    .b = @as(u8, @intFromFloat(150.0 * intensity)),
                    .a = @as(u8, @intFromFloat(60.0 * intensity)), // Low alpha for gentle glow
                };
            },
            .lifestone_attuned => {
                // Vibrant bright cyan for attuned lifestones
                return Color{
                    .r = @as(u8, @intFromFloat(50.0 * intensity)),
                    .g = @as(u8, @intFromFloat(220.0 * intensity)),
                    .b = @as(u8, @intFromFloat(220.0 * intensity)),
                    .a = @as(u8, @intFromFloat(100.0 * intensity)), // Higher alpha for vibrancy
                };
            },
        }
    }
};

pub const VisualSystem = struct {
    effects: [MAX_VISUAL_EFFECTS]VisualEffect,
    count: usize,
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{
            .effects = undefined,
            .count = 0,
        };
    }
    
    pub fn clear(self: *Self) void {
        self.count = 0;
    }
    
    pub fn addEffect(self: *Self, position: Vec2, radius: f32, effect_type: VisualEffectType, duration: f32) void {
        if (self.count < MAX_VISUAL_EFFECTS) {
            self.effects[self.count] = VisualEffect{
                .position = position,
                .radius = radius,
                .effect_type = effect_type,
                .active = true,
                .start_time = c.SDL_GetPerformanceCounter(),
                .duration = duration,
            };
            self.count += 1;
        }
    }
    
    // Add permanent portal ambient effects for all active portals in a scene
    pub fn addPortalAmbientEffects(self: *Self, portals: anytype, max_portals: usize) void {
        for (0..max_portals) |i| {
            if (portals[i].active) {
                self.addEffect(portals[i].position, portals[i].radius * 1.8, .portal_ambient, 0.0);
            }
        }
    }
    
    // Add permanent lifestone effects for all active lifestones in a scene
    pub fn addLifestoneEffects(self: *Self, lifestones: anytype, max_lifestones: usize) void {
        for (0..max_lifestones) |i| {
            if (lifestones[i].active) {
                const effect_type: VisualEffectType = if (lifestones[i].attuned) .lifestone_attuned else .lifestone_dormant;
                self.addEffect(lifestones[i].position, lifestones[i].radius * 2.2, effect_type, 0.0);
            }
        }
    }
    
    pub fn update(self: *Self) void {
        // Remove expired effects (keep permanent ones)
        var write_index: usize = 0;
        for (0..self.count) |read_index| {
            if (self.effects[read_index].isActive()) {
                if (write_index != read_index) {
                    self.effects[write_index] = self.effects[read_index];
                }
                write_index += 1;
            }
        }
        self.count = write_index;
    }
    
    pub fn render(self: *const Self, game_state: anytype) void {
        // Enable alpha blending for visual effects
        _ = c.SDL_SetRenderDrawBlendMode(@ptrCast(game_state.renderer), c.SDL_BLENDMODE_BLEND);
        
        for (0..self.count) |i| {
            const effect = &self.effects[i];
            if (effect.isActive()) {
                self.drawEntityEffect(game_state, effect);
            }
        }
        
        // Restore default blend mode
        _ = c.SDL_SetRenderDrawBlendMode(@ptrCast(game_state.renderer), c.SDL_BLENDMODE_NONE);
    }
    
    fn drawEntityEffect(self: *const Self, game_state: anytype, effect: *const VisualEffect) void {
        _ = self;
        const current_time = c.SDL_GetPerformanceCounter();
        const frequency = c.SDL_GetPerformanceFrequency();
        const elapsed_sec = @as(f32, @floatFromInt(current_time - effect.start_time)) / @as(f32, @floatFromInt(frequency));
        
        // Calculate pulsing intensity based on effect type
        var pulse_freq: f32 = undefined;
        var base_intensity: f32 = undefined;
        var pulse_amplitude: f32 = undefined;
        
        switch (effect.effect_type) {
            .player_spawn => {
                pulse_freq = 3.0; // Faster pulse for attention
                base_intensity = 0.5;
                pulse_amplitude = 0.5;
            },
            .player_transition => {
                pulse_freq = 3.0; // Same timing as regular spawn
                base_intensity = 0.5;
                pulse_amplitude = 0.5;
            },
            .portal_ambient => {
                pulse_freq = 1.2; // Slightly faster for more noticeable growth
                base_intensity = 0.3; // Lower base so the pulse is more dramatic
                pulse_amplitude = 0.6; // Higher amplitude for stronger growth effect
            },
            .lifestone_dormant => {
                pulse_freq = 1.2; // Gentle pulse
                base_intensity = 0.3;
                pulse_amplitude = 0.4;
            },
            .lifestone_attuned => {
                pulse_freq = 1.8; // More active pulse for attuned
                base_intensity = 0.6;
                pulse_amplitude = 0.4;
            },
        }
        
        const pulse = (math.sin(elapsed_sec * pulse_freq) + 1.0) * 0.5; // 0.0 to 1.0
        const intensity = base_intensity + pulse * pulse_amplitude;
        
        // Transform world position to screen coordinates
        const screen_pos = game_state.worldToScreen(effect.position);
        
        // Handle different effect types with specific behaviors
        switch (effect.effect_type) {
            .player_spawn => {
                // Player spawn: dramatic ripples at drop site with staggered timing
                const ring_configs = [_]struct { lifetime: f32, max_size: f32, delay: f32 }{
                    .{ .lifetime = 0.8, .max_size = 0.8, .delay = 0.0 },   // Fast small ring
                    .{ .lifetime = 1.0, .max_size = 1.2, .delay = 0.1 },  // Medium ring
                    .{ .lifetime = 1.4, .max_size = 1.8, .delay = 0.2 },  // Large ring
                    .{ .lifetime = 1.8, .max_size = 2.4, .delay = 0.3 },  // Very large ring
                    .{ .lifetime = 2.2, .max_size = 3.0, .delay = 0.4 },  // Huge ring
                    .{ .lifetime = 1.2, .max_size = 1.0, .delay = 0.6 },  // Second wave - small
                    .{ .lifetime = 1.6, .max_size = 2.0, .delay = 0.7 },  // Second wave - large
                };
                
                for (ring_configs) |config| {
                    const ring_age = elapsed_sec - config.delay;
                    
                    if (ring_age >= 0 and ring_age <= config.lifetime) {
                        const growth_progress = ring_age / config.lifetime; // 0.0 to 1.0
                        const ring_radius = effect.radius * growth_progress * config.max_size;
                        
                        // Linear alpha fade: start bright, fade to 0
                        const alpha_progress = 1.0 - growth_progress; // 1.0 to 0.0
                        const ring_intensity = alpha_progress * intensity;
                        
                        if (ring_intensity > 0.01) { // Only draw if visible
                            const ring_color = effect.getEffectColor(ring_intensity);
                            game_state.drawCircle(screen_pos, ring_radius, ring_color);
                        }
                    }
                }
            },
            .player_transition => {
                // Player transition: bigger rings spaced slower for scene changes
                const ring_configs = [_]struct { lifetime: f32, max_size: f32, delay: f32 }{
                    .{ .lifetime = 1.2, .max_size = 2.0, .delay = 0.0 },   // Large ring
                    .{ .lifetime = 2.4, .max_size = 5.0, .delay = 0.3 },  // Massive ring (moved up and overlapping)
                };
                
                for (ring_configs) |config| {
                    const ring_age = elapsed_sec - config.delay;
                    
                    if (ring_age >= 0 and ring_age <= config.lifetime) {
                        const growth_progress = ring_age / config.lifetime; // 0.0 to 1.0
                        const ring_radius = effect.radius * growth_progress * config.max_size;
                        
                        // Linear alpha fade: start bright, fade to 0
                        const alpha_progress = 1.0 - growth_progress; // 1.0 to 0.0
                        const ring_intensity = alpha_progress * intensity;
                        
                        if (ring_intensity > 0.01) { // Only draw if visible
                            const ring_color = effect.getEffectColor(ring_intensity);
                            game_state.drawCircle(screen_pos, ring_radius, ring_color);
                        }
                    }
                }
            },
            .portal_ambient => {
                // Portal ambient: slow stable pulsing fields at medium alpha
                const num_rings = 3;
                for (0..num_rings) |i| {
                    const ring_factor = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(num_rings));
                    const base_ring_radius = effect.radius * (0.4 + ring_factor * 0.5); // Base size spacing
                    
                    // Much slower pulse frequencies
                    const ring_pulse_freq = 0.15 + ring_factor * 0.1; // 0.15Hz to 0.25Hz - very slow
                    const ring_pulse = (math.sin(elapsed_sec * ring_pulse_freq * 2 * math.pi) + 1.0) * 0.5; // 0.0 to 1.0
                    
                    // Pulse between smaller and larger size around base
                    const pulse_amount = base_ring_radius * 0.4; // 40% size variation
                    const ring_radius = base_ring_radius + (ring_pulse - 0.5) * pulse_amount; // Pulse ±20% around base size
                    
                    // Constant medium alpha intensity - no fading
                    const ring_intensity = 0.6; // Fixed medium intensity
                    
                    const ring_color = effect.getEffectColor(ring_intensity);
                    game_state.drawCircle(screen_pos, ring_radius, ring_color);
                }
            },
            else => {
                // Standard concentric rings for lifestone effects
                const num_rings = 2;
                for (0..num_rings) |i| {
                    const ring_factor = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(num_rings));
                    const ring_radius = effect.radius * (0.7 + ring_factor * 0.5);
                    const ring_intensity = intensity * (1.1 - ring_factor * 0.4); // Fade outer rings
                    const ring_color = effect.getEffectColor(ring_intensity);
                    
                    game_state.drawCircle(screen_pos, ring_radius, ring_color);
                }
            },
        }
    }
};