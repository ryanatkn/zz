// Raylib Textures Module (rtextures)
// Image and texture operations, color/pixel utilities
const types = @import("raylib_types.zig");

// Import types for internal use
const Image = types.Image;
const Texture = types.Texture;
const Texture2D = types.Texture2D;
const TextureCubemap = types.TextureCubemap;
const RenderTexture2D = types.RenderTexture2D;
const Vector2 = types.Vector2;
const Vector3 = types.Vector3;
const Vector4 = types.Vector4;
const Color = types.Color;
const Rectangle = types.Rectangle;
const Font = types.Font;
const NPatchInfo = types.NPatchInfo;

//----------------------------------------------------------------------------------
// Image and Texture Operations (extern functions)
//----------------------------------------------------------------------------------

// Image loading functions
pub extern fn LoadImage(fileName: [*:0]const u8) Image;
pub extern fn LoadImageRaw(fileName: [*:0]const u8, width: c_int, height: c_int, format: c_int, headerSize: c_int) Image;
pub extern fn LoadImageAnim(fileName: [*:0]const u8, frames: [*c]c_int) Image;
pub extern fn LoadImageAnimFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int, frames: [*c]c_int) Image;
pub extern fn LoadImageFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int) Image;
pub extern fn LoadImageFromTexture(texture: Texture2D) Image;
pub extern fn LoadImageFromScreen() Image;
pub extern fn IsImageValid(image: Image) bool;
pub extern fn UnloadImage(image: Image) void;
pub extern fn ExportImage(image: Image, fileName: [*:0]const u8) bool;
pub extern fn ExportImageToMemory(image: Image, fileType: [*:0]const u8, fileSize: [*c]c_int) [*c]u8;
pub extern fn ExportImageAsCode(image: Image, fileName: [*:0]const u8) bool;

// Image generation functions
pub extern fn GenImageColor(width: c_int, height: c_int, color: Color) Image;
pub extern fn GenImageGradientLinear(width: c_int, height: c_int, direction: c_int, start: Color, end: Color) Image;
pub extern fn GenImageGradientRadial(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) Image;
pub extern fn GenImageGradientSquare(width: c_int, height: c_int, density: f32, inner: Color, outer: Color) Image;
pub extern fn GenImageChecked(width: c_int, height: c_int, checksX: c_int, checksY: c_int, col1: Color, col2: Color) Image;
pub extern fn GenImageWhiteNoise(width: c_int, height: c_int, factor: f32) Image;
pub extern fn GenImagePerlinNoise(width: c_int, height: c_int, offsetX: c_int, offsetY: c_int, scale: f32) Image;
pub extern fn GenImageCellular(width: c_int, height: c_int, tileSize: c_int) Image;
pub extern fn GenImageText(width: c_int, height: c_int, text: [*:0]const u8) Image;

