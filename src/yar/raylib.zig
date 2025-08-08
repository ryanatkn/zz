// Raylib bindings for Zig
// Complete bindings for Raylib 5.5.0
const std = @import("std");

//----------------------------------------------------------------------------------
// Basic Types and Structures
//----------------------------------------------------------------------------------

pub const Vector2 = extern struct {
    x: f32,
    y: f32,
};

pub const Vector3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Vector4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const Quaternion = Vector4;

pub const Matrix = extern struct {
    m0: f32,
    m4: f32,
    m8: f32,
    m12: f32,
    m1: f32,
    m5: f32,
    m9: f32,
    m13: f32,
    m2: f32,
    m6: f32,
    m10: f32,
    m14: f32,
    m3: f32,
    m7: f32,
    m11: f32,
    m15: f32,
};

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const Rectangle = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Image = extern struct {
    data: ?*anyopaque,
    width: c_int,
    height: c_int,
    mipmaps: c_int,
    format: c_int,
};

pub const Texture = extern struct {
    id: c_uint,
    width: c_int,
    height: c_int,
    mipmaps: c_int,
    format: c_int,
};

pub const Texture2D = Texture;
pub const TextureCubemap = Texture;

pub const RenderTexture = extern struct {
    id: c_uint,
    texture: Texture,
    depth: Texture,
};

pub const RenderTexture2D = RenderTexture;

pub const NPatchInfo = extern struct {
    source: Rectangle,
    left: c_int,
    top: c_int,
    right: c_int,
    bottom: c_int,
    layout: c_int,
};

pub const GlyphInfo = extern struct {
    value: c_int,
    offsetX: c_int,
    offsetY: c_int,
    advanceX: c_int,
    image: Image,
};

pub const Font = extern struct {
    baseSize: c_int,
    glyphCount: c_int,
    glyphPadding: c_int,
    texture: Texture2D,
    recs: ?*Rectangle,
    glyphs: ?*GlyphInfo,
};

pub const Camera3D = extern struct {
    position: Vector3,
    target: Vector3,
    up: Vector3,
    fovy: f32,
    projection: c_int,
};

pub const Camera = Camera3D;

pub const Camera2D = extern struct {
    offset: Vector2,
    target: Vector2,
    rotation: f32,
    zoom: f32,
};

pub const Mesh = extern struct {
    vertexCount: c_int,
    triangleCount: c_int,
    vertices: ?[*]f32,
    texcoords: ?[*]f32,
    texcoords2: ?[*]f32,
    normals: ?[*]f32,
    tangents: ?[*]f32,
    colors: ?[*]u8,
    indices: ?[*]c_ushort,
    animVertices: ?[*]f32,
    animNormals: ?[*]f32,
    boneIds: ?[*]u8,
    boneWeights: ?[*]f32,
    boneMatrices: ?[*]Matrix,
    boneCount: c_int,
    vaoId: c_uint,
    vboId: ?[*]c_uint,
};

pub const Shader = extern struct {
    id: c_uint,
    locs: ?[*]c_int,
};

pub const MaterialMap = extern struct {
    texture: Texture2D,
    color: Color,
    value: f32,
};

pub const Material = extern struct {
    shader: Shader,
    maps: ?[*]MaterialMap,
    params: [4]f32,
};

pub const Transform = extern struct {
    translation: Vector3,
    rotation: Quaternion,
    scale: Vector3,
};

pub const BoneInfo = extern struct {
    name: [32]u8,
    parent: c_int,
};

pub const Model = extern struct {
    transform: Matrix,
    meshCount: c_int,
    materialCount: c_int,
    meshes: ?[*]Mesh,
    materials: ?[*]Material,
    meshMaterial: ?[*]c_int,
    boneCount: c_int,
    bones: ?[*]BoneInfo,
    bindPose: ?[*]Transform,
};

pub const ModelAnimation = extern struct {
    boneCount: c_int,
    frameCount: c_int,
    bones: ?[*]BoneInfo,
    framePoses: ?[*]?[*]Transform,
    name: [32]u8,
};

pub const Ray = extern struct {
    position: Vector3,
    direction: Vector3,
};

pub const RayCollision = extern struct {
    hit: bool,
    distance: f32,
    point: Vector3,
    normal: Vector3,
};

pub const BoundingBox = extern struct {
    min: Vector3,
    max: Vector3,
};

pub const Wave = extern struct {
    frameCount: c_uint,
    sampleRate: c_uint,
    sampleSize: c_uint,
    channels: c_uint,
    data: ?*anyopaque,
};

pub const AudioStream = extern struct {
    buffer: ?*anyopaque,
    processor: ?*anyopaque,
    sampleRate: c_uint,
    sampleSize: c_uint,
    channels: c_uint,
};

pub const Sound = extern struct {
    stream: AudioStream,
    frameCount: c_uint,
};

pub const Music = extern struct {
    stream: AudioStream,
    frameCount: c_uint,
    looping: bool,
    ctxType: c_int,
    ctxData: ?*anyopaque,
};

pub const VrDeviceInfo = extern struct {
    hResolution: c_int,
    vResolution: c_int,
    hScreenSize: f32,
    vScreenSize: f32,
    eyeToScreenDistance: f32,
    lensSeparationDistance: f32,
    interpupillaryDistance: f32,
    lensDistortionValues: [4]f32,
    chromaAbCorrection: [4]f32,
};

pub const VrStereoConfig = extern struct {
    projection: [2]Matrix,
    viewOffset: [2]Matrix,
    leftLensCenter: [2]f32,
    rightLensCenter: [2]f32,
    leftScreenCenter: [2]f32,
    rightScreenCenter: [2]f32,
    scale: [2]f32,
    scaleIn: [2]f32,
};

pub const FilePathList = extern struct {
    capacity: c_uint,
    count: c_uint,
    paths: ?[*]?[*:0]u8,
};

pub const AutomationEvent = extern struct {
    frame: c_uint,
    type: c_uint,
    params: [4]c_int,
};

pub const AutomationEventList = extern struct {
    capacity: c_uint,
    count: c_uint,
    events: ?[*]AutomationEvent,
};

//----------------------------------------------------------------------------------
// Enumerations
//----------------------------------------------------------------------------------

pub const ConfigFlags = enum(c_uint) {
    FLAG_VSYNC_HINT = 0x00000040,
    FLAG_FULLSCREEN_MODE = 0x00000002,
    FLAG_WINDOW_RESIZABLE = 0x00000004,
    FLAG_WINDOW_UNDECORATED = 0x00000008,
    FLAG_WINDOW_HIDDEN = 0x00000080,
    FLAG_WINDOW_MINIMIZED = 0x00000200,
    FLAG_WINDOW_MAXIMIZED = 0x00000400,
    FLAG_WINDOW_UNFOCUSED = 0x00000800,
    FLAG_WINDOW_TOPMOST = 0x00001000,
    FLAG_WINDOW_ALWAYS_RUN = 0x00000100,
    FLAG_WINDOW_TRANSPARENT = 0x00000010,
    FLAG_WINDOW_HIGHDPI = 0x00002000,
    FLAG_WINDOW_MOUSE_PASSTHROUGH = 0x00004000,
    FLAG_BORDERLESS_WINDOWED_MODE = 0x00008000,
    FLAG_MSAA_4X_HINT = 0x00000020,
    FLAG_INTERLACED_HINT = 0x00010000,
};

pub const TraceLogLevel = enum(c_int) {
    LOG_ALL = 0,
    LOG_TRACE = 1,
    LOG_DEBUG = 2,
    LOG_INFO = 3,
    LOG_WARNING = 4,
    LOG_ERROR = 5,
    LOG_FATAL = 6,
    LOG_NONE = 7,
};

