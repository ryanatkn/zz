// Controls - centralized input handling and action dispatch
const std = @import("std");
const types = @import("types.zig");
const constants = @import("constants.zig");
const game_controller = @import("game.zig");
const renderer = @import("renderer.zig");
const hud = @import("hud.zig");
const combat = @import("combat.zig");
const sdl = @import("sdl.zig");

const Vec2 = types.Vec2;
const GameState = game_controller.GameState;
const Renderer = renderer.Renderer;
const Hud = hud.Hud;
const c = sdl.c;

pub fn handleSDLEvent(
    game_state: *GameState,
    game_renderer: *Renderer,
    game_hud: *Hud,
    event: *c.SDL_Event,
) !c.SDL_AppResult {
    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            game_state.requestQuit();
            return c.SDL_APP_SUCCESS;
        },
        c.SDL_EVENT_KEY_DOWN => {
            game_state.input_state.handleKeyDown(event.key.scancode);
            switch (event.key.scancode) {
                c.SDL_SCANCODE_ESCAPE => {
                    game_state.requestQuit();
                    return c.SDL_APP_SUCCESS;
                },
                c.SDL_SCANCODE_GRAVE => { // Backtick key - toggle HUD
                    game_hud.toggle();
                },
                c.SDL_SCANCODE_R => { // R key - respawn/reset
                    game_controller.handleRespawn(game_state);
                },
                c.SDL_SCANCODE_SPACE => { // Space key - pause toggle
                    game_state.togglePause();
                },
                c.SDL_SCANCODE_T => { // T key - reset current zone units
                    game_state.resetZone();
                },
                c.SDL_SCANCODE_Y => { // Y key - full game reset
                    game_state.resetGame();
                },
                // Effect testing hotkeys
                c.SDL_SCANCODE_0 => { // 0 - Player spawn effect
                    game_state.effect_system.addPlayerSpawnEffect(game_state.world.player.pos, game_state.world.player.radius);
                },
                c.SDL_SCANCODE_9 => { // 9 - Portal travel effect
                    game_state.effect_system.addPortalTravelEffect(game_state.world.player.pos, game_state.world.player.radius);
                },
                c.SDL_SCANCODE_8 => { // 8 - Portal ripple effect
                    game_state.effect_system.addPortalRippleEffect(game_state.world.player.pos, game_state.world.player.radius * 2.0);
                },
                c.SDL_SCANCODE_7 => { // 7 - Lifestone glow effect (attuned)
                    game_state.effect_system.addLifestoneGlowEffect(game_state.world.player.pos, game_state.world.player.radius * 1.5, true);
                },
                c.SDL_SCANCODE_6 => { // 6 - Lifestone glow effect (not attuned)
                    game_state.effect_system.addLifestoneGlowEffect(game_state.world.player.pos, game_state.world.player.radius * 1.5, false);
                },
                else => {},
            }
        },
        c.SDL_EVENT_KEY_UP => {
            game_state.input_state.handleKeyUp(event.key.scancode);
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            game_state.input_state.handleMouseMotion(event.motion.x, event.motion.y);
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            game_state.input_state.handleMouseButtonDown(event.button.button);
            switch (event.button.button) {
                c.SDL_BUTTON_LEFT => {
                    if (!game_state.world.player.alive) {
                        game_controller.handleRespawn(game_state);
                    }
                },
                c.SDL_BUTTON_RIGHT => {
                    game_controller.handleFireBullet(game_state, &game_renderer.camera);
                },
                else => {},
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_UP => {
            game_state.input_state.handleMouseButtonUp(event.button.button);
        },
        c.SDL_EVENT_MOUSE_WHEEL => {
            // Mouse wheel zoom
            const current_zone = game_state.world.getCurrentZoneMut();
            const zoom_factor = 1.1; // 10% zoom per wheel tick

            if (event.wheel.y > 0) {
                // Zoom in (scroll up)
                current_zone.camera_scale = @min(10.0, current_zone.camera_scale * zoom_factor);
            } else if (event.wheel.y < 0) {
                // Zoom out (scroll down)
                current_zone.camera_scale = @max(0.1, current_zone.camera_scale / zoom_factor);
            }
        },
        else => {},
    }

    return c.SDL_APP_CONTINUE;
}