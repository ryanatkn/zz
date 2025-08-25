/// Unicode Code Point Classification
///
/// Categorizes Unicode code points according to RFC 9839 and Unicode standards.
const std = @import("std");

/// Code point classification
pub const CodePointClass = enum {
    valid, // Normal, valid code point
    control_character, // C0/C1 control characters (except useful ones)
    carriage_return, // U+000D (separate for Unix line ending enforcement)
    surrogate, // U+D800-U+DFFF (invalid in UTF-8)
    noncharacter, // Noncharacter code points
};

/// Classify a Unicode code point
pub fn classifyCodePoint(cp: u32) CodePointClass {
    // Special case for carriage return
    if (cp == 0x0D) {
        return .carriage_return;
    }

    // C0 control characters (U+0000-U+001F)
    // Excluding tab (U+0009) and newline (U+000A)
    if ((cp >= 0x00 and cp <= 0x08) or
        (cp >= 0x0B and cp <= 0x0C) or
        (cp >= 0x0E and cp <= 0x1F))
    {
        return .control_character;
    }

    // DEL character (U+007F)
    if (cp == 0x7F) {
        return .control_character;
    }

    // C1 control characters (U+0080-U+009F)
    if (cp >= 0x80 and cp <= 0x9F) {
        return .control_character;
    }

    // Surrogates (U+D800-U+DFFF)
    // These are invalid in UTF-8 as they're reserved for UTF-16
    if (cp >= 0xD800 and cp <= 0xDFFF) {
        return .surrogate;
    }

    // Noncharacters (U+FDD0-U+FDEF)
    if (cp >= 0xFDD0 and cp <= 0xFDEF) {
        return .noncharacter;
    }

    // Noncharacters at end of each plane (last two code points)
    // U+FFFE, U+FFFF (BMP)
    // U+1FFFE, U+1FFFF (Plane 1)
    // U+2FFFE, U+2FFFF (Plane 2)
    // ... up to ...
    // U+10FFFE, U+10FFFF (Plane 16)
    if ((cp & 0xFFFE) == 0xFFFE and cp <= 0x10FFFF) {
        return .noncharacter;
    }

    // Code points beyond valid Unicode range
    if (cp > 0x10FFFF) {
        return .noncharacter;
    }

    return .valid;
}

/// Check if a code point is a control character
pub fn isControl(cp: u32) bool {
    const class = classifyCodePoint(cp);
    return class == .control_character or class == .carriage_return;
}

/// Check if a code point is a useful control (tab, newline)
pub fn isUsefulControl(cp: u32) bool {
    return cp == 0x09 or cp == 0x0A; // Tab or Newline
}

/// Check if a code point is a surrogate
pub fn isSurrogate(cp: u32) bool {
    return cp >= 0xD800 and cp <= 0xDFFF;
}

/// Check if a code point is a high surrogate (for UTF-16)
pub fn isHighSurrogate(cp: u32) bool {
    return cp >= 0xD800 and cp <= 0xDBFF;
}

/// Check if a code point is a low surrogate (for UTF-16)
pub fn isLowSurrogate(cp: u32) bool {
    return cp >= 0xDC00 and cp <= 0xDFFF;
}

/// Check if a code point is a noncharacter
pub fn isNoncharacter(cp: u32) bool {
    return classifyCodePoint(cp) == .noncharacter;
}

/// Check if a code point is valid for interchange
pub fn isValidForInterchange(cp: u32) bool {
    const class = classifyCodePoint(cp);
    return class == .valid or (class == .carriage_return); // CR is valid, just not preferred
}

/// Get a human-readable description of a code point
pub fn getDescription(cp: u32) []const u8 {
    if (cp == 0x00) return "NULL (U+0000)";
    if (cp == 0x08) return "Backspace (U+0008)";
    if (cp == 0x09) return "Tab (U+0009)";
    if (cp == 0x0A) return "Line Feed (U+000A)";
    if (cp == 0x0B) return "Vertical Tab (U+000B)";
    if (cp == 0x0C) return "Form Feed (U+000C)";
    if (cp == 0x0D) return "Carriage Return (U+000D)";
    if (cp == 0x1B) return "Escape (U+001B)";
    if (cp == 0x7F) return "Delete (U+007F)";
    if (cp == 0xFFFD) return "Replacement Character (U+FFFD)";

    const class = classifyCodePoint(cp);
    return switch (class) {
        .control_character => "Control Character",
        .carriage_return => "Carriage Return",
        .surrogate => "Surrogate (Invalid in UTF-8)",
        .noncharacter => "Noncharacter",
        .valid => "Valid Code Point",
    };
}

