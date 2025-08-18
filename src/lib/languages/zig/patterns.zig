const std = @import("std");

/// Zig language-specific patterns
pub const Patterns = struct {
    // Function patterns
    pub const functions = [_][]const u8{
        "pub fn ",
        "fn ",
        "export fn ",
        "inline fn ",
        "test ",
    };

    // Declaration patterns
    pub const declarations = [_][]const u8{
        "pub fn ",
        "fn ",
        "pub const ",
        "const ",
        "pub var ",
        "var ",
        "test ",
        "comptime ",
        "threadlocal ",
    };

    // Type definition patterns
    pub const types = [_][]const u8{
        "struct",
        "enum",
        "union",
        "error",
        "packed struct",
        "extern struct",
        "opaque",
    };

    // Documentation comment patterns
    pub const docs = [_][]const u8{
        "///",
        "//!",
    };

    // Built-in functions
    pub const builtins = [_][]const u8{
        "@import",       "@export",       "@fieldParentPtr",
        "@typeInfo",     "@typeName",     "@TypeOf",
        "@compileError", "@compileLog",   "@sizeof",
        "@alignOf",      "@memberName",   "@memberType",
        "@memberCount",  "@field",        "@setEvalBranchQuota",
        "@setRuntimeSafety", "@setFloatMode", "@setAlignStack",
        "@setCold",      "@panic",        "@ptrCast",
        "@intCast",      "@floatCast",    "@ptrFromInt",
        "@intFromPtr",   "@intFromFloat", "@floatFromInt",
        "@intFromBool",  "@boolFromInt",  "@intFromEnum",
        "@enumFromInt",  "@errorFromInt", "@intFromError",
        "@embedFile",    "@cImport",      "@cInclude",
        "@hasDecl",      "@hasField",     "@bitCast",
        "@bitOffsetOf",  "@bitSizeOf",    "@divExact",
        "@divFloor",     "@divTrunc",     "@mod",
        "@rem",          "@mulWithOverflow", "@addWithOverflow",
        "@subWithOverflow", "@shlWithOverflow", "@shlExact",
        "@shrExact",     "@min",          "@max",
        "@clz",          "@ctz",          "@popCount",
        "@byteSwap",     "@bitReverse",   "@sqrt",
        "@sin",          "@cos",          "@tan",
        "@exp",          "@exp2",         "@log",
        "@log2",         "@log10",        "@floor",
        "@ceil",         "@trunc",        "@round",
    };

    // Zig keywords
    pub const keywords = [_][]const u8{
        "align",        "allowzero",    "and",          "anyframe",
        "anytype",      "asm",          "async",        "await",
        "break",        "callconv",     "catch",        "comptime",
        "const",        "continue",     "defer",        "else",
        "enum",         "errdefer",     "error",        "export",
        "extern",       "false",        "fn",           "for",
        "if",           "inline",       "linksection",  "noalias",
        "noinline",     "nosuspend",    "null",         "opaque",
        "or",           "orelse",       "packed",       "pub",
        "resume",       "return",       "struct",       "suspend",
        "switch",       "test",         "threadlocal",  "true",
        "try",          "undefined",    "union",        "unreachable",
        "usingnamespace", "var",        "volatile",     "while",
    };

    // Primitive types
    pub const primitive_types = [_][]const u8{
        "void",         "bool",         "noreturn",     "type",
        "anyerror",     "comptime_int", "comptime_float",
        "u8",   "u16",  "u32",  "u64",  "u128", "usize",
        "i8",   "i16",  "i32",  "i64",  "i128", "isize",
        "c_char",       "c_short",      "c_ushort",     "c_int",
        "c_uint",       "c_long",       "c_ulong",      "c_longlong",
        "c_ulonglong",  "c_longdouble", "f16",          "f32",
        "f64",          "f80",          "f128",
    };

    // Check if a line contains a function declaration
    pub fn isFunctionDeclaration(line: []const u8) bool {
        for (functions) |pattern| {
            if (std.mem.indexOf(u8, line, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    // Check if a line contains a type declaration
    pub fn isTypeDeclaration(line: []const u8) bool {
        for (types) |pattern| {
            if (std.mem.indexOf(u8, line, pattern) != null) {
                // Make sure it's actually a type declaration, not just the keyword
                const idx = std.mem.indexOf(u8, line, pattern).?;
                if (idx == 0 or line[idx - 1] == ' ') {
                    return true;
                }
            }
        }
        return false;
    }

    // Check if a line is a documentation comment
    pub fn isDocComment(line: []const u8) bool {
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        for (docs) |pattern| {
            if (std.mem.startsWith(u8, trimmed, pattern)) {
                return true;
            }
        }
        return false;
    }

    // Check if a word is a Zig keyword
    pub fn isKeyword(word: []const u8) bool {
        for (keywords) |kw| {
            if (std.mem.eql(u8, word, kw)) {
                return true;
            }
        }
        return false;
    }

    // Check if a word is a built-in function
    pub fn isBuiltin(word: []const u8) bool {
        for (builtins) |builtin| {
            if (std.mem.eql(u8, word, builtin)) {
                return true;
            }
        }
        return false;
    }

    // Check if a word is a primitive type
    pub fn isPrimitiveType(word: []const u8) bool {
        for (primitive_types) |pt| {
            if (std.mem.eql(u8, word, pt)) {
                return true;
            }
        }
        return false;
    }

    // Check if a line contains a test block
    pub fn isTestBlock(line: []const u8) bool {
        return std.mem.indexOf(u8, line, "test \"") != null or
               std.mem.indexOf(u8, line, "test {") != null;
    }

    // Check if a line contains a comptime block
    pub fn isComptimeBlock(line: []const u8) bool {
        return std.mem.indexOf(u8, line, "comptime {") != null or
               std.mem.indexOf(u8, line, "comptime ") != null;
    }
};

test "Zig patterns - function detection" {
    try std.testing.expect(Patterns.isFunctionDeclaration("pub fn main() void {"));
    try std.testing.expect(Patterns.isFunctionDeclaration("fn helper() !void {"));
    try std.testing.expect(Patterns.isFunctionDeclaration("test \"basic test\" {"));
    try std.testing.expect(!Patterns.isFunctionDeclaration("const value = 42;"));
}

test "Zig patterns - type detection" {
    try std.testing.expect(Patterns.isTypeDeclaration("const MyStruct = struct {"));
    try std.testing.expect(Patterns.isTypeDeclaration("pub const MyEnum = enum {"));
    try std.testing.expect(Patterns.isTypeDeclaration("const MyUnion = union(enum) {"));
    try std.testing.expect(!Patterns.isTypeDeclaration("const value = structValue;"));
}

test "Zig patterns - doc comment detection" {
    try std.testing.expect(Patterns.isDocComment("/// This is a doc comment"));
    try std.testing.expect(Patterns.isDocComment("//! Top-level doc comment"));
    try std.testing.expect(Patterns.isDocComment("  /// Indented doc comment"));
    try std.testing.expect(!Patterns.isDocComment("// Regular comment"));
}

test "Zig patterns - keyword detection" {
    try std.testing.expect(Patterns.isKeyword("const"));
    try std.testing.expect(Patterns.isKeyword("comptime"));
    try std.testing.expect(Patterns.isKeyword("unreachable"));
    try std.testing.expect(!Patterns.isKeyword("myVariable"));
}

test "Zig patterns - builtin detection" {
    try std.testing.expect(Patterns.isBuiltin("@import"));
    try std.testing.expect(Patterns.isBuiltin("@TypeOf"));
    try std.testing.expect(Patterns.isBuiltin("@compileError"));
    try std.testing.expect(!Patterns.isBuiltin("import"));
}

test "Zig patterns - primitive type detection" {
    try std.testing.expect(Patterns.isPrimitiveType("u32"));
    try std.testing.expect(Patterns.isPrimitiveType("bool"));
    try std.testing.expect(Patterns.isPrimitiveType("f64"));
    try std.testing.expect(!Patterns.isPrimitiveType("MyType"));
}