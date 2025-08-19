const std = @import("std");

/// Literal specification for parameterization
pub const LiteralSpec = struct {
    name: [:0]const u8,
    text: []const u8,
    token_kind: TokenKind,
    description: []const u8 = "",
};

// Import TokenKind from the correct location
const TokenKind = @import("predicate.zig").TokenKind;

/// Parameterized literal system for efficient literal parsing
/// Replaces string-based literal matching with direct character sequence matching
/// Memory: Direct character matching vs string allocations
/// Performance: Optimized character-by-character comparison
pub fn LiteralKind(comptime literals: []const LiteralSpec) type {
    // Create enum with optimal integer size
    const TagType = std.math.IntFittingRange(0, literals.len - 1);
    
    // Generate enum fields at comptime
    comptime var fields: [literals.len]std.builtin.Type.EnumField = undefined;
    comptime for (literals, 0..) |literal, i| {
        fields[i] = std.builtin.Type.EnumField{
            .name = literal.name,
            .value = i,
        };
    };
    
    const Kind = @Type(std.builtin.Type{
        .@"enum" = .{
            .tag_type = TagType,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_exhaustive = true,
        },
    });
    
    return struct {
        const Self = @This();
        pub const KindType = Kind;
        pub const LiteralSpecType = LiteralSpec;
        
        /// Get literal text
        pub fn text(kind: Kind) []const u8 {
            const index = @intFromEnum(kind);
            return literals[index].text;
        }
        
        /// Get literal name
        pub fn name(kind: Kind) [:0]const u8 {
            const index = @intFromEnum(kind);
            return literals[index].name;
        }
        
        /// Get token kind for this literal
        pub fn tokenKind(kind: Kind) TokenKind {
            const index = @intFromEnum(kind);
            return literals[index].token_kind;
        }
        
        /// Get literal description
        pub fn description(kind: Kind) []const u8 {
            const index = @intFromEnum(kind);
            return literals[index].description;
        }
        
        /// Find literal by first character (O(1) lookup)
        pub fn fromFirstChar(first_char: u8) ?Kind {
            inline for (literals, 0..) |literal, i| {
                if (literal.text.len > 0 and literal.text[0] == first_char) {
                    return @enumFromInt(i);
                }
            }
            return null;
        }
        
        /// Check if text matches literal exactly
        pub fn matches(kind: Kind, text_to_check: []const u8) bool {
            const index = @intFromEnum(kind);
            return std.mem.eql(u8, literals[index].text, text_to_check);
        }
        
        /// Get all literals as array (for iteration)
        pub fn allLiterals() []const LiteralSpec {
            return literals;
        }
    };
}

// Language-specific literal sets are now defined in their respective language modules:
// - JSON literals: src/lib/languages/json/patterns.zig

// Tests
const testing = std.testing;

test "LiteralKind - basic functionality" {
    const test_literals = [_]LiteralSpec{
        .{
            .name = "yes",
            .text = "yes",
            .token_kind = .boolean_literal,
        },
        .{
            .name = "no",
            .text = "no",
            .token_kind = .boolean_literal,
        },
    };
    
    const TestLiterals = LiteralKind(&test_literals);
    
    // Test first character lookup
    const yes_kind = TestLiterals.fromFirstChar('y').?;
    const no_kind = TestLiterals.fromFirstChar('n').?;
    try testing.expectEqual(@as(?TestLiterals.KindType, null), TestLiterals.fromFirstChar('x'));
    
    // Test text retrieval
    try testing.expectEqualStrings("yes", TestLiterals.text(yes_kind));
    try testing.expectEqualStrings("no", TestLiterals.text(no_kind));
    
    // Test matching
    try testing.expect(TestLiterals.matches(yes_kind, "yes"));
    try testing.expect(!TestLiterals.matches(yes_kind, "no"));
    try testing.expect(!TestLiterals.matches(yes_kind, "maybe"));
    
    // Test token kind
    try testing.expectEqual(TokenKind.boolean_literal, TestLiterals.tokenKind(yes_kind));
    try testing.expectEqual(TokenKind.boolean_literal, TestLiterals.tokenKind(no_kind));
}

// JSON-specific tests are now in src/lib/languages/json/patterns.zig