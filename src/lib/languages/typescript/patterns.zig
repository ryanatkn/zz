const std = @import("std");

/// TypeScript/JavaScript language-specific patterns
pub const Patterns = struct {
    // Function patterns
    pub const functions = [_][]const u8{
        "function ",
        "function* ",
        "export function ",
        "export function* ",
        "export async function ",
        "export async function* ",
        "async function ",
        "async function* ",
        "const ",
        "let ",
        "var ",
    };

    // Type definition patterns
    pub const types = [_][]const u8{
        "interface ",
        "export interface ",
        "type ",
        "export type ",
        "class ",
        "export class ",
        "enum ",
        "export enum ",
    };

    // Import/export patterns
    pub const imports = [_][]const u8{
        "import ",
        "export ",
        "require(",
    };

    // Keywords for syntax highlighting
    pub const keywords = [_][]const u8{
        "async",     "await",     "break",      "case",
        "catch",     "class",     "const",      "continue",
        "debugger",  "default",   "delete",     "do",
        "else",      "enum",      "export",     "extends",
        "false",     "finally",   "for",        "function",
        "if",        "implements", "import",     "in",
        "instanceof", "interface", "let",        "new",
        "null",      "of",        "package",    "private",
        "protected", "public",    "return",     "static",
        "super",     "switch",    "this",       "throw",
        "true",      "try",       "typeof",     "undefined",
        "var",       "void",      "while",      "with",
        "yield",     "as",        "from",       "get",
        "module",    "namespace", "readonly",   "require",
        "set",       "type",
    };

    // Common method names for detection
    pub const common_methods = [_][]const u8{
        "constructor",
        "render",
        "componentDidMount",
        "componentWillUnmount",
        "useState",
        "useEffect",
        "ngOnInit",
        "ngOnDestroy",
    };

    // Check if a line likely contains a function declaration
    pub fn isFunctionDeclaration(line: []const u8) bool {
        for (functions) |pattern| {
            if (std.mem.indexOf(u8, line, pattern) != null) {
                return true;
            }
        }
        // Arrow functions
        return std.mem.indexOf(u8, line, "=>") != null;
    }

    // Check if a line likely contains a type declaration
    pub fn isTypeDeclaration(line: []const u8) bool {
        for (types) |pattern| {
            if (std.mem.indexOf(u8, line, pattern) != null) {
                return true;
            }
        }
        return false;
    }

    // Check if a line is an import/export statement
    pub fn isImportExport(line: []const u8) bool {
        const trimmed = std.mem.trim(u8, line, " \t");
        for (imports) |pattern| {
            if (std.mem.startsWith(u8, trimmed, pattern)) {
                return true;
            }
        }
        return false;
    }

    // Check if a word is a TypeScript keyword
    pub fn isKeyword(word: []const u8) bool {
        for (keywords) |kw| {
            if (std.mem.eql(u8, word, kw)) {
                return true;
            }
        }
        return false;
    }
};

test "TypeScript patterns - function detection" {
    try std.testing.expect(Patterns.isFunctionDeclaration("export function test() {"));
    try std.testing.expect(Patterns.isFunctionDeclaration("const arrow = () => {}"));
    try std.testing.expect(Patterns.isFunctionDeclaration("async function* generator() {"));
    try std.testing.expect(!Patterns.isFunctionDeclaration("// just a comment"));
}

test "TypeScript patterns - type detection" {
    try std.testing.expect(Patterns.isTypeDeclaration("interface User {"));
    try std.testing.expect(Patterns.isTypeDeclaration("export type Result<T> = T | Error"));
    try std.testing.expect(Patterns.isTypeDeclaration("class Component extends Base {"));
    try std.testing.expect(!Patterns.isTypeDeclaration("const value = 42"));
}

test "TypeScript patterns - import/export detection" {
    try std.testing.expect(Patterns.isImportExport("import { Component } from 'react'"));
    try std.testing.expect(Patterns.isImportExport("export default class"));
    try std.testing.expect(Patterns.isImportExport("  export { utils }"));
    try std.testing.expect(!Patterns.isImportExport("function exported() {}"));
}

test "TypeScript patterns - keyword detection" {
    try std.testing.expect(Patterns.isKeyword("async"));
    try std.testing.expect(Patterns.isKeyword("interface"));
    try std.testing.expect(Patterns.isKeyword("typeof"));
    try std.testing.expect(!Patterns.isKeyword("myVariable"));
}