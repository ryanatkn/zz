const std = @import("std");
const Span = @import("span.zig").Span;
const Predicate = @import("predicate.zig").Predicate;
const Value = @import("predicate.zig").Value;

/// Unique identifier for facts in the system
pub const FactId = u32;

/// Generation counter for tracking fact stream updates
/// Used for cache invalidation and incremental updates
pub const Generation = u32;

/// Confidence level for facts (0.0 = no confidence, 1.0 = certain)
/// Used for ambiguous parses and speculative execution
pub const Confidence = f32;

/// Immutable fact about a span of text
/// Facts form the basis of the stratified parser's intermediate representation
/// instead of traditional AST trees
pub const Fact = struct {
    /// Unique identifier for this fact
    id: FactId,
    
    /// Text span this fact describes
    subject: Span,
    
    /// What kind of information this fact conveys
    predicate: Predicate,
    
    /// Additional value associated with this predicate (if any)
    object: ?Value,
    
    /// Confidence level for this fact (0.0 to 1.0)
    confidence: Confidence,
    
    /// Generation when this fact was created
    generation: Generation,

    /// Create a new fact with all required fields
    pub fn init(
        id: FactId,
        subject: Span,
        predicate: Predicate,
        object: ?Value,
        confidence: Confidence,
        generation: Generation,
    ) Fact {
        return .{
            .id = id,
            .subject = subject,
            .predicate = predicate,
            .object = object,
            .confidence = confidence,
            .generation = generation,
        };
    }

    /// Create a fact with high confidence (1.0) and no object value
    pub fn simple(
        id: FactId,
        subject: Span,
        predicate: Predicate,
        generation: Generation,
    ) Fact {
        return init(id, subject, predicate, null, 1.0, generation);
    }

    /// Create a fact with a value object
    pub fn withValue(
        id: FactId,
        subject: Span,
        predicate: Predicate,
        value: Value,
        generation: Generation,
    ) Fact {
        return init(id, subject, predicate, value, 1.0, generation);
    }

    /// Create a speculative fact with lower confidence
    pub fn speculative(
        id: FactId,
        subject: Span,
        predicate: Predicate,
        confidence: Confidence,
        generation: Generation,
    ) Fact {
        return init(id, subject, predicate, null, confidence, generation);
    }

    /// Check if this fact overlaps with a given span
    pub fn overlapsSpan(self: Fact, span: Span) bool {
        return self.subject.overlaps(span);
    }

    /// Check if this fact contains a position
    pub fn containsPosition(self: Fact, pos: usize) bool {
        return self.subject.contains(pos);
    }

    /// Check if this fact is certain (confidence = 1.0)
    pub fn isCertain(self: Fact) bool {
        return self.confidence >= 1.0;
    }

    /// Check if this fact is speculative (confidence < 1.0)
    pub fn isSpeculative(self: Fact) bool {
        return self.confidence < 1.0;
    }

    /// Check if this fact has an object value
    pub fn hasValue(self: Fact) bool {
        return self.object != null;
    }

    /// Get the object value, returning a default if none
    pub fn getValue(self: Fact, default: Value) Value {
        return self.object orelse default;
    }

    /// Check if this fact represents a relationship to another fact
    pub fn isRelational(self: Fact) bool {
        return self.predicate.isRelational();
    }

    /// Get the category of this fact for indexing
    pub fn category(self: Fact) @import("predicate.zig").PredicateCategory {
        return self.predicate.category();
    }

    /// Get the span length for this fact
    pub fn length(self: Fact) usize {
        return self.subject.len();
    }

    /// Check if this fact is from a specific generation
    pub fn isFromGeneration(self: Fact, gen: Generation) bool {
        return self.generation == gen;
    }

    /// Check if this fact is newer than a generation
    pub fn isNewerThan(self: Fact, gen: Generation) bool {
        return self.generation > gen;
    }

    /// Compare facts by their subject spans for ordering
    pub fn order(self: Fact, other: Fact) std.math.Order {
        return self.subject.order(other.subject);
    }

    /// Compare facts by ID for stable ordering
    pub fn orderById(self: Fact, other: Fact) std.math.Order {
        if (self.id < other.id) return .lt;
        if (self.id > other.id) return .gt;
        return .eq;
    }

    /// Check if two facts are equal (all fields match)
    pub fn eql(self: Fact, other: Fact) bool {
        return self.id == other.id and
            self.subject.eql(other.subject) and
            self.predicate.eql(other.predicate) and
            std.meta.eql(self.object, other.object) and
            self.confidence == other.confidence and
            self.generation == other.generation;
    }

    /// Calculate hash for this fact (primarily based on ID)
    pub fn hash(self: Fact) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.id));
        return hasher.final();
    }

    /// Format fact for debugging
    pub fn format(
        self: Fact,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Fact(id={d}, subject={}, predicate={}", .{
            self.id,
            self.subject,
            self.predicate,
        });
        
        if (self.object) |obj| {
            try writer.print(", object={}", .{obj});
        }
        
        if (self.confidence < 1.0) {
            try writer.print(", confidence={d:.2}", .{self.confidence});
        }
        
        try writer.print(", gen={d})", .{self.generation});
    }
};

