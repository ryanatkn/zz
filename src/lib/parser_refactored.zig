const std = @import("std");
const ts = @import("tree-sitter");

// Language-specific parsers
const zig_parser = @import("parsers/zig.zig");
const css_parser = @import("parsers/css.zig");
const html_parser = @import("parsers/html.zig");
const json_parser = @import("parsers/json.zig");
const typescript_parser = @import("parsers/typescript.zig");
const svelte_parser = @import("parsers/svelte.zig");

pub const Language = enum {
    zig,
    css,
    html,
    json,
    typescript,
    svelte,
    unknown,

    pub fn fromExtension(ext: []const u8) Language {
        if (std.mem.eql(u8, ext, ".zig")) return .zig;
        if (std.mem.eql(u8, ext, ".css")) return .css;
        if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .html;
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".ts")) return .typescript;
        if (std.mem.eql(u8, ext, ".svelte")) return .svelte;
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
    language: Language,

    pub fn init(allocator: std.mem.Allocator, language: Language) !Parser {
        return Parser{
            .allocator = allocator,
            .language = language,
        };
    }

    pub fn deinit(self: *Parser) void {
        _ = self; // Nothing to clean up anymore
    }

    pub fn extract(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        // For now, if full flag is set or no specific flags, return full source
        if (flags.full or flags.isDefault()) {
            return self.allocator.dupe(u8, source);
        }

        // Use simple extraction for now (tree-sitter only for Zig)
        return self.extractSimple(source, flags);
    }

    fn extractSimple(self: *Parser, source: []const u8, flags: ExtractionFlags) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        switch (self.language) {
            .zig => {
                // Try tree-sitter first for Zig
                if (zig_parser.extractWithTreeSitter(self.allocator, source, flags)) |extracted| {
                    return extracted;
                } else |_| {
                    // Fall back to simple extraction
                    try zig_parser.extractSimple(source, flags, &result);
                }
            },
            .css => try css_parser.extractSimple(source, flags, &result),
            .html => try html_parser.extractSimple(source, flags, &result),
            .json => try json_parser.extractSimple(source, flags, &result),
            .typescript => try typescript_parser.extractSimple(source, flags, &result),
            .svelte => try svelte_parser.extractSimple(source, flags, &result),
            .unknown => {
                // For unknown languages, return full source
                try result.appendSlice(source);
            },
        }

        return result.toOwnedSlice();
    }
};