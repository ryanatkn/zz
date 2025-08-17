const std = @import("std");

// Import foundation types
const Span = @import("../foundation/types/span.zig").Span;

/// Represents an edit operation in the source text
/// Used for incremental parsing and fact updates
pub const Edit = struct {
    /// Span of text being modified
    span: Span,
    
    /// Type of edit operation
    operation: EditOperation,
    
    /// New text content (for insert/replace operations)
    new_text: []const u8,
    
    /// Timestamp when edit was made (for temporal ordering)
    timestamp: i64,
    
    /// Optional edit metadata
    metadata: EditMetadata,
    
    pub fn init(span: Span, operation: EditOperation, new_text: []const u8) Edit {
        return Edit{
            .span = span,
            .operation = operation,
            .new_text = new_text,
            .timestamp = std.time.timestamp(),
            .metadata = EditMetadata{},
        };
    }
    
    /// Create an insert edit
    pub fn insert(position: usize, text: []const u8) Edit {
        return Edit.init(
            Span.init(position, position),
            .insert,
            text,
        );
    }
    
    /// Create a delete edit
    pub fn delete(span: Span) Edit {
        return Edit.init(
            span,
            .delete,
            "",
        );
    }
    
    /// Create a replace edit
    pub fn replace(span: Span, new_text: []const u8) Edit {
        return Edit.init(
            span,
            .replace,
            new_text,
        );
    }
    
    /// Calculate the net change in text length
    pub fn deltaLength(self: Edit) i32 {
        const old_length = @as(i32, @intCast(self.span.len()));
        const new_length = @as(i32, @intCast(self.new_text.len));
        
        return switch (self.operation) {
            .insert => new_length,
            .delete => -old_length,
            .replace => new_length - old_length,
        };
    }
    
    /// Check if this edit affects a given span
    pub fn affects(self: Edit, target_span: Span) bool {
        return self.span.overlaps(target_span) or 
               (self.operation == .insert and target_span.start >= self.span.start);
    }
    
    /// Apply this edit to adjust a span's position after the edit
    pub fn adjustSpan(self: Edit, target_span: Span) Span {
        const delta = self.deltaLength();
        
        if (target_span.end <= self.span.start) {
            // Target is before edit, no change
            return target_span;
        } else if (target_span.start >= self.span.end) {
            // Target is after edit, shift by delta
            return Span.init(
                @as(usize, @intCast(@as(i32, @intCast(target_span.start)) + delta)),
                @as(usize, @intCast(@as(i32, @intCast(target_span.end)) + delta)),
            );
        } else {
            // Target overlaps with edit, more complex adjustment needed
            return self.adjustOverlappingSpan(target_span);
        }
    }
    
    /// Adjust span that overlaps with this edit
    fn adjustOverlappingSpan(self: Edit, target_span: Span) Span {
        switch (self.operation) {
            .insert => {
                // Insert doesn't change existing content, just shifts positions
                const delta = @as(i32, @intCast(self.new_text.len));
                if (target_span.start >= self.span.start) {
                    return Span.init(
                        @as(usize, @intCast(@as(i32, @intCast(target_span.start)) + delta)),
                        @as(usize, @intCast(@as(i32, @intCast(target_span.end)) + delta)),
                    );
                } else {
                    // Only end position shifts
                    return Span.init(
                        target_span.start,
                        @as(usize, @intCast(@as(i32, @intCast(target_span.end)) + delta)),
                    );
                }
            },
            .delete => {
                // Delete operation shrinks the span
                const delete_start = self.span.start;
                const delete_end = self.span.end;
                
                if (target_span.start >= delete_end) {
                    // Target starts after deleted region
                    const delta = @as(i32, @intCast(delete_end - delete_start));
                    return Span.init(
                        target_span.start - @as(usize, @intCast(delta)),
                        target_span.end - @as(usize, @intCast(delta)),
                    );
                } else if (target_span.end <= delete_start) {
                    // Target ends before deleted region
                    return target_span;
                } else {
                    // Target overlaps with deleted region
                    const new_start = @min(target_span.start, delete_start);
                    const new_end = if (target_span.end <= delete_end)
                        delete_start
                    else
                        delete_start + (target_span.end - delete_end);
                    
                    return Span.init(new_start, new_end);
                }
            },
            .replace => {
                // Replace is delete + insert
                const delete_edit = Edit.delete(self.span);
                const adjusted_after_delete = delete_edit.adjustSpan(target_span);
                
                const insert_edit = Edit.insert(self.span.start, self.new_text);
                return insert_edit.adjustSpan(adjusted_after_delete);
            },
        }
    }
};

