const std = @import("std");
const ExtractionFlags = @import("../language/flags.zig").ExtractionFlags;
const line_processing = @import("../text/line_processing.zig");
const patterns = @import("../text/patterns.zig");
const builders = @import("../text/builders.zig");

pub fn extract(source: []const u8, flags: ExtractionFlags, result: *std.ArrayList(u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var block_tracker = line_processing.BlockTracker.init();
    
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        
        // Track block depth for multi-line interfaces/types
        if (block_tracker.isInBlock()) {
            try builders.appendLine(result, line);
            
            // Update block tracking
            block_tracker.processLine(line);
            continue;
        }
        
        // Functions
        if (flags.signatures) {
            if (patterns.startsWithAny(trimmed, &patterns.Patterns.ts_functions) or
                std.mem.indexOf(u8, trimmed, "=>") != null) {
                try builders.appendLine(result, line);
            }
        }
        
        // Types - need to capture full interface/type blocks
        if (flags.types) {
            if (patterns.startsWithAny(trimmed, &patterns.Patterns.ts_types)) {
                try builders.appendLine(result, line);
                
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
                try builders.appendLine(result, line);
            }
        }
    }
}