pub const KeyboardKey = enum(c_int) {
    KEY_NULL = 0,
    // Alphanumeric keys
    KEY_APOSTROPHE = 39,
    KEY_COMMA = 44,
    KEY_MINUS = 45,
    KEY_PERIOD = 46,
    KEY_SLASH = 47,
    KEY_ZERO = 48,
    KEY_ONE = 49,
    KEY_TWO = 50,
    KEY_THREE = 51,
    KEY_FOUR = 52,
    KEY_FIVE = 53,
    KEY_SIX = 54,
    KEY_SEVEN = 55,
    KEY_EIGHT = 56,
    KEY_NINE = 57,
    KEY_SEMICOLON = 59,
    KEY_EQUAL = 61,
    KEY_A = 65,
    KEY_B = 66,
    KEY_C = 67,
    KEY_D = 68,
    KEY_E = 69,
    KEY_F = 70,
    KEY_G = 71,
    KEY_H = 72,
    KEY_I = 73,
    KEY_J = 74,
    KEY_K = 75,
    KEY_L = 76,
    KEY_M = 77,
    KEY_N = 78,
    KEY_O = 79,
    KEY_P = 80,
    KEY_Q = 81,
    KEY_R = 82,
    KEY_S = 83,
    KEY_T = 84,
    KEY_U = 85,
    KEY_V = 86,
    KEY_W = 87,
    KEY_X = 88,
    KEY_Y = 89,
    KEY_Z = 90,
    KEY_LEFT_BRACKET = 91,
    KEY_BACKSLASH = 92,
    KEY_RIGHT_BRACKET = 93,
    KEY_GRAVE = 96,
    // Function keys
    KEY_SPACE = 32,
    KEY_ESCAPE = 256,
    KEY_ENTER = 257,
    KEY_TAB = 258,
    KEY_BACKSPACE = 259,
    KEY_INSERT = 260,
    KEY_DELETE = 261,
    KEY_RIGHT = 262,
    KEY_LEFT = 263,
    KEY_DOWN = 264,
    KEY_UP = 265,
    KEY_PAGE_UP = 266,
    KEY_PAGE_DOWN = 267,
    KEY_HOME = 268,
    KEY_END = 269,
    KEY_CAPS_LOCK = 280,
    KEY_SCROLL_LOCK = 281,
    KEY_NUM_LOCK = 282,
    KEY_PRINT_SCREEN = 283,
    KEY_PAUSE = 284,
    KEY_F1 = 290,
    KEY_F2 = 291,
    KEY_F3 = 292,
    KEY_F4 = 293,
    KEY_F5 = 294,
    KEY_F6 = 295,
    KEY_F7 = 296,
    KEY_F8 = 297,
    KEY_F9 = 298,
    KEY_F10 = 299,
    KEY_F11 = 300,
    KEY_F12 = 301,
    KEY_LEFT_SHIFT = 340,
    KEY_LEFT_CONTROL = 341,
    KEY_LEFT_ALT = 342,
    KEY_LEFT_SUPER = 343,
    KEY_RIGHT_SHIFT = 344,
    KEY_RIGHT_CONTROL = 345,
    KEY_RIGHT_ALT = 346,
    KEY_RIGHT_SUPER = 347,
    KEY_KB_MENU = 348,
    // Keypad keys
    KEY_KP_0 = 320,
    KEY_KP_1 = 321,
    KEY_KP_2 = 322,
    KEY_KP_3 = 323,
    KEY_KP_4 = 324,
    KEY_KP_5 = 325,
    KEY_KP_6 = 326,
    KEY_KP_7 = 327,
    KEY_KP_8 = 328,
    KEY_KP_9 = 329,
    KEY_KP_DECIMAL = 330,
    KEY_KP_DIVIDE = 331,
    KEY_KP_MULTIPLY = 332,
    KEY_KP_SUBTRACT = 333,
    KEY_KP_ADD = 334,
    KEY_KP_ENTER = 335,
    KEY_KP_EQUAL = 336,
    // Android key buttons
    KEY_BACK = 4,
    KEY_MENU = 5,
    KEY_VOLUME_UP = 24,
    KEY_VOLUME_DOWN = 25,
};

pub const MouseButton = enum(c_int) {
    MOUSE_BUTTON_LEFT = 0,
    MOUSE_BUTTON_RIGHT = 1,
    MOUSE_BUTTON_MIDDLE = 2,
    MOUSE_BUTTON_SIDE = 3,
    MOUSE_BUTTON_EXTRA = 4,
    MOUSE_BUTTON_FORWARD = 5,
    MOUSE_BUTTON_BACK = 6,
};

pub const MouseCursor = enum(c_int) {
    MOUSE_CURSOR_DEFAULT = 0,
    MOUSE_CURSOR_ARROW = 1,
    MOUSE_CURSOR_IBEAM = 2,
    MOUSE_CURSOR_CROSSHAIR = 3,
    MOUSE_CURSOR_POINTING_HAND = 4,
    MOUSE_CURSOR_RESIZE_EW = 5,
    MOUSE_CURSOR_RESIZE_NS = 6,
    MOUSE_CURSOR_RESIZE_NWSE = 7,
    MOUSE_CURSOR_RESIZE_NESW = 8,
    MOUSE_CURSOR_RESIZE_ALL = 9,
    MOUSE_CURSOR_NOT_ALLOWED = 10,
};

pub const GamepadButton = enum(c_int) {
    GAMEPAD_BUTTON_UNKNOWN = 0,
    GAMEPAD_BUTTON_LEFT_FACE_UP = 1,
    GAMEPAD_BUTTON_LEFT_FACE_RIGHT = 2,
    GAMEPAD_BUTTON_LEFT_FACE_DOWN = 3,
    GAMEPAD_BUTTON_LEFT_FACE_LEFT = 4,
    GAMEPAD_BUTTON_RIGHT_FACE_UP = 5,
    GAMEPAD_BUTTON_RIGHT_FACE_RIGHT = 6,
    GAMEPAD_BUTTON_RIGHT_FACE_DOWN = 7,
    GAMEPAD_BUTTON_RIGHT_FACE_LEFT = 8,
    GAMEPAD_BUTTON_LEFT_TRIGGER_1 = 9,
    GAMEPAD_BUTTON_LEFT_TRIGGER_2 = 10,
    GAMEPAD_BUTTON_RIGHT_TRIGGER_1 = 11,
    GAMEPAD_BUTTON_RIGHT_TRIGGER_2 = 12,
    GAMEPAD_BUTTON_MIDDLE_LEFT = 13,
    GAMEPAD_BUTTON_MIDDLE = 14,
    GAMEPAD_BUTTON_MIDDLE_RIGHT = 15,
    GAMEPAD_BUTTON_LEFT_THUMB = 16,
    GAMEPAD_BUTTON_RIGHT_THUMB = 17,
};

pub const GamepadAxis = enum(c_int) {
    GAMEPAD_AXIS_LEFT_X = 0,
    GAMEPAD_AXIS_LEFT_Y = 1,
    GAMEPAD_AXIS_RIGHT_X = 2,
    GAMEPAD_AXIS_RIGHT_Y = 3,
    GAMEPAD_AXIS_LEFT_TRIGGER = 4,
    GAMEPAD_AXIS_RIGHT_TRIGGER = 5,
};

pub const MaterialMapIndex = enum(c_int) {
    MATERIAL_MAP_ALBEDO = 0,
    MATERIAL_MAP_METALNESS = 1,
    MATERIAL_MAP_NORMAL = 2,
    MATERIAL_MAP_ROUGHNESS = 3,
    MATERIAL_MAP_OCCLUSION = 4,
    MATERIAL_MAP_EMISSION = 5,
    MATERIAL_MAP_HEIGHT = 6,
    MATERIAL_MAP_CUBEMAP = 7,
    MATERIAL_MAP_IRRADIANCE = 8,
    MATERIAL_MAP_PREFILTER = 9,
    MATERIAL_MAP_BRDF = 10,
};

pub const ShaderLocationIndex = enum(c_int) {
    SHADER_LOC_VERTEX_POSITION = 0,
    SHADER_LOC_VERTEX_TEXCOORD01 = 1,
    SHADER_LOC_VERTEX_TEXCOORD02 = 2,
    SHADER_LOC_VERTEX_NORMAL = 3,
    SHADER_LOC_VERTEX_TANGENT = 4,
    SHADER_LOC_VERTEX_COLOR = 5,
    SHADER_LOC_MATRIX_MVP = 6,
    SHADER_LOC_MATRIX_VIEW = 7,
    SHADER_LOC_MATRIX_PROJECTION = 8,
    SHADER_LOC_MATRIX_MODEL = 9,
    SHADER_LOC_MATRIX_NORMAL = 10,
    SHADER_LOC_VECTOR_VIEW = 11,
    SHADER_LOC_COLOR_DIFFUSE = 12,
    SHADER_LOC_COLOR_SPECULAR = 13,
    SHADER_LOC_COLOR_AMBIENT = 14,
    SHADER_LOC_MAP_ALBEDO = 15,
    SHADER_LOC_MAP_METALNESS = 16,
    SHADER_LOC_MAP_NORMAL = 17,
    SHADER_LOC_MAP_ROUGHNESS = 18,
    SHADER_LOC_MAP_OCCLUSION = 19,
    SHADER_LOC_MAP_EMISSION = 20,
    SHADER_LOC_MAP_HEIGHT = 21,
    SHADER_LOC_MAP_CUBEMAP = 22,
    SHADER_LOC_MAP_IRRADIANCE = 23,
    SHADER_LOC_MAP_PREFILTER = 24,
    SHADER_LOC_MAP_BRDF = 25,
    SHADER_LOC_VERTEX_BONEIDS = 26,
    SHADER_LOC_VERTEX_BONEWEIGHTS = 27,
    SHADER_LOC_BONE_MATRICES = 28,
};

pub const ShaderUniformDataType = enum(c_int) {
    SHADER_UNIFORM_FLOAT = 0,
    SHADER_UNIFORM_VEC2 = 1,
    SHADER_UNIFORM_VEC3 = 2,
    SHADER_UNIFORM_VEC4 = 3,
    SHADER_UNIFORM_INT = 4,
    SHADER_UNIFORM_IVEC2 = 5,
    SHADER_UNIFORM_IVEC3 = 6,
    SHADER_UNIFORM_IVEC4 = 7,
    SHADER_UNIFORM_SAMPLER2D = 8,
};

pub const ShaderAttributeDataType = enum(c_int) {
    SHADER_ATTRIB_FLOAT = 0,
    SHADER_ATTRIB_VEC2 = 1,
    SHADER_ATTRIB_VEC3 = 2,
    SHADER_ATTRIB_VEC4 = 3,
};

