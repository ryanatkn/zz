// Raylib Core Module (rcore)
// Window management, input handling, timing, file operations, and system functions
const std = @import("std");
const types = @import("raylib_types.zig");

// Import types for internal use
const Vector2 = types.Vector2;
const Vector3 = types.Vector3;
const Color = types.Color;
const Rectangle = types.Rectangle;
const Camera2D = types.Camera2D;
const Camera3D = types.Camera3D;
const Camera = types.Camera;
const Image = types.Image;
const Texture2D = types.Texture2D;
const Shader = types.Shader;
const Matrix = types.Matrix;
const RenderTexture2D = types.RenderTexture2D;
const VrStereoConfig = types.VrStereoConfig;
const VrDeviceInfo = types.VrDeviceInfo;
const FilePathList = types.FilePathList;
const AutomationEvent = types.AutomationEvent;
const AutomationEventList = types.AutomationEventList;

//----------------------------------------------------------------------------------
// Window and System Management (extern functions)
//----------------------------------------------------------------------------------

// Window-related functions
pub extern fn InitWindow(width: c_int, height: c_int, title: [*:0]const u8) void;
pub extern fn CloseWindow() void;
pub extern fn WindowShouldClose() bool;
pub extern fn IsWindowReady() bool;
pub extern fn IsWindowFullscreen() bool;
pub extern fn IsWindowHidden() bool;
pub extern fn IsWindowMinimized() bool;
pub extern fn IsWindowMaximized() bool;
pub extern fn IsWindowFocused() bool;
pub extern fn IsWindowResized() bool;
pub extern fn IsWindowState(flag: c_uint) bool;
pub extern fn SetWindowState(flags: c_uint) void;
pub extern fn ClearWindowState(flags: c_uint) void;
pub extern fn ToggleFullscreen() void;
pub extern fn ToggleBorderlessWindowed() void;
pub extern fn MaximizeWindow() void;
pub extern fn MinimizeWindow() void;
pub extern fn RestoreWindow() void;
pub extern fn SetWindowIcon(image: Image) void;
pub extern fn SetWindowIcons(images: [*]Image, count: c_int) void;
pub extern fn SetWindowTitle(title: [*:0]const u8) void;
pub extern fn SetWindowPosition(x: c_int, y: c_int) void;
pub extern fn SetWindowMonitor(monitor: c_int) void;
pub extern fn SetWindowMinSize(width: c_int, height: c_int) void;
pub extern fn SetWindowMaxSize(width: c_int, height: c_int) void;
pub extern fn SetWindowSize(width: c_int, height: c_int) void;
pub extern fn SetWindowOpacity(opacity: f32) void;
pub extern fn SetWindowFocused() void;
pub extern fn GetWindowHandle() ?*anyopaque;
pub extern fn GetScreenWidth() c_int;
pub extern fn GetScreenHeight() c_int;
pub extern fn GetRenderWidth() c_int;
pub extern fn GetRenderHeight() c_int;
pub extern fn GetMonitorCount() c_int;
pub extern fn GetCurrentMonitor() c_int;
pub extern fn GetMonitorPosition(monitor: c_int) Vector2;
pub extern fn GetMonitorWidth(monitor: c_int) c_int;
pub extern fn GetMonitorHeight(monitor: c_int) c_int;
pub extern fn GetMonitorPhysicalWidth(monitor: c_int) c_int;
pub extern fn GetMonitorPhysicalHeight(monitor: c_int) c_int;
pub extern fn GetMonitorRefreshRate(monitor: c_int) c_int;
pub extern fn GetWindowPosition() Vector2;
pub extern fn GetWindowScaleDPI() Vector2;
pub extern fn GetMonitorName(monitor: c_int) [*:0]const u8;
pub extern fn SetClipboardText(text: [*:0]const u8) void;
pub extern fn GetClipboardText() [*:0]const u8;
pub extern fn GetClipboardImage() Image;
pub extern fn EnableEventWaiting() void;
pub extern fn DisableEventWaiting() void;

