const std = @import("std");
const ExtractionFlags = @import("../extraction_flags.zig").ExtractionFlags;
const line_utils = @import("../line_utils.zig");
const patterns = @import("../text_patterns.zig");

pub fn extract(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var block_tracker = line_utils.BlockTracker.init();
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Track block depth for multi-line interfaces/types
        if (block_tracker.isInBlock()) {
            try result.appendSlice(line);
            try result.append('\n');
            
            // Update block tracking
            block_tracker.processLine(line);
            continue;
        }
        
        // Functions
        if (flags.signatures) {
            if (patterns.startsWithAny(trimmed, &patterns.Patterns.ts_functions) or
                std.mem.indexOf(u8, trimmed, "=>") != null) {
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
        
        // Types - need to capture full interface/type blocks
        if (flags.types) {
            if (patterns.startsWithAny(trimmed, &patterns.Patterns.ts_types)) {
                try result.appendSlice(line);
                try result.append('\n');
                
                // Check if this starts a block
                if (std.mem.indexOf(u8, line, "{") != null) {
                    block_tracker.processLine(line);
                }
            }
        }
        
        // Imports
        if (flags.imports) {
            const import_patterns = [_][]const u8{ "import ", "export " };
            if (patterns.startsWithAny(trimmed, &import_patterns)) { // import, export
                try result.appendSlice(line);
                try result.append('\n');
            }
        }
    }
}