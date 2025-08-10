const std = @import("std");
const math = std.math;

const sdl = @import("sdl.zig").c;

const types = @import("types.zig");
const Color = types.Color;
const constants = @import("constants.zig");

// Border animation constants
const ASPECT_RATIO = 16.0 / 9.0;
const BORDER_PULSE_PAUSED = 1.5;
const BORDER_PULSE_DEAD = 1.2;

// Screen constants for border calculations
const SCREEN_WIDTH = constants.SCREEN_WIDTH;
const SCREEN_HEIGHT = constants.SCREEN_HEIGHT;

// Iris wipe constants
pub const IRIS_WIPE_DURATION = 2.5; // Increased from 1.5 seconds
pub const IRIS_WIPE_BAND_COUNT = 6;
pub const IRIS_WIPE_BAND_WIDTH = 30.0; // Increased from 12.0 pixels

// Color constants for borders
const BLUE_BRIGHT = Color{ .r = 100, .g = 150, .b = 255, .a = 255 };
const GREEN_BRIGHT = Color{ .r = 80, .g = 220, .b = 80, .a = 255 };
const PURPLE_BRIGHT = Color{ .r = 180, .g = 100, .b = 240, .a = 255 };
const RED_BRIGHT = Color{ .r = 255, .g = 100, .b = 100, .a = 255 };
const YELLOW_BRIGHT = Color{ .r = 255, .g = 220, .b = 80, .a = 255 };
const ORANGE_BRIGHT = Color{ .r = 255, .g = 180, .b = 80, .a = 255 };
const CYAN = Color{ .r = 0, .g = 200, .b = 200, .a = 255 };

// Border color definitions for cycling
pub const BorderColorPair = struct {
    dark: struct { r: f32, g: f32, b: f32 },
    bright: struct { r: f32, g: f32, b: f32 },
};

pub const GOLD_YELLOW_COLORS = BorderColorPair{
    .dark = .{ .r = 200.0, .g = 150.0, .b = 10.0 },
    .bright = .{ .r = 255.0, .g = 240.0, .b = 0.0 },
};

pub const RED_COLORS = BorderColorPair{
    .dark = .{ .r = 180.0, .g = 40.0, .b = 40.0 },
    .bright = .{ .r = 255.0, .g = 30.0, .b = 30.0 },
};

pub const GREEN_COLORS = BorderColorPair{
    .dark = .{ .r = 20.0, .g = 160.0, .b = 20.0 },
    .bright = .{ .r = 50.0, .g = 220.0, .b = 80.0 },
};

// Border system for declarative stacked borders
const MAX_BORDER_LAYERS = 8;

pub const BorderSpec = struct {
    base_width: f32,
    base_color: Color,
    color_pair: ?BorderColorPair, // null = static color, value = animated color
    pulse_freq: ?f32, // null = no pulse, value = pulse frequency
    pulse_amplitude: f32, // how much the pulse changes the width

    pub fn getCurrentWidth(self: *const BorderSpec) f32 {
        if (self.pulse_freq) |freq| {
            const pulse = calculateAnimationPulse(freq);
            return self.base_width + pulse * self.pulse_amplitude;
        } else {
            return self.base_width;
        }
    }

    pub fn getMaxWidth(self: *const BorderSpec) f32 {
        // Maximum possible width this border could reach
        return self.base_width + self.pulse_amplitude;
    }

    pub fn getCurrentColor(self: *const BorderSpec) Color {
        if (self.color_pair) |colors| {
            const pulse = calculateAnimationPulse(self.pulse_freq orelse 4.0);
            const hue_cycle = calculateColorCycle();
            const intensity = 0.7 + pulse * 0.3;
            return interpolateColor(colors, hue_cycle, intensity);
        } else {
            return self.base_color;
        }
    }
};

pub const BorderStack = struct {
    specs: [MAX_BORDER_LAYERS]BorderSpec,
    count: usize,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .specs = undefined,
            .count = 0,
        };
    }

    pub fn clear(self: *Self) void {
        self.count = 0;
    }

    pub fn push(self: *Self, base_width: f32, base_color: Color, color_pair: ?BorderColorPair, pulse_freq: ?f32, pulse_amplitude: f32) void {
        if (self.count < MAX_BORDER_LAYERS) {
            self.specs[self.count] = BorderSpec{
                .base_width = base_width,
                .base_color = base_color,
                .color_pair = color_pair,
                .pulse_freq = pulse_freq,
                .pulse_amplitude = pulse_amplitude,
            };
            self.count += 1;
        }
    }

    pub fn pushStatic(self: *Self, width: f32, color: Color) void {
        self.push(width, color, null, null, 0.0);
    }

    pub fn pushAnimated(self: *Self, base_width: f32, color_pair: BorderColorPair, pulse_freq: f32, pulse_amplitude: f32) void {
        // Use the dark color from the pair as base color
        const base_color = Color{
            .r = @intFromFloat(color_pair.dark.r),
            .g = @intFromFloat(color_pair.dark.g),
            .b = @intFromFloat(color_pair.dark.b),
            .a = 255,
        };
        self.push(base_width, base_color, color_pair, pulse_freq, pulse_amplitude);
    }

    pub fn render(self: *const Self, game_state: anytype) void {
        // Calculate cumulative offset based on current animated widths
        var current_offset: f32 = 0;

        for (0..self.count) |i| {
            const spec = &self.specs[i];
            const current_width = spec.getCurrentWidth();
            const current_color = spec.getCurrentColor();

            game_state.drawBorderWithOffset(current_color, current_width, current_offset);
            current_offset += current_width;
        }
    }
};

