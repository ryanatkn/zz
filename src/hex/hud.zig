const std = @import("std");

// SDL C imports
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
});

// Import shared types
const types = @import("types.zig");
const Color = types.Color;

// Screen constants for HUD positioning
const SCREEN_WIDTH: f32 = 1920;
const SCREEN_HEIGHT: f32 = 1080;

// HUD colors
const WHITE = Color{ .r = 230, .g = 230, .b = 230, .a = 255 };

// Simple bitmap digits for FPS display (5x7 pixels each)
const DIGIT_WIDTH = 6; // 5 + 1 spacing
const DIGIT_HEIGHT = 7;

const DIGITS = [_][7]u8{
    // 0
    [_]u8{ 0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110 },
    // 1
    [_]u8{ 0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110 },
    // 2
    [_]u8{ 0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111 },
    // 3
    [_]u8{ 0b01110, 0b10001, 0b00001, 0b00110, 0b00001, 0b10001, 0b01110 },
    // 4
    [_]u8{ 0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010 },
    // 5
    [_]u8{ 0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110 },
    // 6
    [_]u8{ 0b01110, 0b10001, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110 },
    // 7
    [_]u8{ 0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000 },
    // 8
    [_]u8{ 0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110 },
    // 9
    [_]u8{ 0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b10001, 0b01110 },
};

pub const HUD = struct {
    // FPS tracking with SDL high-resolution timers
    fps_counter: u32,
    fps_frames: u32,
    fps_last_time: u64,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .fps_counter = 60, // Start with reasonable default
            .fps_frames = 0,
            .fps_last_time = c.SDL_GetPerformanceCounter(),
        };
    }

    pub fn updateFPS(self: *Self) void {
        self.fps_frames += 1;
        const current_time = c.SDL_GetPerformanceCounter();
        const elapsed_ticks = current_time - self.fps_last_time;
        const frequency = c.SDL_GetPerformanceFrequency();

        // Update FPS counter every second
        if (elapsed_ticks >= frequency) { // 1 second has passed
            self.fps_counter = self.fps_frames;
            self.fps_frames = 0;
            self.fps_last_time = current_time;
        }
    }

    fn drawDigit(self: *const Self, game_state: anytype, digit: u8, x: f32, y: f32) void {
        _ = self;
        if (digit > 9) return;

        const pattern = DIGITS[digit];
        for (0..DIGIT_HEIGHT) |row| {
            const line = pattern[row];
            for (0..5) |col| { // 5 bits wide
                if ((line >> @intCast(4 - col)) & 1 != 0) {
                    const px = x + @as(f32, @floatFromInt(col));
                    const py = y + @as(f32, @floatFromInt(row));
                    _ = c.SDL_RenderPoint(game_state.renderer, px, py);
                }
            }
        }
    }

    pub fn render(self: *const Self, game_state: anytype) void {
        // Set color for FPS text
        game_state.setRenderColor(WHITE);

        // Draw FPS counter in bottom right
        const fps_text_x = SCREEN_WIDTH - 80.0; // 80 pixels from right edge
        const fps_text_y = SCREEN_HEIGHT - 20.0; // 20 pixels from bottom

        // Draw the FPS counter as a simple number
        // Extract digits from fps_counter
        if (self.fps_counter >= 100) {
            const hundreds = self.fps_counter / 100;
            const tens = (self.fps_counter % 100) / 10;
            const ones = self.fps_counter % 10;
            self.drawDigit(game_state, @intCast(hundreds), fps_text_x, fps_text_y);
            self.drawDigit(game_state, @intCast(tens), fps_text_x + DIGIT_WIDTH, fps_text_y);
            self.drawDigit(game_state, @intCast(ones), fps_text_x + DIGIT_WIDTH * 2, fps_text_y);
        } else if (self.fps_counter >= 10) {
            const tens = self.fps_counter / 10;
            const ones = self.fps_counter % 10;
            self.drawDigit(game_state, @intCast(tens), fps_text_x + DIGIT_WIDTH, fps_text_y);
            self.drawDigit(game_state, @intCast(ones), fps_text_x + DIGIT_WIDTH * 2, fps_text_y);
        } else {
            self.drawDigit(game_state, @intCast(self.fps_counter), fps_text_x + DIGIT_WIDTH * 2, fps_text_y);
        }
    }
};