pub const PixelFormat = enum(c_int) {
    PIXELFORMAT_UNCOMPRESSED_GRAYSCALE = 1,
    PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA = 2,
    PIXELFORMAT_UNCOMPRESSED_R5G6B5 = 3,
    PIXELFORMAT_UNCOMPRESSED_R8G8B8 = 4,
    PIXELFORMAT_UNCOMPRESSED_R5G5B5A1 = 5,
    PIXELFORMAT_UNCOMPRESSED_R4G4B4A4 = 6,
    PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 = 7,
    PIXELFORMAT_UNCOMPRESSED_R32 = 8,
    PIXELFORMAT_UNCOMPRESSED_R32G32B32 = 9,
    PIXELFORMAT_UNCOMPRESSED_R32G32B32A32 = 10,
    PIXELFORMAT_UNCOMPRESSED_R16 = 11,
    PIXELFORMAT_UNCOMPRESSED_R16G16B16 = 12,
    PIXELFORMAT_UNCOMPRESSED_R16G16B16A16 = 13,
    PIXELFORMAT_COMPRESSED_DXT1_RGB = 14,
    PIXELFORMAT_COMPRESSED_DXT1_RGBA = 15,
    PIXELFORMAT_COMPRESSED_DXT3_RGBA = 16,
    PIXELFORMAT_COMPRESSED_DXT5_RGBA = 17,
    PIXELFORMAT_COMPRESSED_ETC1_RGB = 18,
    PIXELFORMAT_COMPRESSED_ETC2_RGB = 19,
    PIXELFORMAT_COMPRESSED_ETC2_EAC_RGBA = 20,
    PIXELFORMAT_COMPRESSED_PVRT_RGB = 21,
    PIXELFORMAT_COMPRESSED_PVRT_RGBA = 22,
    PIXELFORMAT_COMPRESSED_ASTC_4x4_RGBA = 23,
    PIXELFORMAT_COMPRESSED_ASTC_8x8_RGBA = 24,
};

pub const TextureFilter = enum(c_int) {
    TEXTURE_FILTER_POINT = 0,
    TEXTURE_FILTER_BILINEAR = 1,
    TEXTURE_FILTER_TRILINEAR = 2,
    TEXTURE_FILTER_ANISOTROPIC_4X = 3,
    TEXTURE_FILTER_ANISOTROPIC_8X = 4,
    TEXTURE_FILTER_ANISOTROPIC_16X = 5,
};

pub const TextureWrap = enum(c_int) {
    TEXTURE_WRAP_REPEAT = 0,
    TEXTURE_WRAP_CLAMP = 1,
    TEXTURE_WRAP_MIRROR_REPEAT = 2,
    TEXTURE_WRAP_MIRROR_CLAMP = 3,
};

pub const CubemapLayout = enum(c_int) {
    CUBEMAP_LAYOUT_AUTO_DETECT = 0,
    CUBEMAP_LAYOUT_LINE_VERTICAL = 1,
    CUBEMAP_LAYOUT_LINE_HORIZONTAL = 2,
    CUBEMAP_LAYOUT_CROSS_THREE_BY_FOUR = 3,
    CUBEMAP_LAYOUT_CROSS_FOUR_BY_THREE = 4,
};

pub const FontType = enum(c_int) {
    FONT_DEFAULT = 0,
    FONT_BITMAP = 1,
    FONT_SDF = 2,
};

pub const BlendMode = enum(c_int) {
    BLEND_ALPHA = 0,
    BLEND_ADDITIVE = 1,
    BLEND_MULTIPLIED = 2,
    BLEND_ADD_COLORS = 3,
    BLEND_SUBTRACT_COLORS = 4,
    BLEND_ALPHA_PREMULTIPLY = 5,
    BLEND_CUSTOM = 6,
    BLEND_CUSTOM_SEPARATE = 7,
};

pub const Gesture = enum(c_int) {
    GESTURE_NONE = 0,
    GESTURE_TAP = 1,
    GESTURE_DOUBLETAP = 2,
    GESTURE_HOLD = 4,
    GESTURE_DRAG = 8,
    GESTURE_SWIPE_RIGHT = 16,
    GESTURE_SWIPE_LEFT = 32,
    GESTURE_SWIPE_UP = 64,
    GESTURE_SWIPE_DOWN = 128,
    GESTURE_PINCH_IN = 256,
    GESTURE_PINCH_OUT = 512,
};

pub const CameraMode = enum(c_int) {
    CAMERA_CUSTOM = 0,
    CAMERA_FREE = 1,
    CAMERA_ORBITAL = 2,
    CAMERA_FIRST_PERSON = 3,
    CAMERA_THIRD_PERSON = 4,
};

pub const CameraProjection = enum(c_int) {
    CAMERA_PERSPECTIVE = 0,
    CAMERA_ORTHOGRAPHIC = 1,
};

pub const NPatchLayout = enum(c_int) {
    NPATCH_NINE_PATCH = 0,
    NPATCH_THREE_PATCH_VERTICAL = 1,
    NPATCH_THREE_PATCH_HORIZONTAL = 2,
};

//----------------------------------------------------------------------------------
// Predefined Colors
//----------------------------------------------------------------------------------

pub const BLACK = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
pub const WHITE = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
pub const RED = Color{ .r = 230, .g = 41, .b = 55, .a = 255 };
pub const GREEN = Color{ .r = 0, .g = 228, .b = 48, .a = 255 };
pub const BLUE = Color{ .r = 0, .g = 121, .b = 241, .a = 255 };
pub const YELLOW = Color{ .r = 253, .g = 249, .b = 0, .a = 255 };
pub const GRAY = Color{ .r = 130, .g = 130, .b = 130, .a = 255 };
pub const PURPLE = Color{ .r = 200, .g = 122, .b = 255, .a = 255 };
pub const ORANGE = Color{ .r = 255, .g = 161, .b = 0, .a = 255 };
pub const PINK = Color{ .r = 255, .g = 109, .b = 194, .a = 255 };
pub const LIGHTGRAY = Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
pub const DARKGRAY = Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
pub const GOLD = Color{ .r = 255, .g = 203, .b = 0, .a = 255 };
pub const MAROON = Color{ .r = 190, .g = 33, .b = 55, .a = 255 };
pub const LIME = Color{ .r = 0, .g = 158, .b = 47, .a = 255 };
pub const DARKGREEN = Color{ .r = 0, .g = 117, .b = 44, .a = 255 };
pub const SKYBLUE = Color{ .r = 102, .g = 191, .b = 255, .a = 255 };
pub const DARKBLUE = Color{ .r = 0, .g = 82, .b = 172, .a = 255 };
pub const VIOLET = Color{ .r = 135, .g = 60, .b = 190, .a = 255 };
pub const DARKPURPLE = Color{ .r = 112, .g = 31, .b = 126, .a = 255 };
pub const BEIGE = Color{ .r = 211, .g = 176, .b = 131, .a = 255 };
pub const BROWN = Color{ .r = 127, .g = 106, .b = 79, .a = 255 };
pub const DARKBROWN = Color{ .r = 76, .g = 63, .b = 47, .a = 255 };
pub const BLANK = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255, .a = 255 };
pub const RAYWHITE = Color{ .r = 245, .g = 245, .b = 245, .a = 255 };

//----------------------------------------------------------------------------------
// Key Constants (Deprecated style constants for backward compatibility)
//----------------------------------------------------------------------------------

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
pub const KEY_LEFT_BRACKET = 91;
pub const KEY_RIGHT_BRACKET = 93;

// Mouse constants
pub const MOUSE_BUTTON_LEFT = 0;
pub const MOUSE_BUTTON_RIGHT = 1;

//----------------------------------------------------------------------------------
// External Function Declarations
//----------------------------------------------------------------------------------

// Window-related functions
extern fn InitWindow(width: c_int, height: c_int, title: [*:0]const u8) void;
extern fn CloseWindow() void;
extern fn WindowShouldClose() bool;
extern fn IsWindowReady() bool;
extern fn IsWindowFullscreen() bool;
extern fn IsWindowHidden() bool;
extern fn IsWindowMinimized() bool;
extern fn IsWindowMaximized() bool;
extern fn IsWindowFocused() bool;
extern fn IsWindowResized() bool;
extern fn IsWindowState(flag: c_uint) bool;
extern fn SetWindowState(flags: c_uint) void;
extern fn ClearWindowState(flags: c_uint) void;
extern fn ToggleFullscreen() void;
extern fn ToggleBorderlessWindowed() void;
extern fn MaximizeWindow() void;
extern fn MinimizeWindow() void;
extern fn RestoreWindow() void;
extern fn SetWindowIcon(image: Image) void;
extern fn SetWindowIcons(images: [*]Image, count: c_int) void;
extern fn SetWindowTitle(title: [*:0]const u8) void;
extern fn SetWindowPosition(x: c_int, y: c_int) void;
extern fn SetWindowMonitor(monitor: c_int) void;
extern fn SetWindowMinSize(width: c_int, height: c_int) void;
extern fn SetWindowMaxSize(width: c_int, height: c_int) void;
extern fn SetWindowSize(width: c_int, height: c_int) void;
extern fn SetWindowOpacity(opacity: f32) void;
extern fn SetWindowFocused() void;
extern fn GetWindowHandle() ?*anyopaque;
extern fn GetScreenWidth() c_int;
extern fn GetScreenHeight() c_int;
extern fn GetRenderWidth() c_int;
extern fn GetRenderHeight() c_int;
extern fn GetMonitorCount() c_int;
extern fn GetCurrentMonitor() c_int;
extern fn GetMonitorPosition(monitor: c_int) Vector2;
extern fn GetMonitorWidth(monitor: c_int) c_int;
extern fn GetMonitorHeight(monitor: c_int) c_int;
extern fn GetMonitorPhysicalWidth(monitor: c_int) c_int;
extern fn GetMonitorPhysicalHeight(monitor: c_int) c_int;
extern fn GetMonitorRefreshRate(monitor: c_int) c_int;
extern fn GetWindowPosition() Vector2;
extern fn GetWindowScaleDPI() Vector2;
extern fn GetMonitorName(monitor: c_int) [*:0]const u8;
extern fn SetClipboardText(text: [*:0]const u8) void;
extern fn GetClipboardText() [*:0]const u8;
extern fn GetClipboardImage() Image;
extern fn EnableEventWaiting() void;
extern fn DisableEventWaiting() void;

