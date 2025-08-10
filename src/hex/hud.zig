const std = @import("std");

const sdl = @import("sdl.zig").c;

const types = @import("types.zig");

const Color = types.Color;

// HUD system now uses GPU-based rendering through the renderer
// Old bitmap digit constants removed - see renderer.zig for current implementation

pub const Hud = struct {
    // FPS tracking with SDL high-resolution timers
    fps_counter: u32,
    fps_frames: u32,
    fps_last_time: u64,

    // HUD visibility toggle
    visible: bool,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .fps_counter = 60, // Start with reasonable default
            .fps_frames = 0,
            .fps_last_time = sdl.SDL_GetPerformanceCounter(),
            .visible = true, // Start visible
        };
    }

    pub fn toggle(self: *Self) void {
        self.visible = !self.visible;
    }

    pub fn updateFPS(self: *Self, current_time: u64, frequency: u64) void {
        self.fps_frames += 1;
        const elapsed_ticks = current_time - self.fps_last_time;

        // Update FPS counter every second
        if (elapsed_ticks >= frequency) { // 1 second has passed
            self.fps_counter = self.fps_frames;
            self.fps_frames = 0;
            self.fps_last_time = current_time;
        }
    }

    // Note: Rendering is now handled directly by the renderer.drawFPS() method
    // The old render() method with bitmap digits has been replaced by the GPU renderer's
    // more efficient digit drawing system
};