// Tests
const testing = std.testing;

test "classifyCodePoint - control characters" {
    try testing.expect(classifyCodePoint(0x00) == .control_character); // NULL
    try testing.expect(classifyCodePoint(0x08) == .control_character); // Backspace
    try testing.expect(classifyCodePoint(0x09) == .valid); // Tab (useful control)
    try testing.expect(classifyCodePoint(0x0A) == .valid); // Newline (useful control)
    try testing.expect(classifyCodePoint(0x0D) == .carriage_return); // CR (special case)
    try testing.expect(classifyCodePoint(0x1F) == .control_character); // Unit Separator
    try testing.expect(classifyCodePoint(0x7F) == .control_character); // DEL
    try testing.expect(classifyCodePoint(0x85) == .control_character); // NEL (C1 control)
    try testing.expect(classifyCodePoint(0x9F) == .control_character); // APC (C1 control)
}

test "classifyCodePoint - surrogates" {
    try testing.expect(classifyCodePoint(0xD800) == .surrogate); // First high surrogate
    try testing.expect(classifyCodePoint(0xDBFF) == .surrogate); // Last high surrogate
    try testing.expect(classifyCodePoint(0xDC00) == .surrogate); // First low surrogate
    try testing.expect(classifyCodePoint(0xDFFF) == .surrogate); // Last low surrogate
    try testing.expect(classifyCodePoint(0xD7FF) == .valid); // Just before surrogates
    try testing.expect(classifyCodePoint(0xE000) == .valid); // Just after surrogates
}

test "classifyCodePoint - noncharacters" {
    // Range U+FDD0-U+FDEF
    try testing.expect(classifyCodePoint(0xFDD0) == .noncharacter);
    try testing.expect(classifyCodePoint(0xFDEF) == .noncharacter);
    try testing.expect(classifyCodePoint(0xFDCF) == .valid); // Just before range
    try testing.expect(classifyCodePoint(0xFDF0) == .valid); // Just after range

    // End of BMP
    try testing.expect(classifyCodePoint(0xFFFE) == .noncharacter);
    try testing.expect(classifyCodePoint(0xFFFF) == .noncharacter);
    try testing.expect(classifyCodePoint(0xFFFD) == .valid); // Replacement character

    // End of Plane 1
    try testing.expect(classifyCodePoint(0x1FFFE) == .noncharacter);
    try testing.expect(classifyCodePoint(0x1FFFF) == .noncharacter);

    // End of Plane 16 (last valid plane)
    try testing.expect(classifyCodePoint(0x10FFFE) == .noncharacter);
    try testing.expect(classifyCodePoint(0x10FFFF) == .noncharacter);

    // Beyond valid Unicode
    try testing.expect(classifyCodePoint(0x110000) == .noncharacter);
}

test "helper functions" {
    try testing.expect(isControl(0x00));
    try testing.expect(isControl(0x0D));
    try testing.expect(!isControl(0x41)); // 'A'

    try testing.expect(isUsefulControl(0x09)); // Tab
    try testing.expect(isUsefulControl(0x0A)); // Newline
    try testing.expect(!isUsefulControl(0x0D)); // CR not useful

    try testing.expect(isSurrogate(0xD800));
    try testing.expect(isHighSurrogate(0xD800));
    try testing.expect(!isLowSurrogate(0xD800));
    try testing.expect(isLowSurrogate(0xDC00));

    try testing.expect(isNoncharacter(0xFFFE));
    try testing.expect(!isNoncharacter(0xFFFD)); // Replacement character is valid

    try testing.expect(isValidForInterchange(0x41)); // 'A'
    try testing.expect(isValidForInterchange(0x0D)); // CR is valid but not preferred
    try testing.expect(!isValidForInterchange(0xD800)); // Surrogate
}