// Image manipulation functions
pub extern fn ImageCopy(image: Image) Image;
pub extern fn ImageFromImage(image: Image, rec: Rectangle) Image;
pub extern fn ImageFromChannel(image: Image, selectedChannel: c_int) Image;
pub extern fn ImageText(text: [*:0]const u8, fontSize: c_int, color: Color) Image;
pub extern fn ImageTextEx(font: Font, text: [*:0]const u8, fontSize: f32, spacing: f32, tint: Color) Image;
pub extern fn ImageFormat(image: *Image, newFormat: c_int) void;
pub extern fn ImageToPOT(image: *Image, fill: Color) void;
pub extern fn ImageCrop(image: *Image, crop: Rectangle) void;
pub extern fn ImageAlphaCrop(image: *Image, threshold: f32) void;
pub extern fn ImageAlphaClear(image: *Image, color: Color, threshold: f32) void;
pub extern fn ImageAlphaMask(image: *Image, alphaMask: Image) void;
pub extern fn ImageAlphaPremultiply(image: *Image) void;
pub extern fn ImageBlurGaussian(image: *Image, blurSize: c_int) void;
pub extern fn ImageKernelConvolution(image: *Image, kernel: [*c]const f32, kernelSize: c_int) void;
pub extern fn ImageResize(image: *Image, newWidth: c_int, newHeight: c_int) void;
pub extern fn ImageResizeNN(image: *Image, newWidth: c_int, newHeight: c_int) void;
pub extern fn ImageResizeCanvas(image: *Image, newWidth: c_int, newHeight: c_int, offsetX: c_int, offsetY: c_int, fill: Color) void;
pub extern fn ImageMipmaps(image: *Image) void;
pub extern fn ImageDither(image: *Image, rBpp: c_int, gBpp: c_int, bBpp: c_int, aBpp: c_int) void;
pub extern fn ImageFlipVertical(image: *Image) void;
pub extern fn ImageFlipHorizontal(image: *Image) void;
pub extern fn ImageRotate(image: *Image, degrees: c_int) void;
pub extern fn ImageRotateCW(image: *Image) void;
pub extern fn ImageRotateCCW(image: *Image) void;
pub extern fn ImageColorTint(image: *Image, color: Color) void;
pub extern fn ImageColorInvert(image: *Image) void;
pub extern fn ImageColorGrayscale(image: *Image) void;
pub extern fn ImageColorContrast(image: *Image, contrast: f32) void;
pub extern fn ImageColorBrightness(image: *Image, brightness: c_int) void;
pub extern fn ImageColorReplace(image: *Image, color: Color, replace: Color) void;
pub extern fn LoadImageColors(image: Image) [*]Color;
pub extern fn LoadImagePalette(image: Image, maxPaletteSize: c_int, colorCount: [*c]c_int) [*]Color;
pub extern fn UnloadImageColors(colors: [*]Color) void;
pub extern fn UnloadImagePalette(colors: [*]Color) void;
pub extern fn GetImageAlphaBorder(image: Image, threshold: f32) Rectangle;
pub extern fn GetImageColor(image: Image, x: c_int, y: c_int) Color;