// Cursor-related functions
extern fn ShowCursor() void;
extern fn HideCursor() void;
extern fn IsCursorHidden() bool;
extern fn EnableCursor() void;
extern fn DisableCursor() void;
extern fn IsCursorOnScreen() bool;

// Drawing-related functions
extern fn ClearBackground(color: Color) void;
extern fn BeginDrawing() void;
extern fn EndDrawing() void;
extern fn BeginMode2D(camera: Camera2D) void;
extern fn EndMode2D() void;
extern fn BeginMode3D(camera: Camera3D) void;
extern fn EndMode3D() void;
extern fn BeginTextureMode(target: RenderTexture2D) void;
extern fn EndTextureMode() void;
extern fn BeginShaderMode(shader: Shader) void;
extern fn EndShaderMode() void;
extern fn BeginBlendMode(mode: c_int) void;
extern fn EndBlendMode() void;
extern fn BeginScissorMode(x: c_int, y: c_int, width: c_int, height: c_int) void;
extern fn EndScissorMode() void;
extern fn BeginVrStereoMode(config: VrStereoConfig) void;
extern fn EndVrStereoMode() void;

// VR stereo config functions for VR simulator
extern fn LoadVrStereoConfig(device: VrDeviceInfo) VrStereoConfig;
extern fn UnloadVrStereoConfig(config: VrStereoConfig) void;

// Shader management functions
extern fn LoadShader(vsFileName: [*:0]const u8, fsFileName: [*:0]const u8) Shader;
extern fn LoadShaderFromMemory(vsCode: [*:0]const u8, fsCode: [*:0]const u8) Shader;
extern fn IsShaderValid(shader: Shader) bool;
extern fn GetShaderLocation(shader: Shader, uniformName: [*:0]const u8) c_int;
extern fn GetShaderLocationAttrib(shader: Shader, attribName: [*:0]const u8) c_int;
extern fn SetShaderValue(shader: Shader, locIndex: c_int, value: ?*const anyopaque, uniformType: c_int) void;
extern fn SetShaderValueV(shader: Shader, locIndex: c_int, value: ?*const anyopaque, uniformType: c_int, count: c_int) void;
extern fn SetShaderValueMatrix(shader: Shader, locIndex: c_int, mat: Matrix) void;
extern fn SetShaderValueTexture(shader: Shader, locIndex: c_int, texture: Texture2D) void;
extern fn UnloadShader(shader: Shader) void;

// Screen-space-related functions
extern fn GetScreenToWorldRay(position: Vector2, camera: Camera) Ray;
extern fn GetScreenToWorldRayEx(position: Vector2, camera: Camera, width: c_int, height: c_int) Ray;
extern fn GetWorldToScreen(position: Vector3, camera: Camera) Vector2;
extern fn GetWorldToScreenEx(position: Vector3, camera: Camera, width: c_int, height: c_int) Vector2;
extern fn GetWorldToScreen2D(position: Vector2, camera: Camera2D) Vector2;
extern fn GetScreenToWorld2D(position: Vector2, camera: Camera2D) Vector2;
extern fn GetCameraMatrix(camera: Camera) Matrix;
extern fn GetCameraMatrix2D(camera: Camera2D) Matrix;

// Timing-related functions
extern fn SetTargetFPS(fps: c_int) void;
extern fn GetFrameTime() f32;
extern fn GetTime() f64;
extern fn GetFPS() c_int;

// Custom frame control functions
extern fn SwapScreenBuffer() void;
extern fn PollInputEvents() void;
extern fn WaitTime(seconds: f64) void;

// Random values generation functions
extern fn SetRandomSeed(seed: c_uint) void;
extern fn GetRandomValue(min: c_int, max: c_int) c_int;
extern fn LoadRandomSequence(count: c_uint, min: c_int, max: c_int) [*]c_int;
extern fn UnloadRandomSequence(sequence: [*]c_int) void;

// Misc. functions
extern fn TakeScreenshot(fileName: [*:0]const u8) void;
extern fn SetConfigFlags(flags: c_uint) void;
extern fn OpenURL(url: [*:0]const u8) void;

// Set custom callbacks
extern fn TraceLog(logLevel: c_int, text: [*:0]const u8, ...) void;
extern fn SetTraceLogLevel(logLevel: c_int) void;
extern fn MemAlloc(size: c_uint) ?*anyopaque;
extern fn MemRealloc(ptr: ?*anyopaque, size: c_uint) ?*anyopaque;
extern fn MemFree(ptr: ?*anyopaque) void;

// Files management functions
extern fn LoadFileData(fileName: [*:0]const u8, dataSize: [*c]c_int) [*c]u8;
extern fn UnloadFileData(data: [*c]u8) void;
extern fn SaveFileData(fileName: [*:0]const u8, data: ?*anyopaque, dataSize: c_int) bool;
extern fn ExportDataAsCode(data: [*c]const u8, dataSize: c_int, fileName: [*:0]const u8) bool;
extern fn LoadFileText(fileName: [*:0]const u8) [*:0]u8;
extern fn UnloadFileText(text: [*:0]u8) void;
extern fn SaveFileText(fileName: [*:0]const u8, text: [*:0]u8) bool;

// File system functions
extern fn FileExists(fileName: [*:0]const u8) bool;
extern fn DirectoryExists(dirPath: [*:0]const u8) bool;
extern fn IsFileExtension(fileName: [*:0]const u8, ext: [*:0]const u8) bool;
extern fn GetFileLength(fileName: [*:0]const u8) c_int;
extern fn GetFileExtension(fileName: [*:0]const u8) [*:0]const u8;
extern fn GetFileName(filePath: [*:0]const u8) [*:0]const u8;
extern fn GetFileNameWithoutExt(filePath: [*:0]const u8) [*:0]const u8;
extern fn GetDirectoryPath(filePath: [*:0]const u8) [*:0]const u8;
extern fn GetPrevDirectoryPath(dirPath: [*:0]const u8) [*:0]const u8;
extern fn GetWorkingDirectory() [*:0]const u8;
extern fn GetApplicationDirectory() [*:0]const u8;
extern fn MakeDirectory(dirPath: [*:0]const u8) c_int;
extern fn ChangeDirectory(dir: [*:0]const u8) bool;
extern fn IsPathFile(path: [*:0]const u8) bool;
extern fn IsFileNameValid(fileName: [*:0]const u8) bool;
extern fn LoadDirectoryFiles(dirPath: [*:0]const u8) FilePathList;
extern fn LoadDirectoryFilesEx(basePath: [*:0]const u8, filter: [*:0]const u8, scanSubdirs: bool) FilePathList;
extern fn UnloadDirectoryFiles(files: FilePathList) void;
extern fn IsFileDropped() bool;
extern fn LoadDroppedFiles() FilePathList;
extern fn UnloadDroppedFiles(files: FilePathList) void;
extern fn GetFileModTime(fileName: [*:0]const u8) c_long;

// Compression/Encoding functionality
extern fn CompressData(data: [*c]const u8, dataSize: c_int, compDataSize: [*c]c_int) [*c]u8;
extern fn DecompressData(compData: [*c]const u8, compDataSize: c_int, dataSize: [*c]c_int) [*c]u8;
extern fn EncodeDataBase64(data: [*c]const u8, dataSize: c_int, outputSize: [*c]c_int) [*:0]u8;
extern fn DecodeDataBase64(data: [*c]const u8, outputSize: [*c]c_int) [*c]u8;
extern fn ComputeCRC32(data: [*c]u8, dataSize: c_int) c_uint;
extern fn ComputeMD5(data: [*c]u8, dataSize: c_int) [*c]c_uint;
extern fn ComputeSHA1(data: [*c]u8, dataSize: c_int) [*c]c_uint;

// Automation events functionality
extern fn LoadAutomationEventList(fileName: [*:0]const u8) AutomationEventList;
extern fn UnloadAutomationEventList(list: AutomationEventList) void;
extern fn ExportAutomationEventList(list: AutomationEventList, fileName: [*:0]const u8) bool;
extern fn SetAutomationEventList(list: *AutomationEventList) void;
extern fn SetAutomationEventBaseFrame(frame: c_int) void;
extern fn StartAutomationEventRecording() void;
extern fn StopAutomationEventRecording() void;
extern fn PlayAutomationEvent(event: AutomationEvent) void;

// Input-related functions: keyboard
extern fn IsKeyPressed(key: c_int) bool;
extern fn IsKeyPressedRepeat(key: c_int) bool;
extern fn IsKeyDown(key: c_int) bool;
extern fn IsKeyReleased(key: c_int) bool;
extern fn IsKeyUp(key: c_int) bool;
extern fn GetKeyPressed() c_int;
extern fn GetCharPressed() c_int;
extern fn SetExitKey(key: c_int) void;

// Input-related functions: gamepads
extern fn IsGamepadAvailable(gamepad: c_int) bool;
extern fn GetGamepadName(gamepad: c_int) [*:0]const u8;
extern fn IsGamepadButtonPressed(gamepad: c_int, button: c_int) bool;
extern fn IsGamepadButtonDown(gamepad: c_int, button: c_int) bool;
extern fn IsGamepadButtonReleased(gamepad: c_int, button: c_int) bool;
extern fn IsGamepadButtonUp(gamepad: c_int, button: c_int) bool;
extern fn GetGamepadButtonPressed() c_int;
extern fn GetGamepadAxisCount(gamepad: c_int) c_int;
extern fn GetGamepadAxisMovement(gamepad: c_int, axis: c_int) f32;
extern fn SetGamepadMappings(mappings: [*:0]const u8) c_int;
extern fn SetGamepadVibration(gamepad: c_int, leftMotor: f32, rightMotor: f32, duration: f32) void;

