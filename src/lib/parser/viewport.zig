/// Viewport optimization for editors
///
/// Prioritizes parsing visible regions for responsive editing experience.
const std = @import("std");
const Token = @import("../token/token.zig").Token;
const Span = @import("../span/span.zig").Span;
const Boundary = @import("structural.zig").Boundary;

/// Viewport region in source
pub const Viewport = struct {
    /// Start line of viewport (0-based)
    start_line: u32,
    /// End line of viewport (exclusive)
    end_line: u32,
    /// Byte offset range
    span: Span,
    /// Priority for parsing (0 = highest)
    priority: u8 = 0,
};

/// Viewport-aware parsing manager
pub const ViewportManager = struct {
    allocator: std.mem.Allocator,
    current_viewport: Viewport,
    parse_queue: std.PriorityQueue(ParseRegion, void, compareRegions),
    parsed_regions: std.ArrayList(ParseRegion),

    const Self = @This();

    const ParseRegion = struct {
        span: Span,
        priority: u8,
        parsed: bool = false,
        boundaries: ?[]Boundary = null,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .current_viewport = .{
                .start_line = 0,
                .end_line = 100,
                .span = .{ .start = 0, .end = 0 },
            },
            .parse_queue = std.PriorityQueue(ParseRegion, void, compareRegions).init(allocator, {}),
            .parsed_regions = std.ArrayList(ParseRegion).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.parse_queue.deinit();
        self.parsed_regions.deinit();
    }

    /// Update current viewport
    pub fn setViewport(self: *Self, viewport: Viewport) !void {
        self.current_viewport = viewport;

        // Reprioritize parse queue
        try self.reprioritize();
    }

    /// Get next region to parse
    pub fn nextRegion(self: *Self) ?ParseRegion {
        return self.parse_queue.removeOrNull();
    }

    /// Mark region as parsed
    pub fn markParsed(self: *Self, region: ParseRegion) !void {
        var updated = region;
        updated.parsed = true;
        try self.parsed_regions.append(updated);
    }

    /// Check if region is in viewport
    pub fn isInViewport(self: *Self, span: Span) bool {
        return span.start < self.current_viewport.span.end and
            span.end > self.current_viewport.span.start;
    }

    /// Calculate priority for region
    pub fn calculatePriority(self: *Self, span: Span) u8 {
        // Viewport gets highest priority
        if (self.isInViewport(span)) {
            return 0;
        }

        // Distance from viewport determines priority
        const viewport_center = (self.current_viewport.span.start + self.current_viewport.span.end) / 2;
        const region_center = (span.start + span.end) / 2;
        const distance = if (region_center > viewport_center)
            region_center - viewport_center
        else
            viewport_center - region_center;

        // Map distance to priority (0-255)
        const max_distance = 100000; // Arbitrary max
        const normalized = @min(distance * 255 / max_distance, 255);
        return @intCast(normalized);
    }

    fn reprioritize(self: *Self) !void {
        // Clear and rebuild queue with new priorities
        var temp = std.ArrayList(ParseRegion).init(self.allocator);
        defer temp.deinit();

        while (self.parse_queue.removeOrNull()) |region| {
            try temp.append(region);
        }

        for (temp.items) |*region| {
            region.priority = self.calculatePriority(region.span);
            try self.parse_queue.add(region.*);
        }
    }

    fn compareRegions(context: void, a: ParseRegion, b: ParseRegion) std.math.Order {
        _ = context;
        return std.math.order(a.priority, b.priority);
    }
};

/// Predictive parser for likely edits
pub const PredictiveParser = struct {
    allocator: std.mem.Allocator,
    edit_history: std.ArrayList(EditPattern),
    predictions: std.ArrayList(Prediction),

    const Self = @This();

    const EditPattern = struct {
        location: Span,
        kind: EditKind,
        frequency: u32,
    };

    const EditKind = enum {
        insertion,
        deletion,
        replacement,
        formatting,
    };

    const Prediction = struct {
        span: Span,
        likelihood: f32,
        suggested_parse: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .edit_history = std.ArrayList(EditPattern).init(allocator),
            .predictions = std.ArrayList(Prediction).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.edit_history.deinit();
        self.predictions.deinit();
    }

    /// Record an edit pattern
    pub fn recordEdit(self: *Self, span: Span, kind: EditKind) !void {
        // Check if pattern exists
        for (self.edit_history.items) |*pattern| {
            if (pattern.location.start == span.start and pattern.kind == kind) {
                pattern.frequency += 1;
                return;
            }
        }

        // New pattern
        try self.edit_history.append(.{
            .location = span,
            .kind = kind,
            .frequency = 1,
        });
    }

    /// Predict likely edit locations
    pub fn predict(self: *Self) []const Prediction {
        // Simple frequency-based prediction
        self.predictions.clearRetainingCapacity();

        for (self.edit_history.items) |pattern| {
            const likelihood = @as(f32, @floatFromInt(pattern.frequency)) / 100.0;
            self.predictions.append(.{
                .span = pattern.location,
                .likelihood = @min(likelihood, 1.0),
                .suggested_parse = "", // Would contain pre-parsed content
            }) catch continue;
        }

        return self.predictions.items;
    }
};
