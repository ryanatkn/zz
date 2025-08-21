/// Query executor with streaming support
const std = @import("std");
const Allocator = std.mem.Allocator;

const Query = @import("query.zig").Query;
const Condition = @import("query.zig").Condition;
const SimpleCondition = @import("query.zig").SimpleCondition;
const CompositeCondition = @import("query.zig").CompositeCondition;
const SelectClause = @import("query.zig").SelectClause;
const OrderBy = @import("query.zig").OrderBy;

const Op = @import("operators.zig").Op;
const Field = @import("operators.zig").Field;
const Value = @import("operators.zig").Value;
const Direction = @import("operators.zig").Direction;

const Fact = @import("../fact/mod.zig").Fact;
const FactStore = @import("../fact/mod.zig").FactStore;
const Predicate = @import("../fact/mod.zig").Predicate;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const unpackSpan = @import("../span/mod.zig").unpackSpan;

const Stream = @import("../stream/mod.zig").Stream;
const QueryIndex = @import("../cache/mod.zig").QueryIndex;

/// Query execution result
pub const QueryResult = struct {
    allocator: Allocator,
    facts: []Fact,
    stats: QueryStats,
    
    pub fn deinit(self: *QueryResult) void {
        self.allocator.free(self.facts);
    }
    
    pub fn format(
        self: QueryResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("QueryResult({} facts, {d:.2}ms)", .{
            self.facts.len,
            @as(f64, @floatFromInt(self.stats.execution_time_ns)) / 1_000_000.0,
        });
    }
};

/// Query execution statistics
pub const QueryStats = struct {
    // Timing
    execution_time_ns: u64 = 0,
    planning_time_ns: u64 = 0,
    
    // Row counts
    rows_examined: usize = 0,
    rows_returned: usize = 0,
    
    // Index usage
    index_used: bool = false,
    index_name: ?[]const u8 = null,
    
    // Memory usage
    memory_used: usize = 0,
    
    pub fn format(
        self: QueryStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print(
            \\QueryStats{{
            \\  execution_time: {d:.2}ms
            \\  rows_examined: {}
            \\  rows_returned: {}
            \\  index_used: {}
            \\}}
        , .{
            @as(f64, @floatFromInt(self.execution_time_ns)) / 1_000_000.0,
            self.rows_examined,
            self.rows_returned,
            self.index_used,
        });
    }
};