// Animation utility functions
fn calculateAnimationPulse(frequency: f32) f32 {
    const current_time_ms = @as(f32, @floatFromInt(sdl.SDL_GetTicks()));
    const current_time_sec = current_time_ms / 1000.0;
    return (math.sin(current_time_sec * frequency) + 1.0) * 0.5;
}

fn calculateColorCycle() f32 {
    const COLOR_CYCLE_FREQ = 4.0;
    const current_time_ms = @as(f32, @floatFromInt(sdl.SDL_GetTicks()));
    const current_time_sec = current_time_ms / 1000.0;
    return (math.sin(current_time_sec * COLOR_CYCLE_FREQ) + 1.0) * 0.5;
}

// Color interpolation utility for border system
fn interpolateColor(color_pair: BorderColorPair, t: f32, intensity: f32) Color {
    return Color{
        .r = @intFromFloat((color_pair.dark.r + (color_pair.bright.r - color_pair.dark.r) * t) * intensity),
        .g = @intFromFloat((color_pair.dark.g + (color_pair.bright.g - color_pair.dark.g) * t) * intensity),
        .b = @intFromFloat((color_pair.dark.b + (color_pair.bright.b - color_pair.dark.b) * t) * intensity),
        .a = 255,
    };
}

// Border rectangle calculations
pub const BorderRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub fn calculateBorderRects(width: f32, offset: f32) [4]BorderRect {
    // Calculate border rectangles INSIDE the remaining space after accounting for outer borders
    const inner_x = offset;
    const inner_y = offset;
    const inner_width = SCREEN_WIDTH - (offset * 2);
    const inner_height = SCREEN_HEIGHT - (offset * 2);

    // Return 4 rectangles that form the border around the inner area
    return [4]BorderRect{
        // Top
        BorderRect{ .x = inner_x, .y = inner_y, .w = inner_width, .h = width },
        // Bottom
        BorderRect{ .x = inner_x, .y = inner_y + inner_height - width, .w = inner_width, .h = width },
        // Left
        BorderRect{ .x = inner_x, .y = inner_y + width, .w = width, .h = inner_height - (width * 2) },
        // Right
        BorderRect{ .x = inner_x + inner_width - width, .y = inner_y + width, .w = width, .h = inner_height - (width * 2) },
    };
}

pub fn drawScreenBorder(game_state: anytype) void {
    var border_stack = BorderStack.init();

    // Iris wipe effect (highest priority - renders over everything)
    if (game_state.iris_wipe_active) {
        const current_time = sdl.SDL_GetPerformanceCounter();
        const frequency = sdl.SDL_GetPerformanceFrequency();
        const elapsed_sec = @as(f32, @floatFromInt(current_time - game_state.iris_wipe_start_time)) / @as(f32, @floatFromInt(frequency));
        const wipe_duration = IRIS_WIPE_DURATION;

        if (elapsed_sec < wipe_duration) {
            const progress = elapsed_sec / wipe_duration; // 0.0 to 1.0
            // Strong ease-out curve: fast at start, very slow at end
            const eased_progress = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress) * (1.0 - progress); // Quartic ease-out
            const shrink_factor = 1.0 - eased_progress; // 1.0 to 0.0 (shrinking with strong ease-out)

            // Create iris wipe bands using existing game colors
            const wipe_colors = [_]Color{
                BLUE_BRIGHT,   GREEN_BRIGHT,  YELLOW_BRIGHT,
                ORANGE_BRIGHT, PURPLE_BRIGHT, CYAN,
            };
            comptime std.debug.assert(wipe_colors.len == IRIS_WIPE_BAND_COUNT);

            for (0..wipe_colors.len) |i| {
                const wipe_color = wipe_colors[i];
                const max_width = IRIS_WIPE_BAND_WIDTH;
                const current_width = max_width * shrink_factor;

                if (current_width > 0.5) { // Only render if visible
                    border_stack.pushStatic(current_width, wipe_color);
                }
            }
        } else {
            // End iris wipe
            game_state.iris_wipe_active = false;
        }
    }

    // Game state borders (lower priority)
    if (game_state.isPaused()) {
        // Animated paused border: base 6px + 4px pulse amplitude
        border_stack.pushAnimated(6.0, GOLD_YELLOW_COLORS, BORDER_PULSE_PAUSED, 4.0);
    }

    if (!game_state.world.player.alive) {
        // Animated dead border: base 9px + 5px pulse amplitude
        border_stack.pushAnimated(9.0, RED_COLORS, BORDER_PULSE_DEAD, 5.0);
    }

    // Render all borders with automatic offset calculation based on current animated widths
    border_stack.render(game_state);
}
