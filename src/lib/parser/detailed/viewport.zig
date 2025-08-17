const std = @import("std");

// Import foundation types
const Span = @import("../foundation/types/span.zig").Span;

// Hash context for Span keys
const SpanContext = struct {
    pub fn hash(self: @This(), span: Span) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&span.start));
        hasher.update(std.mem.asBytes(&span.end));
        return hasher.final();
    }
    
    pub fn eql(self: @This(), a: Span, b: Span) bool {
        _ = self;
        return a.start == b.start and a.end == b.end;
    }
};

// Import structural types
const ParseBoundary = @import("../structural/mod.zig").ParseBoundary;
const BoundaryKind = @import("../foundation/types/predicate.zig").BoundaryKind;

/// Manages viewport detection and parsing prioritization for optimal user experience
/// Prioritizes boundaries based on visibility, recency, and user interaction patterns
pub const ViewportManager = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    
    /// Current viewport span
    current_viewport: Span,
    
    /// Boundaries currently visible in viewport
    visible_boundaries: std.ArrayList(ParseBoundary),
    
    /// Priority queue for predictive parsing
    parse_queue: PriorityQueue(PrioritizedBoundary),
    
    /// Recently edited boundaries (for prioritization)
    recent_edits: std.HashMap(Span, EditInfo, SpanContext, std.hash_map.default_max_load_percentage),
    
    /// Frequently accessed boundaries (for predictive parsing)
    access_frequency: std.HashMap(Span, AccessInfo, SpanContext, std.hash_map.default_max_load_percentage),
    
    /// Scroll direction prediction for smooth scrolling
    scroll_predictor: ScrollPredictor,
    
    /// Performance statistics
    stats: ViewportStats,
    
    pub fn init(allocator: std.mem.Allocator) ViewportManager {
        return ViewportManager{
            .allocator = allocator,
            .current_viewport = Span.init(0, 0),
            .visible_boundaries = std.ArrayList(ParseBoundary).init(allocator),
            .parse_queue = PriorityQueue(PrioritizedBoundary).init(allocator, priorityCompareFn),
            .recent_edits = std.HashMap(Span, EditInfo, SpanContext, 80).init(allocator),
            .access_frequency = std.HashMap(Span, AccessInfo, SpanContext, 80).init(allocator),
            .scroll_predictor = ScrollPredictor.init(),
            .stats = ViewportStats{},
        };
    }
    
    pub fn deinit(self: *ViewportManager) void {
        self.visible_boundaries.deinit();
        self.parse_queue.deinit();
        self.recent_edits.deinit();
        self.access_frequency.deinit();
    }
    
    /// Update the current viewport and recalculate visible boundaries
    pub fn updateViewport(
        self: *ViewportManager,
        new_viewport: Span,
        all_boundaries: []const ParseBoundary,
    ) !void {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.stats.total_update_time_ns += @intCast(elapsed);
            self.stats.viewport_updates += 1;
        }
        
        // Update scroll prediction
        self.scroll_predictor.update(self.current_viewport, new_viewport);
        self.current_viewport = new_viewport;
        
        // Clear previous visible boundaries
        self.visible_boundaries.clearRetainingCapacity();
        
        // Find boundaries that intersect with the viewport
        for (all_boundaries) |boundary| {
            if (boundary.span.overlaps(new_viewport)) {
                try self.visible_boundaries.append(boundary);
                
                // Update access frequency
                try self.updateAccessFrequency(boundary.span);
            }
        }
        
        // Update parsing queue with predictive boundaries
        try self.updateParseQueue(all_boundaries);
        
        self.stats.visible_boundaries_count = self.visible_boundaries.items.len;
    }
    
    /// Get boundaries currently visible in the viewport
    pub fn getVisibleBoundaries(self: ViewportManager) []const ParseBoundary {
        return self.visible_boundaries.items;
    }
    
    /// Get the next boundary to parse based on priority
    pub fn getNextBoundaryToParse(self: *ViewportManager) ?ParseBoundary {
        if (self.parse_queue.removeOrNull()) |prioritized| {
            return prioritized.boundary;
        }
        return null;
    }
    
    /// Record an edit to update boundary priorities
    pub fn recordEdit(self: *ViewportManager, edited_span: Span) !void {
        const now = std.time.timestamp();
        try self.recent_edits.put(edited_span, EditInfo{
            .timestamp = now,
            .edit_count = blk: {
                if (self.recent_edits.get(edited_span)) |existing| {
                    break :blk existing.edit_count + 1;
                } else {
                    break :blk 1;
                }
            },
        });
        
        // Remove old edits (older than 5 minutes)
        const cutoff_time = now - 300; // 5 minutes
        var iterator = self.recent_edits.iterator();
        var to_remove = std.ArrayList(Span).init(self.allocator);
        defer to_remove.deinit();
        
        while (iterator.next()) |entry| {
            if (entry.value_ptr.timestamp < cutoff_time) {
                try to_remove.append(entry.key_ptr.*);
            }
        }
        
        for (to_remove.items) |span| {
            _ = self.recent_edits.remove(span);
        }
    }
    
    /// Predict boundaries that will likely be needed next
    pub fn getPredictiveBoundaries(
        self: *ViewportManager,
        all_boundaries: []const ParseBoundary,
        count: usize,
    ) []ParseBoundary {
        var predicted = std.ArrayList(ParseBoundary).init(self.allocator);
        defer predicted.deinit();
        
        // Get predicted viewport based on scroll direction
        const predicted_viewport = self.scroll_predictor.predictNextViewport(self.current_viewport);
        
        // Find boundaries in predicted viewport
        for (all_boundaries) |boundary| {
            if (boundary.span.overlaps(predicted_viewport)) {
                predicted.append(boundary) catch break;
                if (predicted.items.len >= count) break;
            }
        }
        
        return predicted.toOwnedSlice() catch &.{};
    }
    
    /// Get viewport expansion for smooth scrolling
    pub fn getExpandedViewport(self: ViewportManager, expansion_factor: f32) Span {
        const viewport_size = self.current_viewport.len();
        const expansion = @as(usize, @intFromFloat(@as(f32, @floatFromInt(viewport_size)) * expansion_factor));
        
        const expanded_start = if (self.current_viewport.start >= expansion)
            self.current_viewport.start - expansion
        else
            0;
            
        const expanded_end = self.current_viewport.end + expansion;
        
        return Span.init(expanded_start, expanded_end);
    }
    
    // ========================================================================
    // Private Implementation
    // ========================================================================
    
    /// Update the parsing priority queue with predictive boundaries
    fn updateParseQueue(self: *ViewportManager, all_boundaries: []const ParseBoundary) !void {
        // Clear existing queue
        while (self.parse_queue.removeOrNull()) |_| {}
        
        // Add visible boundaries with highest priority
        for (self.visible_boundaries.items) |boundary| {
            const priority = self.calculatePriority(boundary, .visible);
            try self.parse_queue.add(PrioritizedBoundary{
                .boundary = boundary,
                .priority = priority,
                .reason = .visible,
            });
        }
        
        // Add recently edited boundaries
        var edit_iterator = self.recent_edits.iterator();
        while (edit_iterator.next()) |entry| {
            if (self.findBoundaryContaining(all_boundaries, entry.key_ptr.*)) |boundary| {
                const priority = self.calculatePriority(boundary, .recently_edited);
                try self.parse_queue.add(PrioritizedBoundary{
                    .boundary = boundary,
                    .priority = priority,
                    .reason = .recently_edited,
                });
            }
        }
        
        // Add nearby boundaries for smooth scrolling
        const expanded_viewport = self.getExpandedViewport(0.5); // 50% expansion
        for (all_boundaries) |boundary| {
            if (boundary.span.overlaps(expanded_viewport) and !self.isBoundaryVisible(boundary)) {
                const priority = self.calculatePriority(boundary, .nearby);
                try self.parse_queue.add(PrioritizedBoundary{
                    .boundary = boundary,
                    .priority = priority,
                    .reason = .nearby,
                });
            }
        }
        
        // Add frequently accessed boundaries
        var freq_iterator = self.access_frequency.iterator();
        while (freq_iterator.next()) |entry| {
            if (entry.value_ptr.access_count > 3) { // Threshold for "frequent"
                if (self.findBoundaryContaining(all_boundaries, entry.key_ptr.*)) |boundary| {
                    if (!self.isBoundaryVisible(boundary)) {
                        const priority = self.calculatePriority(boundary, .frequently_accessed);
                        try self.parse_queue.add(PrioritizedBoundary{
                            .boundary = boundary,
                            .priority = priority,
                            .reason = .frequently_accessed,
                        });
                    }
                }
            }
        }
    }
    
    /// Calculate priority score for a boundary
    fn calculatePriority(self: *ViewportManager, boundary: ParseBoundary, reason: PriorityReason) f32 {
        var priority: f32 = switch (reason) {
            .visible => 1000.0, // Highest priority
            .recently_edited => 800.0,
            .nearby => 600.0,
            .frequently_accessed => 400.0,
            .predicted => 200.0,
        };
        
        // Adjust based on boundary type
        priority += switch (boundary.kind) {
            .function => 10.0,
            .struct_definition => 8.0,
            .enum_definition => 6.0,
            .block => 4.0,
            else => 0.0,
        };
        
        // Boost priority for recently edited boundaries
        if (self.recent_edits.get(boundary.span)) |edit_info| {
            const age_seconds = std.time.timestamp() - edit_info.timestamp;
            const recency_boost = 100.0 / @max(1.0, @as(f32, @floatFromInt(age_seconds)));
            priority += recency_boost;
            priority += @as(f32, @floatFromInt(edit_info.edit_count)) * 5.0;
        }
        
        // Boost priority for frequently accessed boundaries
        if (self.access_frequency.get(boundary.span)) |access_info| {
            priority += @as(f32, @floatFromInt(access_info.access_count)) * 2.0;
        }
        
        // Distance penalty for non-visible boundaries
        if (reason != .visible) {
            const distance = self.calculateDistanceFromViewport(boundary.span);
            priority -= distance * 0.1;
        }
        
        return priority;
    }
    
    /// Update access frequency for a boundary
    fn updateAccessFrequency(self: *ViewportManager, span: Span) !void {
        if (self.access_frequency.getPtr(span)) |access_info| {
            access_info.access_count += 1;
            access_info.last_access = std.time.timestamp();
        } else {
            try self.access_frequency.put(span, AccessInfo{
                .access_count = 1,
                .last_access = std.time.timestamp(),
            });
        }
    }
    
    /// Find boundary that contains a given span
    fn findBoundaryContaining(
        self: *ViewportManager,
        boundaries: []const ParseBoundary,
        span: Span,
    ) ?ParseBoundary {
        _ = self;
        for (boundaries) |boundary| {
            if (boundary.span.contains(span.start) and boundary.span.contains(span.end)) {
                return boundary;
            }
        }
        return null;
    }
    
    /// Check if a boundary is currently visible
    fn isBoundaryVisible(self: *ViewportManager, boundary: ParseBoundary) bool {
        for (self.visible_boundaries.items) |visible| {
            if (visible.span.start == boundary.span.start and visible.span.end == boundary.span.end) {
                return true;
            }
        }
        return false;
    }
    
    /// Calculate distance from viewport (for prioritization)
    fn calculateDistanceFromViewport(self: *ViewportManager, span: Span) f32 {
        if (span.overlaps(self.current_viewport)) {
            return 0.0; // Inside viewport
        }
        
        if (span.end < self.current_viewport.start) {
            // Above viewport
            return @as(f32, @floatFromInt(self.current_viewport.start - span.end));
        } else {
            // Below viewport
            return @as(f32, @floatFromInt(span.start - self.current_viewport.end));
        }
    }
    
    // ========================================================================
    // Statistics and Performance Monitoring
    // ========================================================================
    
    pub fn getStats(self: ViewportManager) ViewportStats {
        return self.stats;
    }
    
    pub fn resetStats(self: *ViewportManager) void {
        self.stats = ViewportStats{};
    }
};

