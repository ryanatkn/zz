const std = @import("std");
// Using Zig tree-sitter bindings for the base API
const ts = @import("tree-sitter");
// When we add language grammars, we'll import them via c.zig:
// const c = @import("c.zig");
// const ts_zig = c.ts_zig;

pub const Language = enum {
    zig,
    typescript,
    javascript,
    rust,
    go,
    python,
    c,
    cpp,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx")) return .typescript;
        if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx")) return .javascript;
        if (std.mem.eql(u8, ext, ".rs")) return .rust;
        if (std.mem.eql(u8, ext, ".go")) return .go;
        if (std.mem.eql(u8, ext, ".py")) return .python;
        if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .c;
        if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".hpp")) return .cpp;
        return .unknown;
    }
};

pub const ExtractionFlags = struct {
    signatures: bool = false,
    types: bool = false,
    docs: bool = false,
    structure: bool = false,
    imports: bool = false,
    errors: bool = false,
    tests: bool = false,
    full: bool = false,

    pub fn isDefault(self: ExtractionFlags) bool {
        return !self.signatures and !self.types and !self.docs and 
               !self.structure and !self.imports and !self.errors and 
               !self.tests and !self.full;
    }

    pub fn setDefault(self: *ExtractionFlags) void {
        if (self.isDefault()) {
            self.full = true; // Default to full source for backward compatibility
        }
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    ts_parser: ?*ts.Parser,
    language: Language,

    pub fn init(allocator: std.mem.Allocator, language: Language) !Parser {
        return Parser{
            .allocator = allocator,
            .ts_parser = null, // Will be initialized when needed
            .language = language,
        };
    }

    pub fn deinit(self: *Parser) void {
        if (self.ts_parser) |parser| {
            parser.destroy();
        }
    }

    pub fn extract(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        // For now, if full flag is set or no specific flags, return full source
        if (flags.full or flags.isDefault()) {
            return self.allocator.dupe(u8, source);
        }

        // TODO: Implement tree-sitter based extraction
        // For now, fall back to simple extraction
        return self.extractSimple(source, flags);
    }

    fn extractSimple(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        if (self.language == .zig) {
            try self.extractZigSimple(source, flags, &result);
        } else {
            // For other languages, return full source for now
            try result.appendSlice(source);
        }

        return result.toOwnedSlice();
    }

    fn extractZigSimple(_: *Parser, source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
        var lines = std.mem.tokenizeScalar(u8, source, '\n');
        
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            
            // Extract based on flags
            if (flags.signatures) {
                if (std.mem.startsWith(u8, trimmed, "pub fn") or 
                    std.mem.startsWith(u8, trimmed, "fn")) {
                    // Extract until the opening brace or semicolon
                    if (std.mem.indexOf(u8, line, "{")) |brace_pos| {
                        try result.appendSlice(line[0..brace_pos + 1]);
                        try result.append('\n');
                    } else {
                        try result.appendSlice(line);
                        try result.append('\n');
                    }
                }
            }
            
            if (flags.types) {
                if (std.mem.startsWith(u8, trimmed, "pub const") or
                    std.mem.startsWith(u8, trimmed, "const") or
                    std.mem.startsWith(u8, trimmed, "pub var") or
                    std.mem.startsWith(u8, trimmed, "var")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.docs) {
                if (std.mem.startsWith(u8, trimmed, "///") or
                    std.mem.startsWith(u8, trimmed, "//!")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.imports) {
                if (std.mem.indexOf(u8, trimmed, "@import") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.errors) {
                if (std.mem.indexOf(u8, line, "error") != null or
                    std.mem.indexOf(u8, line, "catch") != null or
                    std.mem.indexOf(u8, line, "try") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.tests) {
                if (std.mem.startsWith(u8, trimmed, "test")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
};