// Cursor-related functions
pub extern fn ShowCursor() void;
pub extern fn HideCursor() void;
pub extern fn IsCursorHidden() bool;
pub extern fn EnableCursor() void;
pub extern fn DisableCursor() void;
pub extern fn IsCursorOnScreen() bool;

// Core drawing functions
pub extern fn ClearBackground(color: Color) void;
pub extern fn BeginDrawing() void;
pub extern fn EndDrawing() void;
pub extern fn BeginMode2D(camera: Camera2D) void;
pub extern fn EndMode2D() void;
pub extern fn BeginMode3D(camera: Camera3D) void;
pub extern fn EndMode3D() void;
pub extern fn BeginTextureMode(target: RenderTexture2D) void;
pub extern fn EndTextureMode() void;
pub extern fn BeginShaderMode(shader: Shader) void;
pub extern fn EndShaderMode() void;
pub extern fn BeginBlendMode(mode: c_int) void;
pub extern fn EndBlendMode() void;
pub extern fn BeginScissorMode(x: c_int, y: c_int, width: c_int, height: c_int) void;
pub extern fn EndScissorMode() void;
pub extern fn BeginVrStereoMode(config: VrStereoConfig) void;
pub extern fn EndVrStereoMode() void;

// VR stereo config functions for VR simulator
pub extern fn LoadVrStereoConfig(device: VrDeviceInfo) VrStereoConfig;
pub extern fn UnloadVrStereoConfig(config: VrStereoConfig) void;

// Shader management functions
pub extern fn LoadShader(vsFileName: [*:0]const u8, fsFileName: [*:0]const u8) Shader;
pub extern fn LoadShaderFromMemory(vsCode: [*:0]const u8, fsCode: [*:0]const u8) Shader;
pub extern fn IsShaderValid(shader: Shader) bool;
pub extern fn GetShaderLocation(shader: Shader, uniformName: [*:0]const u8) c_int;
pub extern fn GetShaderLocationAttrib(shader: Shader, attribName: [*:0]const u8) c_int;
pub extern fn SetShaderValue(shader: Shader, locIndex: c_int, value: ?*const anyopaque, uniformType: c_int) void;
pub extern fn SetShaderValueV(shader: Shader, locIndex: c_int, value: ?*const anyopaque, uniformType: c_int, count: c_int) void;
pub extern fn SetShaderValueMatrix(shader: Shader, locIndex: c_int, mat: Matrix) void;
pub extern fn SetShaderValueTexture(shader: Shader, locIndex: c_int, texture: Texture2D) void;
pub extern fn UnloadShader(shader: Shader) void;

// Screen-space-related functions
pub extern fn GetScreenToWorldRay(position: Vector2, camera: Camera) types.Ray;
pub extern fn GetScreenToWorldRayEx(position: Vector2, camera: Camera, width: c_int, height: c_int) types.Ray;
pub extern fn GetWorldToScreen(position: Vector3, camera: Camera) Vector2;
pub extern fn GetWorldToScreenEx(position: Vector3, camera: Camera, width: c_int, height: c_int) Vector2;
pub extern fn GetWorldToScreen2D(position: Vector2, camera: Camera2D) Vector2;
pub extern fn GetScreenToWorld2D(position: Vector2, camera: Camera2D) Vector2;
pub extern fn GetCameraMatrix(camera: Camera) Matrix;
pub extern fn GetCameraMatrix2D(camera: Camera2D) Matrix;

// Timing-related functions
pub extern fn SetTargetFPS(fps: c_int) void;
pub extern fn GetFrameTime() f32;
pub extern fn GetTime() f64;
pub extern fn GetFPS() c_int;

// Custom frame control functions
pub extern fn SwapScreenBuffer() void;
pub extern fn PollInputEvents() void;
pub extern fn WaitTime(seconds: f64) void;

// Random values generation functions
pub extern fn SetRandomSeed(seed: c_uint) void;
pub extern fn GetRandomValue(min: c_int, max: c_int) c_int;
pub extern fn LoadRandomSequence(count: c_uint, min: c_int, max: c_int) [*]c_int;
pub extern fn UnloadRandomSequence(sequence: [*]c_int) void;

