const std = @import("std");
const game = @import("game.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    app_err.reset();

    // Store allocator globally for use in SDL callbacks
    global_allocator = allocator;

    var empty_argv: [0:null]?[*:0]u8 = .{};
    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
    if (app_err.load()) |err| {
        return err;
    }
    if (status != 0) {
        return error.SdlAppError;
    }
}

// SDL C imports
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cDefine("SDL_MAIN_HANDLED", {});
    @cInclude("SDL3/SDL_main.h");
});

const window_w = 1920;
const window_h = 1080;

var fully_initialized = false;
var window: *c.SDL_Window = undefined;
var renderer: *c.SDL_Renderer = undefined;
var global_allocator: std.mem.Allocator = undefined;
var quit_requested = false;

fn sdlAppInit(appstate: ?*?*anyopaque, argv: [][*:0]u8) !c.SDL_AppResult {
    _ = appstate;
    _ = argv;

    try errify(c.SDL_Init(c.SDL_INIT_VIDEO));

    try errify(c.SDL_CreateWindowAndRenderer("Hex", window_w, window_h, c.SDL_WINDOW_RESIZABLE, @ptrCast(&window), @ptrCast(&renderer)));
    errdefer c.SDL_DestroyWindow(window);
    errdefer c.SDL_DestroyRenderer(renderer);

    fully_initialized = true;
    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) !c.SDL_AppResult {
    _ = appstate;

    if (quit_requested) {
        return c.SDL_APP_SUCCESS;
    }

    // Run the game using our game module
    game.run(global_allocator, window, renderer) catch |err| {
        std.debug.print("Game error: {}\n", .{err});
        return c.SDL_APP_FAILURE;
    };

    return c.SDL_APP_SUCCESS; // Game loop handles its own termination
}

fn sdlAppEvent(appstate: ?*anyopaque, event: *c.SDL_Event) !c.SDL_AppResult {
    _ = appstate;

    switch (event.type) {
        c.SDL_EVENT_QUIT => {
            quit_requested = true;
            return c.SDL_APP_SUCCESS;
        },
        else => {},
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppQuit(appstate: ?*anyopaque, result: anyerror!c.SDL_AppResult) void {
    _ = appstate;
    _ = result catch {};

    if (fully_initialized) {
        c.SDL_DestroyRenderer(renderer);
        c.SDL_DestroyWindow(window);
        fully_initialized = false;
    }
}

// Helper function to convert SDL return values to errors
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

// SDL main callbacks boilerplate
fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    return c.SDL_EnterAppMainCallbacks(0, null, sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    _ = argc;
    _ = argv;
    const empty_slice: [][*:0]u8 = &.{};
    return sdlAppInit(appstate.?, empty_slice) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    return sdlAppIterate(appstate) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return sdlAppEvent(appstate, event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(appstate, app_err.load() orelse result);
}

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn reset(es: *ErrorStore) void {
        _ = c.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
        if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = c.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return c.SDL_APP_FAILURE;
    }

    fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};
