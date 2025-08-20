const std = @import("std");
const testing = std.testing;

const fact_mod = @import("mod.zig");
const Fact = fact_mod.Fact;
const FactId = fact_mod.FactId;
const Predicate = fact_mod.Predicate;
const Value = fact_mod.Value;
const FactStore = fact_mod.FactStore;
const Builder = fact_mod.Builder;

const span_mod = @import("../span/mod.zig");
const Span = span_mod.Span;
const PackedSpan = span_mod.PackedSpan;
const packSpan = span_mod.packSpan;

const builder = @import("builder.zig");
const Patterns = builder.Patterns;

test "Fact size is exactly 24 bytes" {
    try testing.expectEqual(@as(usize, 24), @sizeOf(Fact));
}

test "Fact field sizes" {
    try testing.expectEqual(@as(usize, 4), @sizeOf(FactId));
    try testing.expectEqual(@as(usize, 8), @sizeOf(PackedSpan));
    try testing.expectEqual(@as(usize, 2), @sizeOf(Predicate));
    try testing.expectEqual(@as(usize, 8), @sizeOf(Value));
    try testing.expectEqual(@as(usize, 2), @sizeOf(f16));
}

test "Fact creation" {
    const span = packSpan(Span.init(10, 20));
    const fact = Fact.init(
        1,
        span,
        .is_token,
        Value.fromNone(),
        0.9,
    );
    
    try testing.expectEqual(@as(FactId, 1), fact.id);
    try testing.expectEqual(span, fact.subject);
    try testing.expectEqual(Predicate.is_token, fact.predicate);
    try testing.expect(fact.object.isNone());
    try testing.expectEqual(@as(f16, 0.9), fact.confidence);
}

test "Fact confidence helpers" {
    const span = packSpan(Span.init(0, 10));
    
    const certain_fact = Fact.certain(1, span, .is_token, Value.fromNone());
    try testing.expect(certain_fact.isCertain());
    try testing.expect(certain_fact.isConfident());
    try testing.expect(!certain_fact.isUncertain());
    
    const uncertain_fact = Fact.init(2, span, .is_token, Value.fromNone(), 0.3);
    try testing.expect(!uncertain_fact.isCertain());
    try testing.expect(!uncertain_fact.isConfident());
    try testing.expect(uncertain_fact.isUncertain());
}

test "Fact with different value types" {
    const span = packSpan(Span.init(0, 10));
    
    // Number value
    const num_fact = Fact.withNumber(1, span, .has_value, 42);
    // With extern union, we check the actual value, not a tag
    try testing.expectEqual(@as(i64, 42), num_fact.object.number);
    
    // Span value
    const span_value = packSpan(Span.init(20, 30));
    const span_fact = Fact.withSpan(2, span, .has_parent, span_value);
    try testing.expectEqual(span_value, span_fact.object.span);
    
    // Fact reference value
    const ref_fact = Fact.withFactRef(3, span, .follows, 1);
    // Check using the helper function
    const fact_ref = ref_fact.object.getFactRef();
    try testing.expect(fact_ref != null);
    try testing.expectEqual(@as(FactId, 1), fact_ref.?);
}

test "Value creation and type checking" {
    const none = Value.fromNone();
    try testing.expect(none.isNone());
    
    const num = Value.fromNumber(42);
    try testing.expect(!num.isNone());
    try testing.expectEqual(@as(i64, 42), num.number);
    
    const boolean = Value.fromBool(true);
    try testing.expect(boolean.getBool());
    
    const float = Value.fromFloat(3.14);
    try testing.expectApproxEqAbs(@as(f64, 3.14), float.float, 0.001);
    
    // Test atom and fact ref helpers
    const atom = Value.fromAtom(123);
    const atom_id = atom.getAtom();
    try testing.expect(atom_id != null);
    try testing.expectEqual(@as(u32, 123), atom_id.?);
    
    const fact_ref = Value.fromFact(456);
    const ref_id = fact_ref.getFactRef();
    try testing.expect(ref_id != null);
    try testing.expectEqual(@as(u32, 456), ref_id.?);
}

test "Predicate categories" {
    try testing.expectEqual(fact_mod.PredicateCategory.lexical, fact_mod.getCategory(.is_token));
    try testing.expectEqual(fact_mod.PredicateCategory.lexical, fact_mod.getCategory(.has_text));
    try testing.expectEqual(fact_mod.PredicateCategory.structural, fact_mod.getCategory(.is_boundary));
    try testing.expectEqual(fact_mod.PredicateCategory.semantic, fact_mod.getCategory(.defines_symbol));
    try testing.expectEqual(fact_mod.PredicateCategory.diagnostic, fact_mod.getCategory(.has_error));
    try testing.expectEqual(fact_mod.PredicateCategory.language_specific, fact_mod.getCategory(.json_is_object));
}