// Misc. functions
pub extern fn TakeScreenshot(fileName: [*:0]const u8) void;
pub extern fn SetConfigFlags(flags: c_uint) void;
pub extern fn OpenURL(url: [*:0]const u8) void;

// Set custom callbacks
pub extern fn TraceLog(logLevel: c_int, text: [*:0]const u8, ...) void;
pub extern fn SetTraceLogLevel(logLevel: c_int) void;
pub extern fn MemAlloc(size: c_uint) ?*anyopaque;
pub extern fn MemRealloc(ptr: ?*anyopaque, size: c_uint) ?*anyopaque;
pub extern fn MemFree(ptr: ?*anyopaque) void;

// Files management functions
pub extern fn LoadFileData(fileName: [*:0]const u8, dataSize: [*c]c_int) [*c]u8;
pub extern fn UnloadFileData(data: [*c]u8) void;
pub extern fn SaveFileData(fileName: [*:0]const u8, data: ?*anyopaque, dataSize: c_int) bool;
pub extern fn ExportDataAsCode(data: [*c]const u8, dataSize: c_int, fileName: [*:0]const u8) bool;
pub extern fn LoadFileText(fileName: [*:0]const u8) [*:0]u8;
pub extern fn UnloadFileText(text: [*:0]u8) void;
pub extern fn SaveFileText(fileName: [*:0]const u8, text: [*:0]u8) bool;

// File system functions
pub extern fn FileExists(fileName: [*:0]const u8) bool;
pub extern fn DirectoryExists(dirPath: [*:0]const u8) bool;
pub extern fn IsFileExtension(fileName: [*:0]const u8, ext: [*:0]const u8) bool;
pub extern fn GetFileLength(fileName: [*:0]const u8) c_int;
pub extern fn GetFileExtension(fileName: [*:0]const u8) [*:0]const u8;
pub extern fn GetFileName(filePath: [*:0]const u8) [*:0]const u8;
pub extern fn GetFileNameWithoutExt(filePath: [*:0]const u8) [*:0]const u8;
pub extern fn GetDirectoryPath(filePath: [*:0]const u8) [*:0]const u8;
pub extern fn GetPrevDirectoryPath(dirPath: [*:0]const u8) [*:0]const u8;
pub extern fn GetWorkingDirectory() [*:0]const u8;
pub extern fn GetApplicationDirectory() [*:0]const u8;
pub extern fn MakeDirectory(dirPath: [*:0]const u8) c_int;
pub extern fn ChangeDirectory(dir: [*:0]const u8) bool;
pub extern fn IsPathFile(path: [*:0]const u8) bool;
pub extern fn IsFileNameValid(fileName: [*:0]const u8) bool;
pub extern fn LoadDirectoryFiles(dirPath: [*:0]const u8) FilePathList;
pub extern fn LoadDirectoryFilesEx(basePath: [*:0]const u8, filter: [*:0]const u8, scanSubdirs: bool) FilePathList;
pub extern fn UnloadDirectoryFiles(files: FilePathList) void;
pub extern fn IsFileDropped() bool;
pub extern fn LoadDroppedFiles() FilePathList;
pub extern fn UnloadDroppedFiles(files: FilePathList) void;
pub extern fn GetFileModTime(fileName: [*:0]const u8) c_long;

// Compression/Encoding functionality
pub extern fn CompressData(data: [*c]const u8, dataSize: c_int, compDataSize: [*c]c_int) [*c]u8;
pub extern fn DecompressData(compData: [*c]const u8, compDataSize: c_int, dataSize: [*c]c_int) [*c]u8;
pub extern fn EncodeDataBase64(data: [*c]const u8, dataSize: c_int, outputSize: [*c]c_int) [*:0]u8;
pub extern fn DecodeDataBase64(data: [*c]const u8, outputSize: [*c]c_int) [*c]u8;
pub extern fn ComputeCRC32(data: [*c]u8, dataSize: c_int) c_uint;
pub extern fn ComputeMD5(data: [*c]u8, dataSize: c_int) [*c]c_uint;
pub extern fn ComputeSHA1(data: [*c]u8, dataSize: c_int) [*c]c_uint;

