const std = @import("std");
const raylib = @import("raylib.zig");
const types = @import("types.zig");

pub const InputState = struct {
    mousePos: raylib.Vector2,
    leftMouseDown: bool,
    rightMousePressed: bool,
    keyboardMovement: raylib.Vector2,
    restartPressed: bool,
    quitPressed: bool,
};

pub fn getInputState() InputState {
    return InputState{
        .mousePos = raylib.getMousePosition(),
        .leftMouseDown = raylib.isMouseButtonDown(raylib.MOUSE_BUTTON_LEFT),
        .rightMousePressed = raylib.isMouseButtonPressed(raylib.MOUSE_BUTTON_RIGHT),
        .keyboardMovement = getKeyboardMovement(),
        .restartPressed = raylib.isKeyPressed(raylib.KEY_R) or raylib.isMouseButtonPressed(raylib.MOUSE_BUTTON_LEFT),
        .quitPressed = raylib.isKeyPressed(raylib.KEY_ESCAPE),
    };
}

fn getKeyboardMovement() raylib.Vector2 {
    var movement = raylib.Vector2{ .x = 0, .y = 0 };

    if (raylib.isKeyDown(raylib.KEY_W) or raylib.isKeyDown(raylib.KEY_UP)) movement.y -= 1;
    if (raylib.isKeyDown(raylib.KEY_S) or raylib.isKeyDown(raylib.KEY_DOWN)) movement.y += 1;
    if (raylib.isKeyDown(raylib.KEY_A) or raylib.isKeyDown(raylib.KEY_LEFT)) movement.x -= 1;
    if (raylib.isKeyDown(raylib.KEY_D) or raylib.isKeyDown(raylib.KEY_RIGHT)) movement.x += 1;

    // Normalize diagonal movement
    if (movement.x != 0 and movement.y != 0) {
        movement.x *= 0.707;
        movement.y *= 0.707;
    }

    return movement;
}