// Input-related functions: mouse
extern fn IsMouseButtonPressed(button: c_int) bool;
extern fn IsMouseButtonDown(button: c_int) bool;
extern fn IsMouseButtonReleased(button: c_int) bool;
extern fn IsMouseButtonUp(button: c_int) bool;
extern fn GetMouseX() c_int;
extern fn GetMouseY() c_int;
extern fn GetMousePosition() Vector2;
extern fn GetMouseDelta() Vector2;
extern fn SetMousePosition(x: c_int, y: c_int) void;
extern fn SetMouseOffset(offsetX: c_int, offsetY: c_int) void;
extern fn SetMouseScale(scaleX: f32, scaleY: f32) void;
extern fn GetMouseWheelMove() f32;
extern fn GetMouseWheelMoveV() Vector2;
extern fn SetMouseCursor(cursor: c_int) void;

// Input-related functions: touch
extern fn GetTouchX() c_int;
extern fn GetTouchY() c_int;
extern fn GetTouchPosition(index: c_int) Vector2;
extern fn GetTouchPointId(index: c_int) c_int;
extern fn GetTouchPointCount() c_int;

// Gestures and Touch Handling Functions
extern fn SetGesturesEnabled(flags: c_uint) void;
extern fn IsGestureDetected(gesture: c_uint) bool;
extern fn GetGestureDetected() c_int;
extern fn GetGestureHoldDuration() f32;
extern fn GetGestureDragVector() Vector2;
extern fn GetGestureDragAngle() f32;
extern fn GetGesturePinchVector() Vector2;
extern fn GetGesturePinchAngle() f32;

// Camera System Functions
extern fn UpdateCamera(camera: *Camera, mode: c_int) void;
extern fn UpdateCameraPro(camera: *Camera, movement: Vector3, rotation: Vector3, zoom: f32) void;

// Basic shapes drawing functions
extern fn SetShapesTexture(texture: Texture2D, source: Rectangle) void;
extern fn GetShapesTexture() Texture2D;
extern fn GetShapesTextureRectangle() Rectangle;
extern fn DrawPixel(posX: c_int, posY: c_int, color: Color) void;
extern fn DrawPixelV(position: Vector2, color: Color) void;
extern fn DrawLine(startPosX: c_int, startPosY: c_int, endPosX: c_int, endPosY: c_int, color: Color) void;
extern fn DrawLineV(startPos: Vector2, endPos: Vector2, color: Color) void;
extern fn DrawLineEx(startPos: Vector2, endPos: Vector2, thick: f32, color: Color) void;
extern fn DrawLineStrip(points: [*]const Vector2, pointCount: c_int, color: Color) void;
extern fn DrawLineBezier(startPos: Vector2, endPos: Vector2, thick: f32, color: Color) void;
extern fn DrawCircle(centerX: c_int, centerY: c_int, radius: f32, color: Color) void;
extern fn DrawCircleSector(center: Vector2, radius: f32, startAngle: f32, endAngle: f32, segments: c_int, color: Color) void;
extern fn DrawCircleSectorLines(center: Vector2, radius: f32, startAngle: f32, endAngle: f32, segments: c_int, color: Color) void;
extern fn DrawCircleGradient(centerX: c_int, centerY: c_int, radius: f32, inner: Color, outer: Color) void;
extern fn DrawCircleV(center: Vector2, radius: f32, color: Color) void;
extern fn DrawCircleLines(centerX: c_int, centerY: c_int, radius: f32, color: Color) void;
extern fn DrawCircleLinesV(center: Vector2, radius: f32, color: Color) void;
extern fn DrawEllipse(centerX: c_int, centerY: c_int, radiusH: f32, radiusV: f32, color: Color) void;
extern fn DrawEllipseLines(centerX: c_int, centerY: c_int, radiusH: f32, radiusV: f32, color: Color) void;
extern fn DrawRing(center: Vector2, innerRadius: f32, outerRadius: f32, startAngle: f32, endAngle: f32, segments: c_int, color: Color) void;
extern fn DrawRingLines(center: Vector2, innerRadius: f32, outerRadius: f32, startAngle: f32, endAngle: f32, segments: c_int, color: Color) void;
extern fn DrawRectangle(posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) void;
extern fn DrawRectangleV(position: Vector2, size: Vector2, color: Color) void;
extern fn DrawRectangleRec(rec: Rectangle, color: Color) void;
extern fn DrawRectanglePro(rec: Rectangle, origin: Vector2, rotation: f32, color: Color) void;
extern fn DrawRectangleGradientV(posX: c_int, posY: c_int, width: c_int, height: c_int, top: Color, bottom: Color) void;
extern fn DrawRectangleGradientH(posX: c_int, posY: c_int, width: c_int, height: c_int, left: Color, right: Color) void;
extern fn DrawRectangleGradientEx(rec: Rectangle, topLeft: Color, bottomLeft: Color, topRight: Color, bottomRight: Color) void;
extern fn DrawRectangleLines(posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) void;
extern fn DrawRectangleLinesEx(rec: Rectangle, lineThick: f32, color: Color) void;
extern fn DrawRectangleRounded(rec: Rectangle, roundness: f32, segments: c_int, color: Color) void;
extern fn DrawRectangleRoundedLines(rec: Rectangle, roundness: f32, segments: c_int, color: Color) void;
extern fn DrawRectangleRoundedLinesEx(rec: Rectangle, roundness: f32, segments: c_int, lineThick: f32, color: Color) void;
extern fn DrawTriangle(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
extern fn DrawTriangleLines(v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
extern fn DrawTriangleFan(points: [*]const Vector2, pointCount: c_int, color: Color) void;
extern fn DrawTriangleStrip(points: [*]const Vector2, pointCount: c_int, color: Color) void;
extern fn DrawPoly(center: Vector2, sides: c_int, radius: f32, rotation: f32, color: Color) void;
extern fn DrawPolyLines(center: Vector2, sides: c_int, radius: f32, rotation: f32, color: Color) void;
extern fn DrawPolyLinesEx(center: Vector2, sides: c_int, radius: f32, rotation: f32, lineThick: f32, color: Color) void;

// Splines drawing functions
extern fn DrawSplineLinear(points: [*]const Vector2, pointCount: c_int, thick: f32, color: Color) void;
extern fn DrawSplineBasis(points: [*]const Vector2, pointCount: c_int, thick: f32, color: Color) void;
extern fn DrawSplineCatmullRom(points: [*]const Vector2, pointCount: c_int, thick: f32, color: Color) void;
extern fn DrawSplineBezierQuadratic(points: [*]const Vector2, pointCount: c_int, thick: f32, color: Color) void;
extern fn DrawSplineBezierCubic(points: [*]const Vector2, pointCount: c_int, thick: f32, color: Color) void;
extern fn DrawSplineSegmentLinear(p1: Vector2, p2: Vector2, thick: f32, color: Color) void;
extern fn DrawSplineSegmentBasis(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, thick: f32, color: Color) void;
extern fn DrawSplineSegmentCatmullRom(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, thick: f32, color: Color) void;
extern fn DrawSplineSegmentBezierQuadratic(p1: Vector2, c2: Vector2, p3: Vector2, thick: f32, color: Color) void;
extern fn DrawSplineSegmentBezierCubic(p1: Vector2, c2: Vector2, c3: Vector2, p4: Vector2, thick: f32, color: Color) void;

// Spline segment point evaluation functions
extern fn GetSplinePointLinear(startPos: Vector2, endPos: Vector2, t: f32) Vector2;
extern fn GetSplinePointBasis(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, t: f32) Vector2;
extern fn GetSplinePointCatmullRom(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2, t: f32) Vector2;
extern fn GetSplinePointBezierQuad(p1: Vector2, c2: Vector2, p3: Vector2, t: f32) Vector2;
extern fn GetSplinePointBezierCubic(p1: Vector2, c2: Vector2, c3: Vector2, p4: Vector2, t: f32) Vector2;

// Basic shapes collision detection functions
extern fn CheckCollisionRecs(rec1: Rectangle, rec2: Rectangle) bool;
extern fn CheckCollisionCircles(center1: Vector2, radius1: f32, center2: Vector2, radius2: f32) bool;
extern fn CheckCollisionCircleRec(center: Vector2, radius: f32, rec: Rectangle) bool;
extern fn CheckCollisionCircleLine(center: Vector2, radius: f32, p1: Vector2, p2: Vector2) bool;
extern fn CheckCollisionPointRec(point: Vector2, rec: Rectangle) bool;
extern fn CheckCollisionPointCircle(point: Vector2, center: Vector2, radius: f32) bool;
extern fn CheckCollisionPointTriangle(point: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) bool;
extern fn CheckCollisionPointLine(point: Vector2, p1: Vector2, p2: Vector2, threshold: c_int) bool;
extern fn CheckCollisionPointPoly(point: Vector2, points: [*]const Vector2, pointCount: c_int) bool;
extern fn CheckCollisionLines(startPos1: Vector2, endPos1: Vector2, startPos2: Vector2, endPos2: Vector2, collisionPoint: *Vector2) bool;
extern fn GetCollisionRec(rec1: Rectangle, rec2: Rectangle) Rectangle;

// Image loading functions
extern fn LoadImage(fileName: [*:0]const u8) Image;
extern fn LoadImageRaw(fileName: [*:0]const u8, width: c_int, height: c_int, format: c_int, headerSize: c_int) Image;
extern fn LoadImageAnim(fileName: [*:0]const u8, frames: [*c]c_int) Image;
extern fn LoadImageAnimFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int, frames: [*c]c_int) Image;
extern fn LoadImageFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int) Image;
extern fn LoadImageFromTexture(texture: Texture2D) Image;
extern fn LoadImageFromScreen() Image;
extern fn IsImageValid(image: Image) bool;
extern fn UnloadImage(image: Image) void;
extern fn ExportImage(image: Image, fileName: [*:0]const u8) bool;
extern fn ExportImageToMemory(image: Image, fileType: [*:0]const u8, fileSize: [*c]c_int) [*c]u8;
extern fn ExportImageAsCode(image: Image, fileName: [*:0]const u8) bool;