/// Query executor
pub const QueryExecutor = struct {
    allocator: Allocator,
    stats: QueryStats,
    
    pub fn init(allocator: Allocator) QueryExecutor {
        return .{
            .allocator = allocator,
            .stats = .{},
        };
    }
    
    pub fn deinit(self: *QueryExecutor) void {
        _ = self;
    }
    
    /// Execute query and return all results
    pub fn execute(self: *QueryExecutor, query: *const Query) !QueryResult {
        const start = std.time.nanoTimestamp();
        defer {
            const end = std.time.nanoTimestamp();
            self.stats.execution_time_ns = @intCast(end - start);
        }
        
        // Get fact store
        const store = @as(*FactStore, @ptrCast(@alignCast(query.from orelse return error.NoFactStore)));
        
        // Get base facts based on SELECT clause
        var facts = try self.getBaseFacts(query, store);
        // Note: facts ownership is transferred through the pipeline
        var should_free_facts = true;
        defer if (should_free_facts) self.allocator.free(facts);
        
        // Apply WHERE clause
        if (query.where) |where| {
            facts = try self.applyWhere(facts, &where.condition);
            // applyWhere frees the input and returns new allocation
        }
        
        // Apply GROUP BY
        if (query.group_by) |_| {
            // TODO: Implement grouping in Phase 3
        }
        
        // Apply HAVING
        if (query.having) |_| {
            // TODO: Implement having in Phase 3
        }
        
        // Apply ORDER BY
        if (query.order_by) |order_by| {
            try self.applyOrderBy(facts, order_by);
        }
        
        // Apply LIMIT/OFFSET
        facts = try self.applyLimitOffset(facts, query.limit_, query.offset);
        
        // Transfer ownership to result - no need to dupe
        should_free_facts = false;
        
        self.stats.rows_returned = facts.len;
        
        return QueryResult{
            .allocator = self.allocator,
            .facts = facts,
            .stats = self.stats,
        };
    }
    
    /// Execute query and return a stream
    pub fn executeStream(self: *QueryExecutor, query: *const Query) !FactStream {
        _ = self;
        _ = query;
        // TODO: Implement streaming execution in Phase 3
        return error.NotImplemented;
    }
    
    /// Get base facts based on SELECT clause
    fn getBaseFacts(self: *QueryExecutor, query: *const Query, store: *FactStore) ![]Fact {
        var facts = std.ArrayList(Fact).init(self.allocator);
        
        switch (query.select) {
            .all => {
                // Get all facts from store
                var iter = store.iterator();
                while (iter.next()) |fact| {
                    try facts.append(fact);
                    self.stats.rows_examined += 1;
                }
            },
            .predicates => |predicates| {
                // Get facts matching predicates
                // TODO: Use index if available
                var iter = store.iterator();
                while (iter.next()) |fact| {
                    self.stats.rows_examined += 1;
                    for (predicates) |pred| {
                        if (fact.predicate == pred) {
                            try facts.append(fact);
                            break;
                        }
                    }
                }
            },
            .fields => {
                // TODO: Implement field selection with aggregations
                var iter = store.iterator();
                while (iter.next()) |fact| {
                    try facts.append(fact);
                    self.stats.rows_examined += 1;
                }
            },
        }
        
        return facts.toOwnedSlice();
    }
    
    /// Apply WHERE clause filtering
    fn applyWhere(self: *QueryExecutor, facts: []Fact, condition: *const Condition) ![]Fact {
        var result = std.ArrayList(Fact).init(self.allocator);
        
        for (facts) |fact| {
            if (try self.evaluateCondition(fact, condition)) {
                try result.append(fact);
            }
        }
        
        self.allocator.free(facts);
        return result.toOwnedSlice();
    }
    
    /// Evaluate a condition against a fact
    fn evaluateCondition(self: *QueryExecutor, fact: Fact, condition: *const Condition) error{OutOfMemory}!bool {
        return switch (condition.*) {
            .simple => |simple| evaluateSimpleCondition(fact, simple),
            .composite => |composite| try self.evaluateCompositeCondition(fact, composite),
            .not => |not| !try self.evaluateCondition(fact, not),
        };
    }
    
    /// Evaluate a simple condition
    fn evaluateSimpleCondition(fact: Fact, condition: SimpleCondition) bool {
        const field_value = getFieldValue(fact, condition.field);
        return compareValues(field_value, condition.op, condition.value);
    }
    
    /// Evaluate a composite condition
    fn evaluateCompositeCondition(self: *QueryExecutor, fact: Fact, condition: CompositeCondition) error{OutOfMemory}!bool {
        switch (condition.op) {
            .and_op => {
                for (condition.conditions) |cond| {
                    if (!try self.evaluateCondition(fact, &cond)) {
                        return false;
                    }
                }
                return true;
            },
            .or_op => {
                for (condition.conditions) |cond| {
                    if (try self.evaluateCondition(fact, &cond)) {
                        return true;
                    }
                }
                return false;
            },
        }
    }
    
    /// Get field value from fact
    fn getFieldValue(fact: Fact, field: Field) Value {
        return switch (field) {
            .id => Value{ .number = fact.id },
            .subject => Value{ .number = @intCast(fact.subject) },
            .predicate => Value{ .predicate = fact.predicate },
            .object => blk: {
                // Value is an extern union, so we need to interpret based on predicate
                // For now, return as number by default
                break :blk Value{ .number = @bitCast(fact.object.number) };
            },
            .confidence => Value{ .float = @floatCast(fact.confidence) },
            .span_start => blk: {
                const span = unpackSpan(fact.subject);
                break :blk Value{ .number = @intCast(span.start) };
            },
            .span_end => blk: {
                const span = unpackSpan(fact.subject);
                break :blk Value{ .number = @intCast(span.end) };
            },
            .span_length => blk: {
                const span = unpackSpan(fact.subject);
                break :blk Value{ .number = @intCast(span.end - span.start) };
            },
            .value_type => Value{ .number = 0 }, // TODO: Determine from predicate
            .value_number => Value{ .number = fact.object.number },
            .value_atom => Value{ .atom = @intCast(fact.object.uint) },
            .generation => Value{ .number = 0 }, // TODO: Get from store
            .timestamp => Value{ .number = 0 }, // TODO: Get from store
        };
    }
    
    /// Compare two values with an operator
    fn compareValues(left: Value, op: Op, right: Value) bool {
        // Handle null checks
        if (op == .is_null) return left == .none;
        if (op == .is_not_null) return left != .none;
        
        // Handle IN operator specially
        if (op == .in or op == .not_in) {
            // TODO: Implement IN operator with list
            return false;
        }
        
        // Compare based on value type
        return switch (left) {
            .none => false,
            .number => |n| switch (right) {
                .number => |m| switch (op) {
                    .eq => n == m,
                    .neq => n != m,
                    .lt => n < m,
                    .lte => n <= m,
                    .gt => n > m,
                    .gte => n >= m,
                    else => false,
                },
                else => false,
            },
            .float => |f| switch (right) {
                .float => |g| switch (op) {
                    .eq => f == g,
                    .neq => f != g,
                    .lt => f < g,
                    .lte => f <= g,
                    .gt => f > g,
                    .gte => f >= g,
                    else => false,
                },
                .number => |n| switch (op) {
                    .eq => f == @as(f64, @floatFromInt(n)),
                    .neq => f != @as(f64, @floatFromInt(n)),
                    .lt => f < @as(f64, @floatFromInt(n)),
                    .lte => f <= @as(f64, @floatFromInt(n)),
                    .gt => f > @as(f64, @floatFromInt(n)),
                    .gte => f >= @as(f64, @floatFromInt(n)),
                    else => false,
                },
                else => false,
            },
            .predicate => |p| switch (right) {
                .predicate => |q| p == q and (op == .eq or op == .lte or op == .gte),
                else => false,
            },
            .boolean => |b| switch (right) {
                .boolean => |c| b == c and (op == .eq or op == .lte or op == .gte),
                else => false,
            },
            else => false, // Other types not yet supported
        };
    }
    
    // Helper functions removed - Value is extern union, fields are reinterpreted based on context
    
    /// Apply ORDER BY clause
    fn applyOrderBy(self: *QueryExecutor, facts: []Fact, order_by: []const OrderBy) !void {
        _ = self;
        
        if (order_by.len == 0) return;
        
        // Sort by first field only for now
        // TODO: Implement multi-field sorting
        const order = order_by[0];
        
        const Context = struct {
            field: Field,
            direction: Direction,
            
            pub fn lessThan(ctx: @This(), a: Fact, b: Fact) bool {
                const a_val = getFieldValue(a, ctx.field);
                const b_val = getFieldValue(b, ctx.field);
                
                const cmp = compareValues(a_val, .lt, b_val);
                return if (ctx.direction == .ascending) cmp else !cmp;
            }
        };
        
        std.mem.sort(Fact, facts, Context{ .field = order.field, .direction = order.direction }, Context.lessThan);
    }
    
    /// Apply LIMIT and OFFSET (returns new allocation if limit/offset applied)
    fn applyLimitOffset(self: *QueryExecutor, facts: []Fact, limit_: ?usize, offset_: ?usize) ![]Fact {
        const start = offset_ orelse 0;
        if (start >= facts.len) {
            // Free original and return empty
            self.allocator.free(facts);
            return &[_]Fact{};
        }
        
        const end = if (limit_) |l| @min(start + l, facts.len) else facts.len;
        
        // If we're returning the full slice, just return it
        if (start == 0 and end == facts.len) {
            return facts;
        }
        
        // Otherwise create a new allocation with just the subset
        const subset = try self.allocator.dupe(Fact, facts[start..end]);
        self.allocator.free(facts);
        return subset;
    }
    
    pub const FactStream = Stream(Fact);
};