/// Scroll direction predictor for smooth scrolling optimization
const ScrollPredictor = struct {
    last_viewport: Span,
    scroll_velocity: f32,
    scroll_direction: ScrollDirection,
    prediction_confidence: f32,
    
    const ScrollDirection = enum { up, down, none };
    
    fn init() ScrollPredictor {
        return ScrollPredictor{
            .last_viewport = Span.init(0, 0),
            .scroll_velocity = 0.0,
            .scroll_direction = .none,
            .prediction_confidence = 0.0,
        };
    }
    
    fn update(self: *ScrollPredictor, old_viewport: Span, new_viewport: Span) void {
        const delta = @as(i32, @intCast(new_viewport.start)) - @as(i32, @intCast(old_viewport.start));
        
        if (delta > 0) {
            self.scroll_direction = .down;
        } else if (delta < 0) {
            self.scroll_direction = .up;
        } else {
            self.scroll_direction = .none;
        }
        
        self.scroll_velocity = @abs(@as(f32, @floatFromInt(delta)));
        self.prediction_confidence = @min(1.0, self.scroll_velocity / 1000.0);
        self.last_viewport = old_viewport;
    }
    
    fn predictNextViewport(self: ScrollPredictor, current_viewport: Span) Span {
        if (self.scroll_direction == .none or self.prediction_confidence < 0.1) {
            return current_viewport;
        }
        
        const predicted_delta = @as(usize, @intFromFloat(self.scroll_velocity * self.prediction_confidence));
        
        switch (self.scroll_direction) {
            .down => {
                return Span.init(
                    current_viewport.start + predicted_delta,
                    current_viewport.end + predicted_delta,
                );
            },
            .up => {
                const new_start = if (current_viewport.start >= predicted_delta)
                    current_viewport.start - predicted_delta
                else
                    0;
                return Span.init(
                    new_start,
                    current_viewport.end - predicted_delta,
                );
            },
            .none => return current_viewport,
        }
    }
};