/// Type of edit operation
pub const EditOperation = enum {
    insert,   // Insert text at position
    delete,   // Delete text in range
    replace,  // Replace text in range with new text
};

/// Metadata associated with an edit
pub const EditMetadata = struct {
    /// User who made the edit (for collaborative editing)
    user_id: ?[]const u8 = null,
    
    /// Source of the edit (keyboard, paste, refactoring tool, etc.)
    source: EditSource = .user_input,
    
    /// Whether this edit should trigger incremental parsing
    trigger_parsing: bool = true,
    
    /// Whether this edit is part of a larger operation
    is_composite: bool = false,
    
    /// ID of the composite operation this edit belongs to
    composite_id: ?u64 = null,
};

/// Source of an edit operation
pub const EditSource = enum {
    user_input,      // Direct user typing
    paste,           // Clipboard paste
    refactoring,     // Automated refactoring
    completion,      // Code completion
    formatter,       // Code formatting
    external_tool,   // External tool modification
};

/// Sequence of edits that can be applied together
pub const EditSequence = struct {
    edits: std.ArrayList(Edit),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) EditSequence {
        return EditSequence{
            .edits = std.ArrayList(Edit).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EditSequence) void {
        self.edits.deinit();
    }
    
    /// Add an edit to the sequence
    pub fn add(self: *EditSequence, edit: Edit) !void {
        try self.edits.append(edit);
    }
    
    /// Get the total span affected by all edits
    pub fn getAffectedSpan(self: EditSequence) ?Span {
        if (self.edits.items.len == 0) return null;
        
        var min_start = self.edits.items[0].span.start;
        var max_end = self.edits.items[0].span.end;
        
        for (self.edits.items[1..]) |edit| {
            min_start = @min(min_start, edit.span.start);
            max_end = @max(max_end, edit.span.end);
        }
        
        return Span.init(min_start, max_end);
    }
    
    /// Calculate total length delta for all edits
    pub fn getTotalDelta(self: EditSequence) i32 {
        var total_delta: i32 = 0;
        for (self.edits.items) |edit| {
            total_delta += edit.deltaLength();
        }
        return total_delta;
    }
    
    /// Sort edits by position (for safe application)
    pub fn sortByPosition(self: *EditSequence) void {
        std.sort.pdq(Edit, self.edits.items, {}, editCompare);
    }
    
    /// Apply all edits to adjust a span
    pub fn adjustSpan(self: EditSequence, target_span: Span) Span {
        var adjusted = target_span;
        for (self.edits.items) |edit| {
            adjusted = edit.adjustSpan(adjusted);
        }
        return adjusted;
    }
};

/// Compare function for sorting edits by position
fn editCompare(context: void, a: Edit, b: Edit) bool {
    _ = context;
    return a.span.start < b.span.start;
}

