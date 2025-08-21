/// Example data and scenarios for stream demos
const std = @import("std");

const fact_mod = @import("../lib/fact/mod.zig");
const Fact = fact_mod.Fact;
const FactStore = fact_mod.FactStore;
const Predicate = fact_mod.Predicate;
const Value = fact_mod.Value;
const Builder = fact_mod.Builder;

const span_mod = @import("../lib/span/mod.zig");
const Span = span_mod.Span;
const packSpan = span_mod.packSpan;

/// Add sample facts to demonstrate query capabilities
pub fn addSampleFacts(store: *FactStore) !void {

    // Add various facts with different predicates and confidence levels
    const facts = [_]struct {
        span: Span,
        predicate: Predicate,
        confidence: f16,
        value: Value,
    }{
        // High confidence facts
        .{ .span = Span.init(0, 50), .predicate = .is_function, .confidence = 0.95, .value = Value{ .none = 0 } },
        .{ .span = Span.init(51, 100), .predicate = .is_class, .confidence = 0.92, .value = Value{ .none = 0 } },
        .{ .span = Span.init(101, 150), .predicate = .is_variable, .confidence = 0.88, .value = Value{ .none = 0 } },
        .{ .span = Span.init(151, 200), .predicate = .is_type_def, .confidence = 0.90, .value = Value{ .none = 0 } },

        // Medium confidence facts
        .{ .span = Span.init(201, 250), .predicate = .is_comment, .confidence = 0.75, .value = Value{ .none = 0 } },
        .{ .span = Span.init(251, 300), .predicate = .is_string, .confidence = 0.70, .value = Value{ .none = 0 } },
        .{ .span = Span.init(301, 350), .predicate = .is_number, .confidence = 0.72, .value = Value{ .none = 0 } },

        // Low confidence facts
        .{ .span = Span.init(351, 400), .predicate = .is_keyword, .confidence = 0.60, .value = Value{ .none = 0 } },
        .{ .span = Span.init(401, 450), .predicate = .is_operator, .confidence = 0.55, .value = Value{ .none = 0 } },
        .{ .span = Span.init(451, 500), .predicate = .is_identifier, .confidence = 0.50, .value = Value{ .none = 0 } },

        // Facts with values
        .{ .span = Span.init(501, 550), .predicate = .has_text, .confidence = 1.0, .value = Value{ .pair = .{ .a = 42, .b = 0 } } },
        .{ .span = Span.init(551, 600), .predicate = .defines_symbol, .confidence = 0.85, .value = Value{ .pair = .{ .a = 100, .b = 0 } } },
        .{ .span = Span.init(601, 650), .predicate = .has_value, .confidence = 1.0, .value = Value{ .number = 25 } },
    };

    for (facts) |fact_data| {
        const fact = try Builder.new()
            .withSpan(fact_data.span)
            .withPredicate(fact_data.predicate)
            .withConfidence(fact_data.confidence)
            .withObject(fact_data.value)
            .build();

        _ = try store.append(fact);
    }
}

/// Sample JSON data for tokenization demos
pub const sample_json =
    \\{
    \\  "project": {
    \\    "name": "zz",
    \\    "description": "Fast command-line utilities",
    \\    "version": "0.1.0",
    \\    "features": [
    \\      "stream-first",
    \\      "zero-allocation",
    \\      "high-performance"
    \\    ],
    \\    "metrics": {
    \\      "dispatch_cycles": 1.5,
    \\      "throughput": "10MB/sec",
    \\      "memory": "2MB per 1000 lines"
    \\    }
    \\  }
    \\}
;

/// Sample ZON data for tokenization demos
pub const sample_zon =
    \\.{
    \\    .name = "zz",
    \\    .version = "0.1.0",
    \\    .dependencies = .{
    \\        .stream = .{
    \\            .path = "src/lib/stream",
    \\        },
    \\        .fact = .{
    \\            .path = "src/lib/fact",
    \\        },
    \\    },
    \\    .build_options = .{
    \\        .optimize = .ReleaseFast,
    \\        .target = null,
    \\    },
    \\    .features = .{
    \\        .directstream = true,
    \\        .arena_allocation = true,
    \\        .query_engine = true,
    \\    },
    \\}
;

/// Large JSON for performance testing
pub fn generateLargeJson(allocator: std.mem.Allocator, item_count: usize) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    var writer = buffer.writer();

    try writer.writeAll("{\n  \"items\": [\n");

    for (0..item_count) |i| {
        try writer.print("    {{\n", .{});
        try writer.print("      \"id\": {},\n", .{i});
        try writer.print("      \"name\": \"Item_{}\",\n", .{i});
        try writer.print("      \"value\": {d:.2},\n", .{@as(f64, @floatFromInt(i)) * 1.5});
        try writer.print("      \"enabled\": {}\n", .{i % 2 == 0});
        try writer.print("    }}", .{});
        if (i < item_count - 1) {
            try writer.writeAll(",");
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("  ]\n}\n");

    return buffer.toOwnedSlice();
}

/// Large ZON for performance testing
pub fn generateLargeZon(allocator: std.mem.Allocator, item_count: usize) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    var writer = buffer.writer();

    try writer.writeAll(".{\n    .items = .{\n");

    for (0..item_count) |i| {
        try writer.print("        .item_{} = .{{\n", .{i});
        try writer.print("            .id = {},\n", .{i});
        try writer.print("            .value = {d:.1},\n", .{@as(f64, @floatFromInt(i)) * 2.0});
        try writer.print("            .active = {},\n", .{i % 3 == 0});
        try writer.print("        }},\n", .{});
    }

    try writer.writeAll("    },\n}\n");

    return buffer.toOwnedSlice();
}
