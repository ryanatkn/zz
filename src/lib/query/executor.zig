/// Query executor with streaming support
const std = @import("std");
const Allocator = std.mem.Allocator;

const Query = @import("query.zig").Query;
const Condition = @import("query.zig").Condition;
const SimpleCondition = @import("query.zig").SimpleCondition;
const CompositeCondition = @import("query.zig").CompositeCondition;
const SelectClause = @import("query.zig").SelectClause;
const OrderBy = @import("query.zig").OrderBy;
const HavingClause = @import("query.zig").HavingClause;

const Op = @import("operators.zig").Op;
const Field = @import("operators.zig").Field;
const Value = @import("operators.zig").Value;
const Direction = @import("operators.zig").Direction;

const Fact = @import("../fact/mod.zig").Fact;
const FactStore = @import("../fact/mod.zig").FactStore;
const FactIterator = @import("../fact/mod.zig").FactIterator;
const Predicate = @import("../fact/mod.zig").Predicate;
const PackedSpan = @import("../span/mod.zig").PackedSpan;
const unpackSpan = @import("../span/mod.zig").unpackSpan;

const Stream = @import("../stream/mod.zig").Stream;
const DirectStream = @import("../stream/mod.zig").DirectStream;
const directFromSlice = @import("../stream/mod.zig").directFromSlice;
const GeneratorStream = @import("../stream/mod.zig").GeneratorStream;
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
        if (query.group_by) |group_fields| {
            facts = try self.applyGroupBy(facts, group_fields);
            // Note: facts ownership transferred to grouped result
        }

        // Apply HAVING
        if (query.having) |having| {
            facts = try self.applyHaving(facts, &having);
            // Note: facts ownership transferred to filtered result
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
        // Get fact store
        const store = @as(*FactStore, @ptrCast(@alignCast(query.from orelse return error.NoFactStore)));

        // Create streaming context
        const ctx = try self.allocator.create(StreamContext);
        ctx.* = StreamContext{
            .executor = self,
            .query = query,
            .store = store,
            .iterator = store.iterator(),
            .state = .initial,
            .current_fact = null,
        };

        return FactStream{
            .context = ctx,
            .nextFn = streamNext,
            .peekFn = null,
            .closeFn = streamClose,
            .stats = .{},
        };
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
                // Convert fact.Value (extern union) to query.Value (tagged union)
                // The fact.object is an extern union, we need to safely interpret it
                // For now, treat it as a number since we can't determine the actual type
                // TODO: Use predicate to determine proper interpretation
                break :blk Value{ .number = @intCast(fact.object.uint) };
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

    /// Apply GROUP BY clause
    fn applyGroupBy(self: *QueryExecutor, facts: []Fact, group_fields: []const Field) ![]Fact {
        // TODO: Full GROUP BY implementation with aggregations
        // For now, just group by first unique value of each field combination

        if (group_fields.len == 0) return facts;

        // Create a map to track groups
        var groups = std.AutoHashMap(u64, std.ArrayList(Fact)).init(self.allocator);
        defer {
            var iter = groups.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            groups.deinit();
        }

        // Group facts by field values
        for (facts) |fact| {
            // Create a hash of the group key (simplified - just use first field)
            const field_value = getFieldValue(fact, group_fields[0]);
            const hash = switch (field_value) {
                .number => |n| @as(u64, @bitCast(n)),
                .float => |f| @as(u64, @bitCast(f)),
                .predicate => |p| @intFromEnum(p),
                else => 0,
            };

            const result = try groups.getOrPut(hash);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(Fact).init(self.allocator);
            }
            try result.value_ptr.append(fact);
        }

        // Build result with one fact per group (first fact for now)
        var result = std.ArrayList(Fact).init(self.allocator);
        var iter = groups.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.items.len > 0) {
                // TODO: Apply aggregation functions (COUNT, SUM, AVG, etc.)
                // For now, just take the first fact from each group
                try result.append(entry.value_ptr.items[0]);
            }
        }

        self.allocator.free(facts);
        return result.toOwnedSlice();
    }

    /// Apply HAVING clause (post-aggregation filtering)
    fn applyHaving(self: *QueryExecutor, facts: []Fact, having: *const HavingClause) ![]Fact {
        // TODO: Full HAVING implementation with aggregation conditions
        // For now, just return all facts since we can't evaluate aggregation conditions yet

        _ = self;
        _ = having;

        // When GROUP BY and aggregations are fully implemented, this will:
        // 1. Evaluate aggregate functions (COUNT, SUM, AVG, etc.)
        // 2. Filter groups based on aggregate conditions
        // 3. Return only groups that meet the HAVING criteria

        // For now, pass through all facts
        return facts;
    }

    /// Apply ORDER BY clause with multi-field support
    fn applyOrderBy(self: *QueryExecutor, facts: []Fact, order_by: []const OrderBy) !void {
        _ = self;

        if (order_by.len == 0) return;

        const Context = struct {
            orders: []const OrderBy,

            pub fn lessThan(ctx: @This(), a: Fact, b: Fact) bool {
                // Compare using each field in order until we find a difference
                for (ctx.orders) |order| {
                    const a_val = getFieldValue(a, order.field);
                    const b_val = getFieldValue(b, order.field);

                    // Check if values are equal
                    if (compareValues(a_val, .eq, b_val)) {
                        // Values are equal, continue to next field
                        continue;
                    }

                    // Values differ, use this field for comparison
                    const cmp = compareValues(a_val, .lt, b_val);
                    return if (order.direction == .ascending) cmp else !cmp;
                }

                // All fields are equal, maintain original order
                return false;
            }
        };

        std.mem.sort(Fact, facts, Context{ .orders = order_by }, Context.lessThan);
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
    pub const DirectFactStream = DirectStream(Fact);

    /// Create DirectStream from fact slice
    pub fn directFactStream(facts: []const Fact) DirectFactStream {
        return directFromSlice(Fact, facts);
    }

    /// Execute query and return a DirectStream (Phase 5)
    pub fn directExecute(self: *QueryExecutor, query: *const Query) !DirectFactStream {
        // For now, execute normally and convert to DirectStream
        // TODO: Implement true streaming execution without collecting all facts
        var result = try self.execute(query);
        defer result.deinit();

        // Create a copy of facts that DirectStream can own
        const facts_copy = try self.allocator.dupe(Fact, result.facts);
        return directFactStream(facts_copy);
    }

    /// Execute query and return a DirectStream with true streaming (Phase 5B)
    pub fn directExecuteStream(self: *QueryExecutor, query: *const Query) !DirectFactStream {
        // Get fact store
        const store = @as(*FactStore, @ptrCast(@alignCast(query.from orelse return error.NoFactStore)));

        // Create streaming context for DirectStream
        const ctx = try self.allocator.create(DirectStreamContext);
        ctx.* = DirectStreamContext{
            .allocator = self.allocator,
            .store = store,
            .iterator = store.iterator(),
            // Copy only the needed query parts (small structs/enums)
            .where_condition = if (query.where) |w| w.condition else null,
            .select_clause = query.select,
            .limit = query.limit_,
            .offset = query.offset orelse 0,
            .count = 0,
            .skipped = 0,
        };

        // Generator function for streaming facts
        const gen_fn = struct {
            fn generate(ptr: *anyopaque) ?Fact {
                const context = @as(*DirectStreamContext, @ptrCast(@alignCast(ptr)));
                return directStreamNext(context) catch null;
            }
        }.generate;

        // Cleanup function to free the context when done
        const cleanup_fn = struct {
            fn cleanup(ptr: *anyopaque) void {
                const context = @as(*DirectStreamContext, @ptrCast(@alignCast(ptr)));
                context.allocator.destroy(context);
            }
        }.cleanup;

        return DirectFactStream{
            .generator = GeneratorStream(Fact).initWithCleanup(ctx, gen_fn, cleanup_fn),
        };
    }

    /// TODO: Phase 5C - Migrate executeStream to use DirectFactStream
    /// TODO: Delete vtable-based executeStream after full migration
    /// Context for DirectStream streaming query execution
    const DirectStreamContext = struct {
        allocator: std.mem.Allocator,
        store: *FactStore,
        iterator: FactIterator,
        // Copy only the needed query parts (small, can be copied cheaply)
        where_condition: ?Condition = null,
        select_clause: SelectClause = .all,
        limit: ?usize = null,
        offset: usize = 0,
        // Track progress
        count: usize = 0,
        skipped: usize = 0,
    };

    /// Get next fact for DirectStream (zero-allocation streaming)
    fn directStreamNext(ctx: *DirectStreamContext) !?Fact {
        // Apply OFFSET - skip facts if needed
        while (ctx.skipped < ctx.offset) {
            _ = ctx.iterator.next() orelse return null;
            ctx.skipped += 1;
        }

        // Apply LIMIT - stop if we've returned enough facts
        if (ctx.limit) |limit| {
            if (ctx.count >= limit) {
                return null;
            }
        }

        while (ctx.iterator.next()) |fact| {
            // Apply WHERE condition if present
            if (ctx.where_condition) |condition| {
                const result = try evaluateStreamingCondition(fact, condition);
                if (!result) {
                    continue;
                }
            }

            // Apply SELECT predicate filter if not SELECT *
            switch (ctx.select_clause) {
                .all => {
                    ctx.count += 1;
                    return fact;
                },
                .predicates => |predicates| {
                    for (predicates) |pred| {
                        if (fact.predicate == pred) {
                            ctx.count += 1;
                            return fact;
                        }
                    }
                    continue; // Skip this fact
                },
                .fields => {
                    // TODO: Field projection not yet supported in streaming
                    // For now, return all facts when fields are selected
                    ctx.count += 1;
                    return fact;
                },
            }
        }

        return null;
    }

    /// Simple condition evaluation for streaming (without full executor)
    fn evaluateStreamingCondition(fact: Fact, condition: Condition) !bool {
        // Basic evaluation for common conditions
        // This is a simplified version - expand as needed
        switch (condition) {
            .simple => |simple| {
                const field_value = getFieldValue(fact, simple.field);
                return compareValues(field_value, simple.op, simple.value);
            },
            .composite => return error.NotImplemented, // TODO: Support composite conditions
            .not => return error.NotImplemented, // TODO: Support NOT conditions
        }
    }

    /// TODO: Phase 5 - Migrate executeStream to use DirectFactStream
    /// TODO: Implement true streaming without collecting all results first
    /// Context for streaming query execution
    const StreamContext = struct {
        executor: *QueryExecutor,
        query: *const Query,
        store: *FactStore,
        iterator: FactIterator,
        state: StreamState,
        current_fact: ?Fact,
    };

    const StreamState = enum {
        initial,
        filtering,
        done,
    };

    /// Get next fact from stream
    fn streamNext(ctx: *anyopaque) ?Fact {
        const context: *StreamContext = @ptrCast(@alignCast(ctx));

        while (true) {
            // Get next fact from store
            const fact = context.iterator.next() orelse {
                context.state = .done;
                return null;
            };

            context.executor.stats.rows_examined += 1;

            // Apply SELECT filtering
            var matches_select = false;
            switch (context.query.select) {
                .all => matches_select = true,
                .predicates => |predicates| {
                    for (predicates) |pred| {
                        if (fact.predicate == pred) {
                            matches_select = true;
                            break;
                        }
                    }
                },
                .fields => matches_select = true, // TODO: Field filtering
            }

            if (!matches_select) continue;

            // Apply WHERE clause
            if (context.query.where) |where| {
                // TODO: For streaming, we need a non-allocating version of evaluateCondition
                // For now, do simple predicate check
                _ = where;
                // if (!context.executor.evaluateCondition(fact, &where.condition)) continue;
            }

            // TODO: GROUP BY and HAVING need accumulation, incompatible with streaming
            // TODO: ORDER BY needs full dataset, incompatible with streaming

            context.executor.stats.rows_returned += 1;
            return fact;
        }
    }

    /// Clean up streaming context
    fn streamClose(ctx: *anyopaque) void {
        const context: *StreamContext = @ptrCast(@alignCast(ctx));
        context.executor.allocator.destroy(context);
    }
};
