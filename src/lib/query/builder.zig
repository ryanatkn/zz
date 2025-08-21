/// Query builder with SQL-like DSL
const std = @import("std");
const Allocator = std.mem.Allocator;

const Query = @import("query.zig").Query;
const SelectClause = @import("query.zig").SelectClause;
const SelectField = @import("query.zig").SelectField;
const WhereClause = @import("query.zig").WhereClause;
const Condition = @import("query.zig").Condition;
const SimpleCondition = @import("query.zig").SimpleCondition;
const CompositeCondition = @import("query.zig").CompositeCondition;
const HavingClause = @import("query.zig").HavingClause;
const AggregateCondition = @import("query.zig").AggregateCondition;
const OrderBy = @import("query.zig").OrderBy;

const Op = @import("operators.zig").Op;
const Field = @import("operators.zig").Field;
const Value = @import("operators.zig").Value;
const Direction = @import("operators.zig").Direction;
const Aggregation = @import("operators.zig").Aggregation;

const Predicate = @import("../fact/mod.zig").Predicate;
const FactStore = @import("../fact/mod.zig").FactStore;

const QueryExecutor = @import("executor.zig").QueryExecutor;
const QueryResult = @import("executor.zig").QueryResult;

/// Fluent query builder interface
pub const QueryBuilder = struct {
    allocator: Allocator,
    query: Query,
    where_conditions: std.ArrayList(Condition),
    order_by_list: std.ArrayList(OrderBy),
    group_by_list: std.ArrayList(Field),

    pub fn init(allocator: Allocator) QueryBuilder {
        return .{
            .allocator = allocator,
            .query = Query.init(allocator),
            .where_conditions = std.ArrayList(Condition).init(allocator),
            .order_by_list = std.ArrayList(OrderBy).init(allocator),
            .group_by_list = std.ArrayList(Field).init(allocator),
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        for (self.where_conditions.items) |*cond| {
            cond.deinit(self.allocator);
        }
        self.where_conditions.deinit();
        self.order_by_list.deinit();
        self.group_by_list.deinit();
        // Don't deinit query here - it's transferred to caller via build()
    }

    /// Select all facts
    pub fn selectAll(self: *QueryBuilder) *QueryBuilder {
        self.query.select = SelectClause.all;
        return self;
    }

    /// Select specific predicates
    pub fn select(self: *QueryBuilder, predicates: []const Predicate) *QueryBuilder {
        self.query.select = SelectClause{ .predicates = predicates };
        return self;
    }

    /// Select specific fields with optional aggregations
    pub fn selectFields(self: *QueryBuilder, fields: []const SelectField) *QueryBuilder {
        self.query.select = SelectClause{ .fields = fields };
        return self;
    }

    /// Set the fact store to query from
    pub fn from(self: *QueryBuilder, store: *FactStore) *QueryBuilder {
        self.query.from = store;
        return self;
    }

    /// Add a WHERE condition
    pub fn where(self: *QueryBuilder, field: Field, op: Op, value: anytype) !*QueryBuilder {
        const val = try makeValue(value);
        const condition = Condition{
            .simple = SimpleCondition{
                .field = field,
                .op = op,
                .value = val,
            },
        };
        try self.where_conditions.append(condition);
        return self;
    }

    /// Add an AND condition
    pub fn andWhere(self: *QueryBuilder, field: Field, op: Op, value: anytype) !*QueryBuilder {
        return self.where(field, op, value);
    }

    /// Add an OR condition group
    pub fn orWhere(self: *QueryBuilder, field: Field, op: Op, value: anytype) !*QueryBuilder {
        // This creates a new OR group with the previous conditions
        if (self.where_conditions.items.len > 0) {
            // Move existing conditions into an OR group
            const existing = try self.allocator.dupe(Condition, self.where_conditions.items);
            self.where_conditions.clearRetainingCapacity();

            const val = try makeValue(value);
            const new_condition = Condition{
                .simple = SimpleCondition{
                    .field = field,
                    .op = op,
                    .value = val,
                },
            };

            const conditions = try self.allocator.alloc(Condition, 2);
            conditions[0] = Condition{
                .composite = CompositeCondition{
                    .op = .and_op,
                    .conditions = existing,
                },
            };
            conditions[1] = new_condition;

            const or_condition = Condition{
                .composite = CompositeCondition{
                    .op = .or_op,
                    .conditions = conditions,
                },
            };
            try self.where_conditions.append(or_condition);
        } else {
            return self.where(field, op, value);
        }
        return self;
    }

    /// Add a NOT condition
    pub fn whereNot(self: *QueryBuilder, field: Field, op: Op, value: anytype) !*QueryBuilder {
        const val = try makeValue(value);
        const inner = try self.allocator.create(Condition);
        inner.* = Condition{
            .simple = SimpleCondition{
                .field = field,
                .op = op,
                .value = val,
            },
        };
        const condition = Condition{ .not = inner };
        try self.where_conditions.append(condition);
        return self;
    }

    /// Add a BETWEEN condition
    pub fn whereBetween(self: *QueryBuilder, field: Field, min: anytype, max: anytype) !*QueryBuilder {
        const range = Value{
            .range = .{
                .min = @floatCast(@as(f64, @floatFromInt(min))),
                .max = @floatCast(@as(f64, @floatFromInt(max))),
            },
        };
        return self.where(field, .between, range);
    }

    /// Add an IN condition
    pub fn whereIn(self: *QueryBuilder, field: Field, values: []const Value) !*QueryBuilder {
        const list = Value{ .list = values };
        return self.where(field, .in, list);
    }

    /// Group by fields
    pub fn groupBy(self: *QueryBuilder, field: Field) !*QueryBuilder {
        try self.group_by_list.append(field);
        return self;
    }

    /// Add a HAVING condition for aggregations
    pub fn having(self: *QueryBuilder, agg: Aggregation, field: Field, op: Op, value: anytype) !*QueryBuilder {
        const val = try makeValue(value);
        self.query.having = HavingClause{
            .condition = AggregateCondition{
                .aggregation = agg,
                .field = field,
                .op = op,
                .value = val,
            },
        };
        return self;
    }

    /// Order by field
    pub fn orderBy(self: *QueryBuilder, field: Field, direction: Direction) !*QueryBuilder {
        try self.order_by_list.append(OrderBy{
            .field = field,
            .direction = direction,
        });
        return self;
    }

    /// Set result limit
    pub fn limit(self: *QueryBuilder, n: usize) *QueryBuilder {
        self.query.limit_ = n;
        return self;
    }

    /// Set result offset
    pub fn offset(self: *QueryBuilder, n: usize) *QueryBuilder {
        self.query.offset = n;
        return self;
    }

    /// Build the final query
    pub fn build(self: *QueryBuilder) !Query {
        // Combine WHERE conditions
        if (self.where_conditions.items.len > 0) {
            if (self.where_conditions.items.len == 1) {
                self.query.where = WhereClause{
                    .condition = self.where_conditions.items[0],
                };
            } else {
                // Multiple conditions are ANDed by default
                const conditions = try self.allocator.dupe(Condition, self.where_conditions.items);
                self.query.where = WhereClause{
                    .condition = Condition{
                        .composite = CompositeCondition{
                            .op = .and_op,
                            .conditions = conditions,
                        },
                    },
                };
            }
            // Clear to prevent double-free
            self.where_conditions.clearRetainingCapacity();
        }

        // Set GROUP BY
        if (self.group_by_list.items.len > 0) {
            self.query.group_by = try self.allocator.dupe(Field, self.group_by_list.items);
        }

        // Set ORDER BY
        if (self.order_by_list.items.len > 0) {
            self.query.order_by = try self.allocator.dupe(OrderBy, self.order_by_list.items);
        }

        return self.query;
    }

    /// Execute the query immediately (consumes the builder)
    pub fn execute(self: *QueryBuilder) !QueryResult {
        var query = try self.build();
        defer query.deinit();

        var executor = QueryExecutor.init(self.allocator);
        defer executor.deinit();

        return executor.execute(&query);
    }

    /// Execute and return a stream
    pub fn executeStream(self: *QueryBuilder) !QueryExecutor.FactStream {
        var query = try self.build();
        defer query.deinit();

        var executor = QueryExecutor.init(self.allocator);
        return executor.executeStream(&query);
    }

    /// Execute and return a DirectStream (Phase 5B)
    pub fn directExecuteStream(self: *QueryBuilder) !QueryExecutor.DirectFactStream {
        // Build query on stack - no heap allocation needed
        const query = try self.build();

        var executor = QueryExecutor.init(self.allocator);
        return executor.directExecuteStream(&query);
    }

    // TODO: Phase 5C - Delete executeStream after full migration to DirectStream

    // Helper to convert various types to Value
    fn makeValue(value: anytype) !Value {
        const T = @TypeOf(value);

        if (T == Value) return value;

        return switch (@typeInfo(T)) {
            .int, .comptime_int => Value{ .number = @intCast(value) },
            .float, .comptime_float => Value{ .float = @floatCast(value) },
            .bool => Value{ .boolean = value },
            .pointer => |ptr| switch (ptr.size) {
                .Slice => {
                    if (ptr.child == u8) {
                        return Value{ .string = value };
                    }
                    return error.UnsupportedType;
                },
                else => error.UnsupportedType,
            },
            .@"enum" => {
                if (T == Predicate) {
                    // Store predicate as number
                    return Value{ .number = @intFromEnum(value) };
                }
                // For other enums, convert to int
                return Value{ .number = @intFromEnum(value) };
            },
            .void, .null => Value.none,
            else => error.UnsupportedType,
        };
    }
};

// Convenience functions for common queries

/// Create a query for facts with specific predicates
pub fn queryByPredicate(allocator: Allocator, store: *FactStore, predicates: []const Predicate) !QueryBuilder {
    var builder = QueryBuilder.init(allocator);
    return builder.select(predicates).from(store);
}

/// Create a query for high-confidence facts
pub fn queryHighConfidence(allocator: Allocator, store: *FactStore, threshold: f16) !QueryBuilder {
    var builder = QueryBuilder.init(allocator);
    return builder.selectAll().from(store).where(.confidence, .gte, threshold);
}

/// Create a query for facts in a span range
pub fn queryBySpan(allocator: Allocator, store: *FactStore, start: u32, end: u32) !QueryBuilder {
    var builder = QueryBuilder.init(allocator);
    return builder
        .selectAll()
        .from(store)
        .where(.span_start, .gte, start)
        .andWhere(.span_end, .lte, end);
}