// Image drawing functions
pub extern fn ImageClearBackground(dst: *Image, color: Color) void;
pub extern fn ImageDrawPixel(dst: *Image, posX: c_int, posY: c_int, color: Color) void;
pub extern fn ImageDrawPixelV(dst: *Image, position: Vector2, color: Color) void;
pub extern fn ImageDrawLine(dst: *Image, startPosX: c_int, startPosY: c_int, endPosX: c_int, endPosY: c_int, color: Color) void;
pub extern fn ImageDrawLineV(dst: *Image, start: Vector2, end: Vector2, color: Color) void;
pub extern fn ImageDrawLineEx(dst: *Image, start: Vector2, end: Vector2, thick: c_int, color: Color) void;
pub extern fn ImageDrawCircle(dst: *Image, centerX: c_int, centerY: c_int, radius: c_int, color: Color) void;
pub extern fn ImageDrawCircleV(dst: *Image, center: Vector2, radius: c_int, color: Color) void;
pub extern fn ImageDrawCircleLines(dst: *Image, centerX: c_int, centerY: c_int, radius: c_int, color: Color) void;
pub extern fn ImageDrawCircleLinesV(dst: *Image, center: Vector2, radius: c_int, color: Color) void;
pub extern fn ImageDrawRectangle(dst: *Image, posX: c_int, posY: c_int, width: c_int, height: c_int, color: Color) void;
pub extern fn ImageDrawRectangleV(dst: *Image, position: Vector2, size: Vector2, color: Color) void;
pub extern fn ImageDrawRectangleRec(dst: *Image, rec: Rectangle, color: Color) void;
pub extern fn ImageDrawRectangleLines(dst: *Image, rec: Rectangle, thick: c_int, color: Color) void;
pub extern fn ImageDrawTriangle(dst: *Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
pub extern fn ImageDrawTriangleEx(dst: *Image, v1: Vector2, v2: Vector2, v3: Vector2, c1: Color, c2: Color, c3: Color) void;
pub extern fn ImageDrawTriangleLines(dst: *Image, v1: Vector2, v2: Vector2, v3: Vector2, color: Color) void;
pub extern fn ImageDrawTriangleFan(dst: *Image, points: [*]Vector2, pointCount: c_int, color: Color) void;
pub extern fn ImageDrawTriangleStrip(dst: *Image, points: [*]Vector2, pointCount: c_int, color: Color) void;
pub extern fn ImageDraw(dst: *Image, src: Image, srcRec: Rectangle, dstRec: Rectangle, tint: Color) void;
pub extern fn ImageDrawText(dst: *Image, text: [*:0]const u8, posX: c_int, posY: c_int, fontSize: c_int, color: Color) void;
pub extern fn ImageDrawTextEx(dst: *Image, font: Font, text: [*:0]const u8, position: Vector2, fontSize: f32, spacing: f32, tint: Color) void;

// Texture loading functions
pub extern fn LoadTexture(fileName: [*:0]const u8) Texture2D;
pub extern fn LoadTextureFromImage(image: Image) Texture2D;
pub extern fn LoadTextureCubemap(image: Image, layout: c_int) TextureCubemap;
pub extern fn LoadRenderTexture(width: c_int, height: c_int) RenderTexture2D;
pub extern fn IsTextureValid(texture: Texture2D) bool;
pub extern fn UnloadTexture(texture: Texture2D) void;
pub extern fn IsRenderTextureValid(target: RenderTexture2D) bool;
pub extern fn UnloadRenderTexture(target: RenderTexture2D) void;
pub extern fn UpdateTexture(texture: Texture2D, pixels: ?*const anyopaque) void;
pub extern fn UpdateTextureRec(texture: Texture2D, rec: Rectangle, pixels: ?*const anyopaque) void;

// Texture configuration functions
pub extern fn GenTextureMipmaps(texture: *Texture2D) void;
pub extern fn SetTextureFilter(texture: Texture2D, filter: c_int) void;
pub extern fn SetTextureWrap(texture: Texture2D, wrap: c_int) void;

// Texture drawing functions
pub extern fn DrawTexture(texture: Texture2D, posX: c_int, posY: c_int, tint: Color) void;
pub extern fn DrawTextureV(texture: Texture2D, position: Vector2, tint: Color) void;
pub extern fn DrawTextureEx(texture: Texture2D, position: Vector2, rotation: f32, scale: f32, tint: Color) void;
pub extern fn DrawTextureRec(texture: Texture2D, source: Rectangle, position: Vector2, tint: Color) void;
pub extern fn DrawTexturePro(texture: Texture2D, source: Rectangle, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void;
pub extern fn DrawTextureNPatch(texture: Texture2D, nPatchInfo: NPatchInfo, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void;

// Color/pixel related functions
pub extern fn ColorIsEqual(col1: Color, col2: Color) bool;
pub extern fn Fade(color: Color, alpha: f32) Color;
pub extern fn ColorToInt(color: Color) c_int;
pub extern fn ColorNormalize(color: Color) Vector4;
pub extern fn ColorFromNormalized(normalized: Vector4) Color;
pub extern fn ColorToHSV(color: Color) Vector3;
pub extern fn ColorFromHSV(hue: f32, saturation: f32, value: f32) Color;
pub extern fn ColorTint(color: Color, tint: Color) Color;
pub extern fn ColorBrightness(color: Color, factor: f32) Color;
pub extern fn ColorContrast(color: Color, contrast: f32) Color;
pub extern fn ColorAlpha(color: Color, alpha: f32) Color;
pub extern fn ColorAlphaBlend(dst: Color, src: Color, tint: Color) Color;
pub extern fn ColorLerp(color1: Color, color2: Color, factor: f32) Color;
pub extern fn GetColor(hexValue: c_uint) Color;
pub extern fn GetPixelColor(srcPtr: ?*anyopaque, format: c_int) Color;
pub extern fn SetPixelColor(dstPtr: ?*anyopaque, color: Color, format: c_int) void;
pub extern fn GetPixelDataSize(width: c_int, height: c_int, format: c_int) c_int;

