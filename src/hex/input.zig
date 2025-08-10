const std = @import("std");
const types = @import("types.zig");
const camera = @import("camera.zig");
const Vec2 = types.Vec2;

const sdl = @import("sdl.zig").c;

pub const InputState = struct {
    keys_down: std.StaticBitSet(512),
    mouse_pos: Vec2,
    left_mouse_held: bool,
    right_mouse_held: bool,

    const Self = @This();

    pub fn init() Self {
        return .{
            .keys_down = std.StaticBitSet(512).initEmpty(),
            .mouse_pos = Vec2{ .x = 0, .y = 0 },
            .left_mouse_held = false,
            .right_mouse_held = false,
        };
    }

    pub fn handleKeyDown(self: *Self, scancode: c_uint) void {
        self.keys_down.set(@intCast(scancode));
    }

    pub fn handleKeyUp(self: *Self, scancode: c_uint) void {
        self.keys_down.unset(@intCast(scancode));
    }

    pub fn handleMouseMotion(self: *Self, x: f32, y: f32) void {
        self.mouse_pos.x = x;
        self.mouse_pos.y = y;
    }

    pub fn handleMouseButtonDown(self: *Self, button: u8) void {
        switch (button) {
            sdl.SDL_BUTTON_LEFT => self.left_mouse_held = true,
            sdl.SDL_BUTTON_RIGHT => self.right_mouse_held = true,
            else => {},
        }
    }

    pub fn handleMouseButtonUp(self: *Self, button: u8) void {
        switch (button) {
            sdl.SDL_BUTTON_LEFT => self.left_mouse_held = false,
            sdl.SDL_BUTTON_RIGHT => self.right_mouse_held = false,
            else => {},
        }
    }

    pub fn isKeyDown(self: *const Self, scancode: c_uint) bool {
        return self.keys_down.isSet(@intCast(scancode));
    }

    pub fn isLeftMouseHeld(self: *const Self) bool {
        return self.left_mouse_held;
    }

    pub fn isRightMouseHeld(self: *const Self) bool {
        return self.right_mouse_held;
    }

    pub fn getMousePos(self: *const Self) Vec2 {
        return self.mouse_pos;
    }

    pub fn getWorldMousePos(self: *const Self, cam: *const camera.Camera) Vec2 {
        return cam.screenToWorld(self.mouse_pos);
    }

    pub fn getMovementVector(self: *const Self) Vec2 {
        var velocity = Vec2{ .x = 0, .y = 0 };

        if (self.isKeyDown(sdl.SDL_SCANCODE_W)) {
            velocity.y -= 1.0;
        }
        if (self.isKeyDown(sdl.SDL_SCANCODE_S)) {
            velocity.y += 1.0;
        }
        if (self.isKeyDown(sdl.SDL_SCANCODE_A)) {
            velocity.x -= 1.0;
        }
        if (self.isKeyDown(sdl.SDL_SCANCODE_D)) {
            velocity.x += 1.0;
        }

        const length = @sqrt(velocity.x * velocity.x + velocity.y * velocity.y);
        if (length > 0) {
            velocity.x /= length;
            velocity.y /= length;
        }

        return velocity;
    }

    pub fn clearMouseHold(self: *Self) void {
        self.left_mouse_held = false;
        self.right_mouse_held = false;
    }
};