/// Information about recent edits for prioritization
const EditInfo = struct {
    timestamp: i64,
    edit_count: u32,
};

/// Information about boundary access frequency
const AccessInfo = struct {
    access_count: u32,
    last_access: i64,
};

/// Prioritized boundary for parsing queue
const PrioritizedBoundary = struct {
    boundary: ParseBoundary,
    priority: f32,
    reason: PriorityReason,
};

/// Reason for boundary prioritization
const PriorityReason = enum {
    visible,
    recently_edited,
    nearby,
    frequently_accessed,
    predicted,
};

/// Priority comparison function for the queue
fn priorityCompareFn(context: void, a: PrioritizedBoundary, b: PrioritizedBoundary) std.math.Order {
    _ = context;
    return std.math.order(b.priority, a.priority); // Higher priority first
}

/// Statistics for viewport management performance
pub const ViewportStats = struct {
    viewport_updates: u64 = 0,
    total_update_time_ns: u64 = 0,
    visible_boundaries_count: usize = 0,
    predictive_cache_hits: u64 = 0,
    predictive_cache_misses: u64 = 0,
    
    pub fn averageUpdateTime(self: ViewportStats) f64 {
        if (self.viewport_updates == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_update_time_ns)) / @as(f64, @floatFromInt(self.viewport_updates));
    }
    
    pub fn predictionAccuracy(self: ViewportStats) f32 {
        const total_predictions = self.predictive_cache_hits + self.predictive_cache_misses;
        if (total_predictions == 0) return 0.0;
        return @as(f32, @floatFromInt(self.predictive_cache_hits)) / @as(f32, @floatFromInt(total_predictions));
    }
    
    pub fn format(
        self: ViewportStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("ViewportStats{{ updates: {}, avg_time: {d:.1}μs, visible: {}, prediction: {d:.1}% }}", .{
            self.viewport_updates,
            self.averageUpdateTime() / 1000.0,
            self.visible_boundaries_count,
            self.predictionAccuracy() * 100.0,
        });
    }
};

// ============================================================================
// Priority Queue Implementation (simplified)
// ============================================================================

fn PriorityQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        
        items: std.ArrayList(T),
        compare_fn: *const fn (context: void, a: T, b: T) std.math.Order,
        
        fn init(allocator: std.mem.Allocator, compare_fn: *const fn (context: void, a: T, b: T) std.math.Order) Self {
            return Self{
                .items = std.ArrayList(T).init(allocator),
                .compare_fn = compare_fn,
            };
        }
        
        fn deinit(self: *Self) void {
            self.items.deinit();
        }
        
        fn add(self: *Self, item: T) !void {
            try self.items.append(item);
            // Simple sorted insertion (could be optimized with heap)
            var i = self.items.items.len - 1;
            while (i > 0) {
                const parent = (i - 1) / 2;
                if (self.compare_fn({}, self.items.items[i], self.items.items[parent]) == .lt) {
                    break;
                }
                std.mem.swap(T, &self.items.items[i], &self.items.items[parent]);
                i = parent;
            }
        }
        
        fn removeOrNull(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.orderedRemove(0);
        }
    };
}