// Raylib bindings for Zig
const std = @import("std");

// Basic types
pub const Vector2 = extern struct {
    x: f32,
    y: f32,
};

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

// Predefined colors
pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
pub const WHITE = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
pub const RED = Color{ .r = 230, .g = 41, .b = 55, .a = 255 };
pub const BLUE = Color{ .r = 0, .g = 121, .b = 241, .a = 255 };
pub const YELLOW = Color{ .r = 253, .g = 249, .b = 0, .a = 255 };
pub const GRAY = Color{ .r = 130, .g = 130, .b = 130, .a = 255 };
pub const GREEN = Color{ .r = 0, .g = 228, .b = 48, .a = 255 };
pub const PURPLE = Color{ .r = 200, .g = 122, .b = 255, .a = 255 };

// Key constants
pub const KEY_W = 87;
pub const KEY_S = 83;
pub const KEY_A = 65;
pub const KEY_D = 68;
pub const KEY_UP = 265;
pub const KEY_DOWN = 264;
pub const KEY_LEFT = 263;
pub const KEY_RIGHT = 262;
pub const KEY_ESCAPE = 256;
pub const KEY_R = 82;
pub const KEY_SPACE = 32;
pub const KEY_LEFT_BRACKET = 91;  // [
pub const KEY_RIGHT_BRACKET = 93; // ]

// Mouse constants
pub const MOUSE_BUTTON_LEFT = 0;
pub const MOUSE_BUTTON_RIGHT = 1;

// External function declarations
extern fn InitWindow(width: c_int, height: c_int, title: [*:0]const u8) void;
extern fn SetTargetFPS(fps: c_int) void;
extern fn WindowShouldClose() bool;
extern fn CloseWindow() void;
extern fn ToggleFullscreen() void;
extern fn GetScreenWidth() c_int;
extern fn GetScreenHeight() c_int;
extern fn BeginDrawing() void;
extern fn EndDrawing() void;
extern fn ClearBackground(color: Color) void;
extern fn DrawCircleV(center: Vector2, radius: f32, color: Color) void;
extern fn DrawCircleLines(centerX: c_int, centerY: c_int, radius: f32, color: Color) void;
extern fn DrawRectangle(posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) void;
extern fn DrawRectangleV(position: Vector2, size: Vector2, color: Color) void;
extern fn DrawRectangleLines(posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) void;
extern fn DrawTriangle(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
extern fn DrawTriangleLines(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
extern fn DrawText(text: [*:0]const u8, posX: c_int, posY: c_int, fontSize: c_int, color: Color) void;
extern fn GetFrameTime() f32;
extern fn GetFPS() c_int;
extern fn GetTime() f64;
extern fn MeasureText(text: [*:0]const u8, fontSize: c_int) c_int;
extern fn IsKeyDown(key: c_int) bool;
extern fn IsKeyPressed(key: c_int) bool;
extern fn IsMouseButtonPressed(button: c_int) bool;
extern fn IsMouseButtonDown(button: c_int) bool;
extern fn GetMousePosition() Vector2;
extern fn GetRandomValue(min: c_int, max: c_int) c_int;
extern fn SetRandomSeed(seed: c_uint) void;
extern fn TextFormat(text: [*:0]const u8, ...) [*:0]const u8;
extern fn ColorFromHSV(hue: f32, saturation: f32, value: f32) Color;

// Wrapper functions for easier Zig usage
pub fn initWindow(width: i32, height: i32, title: [:0]const u8) void {
    InitWindow(@intCast(width), @intCast(height), title.ptr);
}

pub fn setTargetFPS(fps: i32) void {
    SetTargetFPS(@intCast(fps));
}

pub fn windowShouldClose() bool {
    return WindowShouldClose();
}

pub fn closeWindow() void {
    CloseWindow();
}

pub fn toggleFullscreen() void {
    ToggleFullscreen();
}

pub fn getScreenWidth() i32 {
    return @intCast(GetScreenWidth());
}

pub fn getScreenHeight() i32 {
    return @intCast(GetScreenHeight());
}

pub fn beginDrawing() void {
    BeginDrawing();
}

pub fn endDrawing() void {
    EndDrawing();
}

pub fn clearBackground(color: Color) void {
    ClearBackground(color);
}

pub fn drawCircleV(center: Vector2, radius: f32, color: Color) void {
    DrawCircleV(center, radius, color);
}

pub fn drawCircleLinesV(center: Vector2, radius: f32, color: Color) void {
    DrawCircleLines(@intFromFloat(center.x), @intFromFloat(center.y), radius, color);
}

pub fn drawRectangle(posX: i32, posY: i32, width: i32, height: i32, color: Color) void {
    DrawRectangle(@intCast(posX), @intCast(posY), @intCast(width), @intCast(height), color);
}

pub fn drawRectangleV(position: Vector2, size: Vector2, color: Color) void {
    DrawRectangleV(position, size, color);
}

pub fn drawRectangleLinesV(position: Vector2, size: Vector2, color: Color) void {
    DrawRectangleLines(@intFromFloat(position.x), @intFromFloat(position.y), @intFromFloat(size.x), @intFromFloat(size.y), color);
}

pub fn drawTriangle(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void {
    DrawTriangle(v1, v2, v3, color);
}

pub fn drawTriangleLines(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void {
    DrawTriangleLines(v1, v2, v3, color);
}

pub fn drawText(text: [:0]const u8, posX: i32, posY: i32, fontSize: i32, color: Color) void {
    DrawText(text.ptr, @intCast(posX), @intCast(posY), @intCast(fontSize), color);
}

pub fn getFrameTime() f32 {
    return GetFrameTime();
}

pub fn getFPS() i32 {
    return @intCast(GetFPS());
}

pub fn getTime() f64 {
    return GetTime();
}

pub fn measureText(text: [:0]const u8, fontSize: i32) i32 {
    return @intCast(MeasureText(text.ptr, @intCast(fontSize)));
}

pub fn isKeyDown(key: i32) bool {
    return IsKeyDown(@intCast(key));
}

pub fn isKeyPressed(key: i32) bool {
    return IsKeyPressed(@intCast(key));
}

pub fn isMouseButtonPressed(button: i32) bool {
    return IsMouseButtonPressed(@intCast(button));
}

pub fn isMouseButtonDown(button: i32) bool {
    return IsMouseButtonDown(@intCast(button));
}

pub fn getMousePosition() Vector2 {
    return GetMousePosition();
}

pub fn getRandomValue(min: i32, max: i32) i32 {
    return @intCast(GetRandomValue(@intCast(min), @intCast(max)));
}

pub fn setRandomSeed(seed: u32) void {
    SetRandomSeed(seed);
}

pub fn textFormat(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![:0]u8 {
    return std.fmt.allocPrintZ(allocator, fmt, args);
}

pub fn colorFromHSV(hue: f32, saturation: f32, value: f32) Color {
    return ColorFromHSV(hue, saturation, value);
}