/// Builder for creating facts with a fluent API
pub const FactBuilder = struct {
    id: FactId,
    subject: Span,
    predicate: ?Predicate = null,
    object: ?Value = null,
    confidence: Confidence = 1.0,
    generation: Generation,

    pub fn init(id: FactId, subject: Span, generation: Generation) FactBuilder {
        return .{
            .id = id,
            .subject = subject,
            .generation = generation,
        };
    }

    pub fn withPredicate(self: FactBuilder, predicate: Predicate) FactBuilder {
        var result = self;
        result.predicate = predicate;
        return result;
    }

    pub fn withObject(self: FactBuilder, object: Value) FactBuilder {
        var result = self;
        result.object = object;
        return result;
    }

    pub fn withConfidence(self: FactBuilder, confidence: Confidence) FactBuilder {
        var result = self;
        result.confidence = confidence;
        return result;
    }

    pub fn build(self: FactBuilder) !Fact {
        const predicate = self.predicate orelse return error.MissingPredicate;
        
        return Fact.init(
            self.id,
            self.subject,
            predicate,
            self.object,
            self.confidence,
            self.generation,
        );
    }
};

/// Collection of facts with useful utilities
pub const FactSet = struct {
    facts: std.ArrayList(Fact),

    pub fn init(allocator: std.mem.Allocator) FactSet {
        return .{
            .facts = std.ArrayList(Fact).init(allocator),
        };
    }

    pub fn deinit(self: *FactSet) void {
        self.facts.deinit();
    }

    pub fn add(self: *FactSet, fact: Fact) !void {
        try self.facts.append(fact);
    }

    pub fn len(self: FactSet) usize {
        return self.facts.items.len;
    }

    pub fn get(self: FactSet, index: usize) ?Fact {
        if (index >= self.facts.items.len) return null;
        return self.facts.items[index];
    }

    /// Find facts that overlap with a span
    pub fn findOverlapping(self: FactSet, span: Span, allocator: std.mem.Allocator) ![]Fact {
        var result = std.ArrayList(Fact).init(allocator);
        
        for (self.facts.items) |fact| {
            if (fact.overlapsSpan(span)) {
                try result.append(fact);
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Find facts by predicate category
    pub fn findByCategory(
        self: FactSet,
        category: @import("predicate.zig").PredicateCategory,
        allocator: std.mem.Allocator,
    ) ![]Fact {
        var result = std.ArrayList(Fact).init(allocator);
        
        for (self.facts.items) |fact| {
            if (fact.category() == category) {
                try result.append(fact);
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Find facts from a specific generation
    pub fn findByGeneration(self: FactSet, generation: Generation, allocator: std.mem.Allocator) ![]Fact {
        var result = std.ArrayList(Fact).init(allocator);
        
        for (self.facts.items) |fact| {
            if (fact.isFromGeneration(generation)) {
                try result.append(fact);
            }
        }
        
        return result.toOwnedSlice();
    }

    /// Sort facts by their subject spans
    pub fn sortBySpan(self: *FactSet) void {
        std.sort.heap(Fact, self.facts.items, {}, factSpanLessThan);
    }

    /// Sort facts by their IDs
    pub fn sortById(self: *FactSet) void {
        std.sort.heap(Fact, self.facts.items, {}, factIdLessThan);
    }
};

fn factSpanLessThan(context: void, a: Fact, b: Fact) bool {
    _ = context;
    return a.order(b) == .lt;
}

fn factIdLessThan(context: void, a: Fact, b: Fact) bool {
    _ = context;
    return a.orderById(b) == .lt;
}

// Tests
const testing = std.testing;

test "Fact creation and basic properties" {
    const span = Span.init(10, 20);
    const predicate = @import("predicate.zig").Predicate{ .is_token = .identifier };
    const fact = Fact.simple(1, span, predicate, 0);

    try testing.expectEqual(@as(FactId, 1), fact.id);
    try testing.expect(fact.subject.eql(span));
    try testing.expectEqual(@as(Confidence, 1.0), fact.confidence);
    try testing.expectEqual(@as(Generation, 0), fact.generation);
    try testing.expect(fact.isCertain());
    try testing.expect(!fact.isSpeculative());
    try testing.expect(!fact.hasValue());
}

test "Fact with value" {
    const span = Span.init(5, 15);
    const predicate = @import("predicate.zig").Predicate{ .has_text = "test" };
    const value = Value{ .string = "hello" };
    const fact = Fact.withValue(2, span, predicate, value, 1);

    try testing.expect(fact.hasValue());
    try testing.expectEqual(value, fact.getValue(Value.null_value));
}

test "Speculative fact" {
    const span = Span.init(0, 5);
    const predicate = @import("predicate.zig").Predicate.is_trivia;
    const fact = Fact.speculative(3, span, predicate, 0.7, 2);

    try testing.expect(!fact.isCertain());
    try testing.expect(fact.isSpeculative());
    try testing.expectEqual(@as(Confidence, 0.7), fact.confidence);
}

test "Fact span operations" {
    const span = Span.init(10, 20);
    const predicate = @import("predicate.zig").Predicate{ .is_boundary = .function };
    const fact = Fact.simple(4, span, predicate, 0);

    try testing.expect(fact.containsPosition(15));
    try testing.expect(!fact.containsPosition(5));
    try testing.expect(!fact.containsPosition(25));

    const overlapping_span = Span.init(15, 25);
    const non_overlapping_span = Span.init(25, 35);
    
    try testing.expect(fact.overlapsSpan(overlapping_span));
    try testing.expect(!fact.overlapsSpan(non_overlapping_span));
}

test "Fact ordering" {
    const span1 = Span.init(10, 20);
    const span2 = Span.init(15, 25);
    const predicate = @import("predicate.zig").Predicate{ .is_node = .declaration };
    
    const fact1 = Fact.simple(1, span1, predicate, 0);
    const fact2 = Fact.simple(2, span2, predicate, 0);

    try testing.expectEqual(std.math.Order.lt, fact1.order(fact2));
    try testing.expectEqual(std.math.Order.gt, fact2.order(fact1));
    try testing.expectEqual(std.math.Order.lt, fact1.orderById(fact2));
}

test "Fact equality" {
    const span = Span.init(10, 20);
    const predicate = @import("predicate.zig").Predicate{ .is_token = .keyword };
    
    const fact1 = Fact.simple(1, span, predicate, 0);
    const fact2 = Fact.simple(1, span, predicate, 0);
    const fact3 = Fact.simple(2, span, predicate, 0);

    try testing.expect(fact1.eql(fact2));
    try testing.expect(!fact1.eql(fact3));
}

test "FactBuilder" {
    const span = Span.init(5, 10);
    const predicate = @import("predicate.zig").Predicate{ .highlight_color = .keyword };
    const value = Value{ .string = "test" };

    const fact = try FactBuilder.init(1, span, 0)
        .withPredicate(predicate)
        .withObject(value)
        .withConfidence(0.9)
        .build();

    try testing.expectEqual(@as(FactId, 1), fact.id);
    try testing.expect(fact.subject.eql(span));
    try testing.expectEqual(@as(Confidence, 0.9), fact.confidence);
    try testing.expect(fact.hasValue());
}

test "FactSet operations" {
    var fact_set = FactSet.init(testing.allocator);
    defer fact_set.deinit();

    const span1 = Span.init(0, 10);
    const span2 = Span.init(15, 25);
    const predicate1 = @import("predicate.zig").Predicate{ .is_token = .identifier };
    const predicate2 = @import("predicate.zig").Predicate{ .is_boundary = .function };

    const fact1 = Fact.simple(1, span1, predicate1, 0);
    const fact2 = Fact.simple(2, span2, predicate2, 1);

    try fact_set.add(fact1);
    try fact_set.add(fact2);

    try testing.expectEqual(@as(usize, 2), fact_set.len());
    try testing.expect(fact_set.get(0).?.eql(fact1));
    try testing.expect(fact_set.get(1).?.eql(fact2));

    // Test finding by generation
    const gen0_facts = try fact_set.findByGeneration(0, testing.allocator);
    defer testing.allocator.free(gen0_facts);
    try testing.expectEqual(@as(usize, 1), gen0_facts.len);
    try testing.expect(gen0_facts[0].eql(fact1));

    // Test finding overlapping
    const query_span = Span.init(5, 20);
    const overlapping = try fact_set.findOverlapping(query_span, testing.allocator);
    defer testing.allocator.free(overlapping);
    try testing.expectEqual(@as(usize, 2), overlapping.len);
}