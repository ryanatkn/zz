// Raylib Text Module (rtext)
// Font loading, text drawing, measurement, and string utilities
const types = @import("raylib_types.zig");

// Import types for internal use
const Font = types.Font;
const GlyphInfo = types.GlyphInfo;
const Vector2 = types.Vector2;
const Color = types.Color;
const Rectangle = types.Rectangle;
const Image = types.Image;

//----------------------------------------------------------------------------------
// Font and Text Functions (extern functions)
//----------------------------------------------------------------------------------

// Font loading/unloading functions
pub extern fn GetFontDefault() Font;
pub extern fn LoadFont(fileName: [*:0]const u8) Font;
pub extern fn LoadFontEx(fileName: [*:0]const u8, fontSize: c_int, codepoints: [*c]c_int, codepointCount: c_int) Font;
pub extern fn LoadFontFromImage(image: Image, key: Color, firstChar: c_int) Font;
pub extern fn LoadFontFromMemory(fileType: [*:0]const u8, fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]c_int, codepointCount: c_int) Font;
pub extern fn IsFontValid(font: Font) bool;
pub extern fn LoadFontData(fileData: [*c]const u8, dataSize: c_int, fontSize: c_int, codepoints: [*c]c_int, codepointCount: c_int, type: c_int) [*]GlyphInfo;
pub extern fn GenImageFontAtlas(glyphs: [*c]const GlyphInfo, glyphRecs: [*c][*c]Rectangle, glyphCount: c_int, fontSize: c_int, padding: c_int, packMethod: c_int) Image;
pub extern fn UnloadFontData(glyphs: [*]GlyphInfo, glyphCount: c_int) void;
pub extern fn UnloadFont(font: Font) void;
pub extern fn ExportFontAsCode(font: Font, fileName: [*:0]const u8) bool;

// Text drawing functions
pub extern fn DrawFPS(posX: c_int, posY: c_int) void;
pub extern fn DrawText(text: [*:0]const u8, posX: c_int, posY: c_int, fontSize: c_int, color: Color) void;
pub extern fn DrawTextEx(font: Font, text: [*:0]const u8, position: Vector2, fontSize: f32, spacing: f32, tint: Color) void;
pub extern fn DrawTextPro(font: Font, text: [*:0]const u8, position: Vector2, origin: Vector2, rotation: f32, fontSize: f32, spacing: f32, tint: Color) void;
pub extern fn DrawTextCodepoint(font: Font, codepoint: c_int, position: Vector2, fontSize: f32, tint: Color) void;
pub extern fn DrawTextCodepoints(font: Font, codepoints: [*c]const c_int, codepointCount: c_int, position: Vector2, fontSize: f32, spacing: f32, tint: Color) void;

// Text font info functions
pub extern fn SetTextLineSpacing(spacing: c_int) void;
pub extern fn MeasureText(text: [*:0]const u8, fontSize: c_int) c_int;
pub extern fn MeasureTextEx(font: Font, text: [*:0]const u8, fontSize: f32, spacing: f32) Vector2;
pub extern fn GetGlyphIndex(font: Font, codepoint: c_int) c_int;
pub extern fn GetGlyphInfo(font: Font, codepoint: c_int) GlyphInfo;
pub extern fn GetGlyphAtlasRec(font: Font, codepoint: c_int) Rectangle;

// Text codepoints management functions
pub extern fn LoadUTF8(codepoints: [*c]const c_int, length: c_int) [*:0]u8;
pub extern fn UnloadUTF8(text: [*:0]u8) void;
pub extern fn LoadCodepoints(text: [*:0]const u8, count: [*c]c_int) [*c]c_int;
pub extern fn UnloadCodepoints(codepoints: [*c]c_int) void;
pub extern fn GetCodepointCount(text: [*:0]const u8) c_int;
pub extern fn GetCodepoint(text: [*:0]const u8, codepointSize: [*c]c_int) c_int;
pub extern fn GetCodepointNext(text: [*:0]const u8, codepointSize: [*c]c_int) c_int;
pub extern fn GetCodepointPrevious(text: [*:0]const u8, codepointSize: [*c]c_int) c_int;
pub extern fn CodepointToUTF8(codepoint: c_int, utf8Size: [*c]c_int) [*:0]const u8;

// Text strings management functions
pub extern fn TextCopy(dst: [*:0]u8, src: [*:0]const u8) c_int;
pub extern fn TextIsEqual(text1: [*:0]const u8, text2: [*:0]const u8) bool;
pub extern fn TextLength(text: [*:0]const u8) c_uint;
pub extern fn TextFormat(text: [*:0]const u8, ...) [*:0]const u8;
pub extern fn TextSubtext(text: [*:0]const u8, position: c_int, length: c_int) [*:0]const u8;
pub extern fn TextReplace(text: [*:0]const u8, replace: [*:0]const u8, by: [*:0]const u8) [*:0]u8;
pub extern fn TextInsert(text: [*:0]const u8, insert: [*:0]const u8, position: c_int) [*:0]u8;
pub extern fn TextJoin(textList: [*c][*:0]const u8, count: c_int, delimiter: [*:0]const u8) [*:0]const u8;
pub extern fn TextSplit(text: [*:0]const u8, delimiter: u8, count: [*c]c_int) [*c][*:0]const u8;
pub extern fn TextAppend(text: [*:0]u8, append: [*:0]const u8, position: [*c]c_int) void;
pub extern fn TextFindIndex(text: [*:0]const u8, find: [*:0]const u8) c_int;
pub extern fn TextToUpper(text: [*:0]const u8) [*:0]const u8;
pub extern fn TextToLower(text: [*:0]const u8) [*:0]const u8;
pub extern fn TextToPascal(text: [*:0]const u8) [*:0]const u8;
pub extern fn TextToSnake(text: [*:0]const u8) [*:0]const u8;
pub extern fn TextToCamel(text: [*:0]const u8) [*:0]const u8;
pub extern fn TextToInteger(text: [*:0]const u8) c_int;
pub extern fn TextToFloat(text: [*:0]const u8) f32;

