const std = @import("std");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    var in_type = false;
    var brace_count: u32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        var line_extracted = false;
        
        // Track braces for multi-line types
        if (std.mem.indexOf(u8, line, "{") != null) {
            brace_count += 1;
            if (flags.types and (std.mem.indexOf(u8, trimmed, "interface") != null or
                std.mem.indexOf(u8, trimmed, "class") != null or
                std.mem.indexOf(u8, trimmed, "enum") != null)) {
                in_type = true;
            }
        }
        if (std.mem.indexOf(u8, line, "}") != null) {
            if (brace_count > 0) brace_count -= 1;
            if (brace_count == 0) in_type = false;
        }
        
        // Check types first (highest priority)
        if (flags.types and !line_extracted) {
            if (in_type or
                std.mem.startsWith(u8, trimmed, "interface ") or
                std.mem.startsWith(u8, trimmed, "type ") or
                std.mem.startsWith(u8, trimmed, "enum ") or
                std.mem.startsWith(u8, trimmed, "class ") or
                std.mem.startsWith(u8, trimmed, "export interface ") or
                std.mem.startsWith(u8, trimmed, "export type ") or
                std.mem.startsWith(u8, trimmed, "export enum ") or
                std.mem.startsWith(u8, trimmed, "export class ")) {
                try result.appendSlice(line);
                try result.append('\n');
                line_extracted = true;
            }
        }
        
        // Check signatures second (avoid overlap with types)
        if (flags.signatures and !line_extracted) {
            if (std.mem.startsWith(u8, trimmed, "function ") or
                std.mem.startsWith(u8, trimmed, "export function ") or
                std.mem.startsWith(u8, trimmed, "async function ") or
                std.mem.startsWith(u8, trimmed, "export async function ") or
                std.mem.startsWith(u8, trimmed, "const ") or
                std.mem.startsWith(u8, trimmed, "export const ") or
                std.mem.startsWith(u8, trimmed, "constructor(") or
                std.mem.startsWith(u8, trimmed, "async ") or  // class methods like "async getUser("
                std.mem.indexOf(u8, trimmed, " => ") != null or
                // Method signatures: look for pattern like "methodName(" or "async methodName("
                (std.mem.indexOf(u8, trimmed, "(") != null and 
                 std.mem.indexOf(u8, trimmed, ":") != null and 
                 std.mem.indexOf(u8, trimmed, "{") != null and
                 !std.mem.startsWith(u8, trimmed, "if") and
                 !std.mem.startsWith(u8, trimmed, "for") and
                 !std.mem.startsWith(u8, trimmed, "while"))) {
                // For signatures, always include the full line to preserve readability
                try result.appendSlice(line);
                try result.append('\n');
                line_extracted = true;
            }
        }
        
        // Check docs
        if (flags.docs and !line_extracted) {
            if (std.mem.startsWith(u8, trimmed, "/**") or
                std.mem.startsWith(u8, trimmed, "*") or
                std.mem.startsWith(u8, trimmed, "//")) {
                try result.appendSlice(line);
                try result.append('\n');
                line_extracted = true;
            }
        }
        
        // Check imports (usually mutually exclusive but check anyway)
        if (flags.imports and !line_extracted) {
            if (std.mem.startsWith(u8, trimmed, "import ") or
                std.mem.startsWith(u8, trimmed, "export ") or
                std.mem.startsWith(u8, trimmed, "require(")) {
                try result.appendSlice(line);
                try result.append('\n');
                line_extracted = true;
            }
        }
    }
}