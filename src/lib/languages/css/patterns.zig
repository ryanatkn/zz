const std = @import("std");

/// CSS language-specific patterns
pub const Patterns = struct {
    // Selector patterns
    pub const selectors = [_][]const u8{
        ".", // class selector
        "#", // id selector
        "[", // attribute selector
        ":", // pseudo-class/pseudo-element
    };

    // At-rule patterns
    pub const at_rules = [_][]const u8{
        "@import",
        "@media",
        "@keyframes",
        "@supports",
        "@font-face",
        "@page",
        "@namespace",
        "@charset",
        "@document",
        "@viewport",
        "@counter-style",
        "@property",
        "@layer",
        "@container",
        "@scope",
    };

    // Pseudo-classes
    pub const pseudo_classes = [_][]const u8{
        ":hover",        ":active",       ":focus",        ":visited",
        ":link",         ":disabled",     ":enabled",      ":checked",
        ":empty",        ":first-child",  ":last-child",   ":nth-child",
        ":nth-of-type",  ":only-child",   ":target",       ":root",
        ":first-of-type", ":last-of-type", ":only-of-type", ":nth-last-child",
        ":nth-last-of-type", ":focus-within", ":focus-visible", ":required",
        ":optional",     ":valid",        ":invalid",      ":in-range",
        ":out-of-range", ":placeholder-shown", ":autofill", ":read-only",
        ":read-write",   ":is",           ":where",        ":has",
        ":not",
    };

    // Pseudo-elements
    pub const pseudo_elements = [_][]const u8{
        "::before",
        "::after",
        "::first-line",
        "::first-letter",
        "::selection",
        "::backdrop",
        "::placeholder",
        "::marker",
        "::cue",
        "::grammar-error",
        "::spelling-error",
    };

    // Common CSS properties (for validation/completion)
    pub const common_properties = [_][]const u8{
        "display",       "position",      "top",           "right",
        "bottom",        "left",          "width",         "height",
        "margin",        "padding",       "border",        "background",
        "color",         "font",          "font-size",     "font-weight",
        "font-family",   "text-align",    "text-decoration", "line-height",
        "float",         "clear",         "overflow",      "visibility",
        "opacity",       "z-index",       "transform",     "transition",
        "animation",     "flex",          "grid",          "box-shadow",
        "text-shadow",   "border-radius", "cursor",        "pointer-events",
        "user-select",   "white-space",   "word-wrap",     "vertical-align",
    };

    // CSS units
    pub const units = [_][]const u8{
        "px", "em", "rem", "%", "vh", "vw", "vmin", "vmax",
        "ch", "ex", "cm", "mm", "in", "pt", "pc",
        "deg", "rad", "grad", "turn",
        "s", "ms",
        "Hz", "kHz",
        "fr",
    };

    // Color keywords
    pub const color_functions = [_][]const u8{
        "rgb(",
        "rgba(",
        "hsl(",
        "hsla(",
        "hwb(",
        "lab(",
        "lch(",
        "oklab(",
        "oklch(",
        "color(",
        "color-mix(",
        "color-contrast(",
    };

    // Check if a line contains a CSS selector
    pub fn isSelector(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Check for opening brace (selector rule)
        if (std.mem.indexOf(u8, trimmed, "{") != null and
            !std.mem.startsWith(u8, trimmed, "@")) {
            return true;
        }
        
        // Check for selector patterns
        for (selectors) |pattern| {
            if (std.mem.indexOf(u8, trimmed, pattern) != null) {
                return true;
            }
        }
        
        return false;
    }

    // Check if a line contains an at-rule
    pub fn isAtRule(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        for (at_rules) |rule| {
            if (std.mem.startsWith(u8, trimmed, rule)) {
                return true;
            }
        }
        return false;
    }

    // Check if a line contains a property declaration
    pub fn isPropertyDeclaration(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Look for colon (property: value pattern)
        if (std.mem.indexOf(u8, trimmed, ":") != null and
            !std.mem.startsWith(u8, trimmed, ":") and  // Not a pseudo-class
            !std.mem.startsWith(u8, trimmed, "::")) {   // Not a pseudo-element
            return true;
        }
        
        return false;
    }

    // Check if a word is a CSS property
    pub fn isProperty(word: []const u8) bool {
        for (common_properties) |prop| {
            if (std.mem.eql(u8, word, prop)) {
                return true;
            }
        }
        return false;
    }

    // Check if a string ends with a CSS unit
    pub fn hasUnit(value: []const u8) ?[]const u8 {
        for (units) |unit| {
            if (std.mem.endsWith(u8, value, unit)) {
                return unit;
            }
        }
        return null;
    }

    // Check if a value contains a color function
    pub fn hasColorFunction(value: []const u8) bool {
        for (color_functions) |func| {
            if (std.mem.indexOf(u8, value, func) != null) {
                return true;
            }
        }
        return false;
    }

    // Extract selector type (class, id, element, etc.)
    pub fn getSelectorType(selector: []const u8) SelectorType {
        const trimmed = std.mem.trim(u8, selector, " \t");
        
        if (trimmed.len == 0) return .unknown;
        
        return switch (trimmed[0]) {
            '.' => .class,
            '#' => .id,
            '[' => .attribute,
            ':' => if (trimmed.len > 1 and trimmed[1] == ':') .pseudo_element else .pseudo_class,
            '*' => .universal,
            else => .element,
        };
    }

    pub const SelectorType = enum {
        class,
        id,
        attribute,
        pseudo_class,
        pseudo_element,
        element,
        universal,
        unknown,
    };
};