// Automation events functionality
pub extern fn LoadAutomationEventList(fileName: [*:0]const u8) AutomationEventList;
pub extern fn UnloadAutomationEventList(list: AutomationEventList) void;
pub extern fn ExportAutomationEventList(list: AutomationEventList, fileName: [*:0]const u8) bool;
pub extern fn SetAutomationEventList(list: *AutomationEventList) void;
pub extern fn SetAutomationEventBaseFrame(frame: c_int) void;
pub extern fn StartAutomationEventRecording() void;
pub extern fn StopAutomationEventRecording() void;
pub extern fn PlayAutomationEvent(event: AutomationEvent) void;

// Input-related functions: keyboard
pub extern fn IsKeyPressed(key: c_int) bool;
pub extern fn IsKeyPressedRepeat(key: c_int) bool;
pub extern fn IsKeyDown(key: c_int) bool;
pub extern fn IsKeyReleased(key: c_int) bool;
pub extern fn IsKeyUp(key: c_int) bool;
pub extern fn GetKeyPressed() c_int;
pub extern fn GetCharPressed() c_int;
pub extern fn SetExitKey(key: c_int) void;

// Input-related functions: gamepads
pub extern fn IsGamepadAvailable(gamepad: c_int) bool;
pub extern fn GetGamepadName(gamepad: c_int) [*:0]const u8;
pub extern fn IsGamepadButtonPressed(gamepad: c_int, button: c_int) bool;
pub extern fn IsGamepadButtonDown(gamepad: c_int, button: c_int) bool;
pub extern fn IsGamepadButtonReleased(gamepad: c_int, button: c_int) bool;
pub extern fn IsGamepadButtonUp(gamepad: c_int, button: c_int) bool;
pub extern fn GetGamepadButtonPressed() c_int;
pub extern fn GetGamepadAxisCount(gamepad: c_int) c_int;
pub extern fn GetGamepadAxisMovement(gamepad: c_int, axis: c_int) f32;
pub extern fn SetGamepadMappings(mappings: [*:0]const u8) c_int;
pub extern fn SetGamepadVibration(gamepad: c_int, leftMotor: f32, rightMotor: f32, duration: f32) void;

// Input-related functions: mouse
pub extern fn IsMouseButtonPressed(button: c_int) bool;
pub extern fn IsMouseButtonDown(button: c_int) bool;
pub extern fn IsMouseButtonReleased(button: c_int) bool;
pub extern fn IsMouseButtonUp(button: c_int) bool;
pub extern fn GetMouseX() c_int;
pub extern fn GetMouseY() c_int;
pub extern fn GetMousePosition() Vector2;
pub extern fn GetMouseDelta() Vector2;
pub extern fn SetMousePosition(x: c_int, y: c_int) void;
pub extern fn SetMouseOffset(offsetX: c_int, offsetY: c_int) void;
pub extern fn SetMouseScale(scaleX: f32, scaleY: f32) void;
pub extern fn GetMouseWheelMove() f32;
pub extern fn GetMouseWheelMoveV() Vector2;
pub extern fn SetMouseCursor(cursor: c_int) void;

// Input-related functions: touch
pub extern fn GetTouchX() c_int;
pub extern fn GetTouchY() c_int;
pub extern fn GetTouchPosition(index: c_int) Vector2;
pub extern fn GetTouchPointId(index: c_int) c_int;
pub extern fn GetTouchPointCount() c_int;

// Gestures and Touch Handling Functions
pub extern fn SetGesturesEnabled(flags: c_uint) void;
pub extern fn IsGestureDetected(gesture: c_uint) bool;
pub extern fn GetGestureDetected() c_int;
pub extern fn GetGestureHoldDuration() f32;
pub extern fn GetGestureDragVector() Vector2;
pub extern fn GetGestureDragAngle() f32;
pub extern fn GetGesturePinchVector() Vector2;
pub extern fn GetGesturePinchAngle() f32;

// Camera System Functions
pub extern fn UpdateCamera(camera: *Camera, mode: c_int) void;
pub extern fn UpdateCameraPro(camera: *Camera, movement: Vector3, rotation: Vector3, zoom: f32) void;