// Image generation functions
extern fn GenImageColor(width: c_int, height: c_int, color: Color) Image;
extern fn GenImageGradientLinear(width: c_int, height: c_int, direction: c_int, start: Color, end: Color) Image;
extern fn GenImageGradientRadial(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) Image;
extern fn GenImageGradientSquare(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) Image;
extern fn GenImageChecked(width: c_int, height: c_int, checksX: c_int, checksY: c_int, col1: Color, col2: Color) Image;
extern fn GenImageWhiteNoise(width: c_int, height: c_int, factor: f32) Image;
extern fn GenImagePerlinNoise(width: c_int, height: c_int, offsetX: c_int, offsetY: c_int, scale: f32) Image;
extern fn GenImageCellular(width: c_int, height: c_int, tileSize: c_int) Image;
extern fn GenImageText(width: c_int, height: c_int, text: [*:0]const u8) Image;

// Image manipulation functions
extern fn ImageCopy(image: Image) Image;
extern fn ImageFromImage(image: Image, rec: Rectangle) Image;
extern fn ImageFromChannel(image: Image, selectedChannel: c_int) Image;
extern fn ImageText(text: [*:0]const u8, fontSize: c_int, color: Color) Image;
extern fn ImageTextEx(font: Font, text: [*:0]const u8, fontSize: f32, spacing: f32, tint: Color) Image;
extern fn ImageFormat(image: *Image, newFormat: c_int) void;
extern fn ImageToPOT(image: *Image, fill: Color) void;
extern fn ImageCrop(image: *Image, crop: Rectangle) void;
extern fn ImageAlphaCrop(image: *Image, threshold: f32) void;
extern fn ImageAlphaClear(image: *Image, color: Color, threshold: f32) void;
extern fn ImageAlphaMask(image: *Image, alphaMask: Image) void;
extern fn ImageAlphaPremultiply(image: *Image) void;
extern fn ImageBlurGaussian(image: *Image, blurSize: c_int) void;
extern fn ImageKernelConvolution(image: *Image, kernel: [*c]const f32, kernelSize: c_int) void;
extern fn ImageResize(image: *Image, newWidth: c_int, newHeight: c_int) void;
extern fn ImageResizeNN(image: *Image, newWidth: c_int, newHeight: c_int) void;
extern fn ImageResizeCanvas(image: *Image, newWidth: c_int, newHeight: c_int, offsetX: c_int, offsetY: c_int, fill: Color) void;
extern fn ImageMipmaps(image: *Image) void;
extern fn ImageDither(image: *Image, rBpp: c_int, gBpp: c_int, bBpp: c_int, aBpp: c_int) void;
extern fn ImageFlipVertical(image: *Image) void;
extern fn ImageFlipHorizontal(image: *Image) void;
extern fn ImageRotate(image: *Image, degrees: c_int) void;
extern fn ImageRotateCW(image: *Image) void;
extern fn ImageRotateCCW(image: *Image) void;
extern fn ImageColorTint(image: *Image, color: Color) void;
extern fn ImageColorInvert(image: *Image) void;
extern fn ImageColorGrayscale(image: *Image) void;
extern fn ImageColorContrast(image: *Image, contrast: f32) void;
extern fn ImageColorBrightness(image: *Image, brightness: c_int) void;
extern fn ImageColorReplace(image: *Image, color: Color, replace: Color) void;
extern fn LoadImageColors(image: Image) [*]Color;
extern fn LoadImagePalette(image: Image, maxPaletteSize: c_int, colorCount: [*c]c_int) [*]Color;
extern fn UnloadImageColors(colors: [*]Color) void;
extern fn UnloadImagePalette(colors: [*]Color) void;
extern fn GetImageAlphaBorder(image: Image, threshold: f32) Rectangle;
extern fn GetImageColor(image: Image, x: c_int, y: c_int) Color;