test "FactStore basic operations" {
    var store = FactStore.init(testing.allocator);
    defer store.deinit();
    
    try testing.expect(store.isEmpty());
    try testing.expectEqual(@as(usize, 0), store.count());
    
    const span = packSpan(Span.init(0, 10));
    const fact = Fact.simple(0, span, .is_token);
    
    const id = try store.append(fact);
    try testing.expectEqual(@as(FactId, 1), id);
    try testing.expect(!store.isEmpty());
    try testing.expectEqual(@as(usize, 1), store.count());
    
    const retrieved = store.get(id);
    try testing.expect(retrieved != null);
    try testing.expectEqual(id, retrieved.?.id);
    try testing.expectEqual(span, retrieved.?.subject);
    try testing.expectEqual(Predicate.is_token, retrieved.?.predicate);
}

test "FactStore batch operations" {
    var store = FactStore.init(testing.allocator);
    defer store.deinit();
    
    const facts = [_]Fact{
        Fact.simple(0, packSpan(Span.init(0, 10)), .is_token),
        Fact.simple(0, packSpan(Span.init(10, 20)), .is_identifier),
        Fact.simple(0, packSpan(Span.init(20, 30)), .is_keyword),
    };
    
    const ids = try store.appendBatch(&facts);
    defer testing.allocator.free(ids);
    
    try testing.expectEqual(@as(usize, 3), ids.len);
    try testing.expectEqual(@as(usize, 3), store.count());
    
    for (ids, 0..) |id, i| {
        const fact = store.get(id);
        try testing.expect(fact != null);
        try testing.expectEqual(facts[i].predicate, fact.?.predicate);
    }
}

test "FactStore generation tracking" {
    var store = FactStore.init(testing.allocator);
    defer store.deinit();
    
    try testing.expectEqual(@as(fact_mod.Generation, 0), store.getGeneration());
    
    const gen1 = store.nextGeneration();
    try testing.expectEqual(@as(fact_mod.Generation, 1), gen1);
    try testing.expectEqual(@as(fact_mod.Generation, 1), store.getGeneration());
    
    const gen2 = store.nextGeneration();
    try testing.expectEqual(@as(fact_mod.Generation, 2), gen2);
}

test "FactStore compaction" {
    var store = FactStore.init(testing.allocator);
    defer store.deinit();
    
    const span = packSpan(Span.init(0, 10));
    
    // Add facts with different confidence levels
    _ = try store.append(Fact.init(0, span, .is_token, Value.fromNone(), 0.9));
    _ = try store.append(Fact.init(0, span, .is_token, Value.fromNone(), 0.3));
    _ = try store.append(Fact.init(0, span, .is_token, Value.fromNone(), 0.7));
    _ = try store.append(Fact.init(0, span, .is_token, Value.fromNone(), 0.1));
    
    try testing.expectEqual(@as(usize, 4), store.count());
    
    // Compact to keep only facts with confidence >= 0.5
    store.compact(0.5);
    
    try testing.expectEqual(@as(usize, 2), store.count());
    
    // Verify remaining facts have high confidence
    for (store.getAll()) |fact| {
        try testing.expect(fact.confidence >= 0.5);
    }
}

test "FactStore iterator" {
    var store = FactStore.init(testing.allocator);
    defer store.deinit();
    
    const num_facts = 5;
    for (0..num_facts) |i| {
        const span = packSpan(Span.init(@intCast(i * 10), @intCast((i + 1) * 10)));
        _ = try store.append(Fact.simple(0, span, .is_token));
    }
    
    var iter = store.iterator();
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }
    try testing.expectEqual(num_facts, count);
    
    // Test peek and skip
    iter.reset();
    const first = iter.peek();
    try testing.expect(first != null);
    const next = iter.next();
    try testing.expect(next != null);
    try testing.expectEqual(first.?.id, next.?.id);
    
    iter.skip(2);
    const after_skip = iter.next();
    try testing.expect(after_skip != null);
    try testing.expectEqual(@as(FactId, 4), after_skip.?.id);
}

