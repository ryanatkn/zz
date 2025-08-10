const std = @import("std");

// Import new modules
const entities = @import("entities.zig");
const behaviors = @import("behaviors.zig");
const physics = @import("physics.zig");
const renderer = @import("renderer.zig");
const loader = @import("loader.zig");
const types = @import("types.zig");
const hud = @import("hud.zig");
const input = @import("input.zig");
const game_controller = @import("game.zig");
const combat = @import("combat.zig");
const player_controller = @import("player.zig");
const portals = @import("portals.zig");
const maths = @import("maths.zig");
const controls = @import("controls.zig");

// Debug test (only load if needed)
const gpu_circle_test = @import("gpu_circle_test.zig");

const Vec2 = types.Vec2;
const Color = types.Color;
const World = entities.World;
const Renderer = renderer.Renderer;
const GameState = game_controller.GameState;
const Hud = hud.Hud;

// Test mode for debugging - change to enable debug tests
const DEBUG_MODE = false; // Set to true to run debug tests instead of game

pub fn run(allocator: std.mem.Allocator) !void {
    app_err.reset();

    // Store allocator globally for use in SDL callbacks
    global_allocator = allocator;

    var empty_argv: [0:null]?[*:0]u8 = .{};
    const status: u8 = @truncate(@as(c_uint, @bitCast(sdl.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
    if (app_err.load()) |err| {
        return err;
    }
    if (status != 0) {
        return error.SdlAppError;
    }
}

const sdl = @import("sdl.zig").c;

const constants = @import("constants.zig");
const window_w = @as(u32, @intFromFloat(constants.SCREEN_WIDTH));
const window_h = @as(u32, @intFromFloat(constants.SCREEN_HEIGHT));

var fully_initialized = false;
var window: *sdl.SDL_Window = undefined;
var game_renderer: Renderer = undefined;
var game_state: GameState = undefined;
var game_hud: Hud = undefined;
var global_allocator: std.mem.Allocator = undefined;

// Timing
var last_time: u64 = 0;

// Debug test globals
var circle_test: ?gpu_circle_test.CircleTest = null;

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !sdl.SDL_AppResult {
    _ = appstate;
    _ = argv;

    try errify(sdl.SDL_Init(sdl.SDL_INIT_VIDEO));

    // Create window hidden initially
    window = sdl.SDL_CreateWindow("Hex GPU Game", window_w, window_h, sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN) orelse {
        return error.SdlError;
    };
    errdefer sdl.SDL_DestroyWindow(window);

    if (DEBUG_MODE) {
        // Debug mode - no GPU renderer needed
        fully_initialized = true;
        return sdl.SDL_APP_CONTINUE;
    }

    // Initialize renderer
    game_renderer = try Renderer.init(global_allocator, window);

    // Initialize game state
    game_state = GameState.init();

    // Initialize HUD
    game_hud = Hud.init();

    // Load game data
    loader.loadGameData(global_allocator, &game_state.world) catch |err| {
        std.debug.print("Failed to load game data from ZON file: {}\n", .{err});
        std.debug.print("Please check that game_data.zon exists and is valid\n", .{});
        return err;
    };

    // Initialize ambient effects for starting zone
    game_state.effect_system.refreshAmbientEffects(&game_state.world);

    // Show window after initialization
    _ = sdl.SDL_ShowWindow(window);

    last_time = sdl.SDL_GetPerformanceCounter();

    fully_initialized = true;
    std.debug.print("Hex GPU game initialized successfully\n", .{});
    std.debug.print("Controls: Hold mouse to move, WASD for direct movement, Space to pause, ESC to quit\n", .{});
    std.debug.print("Portal interaction: Walk into portals to travel between zones\n", .{});
    return sdl.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !sdl.SDL_AppResult {
    _ = appstate;

    if (game_state.shouldQuit()) {
        return sdl.SDL_APP_SUCCESS;
    }

    if (DEBUG_MODE) {
        // Debug mode - run GPU tests
        try runDebugTests(global_allocator, window);
    } else {
        // Game mode - run actual game
        try runGameLoop();
    }

    return sdl.SDL_APP_CONTINUE;
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *sdl.SDL_Event) !sdl.SDL_AppResult {
    _ = appstate;
    return controls.handleSDLEvent(&game_state, &game_renderer, &game_hud, event);
}

fn sdlAppQuit(appstate: ?*anyopaque, result: anyerror!sdl.SDL_AppResult) void {
    _ = appstate;
    _ = result catch {};

    if (fully_initialized) {
        if (DEBUG_MODE) {
            if (circle_test) |*c_test| {
                c_test.deinit();
                circle_test = null;
            }
        } else {
            game_renderer.deinit();
            loader.deinit(); // Clean up ZON data memory
        }
        sdl.SDL_DestroyWindow(window);
        fully_initialized = false;
    }
}

// Game loop functions
fn runGameLoop() !void {
    // Calculate delta time
    const current_time = sdl.SDL_GetPerformanceCounter();
    const frequency = sdl.SDL_GetPerformanceFrequency();
    const delta_ticks = current_time - last_time;
    const deltaTime: f32 = @as(f32, @floatFromInt(delta_ticks)) / @as(f32, @floatFromInt(frequency));
    last_time = current_time;

    // Update HUD system
    game_hud.updateFPS(current_time, frequency);

    // Update camera before game logic (for correct mouse coordinate transformation)
    game_renderer.updateCamera(&game_state.world);

    // Update game state
    game_controller.updateGame(&game_state, &game_renderer.camera, deltaTime);

    // Render
    try renderGame();
}

fn renderGame() !void {
    const zone = game_state.world.getCurrentZone();

    // Begin GPU frame
    const cmd_buffer = try game_renderer.beginFrame(window);
    const render_pass = try game_renderer.beginRenderPass(cmd_buffer, window, zone.background_color);

    // Render all entities
    game_renderer.renderZone(cmd_buffer, render_pass, &game_state.world);

    // Render visual effects
    game_renderer.renderEffects(cmd_buffer, render_pass, &game_state.effect_system);

    // Draw HUD
    if (game_hud.visible) {
        game_renderer.drawFPS(cmd_buffer, render_pass, game_hud.fps_counter);
    }

    // Draw state borders with stacking support and iris wipe effect
    game_renderer.drawBorders(cmd_buffer, render_pass, &game_state);

    game_renderer.endRenderPass(render_pass);
    game_renderer.endFrame(cmd_buffer);
}

// Debug test functions
fn runDebugTests(allocator: std.mem.Allocator, win: *sdl.SDL_Window) !void {
    if (circle_test == null) {
        circle_test = gpu_circle_test.CircleTest.init(allocator, win) catch |err| {
            std.debug.print("Circle test initialization failed: {}\n", .{err});
            return err;
        };
        std.debug.print("Circle test initialized successfully\n", .{});
    }

    if (circle_test) |*c_test| {
        c_test.render(win) catch |err| {
            std.debug.print("Circle test render failed: {}\n", .{err});
            return err;
        };
    }
}

// SDL boilerplate
inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
    .bool => void,
    .pointer, .optional => @TypeOf(value.?),
    .int => |info| switch (info.signedness) {
        .signed => @TypeOf(@max(0, value)),
        .unsigned => @TypeOf(value),
    },
    else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
} {
    return switch (@typeInfo(@TypeOf(value))) {
        .bool => if (!value) error.SdlError,
        .pointer, .optional => value orelse error.SdlError,
        .int => |info| switch (info.signedness) {
            .signed => if (value >= 0) @max(0, value) else error.SdlError,
            .unsigned => if (value != 0) value else error.SdlError,
        },
        else => comptime unreachable,
    };
}

// SDL main callbacks
fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    return sdl.SDL_EnterAppMainCallbacks(0, null, sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) sdl.SDL_AppResult {
    _ = argc;
    _ = argv;
    const empty_slice: [][*:0]u8 = &.{};
    return sdlAppInit(appstate.?, empty_slice) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) sdl.SDL_AppResult {
    return sdlAppIterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*sdl.SDL_Event) callconv(.c) sdl.SDL_AppResult {
    return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: sdl.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(appstate, app_err.load() orelse result);
}

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: sdl.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn reset(es: *ErrorStore) void {
        _ = sdl.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    fn store(es: *ErrorStore, err: anyerror) sdl.SDL_AppResult {
        if (sdl.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = sdl.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return sdl.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (sdl.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};