// Image drawing functions
extern fn ImageClearBackground(dst: *Image, color: Color) void;
extern fn ImageDrawPixel(dst: *Image, posX: c_int, posY: c_int, color: Color) void;
extern fn ImageDrawPixelV(dst: *Image, position: Vector2, color: Color) void;
extern fn ImageDrawLine(dst: *Image, startPosX: c_int, startPosY: c_int, endPosX: c_int, endPosY: c_int, color: Color) void;
extern fn ImageDrawLineV(dst: *Image, start: Vector2, end: Vector2, color: Color) void;
extern fn ImageDrawLineEx(dst: *Image, start: Vector2, end: Vector2, thick: c_int, color: Color) void;
extern fn ImageDrawCircle(dst: *Image, centerX: c_int, centerY: c_int, radius: c_int, color: Color) void;
extern fn ImageDrawCircleV(dst: *Image, center: Vector2, radius: c_int, color: Color) void;
extern fn ImageDrawCircleLines(dst: *Image, centerX: c_int, centerY: c_int, radius: c_int, color: Color) void;
extern fn ImageDrawCircleLinesV(dst: *Image, center: Vector2, radius: c_int, color: Color) void;
extern fn ImageDrawRectangle(dst: *Image, posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) void;
extern fn ImageDrawRectangleV(dst: *Image, position: Vector2, size: Vector2, color: Color) void;
extern fn ImageDrawRectangleRec(dst: *Image, rec: Rectangle, color: Color) void;
extern fn ImageDrawRectangleLines(dst: *Image, rec: Rectangle, thick: c_int, color: Color) void;
extern fn ImageDrawTriangle(dst: *Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
extern fn ImageDrawTriangleEx(dst: *Image, v1: Vector2, v2: Vector2, v3: Vector2, c1: Color, c2: Color, c3: Color) void;
extern fn ImageDrawTriangleLines(dst: *Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
extern fn ImageDrawTriangleFan(dst: *Image, points: [*]Vector2, pointCount: c_int, color: Color) void;
extern fn ImageDrawTriangleStrip(dst: *Image, points: [*]Vector2, pointCount: c_int, color: Color) void;
extern fn ImageDraw(dst: *Image, src: Image, srcRec: Rectangle, dstRec: Rectangle, tint: Color) void;
extern fn ImageDrawText(dst: *Image, text: [*:0]const u8, posX: c_int, posY: c_int, fontSize: c_int, color: Color) void;
extern fn ImageDrawTextEx(dst: *Image, font: Font, text: [*:0]const u8, position: Vector2, fontSize: f32, spacing: f32, tint: Color) void;

// Texture loading functions
extern fn LoadTexture(fileName: [*:0]const u8) Texture2D;
extern fn LoadTextureFromImage(image: Image) Texture2D;
extern fn LoadTextureCubemap(image: Image, layout: c_int) TextureCubemap;
extern fn LoadRenderTexture(width: c_int, height: c_int) RenderTexture2D;
extern fn IsTextureValid(texture: Texture2D) bool;
extern fn UnloadTexture(texture: Texture2D) void;
extern fn IsRenderTextureValid(target: RenderTexture2D) bool;
extern fn UnloadRenderTexture(target: RenderTexture2D) void;
extern fn UpdateTexture(texture: Texture2D, pixels: ?*const anyopaque) void;
extern fn UpdateTextureRec(texture: Texture2D, rec: Rectangle, pixels: ?*const anyopaque) void;

// Texture configuration functions
extern fn GenTextureMipmaps(texture: *Texture2D) void;
extern fn SetTextureFilter(texture: Texture2D, filter: c_int) void;
extern fn SetTextureWrap(texture: Texture2D, wrap: c_int) void;

// Texture drawing functions
extern fn DrawTexture(texture: Texture2D, posX: c_int, posY: c_int, tint: Color) void;
extern fn DrawTextureV(texture: Texture2D, position: Vector2, tint: Color) void;
extern fn DrawTextureEx(texture: Texture2D, position: Vector2, rotation: f32, scale: f32, tint: Color) void;
extern fn DrawTextureRec(texture: Texture2D, source: Rectangle, position: Vector2, tint: Color) void;
extern fn DrawTexturePro(texture: Texture2D, source: Rectangle, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void;
extern fn DrawTextureNPatch(texture: Texture2D, nPatchInfo: NPatchInfo, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void;

// Color/pixel related functions
extern fn ColorIsEqual(col1: Color, col2: Color) bool;
extern fn Fade(color: Color, alpha: f32) Color;
extern fn ColorToInt(color: Color) c_int;
extern fn ColorNormalize(color: Color) Vector4;
extern fn ColorFromNormalized(normalized: Vector4) Color;
extern fn ColorToHSV(color: Color) Vector3;
extern fn ColorFromHSV(hue: f32, saturation: f32, value: f32) Color;
extern fn ColorTint(color: Color, tint: Color) Color;
extern fn ColorBrightness(color: Color, factor: f32) Color;
extern fn ColorContrast(color: Color, contrast: f32) Color;
extern fn ColorAlpha(color: Color, alpha: f32) Color;
extern fn ColorAlphaBlend(dst: Color, src: Color, tint: Color) Color;
extern fn ColorLerp(color1: Color, color2: Color, factor: f32) Color;
extern fn GetColor(hexValue: c_uint) Color;
extern fn GetPixelColor(srcPtr: ?*anyopaque, format: c_int) Color;
extern fn SetPixelColor(dstPtr: ?*anyopaque, color: Color, format: c_int) void;
extern fn GetPixelDataSize(width: c_int, height: c_int, format: c_int) c_int;

// Font loading/unloading functions
extern fn GetFontDefault() Font;
extern fn LoadFont(fileName: [*:0]const u8) Font;
extern fn LoadFontEx(fileName: [*:0]const u8, fontSize: c_int, codepoints: [*c]c_int, codepointCount: c_int) Font;
extern fn LoadFontFromImage(image: Image, key: Color, firstChar: c_int) Font;
extern fn LoadFontFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]c_int, codepointCount: c_int) Font;
extern fn IsFontValid(font: Font) bool;
extern fn LoadFontData(fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]c_int, codepointCount: c_int, type: c_int) [*]GlyphInfo;
extern fn GenImageFontAtlas(glyphs: [*c]const GlyphInfo, glyphRecs: [*c][*c]Rectangle, glyphCount: c_int, fontSize: c_int, padding: c_int, packMethod: c_int) Image;
extern fn UnloadFontData(glyphs: [*]GlyphInfo, glyphCount: c_int) void;
extern fn UnloadFont(font: Font) void;
extern fn ExportFontAsCode(font: Font, fileName: [*:0]const u8) bool;

// Text drawing functions
extern fn DrawFPS(posX: c_int, posY: c_int) void;
extern fn DrawText(text: [*:0]const u8, posX: c_int, posY: c_int, fontSize: c_int, color: Color) void;
extern fn DrawTextEx(font: Font, text: [*:0]const u8, position: Vector2, fontSize: f32, spacing: f32, tint: Color) void;
extern fn DrawTextPro(font: Font, text: [*:0]const u8, position: Vector2, origin: Vector2, rotation: f32, fontSize: f32, spacing: f32, tint: Color) void;
extern fn DrawTextCodepoint(font: Font, codepoint: c_int, position: Vector2, fontSize: f32, tint: Color) void;
extern fn DrawTextCodepoints(font: Font, codepoints: [*c]const c_int, codepointCount: c_int, position: Vector2, fontSize: f32, spacing: f32, tint: Color) void;

// Text font info functions
extern fn SetTextLineSpacing(spacing: c_int) void;
extern fn MeasureText(text: [*:0]const u8, fontSize: c_int) c_int;
extern fn MeasureTextEx(font: Font, text: [*:0]const u8, fontSize: f32, spacing: f32) Vector2;
extern fn GetGlyphIndex(font: Font, codepoint: c_int) c_int;
extern fn GetGlyphInfo(font: Font, codepoint: c_int) GlyphInfo;
extern fn GetGlyphAtlasRec(font: Font, codepoint: c_int) Rectangle;

// Text codepoints management functions
extern fn LoadUTF8(codepoints: [*c]const c_int, length: c_int) [*:0]u8;
extern fn UnloadUTF8(text: [*:0]u8) void;
extern fn LoadCodepoints(text: [*:0]const u8, count: [*c]c_int) [*c]c_int;
extern fn UnloadCodepoints(codepoints: [*c]c_int) void;
extern fn GetCodepointCount(text: [*:0]const u8) c_int;
extern fn GetCodepoint(text: [*:0]const u8, codepointSize: [*c]c_int) c_int;
extern fn GetCodepointNext(text: [*:0]const u8, codepointSize: [*c]c_int) c_int;
extern fn GetCodepointPrevious(text: [*:0]const u8, codepointSize: [*c]c_int) c_int;
extern fn CodepointToUTF8(codepoint: c_int, utf8Size: [*c]c_int) [*:0]const u8;

// Text strings management functions
extern fn TextCopy(dst: [*:0]u8, src: [*:0]const u8) c_int;
extern fn TextIsEqual(text1: [*:0]const u8, text2: [*:0]const u8) bool;
extern fn TextLength(text: [*:0]const u8) c_uint;
extern fn TextFormat(text: [*:0]const u8, ...) [*:0]const u8;
extern fn TextSubtext(text: [*:0]const u8, position: c_int, length: c_int) [*:0]const u8;
extern fn TextReplace(text: [*:0]const u8, replace: [*:0]const u8, by: [*:0]const u8) [*:0]u8;
extern fn TextInsert(text: [*:0]const u8, insert: [*:0]const u8, position: c_int) [*:0]u8;
extern fn TextJoin(textList: [*c][*:0]const u8, count: c_int, delimiter: [*:0]const u8) [*:0]const u8;
extern fn TextSplit(text: [*:0]const u8, delimiter: u8, count: [*c]c_int) [*c][*:0]const u8;
extern fn TextAppend(text: [*:0]u8, append: [*:0]const u8, position: [*c]c_int) void;
extern fn TextFindIndex(text: [*:0]const u8, find: [*:0]const u8) c_int;
extern fn TextToUpper(text: [*:0]const u8) [*:0]const u8;
extern fn TextToLower(text: [*:0]const u8) [*:0]const u8;
extern fn TextToPascal(text: [*:0]const u8) [*:0]const u8;
extern fn TextToSnake(text: [*:0]const u8) [*:0]const u8;
extern fn TextToCamel(text: [*:0]const u8) [*:0]const u8;
extern fn TextToInteger(text: [*:0]const u8) c_int;
extern fn TextToFloat(text: [*:0]const u8) f32;

// Basic geometric 3D shapes drawing functions
extern fn DrawLine3D(startPos: Vector3, endPos: Vector3, color: Color) void;
extern fn DrawPoint3D(position: Vector3, color: Color) void;
extern fn DrawCircle3D(center: Vector3, radius: f32, rotationAxis: Vector3, rotationAngle: f32, color: Color) void;
extern fn DrawTriangle3D(v1: Vector3, v2: Vector3, v3: Vector3, color: Color) void;
extern fn DrawTriangleStrip3D(points: [*]const Vector3, pointCount: c_int, color: Color) void;
extern fn DrawCube(position: Vector3, width: f32, height: f32, length: f32, color: Color) void;
extern fn DrawCubeV(position: Vector3, size: Vector3, color: Color) void;
extern fn DrawCubeWires(position: Vector3, width: f32, height: f32, length: f32, color: Color) void;
extern fn DrawCubeWiresV(position: Vector3, size: Vector3, color: Color) void;
extern fn DrawSphere(centerPos: Vector3, radius: f32, color: Color) void;
extern fn DrawSphereEx(centerPos: Vector3, radius: f32, rings: c_int, slices: c_int, color: Color) void;
extern fn DrawSphereWires(centerPos: Vector3, radius: f32, rings: c_int, slices: c_int, color: Color) void;
extern fn DrawCylinder(position: Vector3, radiusTop: f32, radiusBottom: f32, height: f32, slices: c_int, color: Color) void;
extern fn DrawCylinderEx(startPos: Vector3, endPos: Vector3, startRadius: f32, endRadius: f32, sides: c_int, color: Color) void;
extern fn DrawCylinderWires(position: Vector3, radiusTop: f32, radiusBottom: f32, height: f32, slices: c_int, color: Color) void;
extern fn DrawCylinderWiresEx(startPos: Vector3, endPos: Vector3, startRadius: f32, endRadius: f32, sides: c_int, color: Color) void;
extern fn DrawCapsule(startPos: Vector3, endPos: Vector3, radius: f32, slices: c_int, rings: c_int, color: Color) void;
extern fn DrawCapsuleWires(startPos: Vector3, endPos: Vector3, radius: f32, slices: c_int, rings: c_int, color: Color) void;
extern fn DrawPlane(centerPos: Vector3, size: Vector2, color: Color) void;
extern fn DrawRay(ray: Ray, color: Color) void;
extern fn DrawGrid(slices: c_int, spacing: f32) void;

// Model management functions
extern fn LoadModel(fileName: [*:0]const u8) Model;
extern fn LoadModelFromMesh(mesh: Mesh) Model;
extern fn IsModelValid(model: Model) bool;
extern fn UnloadModel(model: Model) void;
extern fn GetModelBoundingBox(model: Model) BoundingBox;

// Model drawing functions
extern fn DrawModel(model: Model, position: Vector3, scale: f32, tint: Color) void;
extern fn DrawModelEx(model: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: f32, scale: Vector3, tint: Color) void;
extern fn DrawModelWires(model: Model, position: Vector3, scale: f32, tint: Color) void;
extern fn DrawModelWiresEx(model: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: f32, scale: Vector3, tint: Color) void;
extern fn DrawModelPoints(model: Model, position: Vector3, scale: f32, tint: Color) void;
extern fn DrawModelPointsEx(model: Model, position: Vector3, rotationAxis: Vector3, rotationAngle: f32, scale: Vector3, tint: Color) void;
extern fn DrawBoundingBox(box: BoundingBox, color: Color) void;
extern fn DrawBillboard(camera: Camera, texture: Texture2D, position: Vector3, scale: f32, tint: Color) void;
extern fn DrawBillboardRec(camera: Camera, texture: Texture2D, source: Rectangle, position: Vector3, size: Vector2, tint: Color) void;
extern fn DrawBillboardPro(camera: Camera, texture: Texture2D, source: Rectangle, position: Vector3, up: Vector3, size: Vector2, origin: Vector2, rotation: f32, tint: Color) void;

// Mesh management functions
extern fn UploadMesh(mesh: *Mesh, dynamic: bool) void;
extern fn UpdateMeshBuffer(mesh: Mesh, index: c_int, data: ?*const anyopaque, dataSize: c_int, offset: c_int) void;
extern fn UnloadMesh(mesh: Mesh) void;
extern fn DrawMesh(mesh: Mesh, material: Material, transform: Matrix) void;
extern fn DrawMeshInstanced(mesh: Mesh, material: Material, transforms: [*c]const Matrix, instances: c_int) void;
extern fn GetMeshBoundingBox(mesh: Mesh) BoundingBox;
extern fn GenMeshTangents(mesh: *Mesh) void;
extern fn ExportMesh(mesh: Mesh, fileName: [*:0]const u8) bool;
extern fn ExportMeshAsCode(mesh: Mesh, fileName: [*:0]const u8) bool;

// Mesh generation functions
extern fn GenMeshPoly(sides: c_int, radius: f32) Mesh;
extern fn GenMeshPlane(width: f32, length: f32, resX: c_int, resZ: c_int) Mesh;
extern fn GenMeshCube(width: f32, height: f32, length: f32) Mesh;
extern fn GenMeshSphere(radius: f32, rings: c_int, slices: c_int) Mesh;
extern fn GenMeshHemiSphere(radius: f32, rings: c_int, slices: c_int) Mesh;
extern fn GenMeshCylinder(radius: f32, height: f32, slices: c_int) Mesh;
extern fn GenMeshCone(radius: f32, height: f32, slices: c_int) Mesh;
extern fn GenMeshTorus(radius: f32, size: f32, radSeg: c_int, sides: c_int) Mesh;
extern fn GenMeshKnot(radius: f32, size: f32, radSeg: c_int, sides: c_int) Mesh;
extern fn GenMeshHeightmap(heightmap: Image, size: Vector3) Mesh;
extern fn GenMeshCubicmap(cubicmap: Image, cubeSize: Vector3) Mesh;

// Material loading/unloading functions
extern fn LoadMaterials(fileName: [*:0]const u8, materialCount: [*c]c_int) [*]Material;
extern fn LoadMaterialDefault() Material;
extern fn IsMaterialValid(material: Material) bool;
extern fn UnloadMaterial(material: Material) void;
extern fn SetMaterialTexture(material: *Material, mapType: c_int, texture: Texture2D) void;
extern fn SetModelMeshMaterial(model: *Model, meshId: c_int, materialId: c_int) void;

// Model animations loading/unloading functions
extern fn LoadModelAnimations(fileName: [*:0]const u8, animCount: [*c]c_int) [*]ModelAnimation;
extern fn UpdateModelAnimation(model: Model, anim: ModelAnimation, frame: c_int) void;
extern fn UpdateModelAnimationBones(model: Model, anim: ModelAnimation, frame: c_int) void;
extern fn UnloadModelAnimation(anim: ModelAnimation) void;
extern fn UnloadModelAnimations(animations: [*]ModelAnimation, animCount: c_int) void;
extern fn IsModelAnimationValid(model: Model, anim: ModelAnimation) bool;

// Collision detection functions
extern fn CheckCollisionSpheres(center1: Vector3, radius1: f32, center2: Vector3, radius2: f32) bool;
extern fn CheckCollisionBoxes(box1: BoundingBox, box2: BoundingBox) bool;
extern fn CheckCollisionBoxSphere(box: BoundingBox, center: Vector3, radius: f32) bool;
extern fn GetRayCollisionSphere(ray: Ray, center: Vector3, radius: f32) RayCollision;
extern fn GetRayCollisionBox(ray: Ray, box: BoundingBox) RayCollision;
extern fn GetRayCollisionMesh(ray: Ray, mesh: Mesh, transform: Matrix) RayCollision;
extern fn GetRayCollisionTriangle(ray: Ray, p1: Vector3, p2: Vector3, p3: Vector3) RayCollision;
extern fn GetRayCollisionQuad(ray: Ray, p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3) RayCollision;

// Audio device management functions
extern fn InitAudioDevice() void;
extern fn CloseAudioDevice() void;
extern fn IsAudioDeviceReady() bool;
extern fn SetMasterVolume(volume: f32) void;
extern fn GetMasterVolume() f32;

// Wave/Sound loading/unloading functions
extern fn LoadWave(fileName: [*:0]const u8) Wave;
extern fn LoadWaveFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int) Wave;
extern fn IsWaveValid(wave: Wave) bool;
extern fn LoadSound(fileName: [*:0]const u8) Sound;
extern fn LoadSoundFromWave(wave: Wave) Sound;
extern fn LoadSoundAlias(source: Sound) Sound;
extern fn IsSoundValid(sound: Sound) bool;
extern fn UpdateSound(sound: Sound, data: ?*const anyopaque, sampleCount: c_int) void;
extern fn UnloadWave(wave: Wave) void;
extern fn UnloadSound(sound: Sound) void;
extern fn UnloadSoundAlias(alias: Sound) void;
extern fn ExportWave(wave: Wave, fileName: [*:0]const u8) bool;
extern fn ExportWaveAsCode(wave: Wave, fileName: [*:0]const u8) bool;

