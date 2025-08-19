const std = @import("std");

/// Rule ID system for efficient AST node type identification
/// 
/// Instead of runtime string comparisons, we use 16-bit integers for:
/// - 10-100x faster comparisons
/// - 90% memory savings (2 bytes vs 16+ for strings)
/// - Compile-time type safety
/// - Better cache locality

/// Common rule IDs shared across all languages (0-255)
pub const CommonRules = enum(u16) {
    // Structural rules
    root = 0,
    object = 1,
    array = 2,
    list = 3,
    
    // Literal rules
    string_literal = 10,
    number_literal = 11,
    boolean_literal = 12,
    null_literal = 13,
    
    // Common language constructs
    identifier = 20,
    operator = 21,
    delimiter = 22,
    keyword = 23,
    comment = 24,
    
    // Special rules
    error_node = 254,
    unknown = 255,
    
    pub fn name(self: CommonRules) []const u8 {
        return @tagName(self);
    }
    
    pub fn isLiteral(self: CommonRules) bool {
        return switch (self) {
            .string_literal, .number_literal, .boolean_literal, .null_literal => true,
            else => false,
        };
    }
    
    pub fn isContainer(self: CommonRules) bool {
        return switch (self) {
            .object, .array, .list => true,
            else => false,
        };
    }
};

/// JSON-specific rule IDs (256-511)
pub const JsonRules = struct {
    // Reuse common rules
    pub const root = @intFromEnum(CommonRules.root);
    pub const object = @intFromEnum(CommonRules.object);
    pub const array = @intFromEnum(CommonRules.array);
    pub const string_literal = @intFromEnum(CommonRules.string_literal);
    pub const number_literal = @intFromEnum(CommonRules.number_literal);
    pub const boolean_literal = @intFromEnum(CommonRules.boolean_literal);
    pub const null_literal = @intFromEnum(CommonRules.null_literal);
    pub const error_recovery = @intFromEnum(CommonRules.error_node);
    
    // JSON-specific rules
    pub const member: u16 = 256;
    pub const key_value_pair: u16 = 257;
    
    pub fn name(id: u16) []const u8 {
        return switch (id) {
            root => "root",
            object => "object",
            array => "array",
            string_literal => "string_literal",
            number_literal => "number_literal",
            boolean_literal => "boolean_literal",
            null_literal => "null_literal",
            member => "member",
            key_value_pair => "key_value_pair",
            error_recovery => "error",
            else => "unknown",
        };
    }
    
    pub fn isValue(id: u16) bool {
        return switch (id) {
            object, array, string_literal, number_literal, boolean_literal, null_literal => true,
            else => false,
        };
    }
    
    pub fn isContainer(id: u16) bool {
        return id == object or id == array;
    }
};

/// ZON-specific rule IDs (512-767)
pub const ZonRules = struct {
    // Reuse common rules
    pub const root = @intFromEnum(CommonRules.root);
    pub const object = @intFromEnum(CommonRules.object);
    pub const array = @intFromEnum(CommonRules.array);
    pub const string_literal = @intFromEnum(CommonRules.string_literal);
    pub const number_literal = @intFromEnum(CommonRules.number_literal);
    pub const boolean_literal = @intFromEnum(CommonRules.boolean_literal);
    pub const null_literal = @intFromEnum(CommonRules.null_literal);
    pub const identifier = @intFromEnum(CommonRules.identifier);
    pub const error_recovery = @intFromEnum(CommonRules.error_node);
    
    // ZON-specific rules
    pub const field_assignment: u16 = 512;
    pub const field_name: u16 = 513;
    pub const dot_identifier: u16 = 514;
    pub const equals: u16 = 515;
    pub const dot: u16 = 516;
    
    pub fn name(id: u16) []const u8 {
        return switch (id) {
            root => "root",
            object => "object",
            array => "array",
            string_literal => "string_literal",
            number_literal => "number_literal",
            boolean_literal => "boolean_literal",
            null_literal => "null_literal",
            identifier => "identifier",
            field_assignment => "field_assignment",
            field_name => "field_name",
            dot_identifier => "dot_identifier",
            equals => "equals",
            dot => "dot",
            error_recovery => "error",
            else => "unknown",
        };
    }
    
    pub fn isValue(id: u16) bool {
        return switch (id) {
            object, array, string_literal, number_literal, boolean_literal, null_literal, identifier => true,
            else => false,
        };
    }
    
    pub fn isContainer(id: u16) bool {
        return id == object or id == array;
    }
};