/// Utility functions for working with edits
pub const EditUtils = struct {
    /// Merge consecutive edits where possible
    pub fn mergeConsecutiveEdits(
        allocator: std.mem.Allocator,
        edits: []const Edit,
    ) ![]Edit {
        if (edits.len <= 1) return try allocator.dupe(Edit, edits);
        
        var merged = std.ArrayList(Edit).init(allocator);
        errdefer merged.deinit();
        
        try merged.append(edits[0]);
        
        for (edits[1..]) |edit| {
            const last = &merged.items[merged.items.len - 1];
            
            if (canMerge(last.*, edit)) {
                last.* = try mergeEdits(allocator, last.*, edit);
            } else {
                try merged.append(edit);
            }
        }
        
        return merged.toOwnedSlice();
    }
    
    /// Check if two edits can be merged
    fn canMerge(a: Edit, b: Edit) bool {
        // Only merge if they're adjacent and same operation type
        return a.operation == b.operation and
               a.span.end == b.span.start and
               a.timestamp == b.timestamp; // Same edit session
    }
    
    /// Merge two compatible edits
    fn mergeEdits(allocator: std.mem.Allocator, a: Edit, b: Edit) !Edit {
        switch (a.operation) {
            .insert => {
                // Merge inserted text
                const merged_text = try std.fmt.allocPrint(
                    allocator,
                    "{s}{s}",
                    .{ a.new_text, b.new_text },
                );
                return Edit.init(a.span, .insert, merged_text);
            },
            .delete => {
                // Merge deleted ranges
                const merged_span = Span.init(a.span.start, b.span.end);
                return Edit.init(merged_span, .delete, "");
            },
            .replace => {
                // Merge replaced text and range
                const merged_span = Span.init(a.span.start, b.span.end);
                const merged_text = try std.fmt.allocPrint(
                    allocator,
                    "{s}{s}",
                    .{ a.new_text, b.new_text },
                );
                return Edit.init(merged_span, .replace, merged_text);
            },
        }
    }
    
    /// Convert edits to a unified diff format
    pub fn toUnifiedDiff(
        allocator: std.mem.Allocator,
        edits: []const Edit,
        original_text: []const u8,
    ) ![]u8 {
        _ = allocator;
        _ = edits;
        _ = original_text;
        
        // TODO: Implement unified diff format generation
        return "";
    }
    
    /// Apply edits to text and return the result
    pub fn applyEdits(
        allocator: std.mem.Allocator,
        original_text: []const u8,
        edits: []const Edit,
    ) ![]u8 {
        if (edits.len == 0) return try allocator.dupe(u8, original_text);
        
        // Sort edits by position (in reverse to avoid position shifting issues)
        const sorted_edits = try allocator.dupe(Edit, edits);
        defer allocator.free(sorted_edits);
        
        std.sort.pdq(Edit, sorted_edits, {}, editCompareReverse);
        
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();
        
        try result.appendSlice(original_text);
        
        // Apply edits in reverse order
        for (sorted_edits) |edit| {
            switch (edit.operation) {
                .insert => {
                    try result.insertSlice(edit.span.start, edit.new_text);
                },
                .delete => {
                    _ = result.orderedRemove(edit.span.start);
                    // Remove remaining characters in the span
                    for (edit.span.start..@min(edit.span.end, result.items.len)) |_| {
                        if (edit.span.start < result.items.len) {
                            _ = result.orderedRemove(edit.span.start);
                        }
                    }
                },
                .replace => {
                    // Delete old content
                    for (edit.span.start..@min(edit.span.end, result.items.len)) |_| {
                        if (edit.span.start < result.items.len) {
                            _ = result.orderedRemove(edit.span.start);
                        }
                    }
                    // Insert new content
                    try result.insertSlice(edit.span.start, edit.new_text);
                },
            }
        }
        
        return result.toOwnedSlice();
    }
};

/// Compare function for reverse sorting (latest edits first)
fn editCompareReverse(context: void, a: Edit, b: Edit) bool {
    _ = context;
    return a.span.start > b.span.start;
}

// ============================================================================
// Testing Utilities
// ============================================================================

pub const TestHelpers = struct {
    /// Create a simple edit for testing
    pub fn createEdit(start: usize, end: usize, text: []const u8) Edit {
        return Edit.replace(Span.init(start, end), text);
    }
    
    /// Test edit sequence operations
    pub fn testEditSequence(allocator: std.mem.Allocator) !void {
        var sequence = EditSequence.init(allocator);
        defer sequence.deinit();
        
        try sequence.add(Edit.insert(10, "hello"));
        try sequence.add(Edit.replace(Span.init(20, 25), "world"));
        try sequence.add(Edit.delete(Span.init(30, 35)));
        
        const affected = sequence.getAffectedSpan();
        std.debug.assert(affected != null);
        std.debug.assert(affected.?.start == 10);
        std.debug.assert(affected.?.end == 35);
        
        const delta = sequence.getTotalDelta();
        // hello(+5) + world(-5+5=0) + delete(-5) = -5 total
        std.debug.assert(delta == -5);
    }
};