// Wave/Sound management functions
extern fn PlaySound(sound: Sound) void;
extern fn StopSound(sound: Sound) void;
extern fn PauseSound(sound: Sound) void;
extern fn ResumeSound(sound: Sound) void;
extern fn IsSoundPlaying(sound: Sound) bool;
extern fn SetSoundVolume(sound: Sound, volume: f32) void;
extern fn SetSoundPitch(sound: Sound, pitch: f32) void;
extern fn SetSoundPan(sound: Sound, pan: f32) void;
extern fn WaveCopy(wave: Wave) Wave;
extern fn WaveCrop(wave: *Wave, initFrame: c_int, finalFrame: c_int) void;
extern fn WaveFormat(wave: *Wave, sampleRate: c_int, sampleSize: c_int, channels: c_int) void;
extern fn LoadWaveSamples(wave: Wave) [*]f32;
extern fn UnloadWaveSamples(samples: [*]f32) void;

// Music management functions
extern fn LoadMusicStream(fileName: [*:0]const u8) Music;
extern fn LoadMusicStreamFromMemory(fileType: [*:0]const u8, data: [*c]const u8, dataSize: c_int) Music;
extern fn IsMusicValid(music: Music) bool;
extern fn UnloadMusicStream(music: Music) void;
extern fn PlayMusicStream(music: Music) void;
extern fn IsMusicStreamPlaying(music: Music) bool;
extern fn UpdateMusicStream(music: Music) void;
extern fn StopMusicStream(music: Music) void;
extern fn PauseMusicStream(music: Music) void;
extern fn ResumeMusicStream(music: Music) void;
extern fn SeekMusicStream(music: Music, position: f32) void;
extern fn SetMusicVolume(music: Music, volume: f32) void;
extern fn SetMusicPitch(music: Music, pitch: f32) void;
extern fn SetMusicPan(music: Music, pan: f32) void;
extern fn GetMusicTimeLength(music: Music) f32;
extern fn GetMusicTimePlayed(music: Music) f32;

// AudioStream management functions
extern fn LoadAudioStream(sampleRate: c_uint, sampleSize: c_uint, channels: c_uint) AudioStream;
extern fn IsAudioStreamValid(stream: AudioStream) bool;
extern fn UnloadAudioStream(stream: AudioStream) void;
extern fn UpdateAudioStream(stream: AudioStream, data: ?*const anyopaque, frameCount: c_int) void;
extern fn IsAudioStreamProcessed(stream: AudioStream) bool;
extern fn PlayAudioStream(stream: AudioStream) void;
extern fn PauseAudioStream(stream: AudioStream) void;
extern fn ResumeAudioStream(stream: AudioStream) void;
extern fn IsAudioStreamPlaying(stream: AudioStream) bool;
extern fn StopAudioStream(stream: AudioStream) void;
extern fn SetAudioStreamVolume(stream: AudioStream, volume: f32) void;
extern fn SetAudioStreamPitch(stream: AudioStream, pitch: f32) void;
extern fn SetAudioStreamPan(stream: AudioStream, pan: f32) void;
extern fn SetAudioStreamBufferSizeDefault(size: c_int) void;

//----------------------------------------------------------------------------------
// Wrapper Functions for easier Zig usage
//----------------------------------------------------------------------------------

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

pub fn beginMode2D(camera: Camera2D) void {
    BeginMode2D(camera);
}

pub fn endMode2D() void {
    EndMode2D();
}

pub fn clearBackground(color: Color) void {
    ClearBackground(color);
}

pub fn drawCircleV(center: Vector2, radius: f32, color: Color) void {
    DrawCircleV(center, radius, color);
}

pub fn drawCircleLinesV(center: Vector2, radius: f32, color: Color) void {
    DrawCircleLinesV(center, radius, color);
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

pub fn checkCollisionCircles(center1: Vector2, radius1: f32, center2: Vector2, radius2: f32) bool {
    return CheckCollisionCircles(center1, radius1, center2, radius2);
}

pub fn checkCollisionCircleRec(center: Vector2, radius: f32, rec: Rectangle) bool {
    return CheckCollisionCircleRec(center, radius, rec);
}

pub fn checkCollisionRecs(rec1: Rectangle, rec2: Rectangle) bool {
    return CheckCollisionRecs(rec1, rec2);
}

pub fn checkCollisionPointCircle(point: Vector2, center: Vector2, radius: f32) bool {
    return CheckCollisionPointCircle(point, center, radius);
}

pub fn checkCollisionPointRec(point: Vector2, rec: Rectangle) bool {
    return CheckCollisionPointRec(point, rec);
}
