const std = @import("std");
const ExtractionFlags = @import("../parser.zig").ExtractionFlags;

pub fn extractSimple(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.tokenizeScalar(u8, source, '\n');
    var in_script = false;
    var in_style = false;
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Track script and style sections
        if (std.mem.startsWith(u8, trimmed, "<script")) {
            in_script = true;
            if (flags.imports or flags.signatures) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "</script>")) {
            in_script = false;
            if (flags.imports or flags.signatures) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "<style")) {
            in_style = true;
            if (flags.types) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "</style>")) {
            in_style = false;
            if (flags.types) {
                try result.appendSlice(line);
                try result.append('\n');
            }
            continue;
        }
        
        if (in_script) {
            // TypeScript/JavaScript extraction within script tags
            if (flags.signatures or flags.types) {
                if (std.mem.startsWith(u8, trimmed, "function ") or
                    std.mem.startsWith(u8, trimmed, "export ") or
                    std.mem.startsWith(u8, trimmed, "const ") or
                    std.mem.startsWith(u8, trimmed, "let ") or
                    std.mem.startsWith(u8, trimmed, "interface ") or
                    std.mem.startsWith(u8, trimmed, "type ") or
                    std.mem.indexOf(u8, trimmed, " => ") != null) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.imports) {
                if (std.mem.startsWith(u8, trimmed, "import ")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        } else if (in_style) {
            // CSS extraction within style tags
            if (flags.types or flags.structure) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        } else {
            // HTML template extraction
            if (flags.structure) {
                if (std.mem.startsWith(u8, trimmed, "<") and !std.mem.startsWith(u8, trimmed, "<!--")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
            
            if (flags.docs) {
                if (std.mem.startsWith(u8, trimmed, "<!--")) {
                    try result.appendSlice(line);
                    try result.append('\n');
                }
            }
        }
    }
}