/// TypeScript rule IDs (768-1279)
pub const TypeScriptRules = struct {
    // Reuse common rules
    pub const object = @intFromEnum(CommonRules.object);
    pub const array = @intFromEnum(CommonRules.array);
    pub const string_literal = @intFromEnum(CommonRules.string_literal);
    pub const number_literal = @intFromEnum(CommonRules.number_literal);
    pub const boolean_literal = @intFromEnum(CommonRules.boolean_literal);
    pub const null_literal = @intFromEnum(CommonRules.null_literal);
    pub const identifier = @intFromEnum(CommonRules.identifier);
    
    // TypeScript-specific rules
    pub const interface_declaration: u16 = 768;
    pub const type_alias: u16 = 769;
    pub const function_declaration: u16 = 770;
    pub const class_declaration: u16 = 771;
    pub const method_declaration: u16 = 772;
    pub const property_declaration: u16 = 773;
    pub const parameter: u16 = 774;
    pub const type_annotation: u16 = 775;
    pub const generic_type: u16 = 776;
    pub const union_type: u16 = 777;
    pub const intersection_type: u16 = 778;
    pub const literal_type: u16 = 779;
    
    // Add more as needed...
};

/// CSS rule IDs (1280-1535)
pub const CssRules = struct {
    pub const rule_set: u16 = 1280;
    pub const selector: u16 = 1281;
    pub const declaration: u16 = 1282;
    pub const property: u16 = 1283;
    pub const value: u16 = 1284;
    pub const media_query: u16 = 1285;
    pub const keyframes: u16 = 1286;
    
    // Add more as needed...
};

/// HTML rule IDs (1536-1791)
pub const HtmlRules = struct {
    pub const element: u16 = 1536;
    pub const start_tag: u16 = 1537;
    pub const end_tag: u16 = 1538;
    pub const attribute: u16 = 1539;
    pub const text: u16 = 1540;
    pub const comment: u16 = 1541;
    pub const doctype: u16 = 1542;
    
    // Add more as needed...
};

/// Helper to get rule name for any language
pub fn getRuleName(language: []const u8, rule_id: u16) []const u8 {
    if (std.mem.eql(u8, language, "json")) {
        return JsonRules.name(rule_id);
    } else if (std.mem.eql(u8, language, "zon")) {
        return ZonRules.name(rule_id);
    } else if (rule_id <= 255) {
        // Try common rules
        if (std.meta.intToEnum(CommonRules, rule_id)) |common| {
            return common.name();
        } else |_| {
            return "unknown";
        }
    }
    return "unknown";
}

// Tests
const testing = std.testing;

test "Common rules are consistent" {
    try testing.expectEqual(@as(u16, 0), @intFromEnum(CommonRules.root));
    try testing.expectEqual(@as(u16, 1), @intFromEnum(CommonRules.object));
    try testing.expectEqual(@as(u16, 2), @intFromEnum(CommonRules.array));
}

test "JSON rules reuse common IDs" {
    try testing.expectEqual(@intFromEnum(CommonRules.object), JsonRules.object);
    try testing.expectEqual(@intFromEnum(CommonRules.array), JsonRules.array);
    try testing.expect(JsonRules.member > 255); // JSON-specific
}

test "ZON rules reuse common IDs" {
    try testing.expectEqual(@intFromEnum(CommonRules.object), ZonRules.object);
    try testing.expectEqual(@intFromEnum(CommonRules.array), ZonRules.array);
    try testing.expect(ZonRules.field_assignment > 511); // ZON-specific
}

test "Rule name lookup" {
    try testing.expectEqualStrings("object", JsonRules.name(JsonRules.object));
    try testing.expectEqualStrings("member", JsonRules.name(JsonRules.member));
    try testing.expectEqualStrings("field_assignment", ZonRules.name(ZonRules.field_assignment));
}

test "Rule predicates" {
    const common = CommonRules.string_literal;
    try testing.expect(common.isLiteral());
    try testing.expect(!common.isContainer());
    
    try testing.expect(JsonRules.isValue(JsonRules.object));
    try testing.expect(JsonRules.isContainer(JsonRules.object));
    try testing.expect(!JsonRules.isContainer(JsonRules.string_literal));
}