const std = @import("std");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    var in_type = false;
    var brace_count: u32 = 0;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
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
        
        if (flags.signatures) {
            if (std.mem.startsWith(u8, trimmed, "function ") or
                std.mem.startsWith(u8, trimmed, "export function ") or
                std.mem.startsWith(u8, trimmed, "async function ") or
                std.mem.startsWith(u8, trimmed, "export async function ") or
                std.mem.startsWith(u8, trimmed, "const ") or
                std.mem.startsWith(u8, trimmed, "export const ") or
                std.mem.indexOf(u8, trimmed, " => ") != null) {
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
            // Extract type definitions and their content
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
            }
        }
        
        if (flags.docs) {
            if (std.mem.startsWith(u8, trimmed, "/**") or
                std.mem.startsWith(u8, trimmed, "*") or
                std.mem.startsWith(u8, trimmed, "//")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        if (flags.imports) {
            if (std.mem.startsWith(u8, trimmed, "import ") or
                std.mem.startsWith(u8, trimmed, "export ") or
                std.mem.startsWith(u8, trimmed, "require(")) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
}