test "CSS patterns - selector detection" {
    try std.testing.expect(Patterns.isSelector(".container {"));
    try std.testing.expect(Patterns.isSelector("#header {"));
    try std.testing.expect(Patterns.isSelector("div.active {"));
    try std.testing.expect(Patterns.isSelector("input[type=\"text\"] {"));
    try std.testing.expect(!Patterns.isSelector("@media screen {"));
}

test "CSS patterns - at-rule detection" {
    try std.testing.expect(Patterns.isAtRule("@import url('styles.css');"));
    try std.testing.expect(Patterns.isAtRule("@media (min-width: 768px) {"));
    try std.testing.expect(Patterns.isAtRule("  @keyframes slide {"));
    try std.testing.expect(!Patterns.isAtRule(".class { color: red; }"));
}

test "CSS patterns - property detection" {
    try std.testing.expect(Patterns.isPropertyDeclaration("  color: red;"));
    try std.testing.expect(Patterns.isPropertyDeclaration("margin: 10px 20px;"));
    try std.testing.expect(!Patterns.isPropertyDeclaration(":hover {"));
    try std.testing.expect(!Patterns.isPropertyDeclaration("::before {"));
}

test "CSS patterns - unit detection" {
    try std.testing.expectEqualStrings("px", Patterns.hasUnit("10px").?);
    try std.testing.expectEqualStrings("rem", Patterns.hasUnit("1.5rem").?);
    try std.testing.expectEqualStrings("%", Patterns.hasUnit("100%").?);
    try std.testing.expect(Patterns.hasUnit("red") == null);
}

test "CSS patterns - selector type" {
    try std.testing.expectEqual(Patterns.SelectorType.class, Patterns.getSelectorType(".button"));
    try std.testing.expectEqual(Patterns.SelectorType.id, Patterns.getSelectorType("#header"));
    try std.testing.expectEqual(Patterns.SelectorType.pseudo_class, Patterns.getSelectorType(":hover"));
    try std.testing.expectEqual(Patterns.SelectorType.pseudo_element, Patterns.getSelectorType("::before"));
    try std.testing.expectEqual(Patterns.SelectorType.element, Patterns.getSelectorType("div"));
}