test "Builder basic usage" {
    const span = Span.init(10, 20);
    
    const fact = try Builder.new()
        .withId(1)
        .withSpan(span)
        .isToken()
        .withNumber(42)
        .certain()
        .build();
    
    try testing.expectEqual(@as(FactId, 1), fact.id);
    try testing.expectEqual(packSpan(span), fact.subject);
    try testing.expectEqual(Predicate.is_token, fact.predicate);
    try testing.expectEqual(@as(i64, 42), fact.object.number);
    try testing.expectEqual(@as(f16, 1.0), fact.confidence);
}

test "Builder with different confidence levels" {
    const span = Span.init(0, 10);
    
    const certain = Builder.new()
        .withSpan(span)
        .isToken()
        .certain()
        .buildWithDefaults();
    try testing.expectEqual(@as(f16, 1.0), certain.confidence);
    
    const likely = Builder.new()
        .withSpan(span)
        .isToken()
        .likely()
        .buildWithDefaults();
    try testing.expectApproxEqAbs(@as(f16, 0.8), likely.confidence, 0.01);
    
    const possible = Builder.new()
        .withSpan(span)
        .isToken()
        .possible()
        .buildWithDefaults();
    try testing.expectApproxEqAbs(@as(f16, 0.5), possible.confidence, 0.01);
    
    const unlikely = Builder.new()
        .withSpan(span)
        .isToken()
        .unlikely()
        .buildWithDefaults();
    try testing.expectApproxEqAbs(@as(f16, 0.2), unlikely.confidence, 0.01);
}

test "Builder error handling" {
    // Missing subject
    const no_subject = Builder.new()
        .isToken()
        .build();
    try testing.expectError(error.MissingSubject, no_subject);
    
    // Missing predicate
    const no_predicate = Builder.new()
        .withSpan(Span.init(0, 10))
        .build();
    try testing.expectError(error.MissingPredicate, no_predicate);
    
    // buildWithDefaults should always work
    const with_defaults = Builder.new().buildWithDefaults();
    try testing.expectEqual(@as(PackedSpan, 0), with_defaults.subject);
    try testing.expectEqual(Predicate.is_token, with_defaults.predicate);
}

test "Pattern helpers" {
    const span = Span.init(10, 20);
    
    const token = Patterns.token(span, .is_identifier);
    try testing.expectEqual(packSpan(span), token.subject);
    try testing.expectEqual(Predicate.is_identifier, token.predicate);
    try testing.expect(token.isCertain());
    
    const boundary = Patterns.boundary(span);
    try testing.expectEqual(Predicate.is_boundary, boundary.predicate);
    
    const symbol_def = Patterns.symbolDef(span, 123);
    try testing.expectEqual(Predicate.defines_symbol, symbol_def.predicate);
    const symbol_atom = symbol_def.object.getAtom();
    try testing.expect(symbol_atom != null);
    try testing.expectEqual(@as(u32, 123), symbol_atom.?);
    
    const error_fact = Patterns.err(span, 404);
    try testing.expectEqual(Predicate.has_error, error_fact.predicate);
    try testing.expectEqual(@as(i64, 404), error_fact.object.number);
    
    const parent_fact = Patterns.parent(span, 5);
    try testing.expectEqual(Predicate.has_parent, parent_fact.predicate);
    const parent_ref = parent_fact.object.getFactRef();
    try testing.expect(parent_ref != null);
    try testing.expectEqual(@as(FactId, 5), parent_ref.?);
    
    const indent_fact = Patterns.indent(span, 4);
    try testing.expectEqual(Predicate.indent_level, indent_fact.predicate);
    try testing.expectEqual(@as(u64, 4), indent_fact.object.uint);
}

test "Fact formatting" {
    const span = packSpan(Span.init(0, 10));
    const fact = Fact.withNumber(42, span, .has_value, 100);
    
    const output = try std.fmt.allocPrint(testing.allocator, "{}", .{fact});
    defer testing.allocator.free(output);
    
    // Should contain fact ID and predicate
    try testing.expect(std.mem.indexOf(u8, output, "Fact#42") != null);
    try testing.expect(std.mem.indexOf(u8, output, "has_value") != null);
}

test "Value formatting" {
    const values = [_]Value{
        Value.fromNone(),
        Value.fromNumber(42),
        Value.fromBool(true),
        Value.fromFloat(3.14),
    };
    
    for (values) |value| {
        const output = try std.fmt.allocPrint(testing.allocator, "{}", .{value});
        defer testing.allocator.free(output);
        try testing.expect(output.len > 0);
    }
}